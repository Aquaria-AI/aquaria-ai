from __future__ import annotations

import json
import os
import re
import secrets
import sqlite3
import time
from datetime import date, datetime
from io import BytesIO
from typing import Any, Dict, List, Optional

import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.base import MIMEBase
from email import encoders

import anthropic
from google import genai
import jwt
import requests as http_requests
import urllib.request
from PIL import Image
from jwt import PyJWKClient
from fastapi import Depends, FastAPI, Form, Header, HTTPException, Request, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from starlette.responses import JSONResponse

# ---------------------------------------------------------------------------
# Supabase JWT verification
# ---------------------------------------------------------------------------

_SUPABASE_JWT_SECRET = os.environ.get("SUPABASE_JWT_SECRET", "")
_SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://jdiwsvealnrzdxofomvz.supabase.co")
_SUPABASE_SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
_JWKS_URL = f"{_SUPABASE_URL}/auth/v1/.well-known/jwks.json"
_jwks_client: PyJWKClient | None = None

# ---------------------------------------------------------------------------
# Discord integration
# ---------------------------------------------------------------------------
_DISCORD_CLIENT_ID = os.environ.get("DISCORD_CLIENT_ID", "")
_DISCORD_CLIENT_SECRET = os.environ.get("DISCORD_CLIENT_SECRET", "")
_DISCORD_BOT_TOKEN = os.environ.get("DISCORD_BOT_TOKEN", "")
_DISCORD_REDIRECT_URI = os.environ.get("DISCORD_REDIRECT_URI", "https://aquaria-ai-production.up.railway.app/discord/callback")
_DISCORD_API = "https://discord.com/api/v10"
_DISCORD_SCOPES = "identify guilds"

# OAuth state helpers (persisted in Supabase to survive redeploys)
def _save_oauth_state(state: str, provider: str, user_id: str, code_verifier: str = ""):
    _supabase_rest("POST", "oauth_auth_states", body={
        "state": state, "provider": provider, "user_id": user_id,
        "code_verifier": code_verifier or None,
    }, prefer="return=minimal")

def _pop_oauth_state(state: str, provider: str) -> dict | None:
    rows = _supabase_rest("GET", "oauth_auth_states",
                          params=f"state=eq.{state}&provider=eq.{provider}")
    if not rows:
        return None
    _supabase_rest("DELETE", "oauth_auth_states", params=f"state=eq.{state}")
    row = rows[0]
    return {"user_id": row["user_id"], "code_verifier": row.get("code_verifier", "")}

# ---------------------------------------------------------------------------
# Twitter/X integration
# ---------------------------------------------------------------------------
_TWITTER_CLIENT_ID = os.environ.get("TWITTER_CLIENT_ID", "")
_TWITTER_CLIENT_SECRET = os.environ.get("TWITTER_CLIENT_SECRET", "")
_TWITTER_REDIRECT_URI = os.environ.get("TWITTER_REDIRECT_URI", "https://aquaria-ai-production.up.railway.app/twitter/callback")
_TWITTER_API = "https://api.x.com/2"
_TWITTER_UPLOAD_API = "https://upload.twitter.com/1.1"
_TWITTER_SCOPES = "tweet.read tweet.write users.read media.write offline.access"

def _get_jwks_client() -> PyJWKClient:
    global _jwks_client
    if _jwks_client is None:
        _jwks_client = PyJWKClient(_JWKS_URL, cache_keys=True)
    return _jwks_client

def _get_user_id(request: Request) -> str:
    """Extract and verify the Supabase JWT from the Authorization header.
    Returns the user's sub (UUID). Raises 401 on any failure."""
    auth = request.headers.get("authorization", "")
    if not auth.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing authorization header")
    token = auth[7:]
    try:
        # Try JWKS first — supports RS256, ES256, etc.
        signing_key = _get_jwks_client().get_signing_key_from_jwt(token)
        # Read the algorithm from the JWKS key itself
        header = jwt.get_unverified_header(token)
        payload = jwt.decode(
            token,
            signing_key.key,
            algorithms=[header.get("alg", "ES256")],
            audience="authenticated",
        )
    except Exception:
        # Fall back to HS256 with legacy JWT secret
        if not _SUPABASE_JWT_SECRET:
            raise HTTPException(status_code=401, detail="Token verification failed")
        try:
            payload = jwt.decode(
                token,
                _SUPABASE_JWT_SECRET,
                algorithms=["HS256"],
                audience="authenticated",
            )
        except jwt.ExpiredSignatureError:
            raise HTTPException(status_code=401, detail="Token expired")
        except jwt.InvalidTokenError as e:
            raise HTTPException(status_code=401, detail=f"Invalid token: {e}")
    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(status_code=401, detail="Invalid token: no sub claim")
    return user_id

# ---------------------------------------------------------------------------
# Rate limiting
# ---------------------------------------------------------------------------

def _rate_limit_key(request: Request) -> str:
    """Use authenticated user ID for rate-limit key, fall back to IP."""
    auth = request.headers.get("authorization", "")
    if auth.startswith("Bearer "):
        try:
            token = auth[7:]
            try:
                signing_key = _get_jwks_client().get_signing_key_from_jwt(token)
                header = jwt.get_unverified_header(token)
                payload = jwt.decode(token, signing_key.key, algorithms=[header.get("alg", "ES256")], audience="authenticated")
            except Exception:
                payload = jwt.decode(token, _SUPABASE_JWT_SECRET, algorithms=["HS256"], audience="authenticated")
            return payload.get("sub", get_remote_address(request))
        except Exception:
            pass
    return get_remote_address(request)

limiter = Limiter(key_func=_rate_limit_key)

# ---------------------------------------------------------------------------
# App setup
# ---------------------------------------------------------------------------

app = FastAPI()
app.state.limiter = limiter

@app.exception_handler(RateLimitExceeded)
async def _rate_limit_handler(request: Request, exc: RateLimitExceeded):
    return JSONResponse(
        status_code=429,
        content={"detail": "Too many requests. Please slow down."},
    )

_ALLOWED_ORIGINS = [
    "https://aquaria-ai.com",
    "https://www.aquaria-ai.com",
    "https://aquaria-ai-production.up.railway.app",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=_ALLOWED_ORIGINS,
    allow_methods=["POST", "GET", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)


# ---------------------------------------------------------------------------
# LLM provider toggle: set LLM_PROVIDER=gemini to use Google Gemini
# ---------------------------------------------------------------------------

_LLM_PROVIDER = os.environ.get("LLM_PROVIDER", "anthropic").lower()  # "anthropic" or "gemini"
_GOOGLE_API_KEY = os.environ.get("GOOGLE_API_KEY", "")

_MODEL_HAIKU = "claude-haiku-4-5"
_MODEL_SONNET = "claude-sonnet-4-20250514"

# Gemini model mapping
_GEMINI_MODEL_MAP = {
    "claude-haiku-4-5": "gemini-2.5-flash",
    "claude-sonnet-4-20250514": "gemini-2.5-flash",
}
_GEMINI_DEFAULT_MODEL = "gemini-2.5-flash"


def _pick_model(experience: str = "", water_type: str = "", all_water_types: list = None) -> str:
    """Use Sonnet for all chat/summary requests for best analysis quality."""
    return _MODEL_SONNET


def _get_llm_client():
    """Return an LLM client and True if available, or (None, False).
    For Gemini, the client is a dummy since _chat_gemini creates its own."""
    if _LLM_PROVIDER == "gemini":
        if not _GOOGLE_API_KEY:
            return None, False
        return "gemini", True  # placeholder; _chat_gemini uses the key directly
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        return None, False
    return anthropic.Anthropic(api_key=api_key), True


class _LLMResponse:
    """Provider-agnostic response wrapper so callers don't need to change."""
    def __init__(self, text: str, model: str, input_tokens: int, output_tokens: int,
                 tool_calls: list = None):
        self.content = [type("Block", (), {"text": text})()]
        self.model = model
        self.usage = type("Usage", (), {"input_tokens": input_tokens, "output_tokens": output_tokens})()
        self.tool_calls = tool_calls or []  # List of {"name": str, "input": dict}


def _chat(client, **kwargs):
    """Provider-agnostic LLM call. Dispatches to Anthropic or Gemini based on LLM_PROVIDER."""
    if _LLM_PROVIDER == "gemini":
        return _chat_gemini(**kwargs)
    return _chat_anthropic(client, **kwargs)


def _chat_anthropic(client: anthropic.Anthropic, **kwargs):
    """Call Anthropic messages API with retry on 529."""
    for attempt in range(4):
        try:
            response = client.messages.create(**kwargs)
            _log_api_usage(response.model or kwargs.get("model", ""),
                           response.usage.input_tokens, response.usage.output_tokens)
            # If tools were used, wrap in _LLMResponse with tool_calls extracted
            if kwargs.get("tools"):
                text_parts = []
                tool_calls = []
                for block in response.content:
                    if getattr(block, "type", None) == "text":
                        text_parts.append(block.text)
                    elif getattr(block, "type", None) == "tool_use":
                        tool_calls.append({"name": block.name, "input": block.input})
                return _LLMResponse(
                    text="\n".join(text_parts),
                    model=response.model or kwargs.get("model", ""),
                    input_tokens=response.usage.input_tokens,
                    output_tokens=response.usage.output_tokens,
                    tool_calls=tool_calls,
                )
            return response
        except anthropic.APIStatusError as e:
            if e.status_code == 529 and attempt < 3:
                time.sleep(2 ** attempt)
                continue
            raise


def _chat_gemini(**kwargs):
    """Call Google Gemini API, translating Anthropic-style kwargs."""
    gemini_client = genai.Client(api_key=_GOOGLE_API_KEY)

    # Map Anthropic model to Gemini model
    anthropic_model = kwargs.get("model", _MODEL_SONNET)
    gemini_model = _GEMINI_MODEL_MAP.get(anthropic_model, _GEMINI_DEFAULT_MODEL)

    # Build system instruction from Anthropic's "system" kwarg
    system = kwargs.get("system", "")
    config = {}
    if system:
        # Anthropic sometimes passes system as list-of-dicts (with cache_control); flatten to string
        if isinstance(system, list):
            system = "\n".join(item.get("text", "") for item in system if isinstance(item, dict))
        config["system_instruction"] = system
    if kwargs.get("max_tokens"):
        config["max_output_tokens"] = kwargs["max_tokens"]

    # Translate Anthropic tools to Gemini function declarations
    if kwargs.get("tools"):
        func_decls = []
        for t in kwargs["tools"]:
            schema = t.get("input_schema", {})
            func_decls.append(genai.types.FunctionDeclaration(
                name=t["name"],
                description=t.get("description", ""),
                parameters=_anthropic_schema_to_gemini(schema),
            ))
        config["tools"] = [genai.types.Tool(function_declarations=func_decls)]
        config["tool_config"] = genai.types.ToolConfig(
            function_calling_config=genai.types.FunctionCallingConfig(mode="AUTO"),
        )

    # Convert Anthropic messages to Gemini contents
    messages = kwargs.get("messages", [])
    contents = []
    for msg in messages:
        role = "user" if msg["role"] == "user" else "model"
        contents.append({"role": role, "parts": [{"text": msg["content"]}]})

    response = gemini_client.models.generate_content(
        model=gemini_model,
        contents=contents,
        config=config,
    )

    # Extract text and tool calls from response parts
    text_parts = []
    tool_calls = []
    if response.candidates and response.candidates[0].content:
        for part in response.candidates[0].content.parts:
            if hasattr(part, "function_call") and part.function_call:
                fc = part.function_call
                tool_calls.append({"name": fc.name, "input": dict(fc.args) if fc.args else {}})
            elif hasattr(part, "text") and part.text:
                text_parts.append(part.text)

    text = "\n".join(text_parts) if text_parts else (response.text or "")
    input_tokens = getattr(response.usage_metadata, "prompt_token_count", 0) or 0
    output_tokens = getattr(response.usage_metadata, "candidates_token_count", 0) or 0

    _log_api_usage(gemini_model, input_tokens, output_tokens)

    return _LLMResponse(text=text, model=gemini_model,
                        input_tokens=input_tokens, output_tokens=output_tokens,
                        tool_calls=tool_calls)


def _anthropic_schema_to_gemini(schema: dict) -> dict:
    """Convert Anthropic-style JSON Schema to Gemini-compatible schema dict."""
    # Gemini accepts a subset of JSON Schema via genai.types.Schema
    # but also accepts raw dicts — pass through with minor adjustments
    result = {}
    if "type" in schema:
        result["type"] = schema["type"].upper()  # Gemini expects "OBJECT", "ARRAY", "STRING", etc.
    if "properties" in schema:
        result["properties"] = {
            k: _anthropic_schema_to_gemini(v) for k, v in schema["properties"].items()
        }
    if "items" in schema:
        result["items"] = _anthropic_schema_to_gemini(schema["items"])
    if "required" in schema:
        result["required"] = schema["required"]
    if "enum" in schema:
        result["enum"] = schema["enum"]
    if "description" in schema:
        result["description"] = schema["description"]
    return result


# Cost per million tokens
_COST_PER_M = {
    "claude-haiku-4-5": {"input": 0.80, "output": 4.00},
    "claude-sonnet-4-20250514": {"input": 3.00, "output": 15.00},
    "gemini-2.5-flash": {"input": 0.15, "output": 0.60},
}


def _log_api_usage(model: str, input_tokens: int, output_tokens: int):
    """Log API token usage and cost to Supabase."""
    if not _SUPABASE_SERVICE_KEY:
        return
    try:
        rates = None
        for key, val in _COST_PER_M.items():
            if key in model or model.startswith(key):
                rates = val
                break
        if rates is None:
            rates = {"input": 3.00, "output": 15.00}
        cost = (input_tokens * rates["input"] + output_tokens * rates["output"]) / 1_000_000
        payload = json.dumps({
            "model": model,
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "cost_usd": round(cost, 6),
        }).encode()
        req = urllib.request.Request(
            f"{_SUPABASE_URL}/rest/v1/api_usage",
            data=payload,
            headers={
                "apikey": _SUPABASE_SERVICE_KEY,
                "Authorization": f"Bearer {_SUPABASE_SERVICE_KEY}",
                "Content-Type": "application/json",
                "Prefer": "return=minimal",
            },
            method="POST",
        )
        urllib.request.urlopen(req, timeout=5)
    except Exception as e:
        print(f"[APIUsage] log error: {e}", flush=True)


# ─── Knowledge base (RAG) ────────────────────────────────────────────────────

_KNOWLEDGE_DB_PATH = os.path.join(os.path.dirname(__file__), "knowledge.db")

_SEED_ENTRIES = [
    # New tank / cycling
    ("any", "", "ammonia,nitrite,cycling,new tank", "cycling,new tank",
     "Ammonia or nitrite spiked in a new tank", "Tank is still cycling. Perform daily 20-30% water changes to keep levels safe. Do not add more fish until ammonia and nitrite both read 0 for several consecutive days."),
    ("any", "", "ammonia", "ammonia spike",
     "Ammonia spike in established tank", "Check stocking density, feeding amount, and filter health. Rinse filter media in old tank water (never tap). Do a 25% water change and retest in 24 hours."),
    ("any", "", "nitrite", "nitrite spike",
     "Nitrite elevated above 0 in established tank", "Nitrite spike often follows an ammonia spike. Perform 25% water changes daily until it returns to 0. Avoid adding new fish or plants temporarily."),
    ("any", "", "nitrate", "nitrate high",
     "Nitrate consistently above 40 ppm", "Increase water change frequency to 25% twice weekly. Reduce feeding. Live plants help absorb nitrates long-term."),
    # pH problems
    ("freshwater", "", "ph,kh", "ph crash",
     "pH crashed suddenly in freshwater tank", "Low KH (carbonate hardness) is the usual cause. Add crushed coral or a KH buffer in small increments. Avoid rapid pH correction — aim for no more than 0.2 units per 24 hours."),
    ("saltwater,reef", "", "ph", "ph low reef",
     "pH chronically low in reef or saltwater tank", "Increase surface agitation to improve gas exchange. Run the skimmer with fresh air intake. Adding a refugium with macroalgae on a reverse light cycle raises pH naturally."),
    # Algae
    ("any", "", "algae", "green algae",
     "Green algae on glass and decor", "Normal in a healthy tank. Reduce light duration to 8 hours, cut back feeding, and add a cleanup crew (nerite snails, otocinclus, amano shrimp for freshwater)."),
    ("any", "", "algae", "brown algae diatoms",
     "Brown algae (diatoms) coating surfaces in new tank", "Diatom blooms are normal in new tanks and usually disappear within 4-8 weeks as silicates are consumed. Nerite snails or an otocinclus will clean it quickly."),
    ("any", "", "algae", "green water algae bloom",
     "Green water — entire tank turned green", "Caused by free-floating algae from excess light or nutrients. Run a 3-day blackout (cover tank completely), reduce feeding for a week, and consider a UV steriliser for future prevention."),
    ("any", "", "algae", "bba black beard algae",
     "Black beard algae (BBA) on plants and hardscape", "Usually caused by inconsistent CO2 or low flow. Spot-treat with liquid carbon (Excel) directly on algae using a syringe. Improve circulation near problem areas."),
    ("freshwater", "", "algae,co2", "hair algae",
     "Hair or thread algae overrunning plants", "Caused by high light and low CO2. Reduce lighting to 6-7 hours, increase CO2 if injecting, and add fast-growing plants to out-compete the algae. Amano shrimp graze it heavily."),
    # Disease
    ("any", "fish", "ich,white spots", "ich treatment",
     "White spots on fish (ich / white spot disease)", "Raise temperature gradually to 82-86°F over 48 hours to speed up the parasite lifecycle. Treat with ich medication — avoid copper if invertebrates are present. Continue for 2 weeks after spots disappear."),
    ("any", "fish", "velvet,gold dust", "velvet treatment",
     "Gold or rust-colored dust on fish skin (velvet)", "Velvet is more dangerous than ich. Dim the lights as soon as possible (the parasite is photosensitive). Treat with a copper-based medication in a hospital tank if invertebrates are present."),
    ("any", "fish", "fin rot,fin damage", "fin rot treatment",
     "Fins appear ragged, discolored, or deteriorating", "Often stress or bacterial infection. Improve water quality first — do a 25% water change. Add aquarium salt (1 tsp/gallon) for freshwater fish. If worsening, treat with an antibacterial medication."),
    ("any", "fish", "bloat,dropsy,pinecone scales", "dropsy treatment",
     "Fish bloated with raised scales (pinecone appearance)", "Dropsy is usually organ failure — very difficult to treat. Isolating the fish can reduce stress. Epsom salt (1 tbsp/5 gal) can reduce fluid retention. Antibiotics sometimes help if caught early."),
    ("any", "fish", "swim bladder,floating,sinking", "swim bladder issue",
     "Fish floating upside-down or struggling to maintain depth", "Fast the fish for 2-3 days. If constipation is the cause, feeding a peeled, cooked pea often helps. Avoid overfeeding going forward."),
    # Compatibility
    ("freshwater", "betta", "aggression,fighting", "betta compatibility",
     "Betta attacking or fin-nipping tank mates", "Bettas are territorial. Consider removing long-finned or brightly colored fish. Bottom-dwellers and fast-moving schooling fish fare best. Only one male betta per tank."),
    ("freshwater", "cichlid,oscar,convict", "aggression,fighting,hiding", "cichlid aggression",
     "Aggressive cichlid bullying or injuring other fish", "Add dense cover — rocks, caves, tall plants — to break sightlines. Rearrange decor to reset territories. Consider separating persistent aggressors."),
    ("freshwater", "shrimp,neocaridina,caridina,cherry shrimp", "dying,death,disappearing", "shrimp dying",
     "Shrimp dying or disappearing after water change", "Tap water copper or chloramine can be lethal even in trace amounts. Use a high-quality dechlorinator (Seachem Prime). Check GH/KH — neocaridina prefer GH 6-8 dGH. Match temperature before adding water."),
    # Oxygen / surface
    ("any", "fish", "oxygen,gasping,surface", "low oxygen",
     "Fish gasping at the surface or near the filter output", "Surface agitation is insufficient. Increase filter flow, add an airstone, or lower the water level slightly to increase surface turbulence. Check temperature — warmer water holds less oxygen."),
    # Plants
    ("freshwater", "", "plants,yellowing,melting", "plant melt",
     "Newly added plants melting or yellowing", "Transition melt is normal when plants adjust from emersed (above water) to submersed growth. Trim dead leaves, ensure adequate light (8 hours) and root tabs or liquid fertiliser. New growth should appear within 2-3 weeks."),
    ("freshwater", "", "plants,potassium,holes,yellow edges", "potassium deficiency",
     "Yellow leaf edges with holes in plant leaves", "Classic potassium deficiency. Dose with a liquid potassium fertiliser. Target 10-20 ppm. Easy plants like java fern and anubias rarely show this; stem plants are most affected."),
    # Saltwater / reef
    ("saltwater,reef", "coral", "bleaching,pale,white", "coral bleaching",
     "Coral bleaching or turning pale/white", "Bleaching = loss of zooxanthellae, usually from temperature stress or sudden light change. Reduce light intensity, stabilise temperature (76-78°F), and ensure alkalinity/calcium are in range. Recovery is possible if addressed quickly."),
    ("saltwater,reef", "", "alkalinity,alk,kh", "alk swing reef",
     "Alkalinity swinging or unstable in reef tank", "Large alk swings stress corals severely. Dose in small increments — never raise by more than 1 dKH per day. Two-part or kalkwasser dosed consistently avoids swings better than manual top-ups."),
    ("saltwater,reef", "", "salinity,specific gravity", "salinity too high",
     "Salinity or specific gravity elevated above 1.026", "Evaporation concentrates salt — only top off with fresh RO/DI water, never saltwater. Use an ATO (auto top-off) system to keep evaporation in check."),
    # Cloudiness
    ("any", "", "cloudy,white water,bacterial bloom", "bacterial bloom",
     "Tank water suddenly turned white/milky cloudy", "Bacterial bloom, common in new or recently disturbed tanks. Do not perform a large water change — it feeds the cycle. Ensure filtration is running well, reduce feeding, and the cloudiness usually clears in 2-5 days."),
    ("freshwater", "", "cloudy,green", "green water",
     "Water turned green and cloudy gradually", "Algae bloom from excess light or nutrients. Reduce light to 6 hours, cut feeding in half, do a 25% water change, and consider a UV steriliser."),
    # Smell
    ("any", "", "smell,odor,sulfur,rotten egg", "hydrogen sulfide",
     "Strong sulfur or rotten egg smell from tank", "Hydrogen sulfide from anaerobic pockets in substrate or a dead animal. Gently vacuum the substrate in sections without disturbing it all at once. Check for any hidden dead fish or invertebrates. Increase surface agitation."),
    # Temperature
    ("any", "", "temperature,heater,heat", "heater failure",
     "Temperature dropped suddenly or heater appears to have failed", "The heater should be replaced. When reheating, do it slowly — no more than 2°F per hour. Cold shock stresses fish as much as heat shock does."),
]


def _init_knowledge_db() -> None:
    conn = sqlite3.connect(_KNOWLEDGE_DB_PATH)
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS knowledge_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            water_type TEXT NOT NULL DEFAULT 'any',
            species_tags TEXT NOT NULL DEFAULT '',
            parameter_tags TEXT NOT NULL DEFAULT '',
            topic_tags TEXT NOT NULL DEFAULT '',
            observation TEXT NOT NULL,
            resolution TEXT NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            is_seed INTEGER DEFAULT 0
        )
    """)
    # Only seed if the table is empty
    cur.execute("SELECT COUNT(*) FROM knowledge_entries WHERE is_seed = 1")
    if cur.fetchone()[0] == 0:
        cur.executemany(
            "INSERT INTO knowledge_entries (water_type, species_tags, parameter_tags, topic_tags, observation, resolution, is_seed) VALUES (?,?,?,?,?,?,1)",
            _SEED_ENTRIES,
        )
    # Feedback table
    cur.execute("""
        CREATE TABLE IF NOT EXISTS feedback (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            message TEXT NOT NULL,
            device TEXT,
            attachment_name TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
    """)
    conn.commit()
    conn.close()
    print("[Knowledge] DB initialised")


_init_knowledge_db()


def _search_knowledge(message: str, water_type: str, species: List[str], max_results: int = 2) -> str:
    """Keyword-match the knowledge base and return formatted context for the prompt."""
    msg_words = set(re.findall(r'\b\w+\b', message.lower()))
    wt = water_type.lower() if water_type else "freshwater"
    species_lower = [s.lower() for s in species]

    try:
        conn = sqlite3.connect(_KNOWLEDGE_DB_PATH)
        cur = conn.cursor()
        cur.execute(
            "SELECT water_type, species_tags, parameter_tags, topic_tags, observation, resolution "
            "FROM knowledge_entries "
            "WHERE water_type = 'any' OR water_type LIKE ?",
            (f"%{wt}%",),
        )
        rows = cur.fetchall()
        conn.close()
    except Exception as e:
        print(f"[Knowledge] search error: {e}")
        return ""

    scored: List[tuple] = []
    for row_wt, sp_tags, param_tags, topic_tags, observation, resolution in rows:
        score = 0
        # Species overlap — high weight
        if sp_tags:
            for tag in sp_tags.split(","):
                tag = tag.strip().lower()
                if tag and any(tag in s or s in tag for s in species_lower):
                    score += 3
        # Parameter + topic keyword match against message
        for tag_str in (param_tags, topic_tags):
            if tag_str:
                for tag in tag_str.split(","):
                    tag = tag.strip().lower()
                    if tag and tag in msg_words:
                        score += 2
        if score > 0:
            scored.append((score, observation, resolution))

    scored.sort(reverse=True)
    top = scored[:max_results]
    if not top:
        return ""

    lines = ["Relevant patterns from other Aquaria users:"]
    for _, obs, res in top:
        lines.append(f"• {obs} → {res}")
    return "\n".join(lines)


# -------------------------
# Request models
# -------------------------
class ParseRequest(BaseModel):
    text: str
    context: Optional[str] = None  # Recent conversation context for resolving ambiguous references
    client_date: Optional[str] = None  # Device-local date (YYYY-MM-DD) — preferred over server date


class AdviseRequest(BaseModel):
    tank: Optional[Dict[str, Any]] = None
    initial: Optional[Dict[str, Any]] = None


class SummaryRequest(BaseModel):
    logs: List[Dict[str, Any]]
    water_type: Optional[str] = None  # 'freshwater', 'saltwater', 'reef', etc.
    gallons: Optional[int] = None
    equipment: Optional[Dict[str, Any]] = None
    inhabitants: Optional[List[str]] = None
    plants: Optional[List[str]] = None


class ChatRequest(BaseModel):
    tank: Optional[Dict[str, Any]] = None
    available_tanks: Optional[List[str]] = None
    available_tanks_detail: Optional[List[Dict[str, Any]]] = None
    message: str
    history: Optional[List[Dict[str, Any]]] = None
    recent_logs: Optional[List[str]] = None
    system_context: Optional[str] = None
    health_profile: Optional[Dict[str, Any]] = None
    behavior_profile: Optional[Dict[str, Any]] = None
    session_summaries: Optional[List[str]] = None
    experience_level: Optional[str] = None  # 'beginner', 'intermediate', 'advanced'
    extract_tasks_only: Optional[bool] = False
    client_date: Optional[str] = None  # Device-local date (YYYY-MM-DD)


class SummarizeSessionRequest(BaseModel):
    messages: List[Dict[str, Any]]
    tank_name: Optional[str] = None


class FeedbackRequest(BaseModel):
    message: str
    device: Optional[str] = None


class ModerationRequest(BaseModel):
    tasks: List[str]


class KnowledgeIngestRequest(BaseModel):
    water_type: str = "any"
    species_tags: str = ""       # comma-separated, e.g. "betta,neon tetra"
    parameter_tags: str = ""     # comma-separated, e.g. "ammonia,nitrite"
    topic_tags: str = ""         # comma-separated, e.g. "algae,cycling"
    observation: str
    resolution: str


# -------------------------
# Simple (non-AI) extractors
# -------------------------
def extract_name(text: str) -> Optional[str]:
    # Matches:
    # "name: Living Room Tank"
    # "named Living Room Tank"
    # "called Living Room Tank"
    m = re.search(
        r'(?:\bname\b\s*[:=-]\s*|\bnamed\b\s+|\bcalled\b\s+)(["\']?)([^"\',\n.;]+)\1',
        text,
        flags=re.IGNORECASE,
    )
    if not m:
        return None
    name = m.group(2).strip()
    return name if name else None


def extract_gallons(text: str) -> Optional[int]:
    """
    Extract gallons from text like:
      - "95 gallon"
      - "95 gallons"
      - "95 gal"
      - "95g"
    """
    m = re.search(r"\b(\d{1,4})\s*(gallons?|gal|g)\b", text.lower())
    return int(m.group(1)) if m else None


def extract_water_type(text: str) -> str:
    """
    Infer water type from keywords.
    Defaults to freshwater.
    """
    t = text.lower()
    if "saltwater" in t or "salt water" in t or "reef" in t or "marine" in t:
        return "saltwater"
    return "freshwater"


def extract_plants(text: str) -> List[str]:
    """
    Very naive plant extraction:
    If user writes "plants: anubias, java fern" we split on commas.
    """
    t = text.lower()
    m = re.search(r"plants?\s*:\s*([^\n]+)", t)
    if not m:
        return []
    raw = m.group(1)
    parts = [p.strip() for p in raw.split(",")]
    return [p for p in parts if p]


def extract_inhabitants(text: str) -> List[Dict[str, Any]]:
    """
    Very naive inhabitants extraction:
    Matches patterns like "8 neon tetras" or "2 clownfish".
    """
    t = text.lower()
    out: List[Dict[str, Any]] = []

    for m in re.finditer(r"\b(\d{1,3})\s+([a-z][a-z\s\-]{1,40})\b", t):
        count = int(m.group(1))
        name = m.group(2).strip()

        # Avoid obvious non-inhabitant matches
        if any(
            k in name
            for k in ["gallon", "gallons", "gal", "plants", "freshwater", "saltwater"]
        ):
            continue

        # Deduplicate exact repeats
        if any(x.get("name") == name and x.get("count") == count for x in out):
            continue

        out.append({"name": name, "count": count})

    return out


_INHABITANTS_SYSTEM_PROMPT = """Parse the aquarium inhabitants description and return JSON.

Categorize each organism with one of these types:
- "fish"         — any fish species
- "invertebrate" — shrimp, snails, crabs, starfish, urchins, etc.
- "coral"        — hard corals (LPS, SPS), soft corals
- "polyp"        — zoanthids, palythoa, mushroom corals
- "anemone"      — all anemone species
- "plant"        — aquatic plants, macroalgae, moss

Return ONLY valid JSON — no markdown, no code fences:
{
  "inhabitants": [
    {"name": "Neon Tetra", "count": 10, "type": "fish"},
    {"name": "Cherry Shrimp", "count": 5, "type": "invertebrate"},
    {"name": "Hammer Coral", "count": 2, "type": "coral"},
    {"name": "Zoanthid", "count": 1, "type": "polyp"},
    {"name": "Bubble Tip Anemone", "count": 1, "type": "anemone"},
    {"name": "Java Fern", "count": 1, "type": "plant"}
  ]
}

Rules:
- If no count is mentioned, use 1
- Use Title Case for species names (e.g. "Neon Tetra" not "neon tetra")
- Use singular species names (e.g. "Neon Tetra" not "Neon Tetras")
- Include every organism mentioned
- Empty or irrelevant input: return {"inhabitants": []}"""


def _parse_inhabitants_with_llm(text: str) -> Optional[List[Dict[str, Any]]]:
    """Call Claude to parse and categorize inhabitants. Returns None on failure."""
    client, available = _get_llm_client()
    if not available:
        return None
    try:
        response = _chat(client,
            model="claude-haiku-4-5",
            max_tokens=512,
            system=_INHABITANTS_SYSTEM_PROMPT,
            messages=[{"role": "user", "content": text}],
        )
        raw = response.content[0].text.strip()
        raw = re.sub(r"^```(?:json)?\s*", "", raw)
        raw = re.sub(r"\s*```$", "", raw).strip()
        parsed = json.loads(raw)
        return parsed.get("inhabitants", [])
    except Exception as e:
        print(f"[LLM inhabitants] error: {e}")
        return None


# -------------------------
# Routes
# -------------------------
@app.post("/parse/tank-note")
@limiter.limit("30/minute")
def parse_tank_note(request: Request, req: ParseRequest, user_id: str = Depends(_get_user_id)):
    text = (req.text or "").strip()

    # Try LLM parsing first for grouped/typed inhabitants
    all_items = _parse_inhabitants_with_llm(text)

    if all_items is not None:
        inhabitants = [i for i in all_items if i.get("type") != "plant"]
        plants = [i["name"] for i in all_items if i.get("type") == "plant"]
    else:
        # Regex fallback
        inhabitants = extract_inhabitants(text)
        plants = extract_plants(text)

    return {
        "schemaVersion": 1,
        "tank": {"name": None, "gallons": None, "waterType": None},
        "initial": {"inhabitants": inhabitants, "plants": plants},
        "confidence": {
            "inhabitants": 0.85 if all_items is not None else 0.3,
            "plants": 0.85 if all_items is not None else 0.3,
        },
        "warnings": [],
    }


def _extract_params(fragment: str, params: Dict[str, Any]) -> bool:
    """
    Try to extract a hard measurement from the fragment.
    Returns True if something was matched.
    All of these require a keyword AND a numeric value.
    """
    matched = False

    checks = [
        (r"\bph\s*[:=]?\s*([\d.]+)", "pH", float),
        (r"\bkh\s*[:=]?\s*([\d.]+)", "KH", float),
        (r"\bgh\s*[:=]?\s*([\d.]+)", "GH", float),
        (r"\b(?:ca|calcium)\s*[:=]?\s*([\d.]+)", "Ca", float),
        (r"\b(?:mg|magnesium)\s*[:=]?\s*([\d.]+)", "Mg", float),
        (r"\bammonia\s*[:=]?\s*([\d.]+)|\bnh[34]\s*[:=]?\s*([\d.]+)", "ammonia", float),
        (r"\bnitrite\s*[:=]?\s*([\d.]+)|\bno2\s*[:=]?\s*([\d.]+)", "nitrite", float),
        (r"\bnitrate\s*[:=]?\s*([\d.]+)|\bno3\s*[:=]?\s*([\d.]+)", "nitrate", float),
        (r"\b(?:potassium|k)\s*[:=]?\s*([\d.]+)", "K", float),
        (r"\bsalinity\s*[:=]?\s*([\d.]+)", "salinity", float),
    ]
    for pattern, key, cast in checks:
        m = re.search(pattern, fragment, re.IGNORECASE)
        if m:
            val = next(v for v in m.groups() if v is not None)
            params[key] = cast(val)
            matched = True

    # Temperature: "78F", "26C", "78°F", "temp 26C"
    m = re.search(r"([\d.]+)\s*°?\s*([fc])\b", fragment, re.IGNORECASE)
    if m:
        params["temp"] = f"{m.group(1)}°{m.group(2).upper()}"
        matched = True

    return matched


_ACTION_VERBS = re.compile(
    r"\b(?:"
    r"add|added|adds|"
    r"dose|dosed|doses|"
    r"fed|feed|feeding|"
    r"food|"
    r"water\s+change|"
    r"clean|cleaned|"
    r"trim|trimmed|"
    r"prune|pruned|"
    r"scrape|scraped|"
    r"siphon|siphoned|"
    r"vacuum|vacuumed|"
    r"replace|replaced|"
    r"remove|removed|"
    r"install|installed|"
    r"fertilize|fertilized|fertilizer|"
    r"medicate|medicated|medication|"
    r"treat|treated|treatment|"
    r"top\s+off|topped\s+off"
    r")\b",
    re.IGNORECASE,
)

_DOSE_QUANTITY = re.compile(
    r"\b\d+\s*(?:ml|mg|g|gal|gallons?|l|liters?|tsp|tbsp|drops?)\b",
    re.IGNORECASE,
)


def _is_action(fragment: str) -> bool:
    """
    Returns True if the fragment describes something the user actively did.
    Signals: action verbs, or a dosing quantity (number + volume/weight unit).
    """
    return bool(_ACTION_VERBS.search(fragment) or _DOSE_QUANTITY.search(fragment))


_LOG_SYSTEM_PROMPT = """You parse aquarium tank journal entries by calling the appropriate tools. You may call multiple tools in one response.

RULES:
1. Only log content related to the aquarium hobby. Off-topic → call no tools.
2. Questions are NEVER loggable. Numbers in questions are hypothetical, not readings. If a message mixes facts and questions, log only the factual parts.
3. Short replies with no tank data ("yes", "ok", "no") → call no tools.
4. Requests to create/name a tank or add inhabitants → call no tools (handled elsewhere).
5. Actions: things the user physically DID. Use short form with quantities when available ("5ml Prime", "20% water change", "Cleaned filter").
6. Notes: observations — visual, olfactory, behavioral, condition, deaths, smells, cloudiness, qualitative trends.
7. Measurements: extract numeric values for known parameters (pH, KH, GH, Ca, Mg, ammonia, nitrite, nitrate, K, salinity, temp). If a sentence has both qualitative language AND a number (e.g. "GH went wild to 10"), log the number as a measurement AND the qualitative part as a note.
8. Tasks: aquarium-related scheduling/reminders only. Compute absolute due dates from relative references.
9. SINGLE-ENTRY: combine everything from a single date into one set of tool calls. Only use separate tool calls with different dates if the user explicitly references different dates.
10. SERIES: When the user provides measurements from distinct contexts on the same day (e.g. before vs after a water change, morning vs evening, pre-dose vs post-dose), call log_measurements MULTIPLE times with different series_label values. For example: log_measurements(series_label="Before water change", ph=9, nitrate=35) and log_measurements(series_label="After water change", ph=8, nitrate=15). Only use series when the user clearly distinguishes contexts — do NOT create series for a single set of readings.
11. If the message has no loggable content, respond with a short text explanation and call no tools.
12. Parameter aliases: "General Hardness"/hardness = GH, "carbonate hardness" = KH, NH3 = ammonia, NO2 = nitrite, NO3 = nitrate, potassium = K, calcium = Ca, magnesium = Mg."""


def _build_parse_tools(today: str) -> list:
    """Build tool definitions for the parse endpoint."""
    return [
        {
            "name": "log_measurements",
            "description": f"Log numeric water parameter measurements. Today is {today}. "
                "Use standard keys: pH, KH, GH, Ca, Mg, ammonia, nitrite, nitrate, K, salinity, temp. "
                "Temp should include unit like '78°F' or '26°C'. All others are numeric. "
                "If measurements reference a past date, set the date field. "
                "Relative dates: 'last week' = 7 days ago, 'yesterday' = 1 day ago, etc. "
                "Use series_label when the user provides distinct measurement contexts on the same day "
                "(e.g. 'Before water change', 'After water change', 'Morning', 'Evening'). "
                "Call this tool MULTIPLE times with different series_label values to create separate series.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "measurements": {
                        "type": "object",
                        "description": "Key-value pairs of parameter name to value. Keys: pH, KH, GH, Ca, Mg, ammonia, nitrite, nitrate, K, salinity, temp.",
                    },
                    "date": {
                        "type": "string",
                        "description": "YYYY-MM-DD date for these measurements. null if not specified.",
                        "nullable": True,
                    },
                    "series_label": {
                        "type": "string",
                        "description": "Label for this measurement series (e.g. 'Before water change', 'After water change', 'Morning', 'Evening'). Omit if only one set of readings.",
                        "nullable": True,
                    },
                    "is_tap_water": {
                        "type": "boolean",
                        "description": "Set to true if these measurements are from tap/source/municipal/faucet water (not tank water). Omit or false for normal tank readings.",
                        "nullable": True,
                    },
                },
                "required": ["measurements"],
            },
        },
        {
            "name": "log_actions",
            "description": "Log maintenance actions the user physically performed on the tank. "
                "Use short, concise descriptions. Include quantities when provided. "
                "Examples: '5ml Prime', '20% water change', 'Cleaned filter', 'Fed fish', 'Trimmed plants'.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "actions": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "List of action descriptions in short form.",
                    },
                    "date": {
                        "type": "string",
                        "description": "YYYY-MM-DD date for these actions. null if not specified.",
                        "nullable": True,
                    },
                },
                "required": ["actions"],
            },
        },
        {
            "name": "log_notes",
            "description": "Log observations the user noticed about their tank. "
                "Visual, olfactory, behavioral, condition notes. Includes deaths, smells, cloudiness, qualitative trends. "
                "NEVER log questions as notes.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "notes": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "List of observation strings.",
                    },
                    "date": {
                        "type": "string",
                        "description": "YYYY-MM-DD date for these notes. null if not specified.",
                        "nullable": True,
                    },
                },
                "required": ["notes"],
            },
        },
        {
            "name": "schedule_task",
            "description": f"Schedule an aquarium-related reminder or task. Today is {today}. "
                "Compute absolute due dates: tomorrow = today+1, next week = today+7, in N days = today+N. "
                "Only for aquarium care tasks — not personal reminders.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "description": {
                        "type": "string",
                        "description": "Short task description.",
                    },
                    "due_date": {
                        "type": "string",
                        "description": "YYYY-MM-DD due date. null if vague or unspecified.",
                        "nullable": True,
                    },
                },
                "required": ["description"],
            },
        },
    ]



_MONTH_NAMES = {
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
    "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    "january": 1, "february": 2, "march": 3, "april": 4, "june": 6,
    "july": 7, "august": 8, "september": 9, "october": 10, "november": 11, "december": 12,
}


def _extract_date_regex(text: str, client_date: Optional[str] = None) -> Optional[str]:
    """Extract a date from common formats like 2.21.26, 2/21/2026, Feb 21, etc."""
    today = date.fromisoformat(client_date) if client_date else date.today()

    # M.D.YY, M/D/YY, M-D-YY, M.D.YYYY etc.
    m = re.search(r'\b(\d{1,2})[./\-](\d{1,2})[./\-](\d{2,4})\b', text)
    if m:
        month, day, year = int(m.group(1)), int(m.group(2)), int(m.group(3))
        if year < 100:
            year += 2000
        try:
            return date(year, month, day).isoformat()
        except ValueError:
            pass

    # "Feb 21" or "February 21" optionally followed by a 4-digit year
    month_pattern = '|'.join(_MONTH_NAMES.keys())
    m = re.search(rf'\b({month_pattern})\s+(\d{{1,2}})(?:\s+(\d{{4}}))?\b', text, re.IGNORECASE)
    if m:
        month = _MONTH_NAMES[m.group(1).lower()]
        day = int(m.group(2))
        year = int(m.group(3)) if m.group(3) else today.year
        try:
            d = date(year, month, day)
            if m.group(3) is None and d > today:
                d = date(year - 1, month, day)
            return d.isoformat()
        except ValueError:
            pass

    return None


def _sentence_case(s: str) -> str:
    """Capitalize the first letter of a string, leave rest as-is."""
    if not s:
        return s
    return s[0].upper() + s[1:]


def _parse_with_llm(text: str, today: str, context: Optional[str] = None) -> Optional[List[Dict[str, Any]]]:
    """Call LLM with tool calling to parse the log entry. Returns a list of log dicts, or None on failure."""
    client, available = _get_llm_client()
    if not available:
        print("[LLM] No LLM API key set — using regex fallback")
        return None
    try:
        system = _LOG_SYSTEM_PROMPT + f"\n\nToday's date is {today}."
        if context:
            system += f"\n\nRecent conversation context (use this to resolve ambiguous references in the user's message):\n{context}"
        tools = _build_parse_tools(today)
        response = _chat(client,
            model="claude-haiku-4-5",
            max_tokens=1024,
            system=system,
            messages=[{"role": "user", "content": text}],
            tools=tools,
            tool_choice={"type": "auto"},
        )
        tool_calls = getattr(response, "tool_calls", []) or []
        if not tool_calls:
            # No tools called = nothing loggable (question, off-topic, etc.)
            print(f"[LLM parse] no tools called — nothing to log")
            return [{"schemaVersion": 1, "measurements": {}, "actions": [], "notes": [], "tasks": [], "date": None}]

        # Group tool calls by date to support multi-date entries
        date_entries: Dict[Optional[str], Dict[str, Any]] = {}
        # Track measurement series per date: date -> list of (label, measurements)
        date_series: Dict[Optional[str], list] = {}

        def _get_entry(d: Optional[str]) -> Dict[str, Any]:
            if d not in date_entries:
                date_entries[d] = {"schemaVersion": 1, "measurements": {}, "actions": [], "notes": [], "tasks": [], "date": d}
            return date_entries[d]

        for tc in tool_calls:
            name = tc["name"]
            inp = tc.get("input", {})
            entry_date = inp.get("date")

            if name == "log_measurements" and inp.get("measurements"):
                entry = _get_entry(entry_date)
                if inp.get("is_tap_water"):
                    entry["source"] = "tap_water"
                series_label = inp.get("series_label")
                if entry_date not in date_series:
                    date_series[entry_date] = []
                date_series[entry_date].append({"_label": series_label, **inp["measurements"]})
            elif name == "log_actions" and inp.get("actions"):
                entry = _get_entry(entry_date)
                entry["actions"].extend([_sentence_case(a) for a in inp["actions"]])
            elif name == "log_notes" and inp.get("notes"):
                entry = _get_entry(entry_date)
                entry["notes"].extend([_sentence_case(n) for n in inp["notes"]])
            elif name == "schedule_task":
                entry = _get_entry(None)  # tasks go on the "no date" entry
                entry["tasks"].append({
                    "description": inp.get("description", ""),
                    "due_date": inp.get("due_date"),
                })

        # Build measurements: use _series format if multiple series exist, flat otherwise
        for d, series_list in date_series.items():
            entry = date_entries[d]
            has_labels = any(s.get("_label") for s in series_list)
            if len(series_list) > 1 or has_labels:
                entry["measurements"] = {"_series": series_list}
            else:
                # Single unlabeled series — keep flat for backward compatibility
                flat = {k: v for k, v in series_list[0].items() if k != "_label"}
                entry["measurements"] = flat

        result = list(date_entries.values())
        return result if result else None
    except Exception as e:
        print(f"[LLM] error: {e} — using regex fallback")
        return None


def _parse_with_regex(text: str) -> List[Dict[str, Any]]:
    """Regex fallback parser. Returns a single-item list."""
    params: Dict[str, Any] = {}
    actions: List[str] = []
    notes: List[str] = []
    fragments = [f.strip() for f in re.split(r"[,;]|\band\b", text, flags=re.IGNORECASE) if f.strip()]
    for fragment in fragments:
        if _extract_params(fragment, params):
            continue
        if _is_action(fragment):
            actions.append(_sentence_case(fragment))
        else:
            notes.append(_sentence_case(fragment))
    return [{"schemaVersion": 1, "measurements": params, "actions": actions, "notes": notes, "date": None}]


@app.post("/parse/tank-log")
@limiter.limit("30/minute")
def parse_tank_log(request: Request, req: ParseRequest, user_id: str = Depends(_get_user_id)):
    text = (req.text or "").strip()
    today = req.client_date or date.today().isoformat()
    logs = _parse_with_llm(text, today, context=req.context)
    if logs is None:
        logs = _parse_with_regex(text)
        logs[0]["date"] = _extract_date_regex(text, client_date=req.client_date)
    return {"logs": logs}


_SUMMARY_SYSTEM_PROMPT = """You are a concise aquarium assistant. Given recent tank journal entries, write a 2-3 sentence summary of the tank's current status. Focus on the most recent measurements, any logged concerns (deaths, high parameters, unusual smells), and recent maintenance. Be direct. Return ONLY the summary text — no JSON, no bullet points, no formatting. Default to American English spelling, but if the user writes in a different language, respond in that language.

Rules:
- Summarize only. Do NOT ask questions. Do NOT request clarification. Do NOT prompt the user for more information.
- Do NOT describe yourself, your capabilities, or your limitations. Never say what you can or cannot do.
- Do NOT invite the user to share data or explain how to use the app.
- If the logs contain no useful aquarium data, return exactly: "No data logged yet."
- Do not provide detailed advice or troubleshooting steps. However, you MAY note when a water change appears due (e.g. based on high nitrate or time since last change) or when updated measurements would be helpful (e.g. if the most recent readings are stale).
- keep the summary to 3-4 sentences max. Focus on the most important points.
- You may indicate whether measurements are high, low, or in range. Use moderate language like "high", "low", "a bit elevated", or "on the low side". Do NOT use intense or alarming words like "extremely", "severely", "massively", "dangerously", "critically", or "immediately".
- Do not make statements inferring accuracy.
- IMPORTANT: When notes or actions mention corrective measures taken AFTER the measurements (e.g., "added epsom salt", "dosed magnesium", "did a water change after testing"), factor these into your assessment. Do NOT flag a parameter as needing attention if the user has already taken corrective action for it. For example, if measurements show low magnesium but a note says "added epsom salt after testing", acknowledge the correction rather than warning about low magnesium.
- If the logs indicate a recent unresolved problem, mention it without speculating on causes or solutions.
- Use these reference ranges as GUIDELINES when characterizing parameter levels as low, normal, or high. The tank's water type determines which set applies. IMPORTANT: These are general defaults. When specific fish or plant species are known, their preferred ranges carry slightly more weight. If a species preference conflicts with the general range, prioritize the species preference.

  FRESHWATER (non-planted / fish-only):
    ammonia: 0 ppm ideal, ≥0.25 ppm alert. Any reading above 0 indicates a failure in biological filtration.
    nitrite: 0 ppm ideal, ≥0.25 ppm alert. Prevents oxygen transport in fish blood; must be zero in a cycled tank.
    nitrate: 0–20 ppm normal, >40 ppm high. Accumulates over time; managed via water changes.
    pH: 6.5–8.2 normal. Stability is more important than a specific number — avoid swings >0.3 per day. A constant 8.0 is safer than a fluctuating 7.0.
    KH (carbonate hardness): 4–8 dKH normal. Below 3 dKH the tank is at risk of a pH crash.
    GH (general hardness): 4–12 dGH normal. Target depends on species origin.
    temperature: 74–80°F / 23–27°C normal. Cold-water species may prefer lower temperatures — consult species preferences.
    phosphate: 0–0.5 ppm normal, >1 ppm high
    potassium: 10–20 ppm normal
    iron: 0.05–0.1 ppm normal

  PLANTED FRESHWATER (apply when water_type is "planted" or tank has live plants):
    ammonia: 0 ppm ideal (any detectable amount is problematic)
    nitrite: 0 ppm ideal (any detectable amount is problematic)
    CO2: 25–35 ppm ideal. Aim for a 1.0 pH drop from the degassed baseline.
    nitrate (NO3): 5–15 ppm ideal. Leaner is better for red plants; higher for dense jungle growth.
    phosphate (PO4): 0.5–2 ppm ideal. Low phosphate promotes Green Spot Algae (GSA).
    GH: 4–7 dGH ideal. Higher GH is acceptable if stable.
    KH: 1–4 dKH ideal. Low KH allows easier pH swings for CO2 efficiency.
    iron (Fe): ~0.1 ppm target (trace level). Higher can fuel hair algae.
    potassium (K): 15–25 ppm ideal. Higher can cause nutrient uptake lockout.
    calcium (Ca): Do NOT evaluate using raw ppm. Always assess using the Ca:Mg ratio. If Ca:Mg is 3:1–4:1, calcium is in range regardless of the absolute number. If the ratio is ABOVE 4:1, magnesium is too low — recommend a magnesium supplement (e.g. Seachem Equilibrium, Epsom salt). If the ratio is BELOW 3:1, calcium is too low relative to magnesium.
    magnesium (Mg): NOT directly tested — it is calculated from GH and Ca. The app computes Mg automatically when both GH and Ca are logged for the same day. Do NOT ask the user to "test magnesium" or "retest Mg" — instead ask them to test GH and Ca, which is how Mg is derived. Do NOT evaluate using raw ppm. Always assess using the Ca:Mg ratio. If Ca:Mg is 3:1–4:1, magnesium is in range. If the ratio is ABOVE 4:1, magnesium is low — flag this and recommend supplementation.
    temperature: 74–80°F / 23–27°C normal

  PLANTED TANK NUTRIENT ANALYSIS:
  Magnesium is NOT directly testable in a standard freshwater kit — it is calculated from GH and Ca measured on the same day.
  Mg (ppm) ≈ (GH in ppm CaCO₃ − Ca in ppm × 2.5) / 4.12
  If the calculated Mg is zero or negative, note a potential testing inconsistency.
  CRITICAL: Always evaluate Ca and Mg using the Ca:Mg RATIO, never the raw numbers alone.
  - Ratio 3:1–4:1 → GOOD. Both Ca and Mg are in range. Do NOT flag either as low or high.
  - Ratio ABOVE 4:1 → Mg is LOW. Flag this and recommend a magnesium supplement for optimal plant health. Example: Ca 70, Mg ~5 = 13:1 ratio — Mg is very low.
  - Ratio BELOW 3:1 → Ca is LOW relative to Mg. Flag this and suggest calcium supplementation.
  - Ratio ABOVE 6:1 or BELOW 1:1 → LOCKOUT RISK. Proactively warn about nutrient lockout.

  SALTWATER / REEF (mixed reef):
    ammonia: 0 ppm ideal (any detectable amount is problematic)
    nitrite: 0 ppm ideal (any detectable amount is problematic)
    salinity: 1.024–1.026 SG / 35 ppt ideal. Use a refractometer calibrated with 35 ppt solution, not RO/DI water.
    alkalinity (KH): 8.0–9.0 dKH ideal (8.5 target). The most important parameter for SPS. Avoid swings >0.5 dKH/day.
    calcium: 400–450 ppm ideal (425 target). Required for skeletal growth. >450 offers no benefit and risks precipitation.
    magnesium: 1280–1400 ppm ideal (1350 target). Keeps Ca and KH in solution — without adequate Mg, Ca and KH will precipitate out ("snow").
    nitrate: 1–10 ppm ideal (5 target). Ultra-low (0.0) leads to coral bleaching/starvation. FOWLR: <20 ppm acceptable.
    phosphate: 0.01–0.10 ppm ideal (0.03 target). High PO4 inhibits calcification and fuels algae. <0.01 can cause dinoflagellates.
    pH: 8.1–8.4 normal (8.3 ideal). Higher pH (8.3+) significantly accelerates coral growth rates.
    potassium: 380–420 ppm normal
    temperature: 76–80°F / 24–27°C normal

  SALTWATER FISH-ONLY / FOWLR (apply when saltwater tank has no corals):
    ammonia: 0 ppm ideal (any detectable amount is problematic)
    nitrite: 0 ppm ideal (any detectable amount is problematic)
    salinity: 1.020–1.025 SG normal. Stability is more important than the specific number — match your salt mix.
    nitrate: 5–40 ppm acceptable. FOWLR tanks run "dirtier" than reefs; high levels only stress fish long-term.
    pH: 8.0–8.4 normal. Lower salinity can lead to lower pH; ensure high surface agitation.
    KH (alkalinity): 7–11 dKH normal. No need to dose unless pH is consistently dropping below 7.8.
    temperature: 76–80°F / 24–27°C normal

  STABILITY GUARDRAIL (applies to ALL tanks — freshwater and saltwater):
  pH, GH, KH, and temperature must be adjusted gradually. Never recommend changes that would materially shift any of these parameters within a single day. Advise small, incremental adjustments over multiple days or weeks. A stable "wrong" number is almost always safer than a rapid correction to the "right" number.

- When measurements are provided in ml, treat them as actions (dosing), not tank parameter measurements.
- When measurements are provided in ppm, degrees, or similar units, treat them as tank parameters.
- If the user logged something vague (e.g. "phosphates are high" with no number), simply note it was logged as an observation — do not ask for a number.
"""


@app.post("/summary/tank-logs")
@limiter.limit("20/minute")
def summarize_tank_logs(request: Request, req: SummaryRequest, user_id: str = Depends(_get_user_id)):
    if not req.logs:
        return {"summary": None}

    lines = []
    for log in req.logs[:10]:
        text = log.get("text", "")
        parsed_str = log.get("parsed", "")
        # Reconstruct from parsed JSON if text is empty or just a placeholder
        if parsed_str and (not text or text.strip().lower() in ("csv import", "")):
            # Reconstruct a readable summary from the parsed JSON
            try:
                import json as _json
                parsed = _json.loads(parsed_str) if isinstance(parsed_str, str) else parsed_str
                parts = []
                if parsed.get("date"):
                    parts.append(f"Date: {parsed['date']}")
                if parsed.get("measurements"):
                    parts.append("Measurements: " + ", ".join(
                        f"{k}={v}" for k, v in parsed["measurements"].items()
                    ))
                if parsed.get("notes"):
                    parts.append("Notes: " + "; ".join(parsed["notes"]))
                if parsed.get("actions"):
                    parts.append("Actions: " + "; ".join(parsed["actions"]))
                if parsed.get("observations"):
                    parts.append("Observations: " + "; ".join(parsed["observations"]))
                text = " | ".join(parts) if parts else ""
            except Exception:
                pass
        if text:
            lines.append(f"- {text}")
    entries = "\n".join(lines)
    if not entries.strip():
        return {"summary": None}

    client, available = _get_llm_client()
    if not available:
        return {"summary": None}

    try:
        system_prompt = _SUMMARY_SYSTEM_PROMPT
        if req.water_type:
            system_prompt += f"\n\nThis is a {req.water_type} tank"
            if req.gallons:
                system_prompt += f" ({req.gallons} gallons)"
            system_prompt += ". Use the corresponding reference ranges above to evaluate parameters."
        if req.inhabitants:
            system_prompt += f"\nInhabitants: {', '.join(req.inhabitants)}. Consider their species-specific preferences when evaluating parameters."
        if req.plants:
            system_prompt += f"\nPlants: {', '.join(req.plants)}."
        if req.equipment and isinstance(req.equipment, dict):
            eq_parts = []
            # Substrate (now a list)
            substrate = req.equipment.get("substrate")
            if substrate:
                if isinstance(substrate, list):
                    sub_names = [s.replace("_", " ").title() for s in substrate if s != "other"]
                    other = req.equipment.get("substrate_other")
                    if other and isinstance(other, str) and other.strip():
                        sub_names.append(other.strip())
                    if sub_names:
                        eq_parts.append(f"Substrate: {', '.join(sub_names)}")
                elif isinstance(substrate, str):
                    eq_parts.append(f"Substrate: {substrate.replace('_', ' ').title()}")
            label_map = {
                "lighting_type": "Lighting", "filter_type": "Filter",
                "photoperiod_hours": "Photoperiod", "target_temp": "Target temp",
                "wc_frequency": "Water change frequency", "wc_percent": "Water change amount",
            }
            bool_labels = {
                "has_heater": "Heater", "has_air_pump": "Air pump", "has_co2": "CO2 injection",
                "has_protein_skimmer": "Protein skimmer",
                "has_calcium_reactor": "Calcium reactor", "has_wavemaker": "Wavemaker/powerhead",
                "has_ato": "Auto top-off (ATO)", "has_dosing_pump": "Dosing pump",
                "has_refugium": "Refugium/sump", "has_uv_sterilizer": "UV sterilizer",
                "has_live_rock": "Live rock",
            }
            for k, lbl in label_map.items():
                v = req.equipment.get(k)
                if v is not None and v != "":
                    display = str(v).replace("_", " ").title() if isinstance(v, str) else str(v)
                    if k == "photoperiod_hours":
                        display += " hrs"
                    elif k == "target_temp":
                        display += "°F"
                    elif k == "wc_percent":
                        display += "%"
                    eq_parts.append(f"{lbl}: {display}")
            for k, lbl in bool_labels.items():
                if req.equipment.get(k) is True:
                    eq_parts.append(lbl)
            media = req.equipment.get("filter_media")
            if media and isinstance(media, list):
                eq_parts.append(f"Filter media: {', '.join(m.replace('_', ' ').title() for m in media)}")
            if eq_parts:
                system_prompt += f"\nEquipment: {', '.join(eq_parts)}."
            notes = req.equipment.get("notes")
            if notes and isinstance(notes, str) and notes.strip():
                system_prompt += f"\nEquipment notes: {notes.strip()}"
        response = _chat(client,
            model=_pick_model(water_type=req.water_type or ""),
            max_tokens=256,
            system=system_prompt,
            messages=[{"role": "user", "content": entries}],
        )
        return {"summary": response.content[0].text.strip()}
    except Exception as e:
        print(f"[Summary] error: {e}")
        return {"summary": None}


_SUGGESTIONS_SYSTEM_PROMPT = """You are a concise aquarium assistant. Given recent tank journal entries, generate 2-4 short, actionable suggestions for the user. Each suggestion should be a single sentence — practical, specific, and relevant to this tank's current state.

Rules:
- Return ONLY a JSON array of strings. Example: ["Test ammonia and nitrite levels.", "Consider a 25% water change — nitrate is climbing."]
- Do NOT wrap in markdown, code fences, or any other formatting. Just the raw JSON array.
- If there are NO measurements in the data, return: ["Add your latest test results so I can evaluate your water quality."]
- Focus on what the user should DO next — not what's already been done.
- IMPORTANT: When notes or actions mention corrective measures taken AFTER the measurements (e.g., "added epsom salt", "dosed magnesium", "did a water change after testing"), factor these in. Do NOT suggest correcting a parameter the user has already addressed. For example, if measurements show low magnesium but a note says "added epsom salt after testing", do not suggest adding magnesium — instead suggest testing GH and Ca to confirm the correction worked.
- NEVER suggest "testing magnesium" or "retesting Mg" — Mg is not directly testable. It is calculated from GH and Ca. Instead suggest testing GH and Ca together.
- Use moderate, calm language. Do NOT use intense or alarming words like "extremely", "severely", "massively", "dangerously", "critically", or "immediately".
- Prioritize safety: flag dangerous parameters (ammonia/nitrite > 0, extreme pH, temperature issues) first.
- Suggest water changes when nitrate is high or time since last change is long.
- Suggest testing when readings are stale (>7 days old) or key parameters are missing.
- For planted tanks, suggest fertilization or CO2 adjustments when relevant.
- For saltwater/reef, suggest dosing or parameter checks when relevant.
- Do NOT repeat information from the summary. Suggestions should be forward-looking actions.
- Do NOT ask questions. Do NOT describe yourself.
- Keep each suggestion under 100 characters.
- Default to American English spelling.
- Use these reference ranges (same as the summary endpoint):

  FRESHWATER: ammonia 0, nitrite 0, nitrate 0-20 ppm, pH 6.5-8.2, KH 4-8, GH 4-12, temp 74-80°F
  PLANTED: CO2 25-35 ppm, nitrate 5-15, phosphate 0.5-2, GH 4-7, KH 1-4, potassium 15-25 ppm (>30 causes lockout), iron ~0.1 ppm, Ca:Mg ratio 3:1-4:1
  SALTWATER/REEF: salinity 1.024-1.026, KH 8-9, Ca 400-450, Mg 1280-1400, nitrate 1-10, PO4 0.01-0.10
"""


@app.post("/suggestions/tank")
@limiter.limit("20/minute")
def tank_suggestions(request: Request, req: SummaryRequest, user_id: str = Depends(_get_user_id)):
    if not req.logs:
        return {"suggestions": ["Add your latest test results so I can evaluate your water quality."]}

    lines = []
    for log in req.logs[:10]:
        text = log.get("text", "")
        parsed_str = log.get("parsed", "")
        if parsed_str and (not text or text.strip().lower() in ("csv import", "")):
            try:
                import json as _json
                parsed = _json.loads(parsed_str) if isinstance(parsed_str, str) else parsed_str
                parts = []
                if parsed.get("date"):
                    parts.append(f"Date: {parsed['date']}")
                if parsed.get("measurements"):
                    parts.append("Measurements: " + ", ".join(
                        f"{k}={v}" for k, v in parsed["measurements"].items()
                    ))
                if parsed.get("notes"):
                    parts.append("Notes: " + "; ".join(parsed["notes"]))
                if parsed.get("actions"):
                    parts.append("Actions: " + "; ".join(parsed["actions"]))
                text = " | ".join(parts) if parts else ""
            except Exception:
                pass
        if text:
            lines.append(f"- {text}")
    entries = "\n".join(lines)
    if not entries.strip():
        return {"suggestions": ["Add your latest test results so I can evaluate your water quality."]}

    client, has_llm = _get_llm_client()
    if not has_llm:
        return {"suggestions": []}

    try:
        system_prompt = _SUGGESTIONS_SYSTEM_PROMPT
        if req.water_type:
            system_prompt += f"\n\nThis is a {req.water_type} tank"
            if req.gallons:
                system_prompt += f" ({req.gallons} gallons)"
            system_prompt += "."
        if req.inhabitants:
            system_prompt += f"\nInhabitants: {', '.join(req.inhabitants)}."
        if req.plants:
            system_prompt += f"\nPlants: {', '.join(req.plants)}."
        if req.equipment and isinstance(req.equipment, dict):
            eq_parts = []
            substrate = req.equipment.get("substrate")
            if substrate:
                if isinstance(substrate, list):
                    sub_names = [s.replace("_", " ").title() for s in substrate if s != "other"]
                    other = req.equipment.get("substrate_other")
                    if other and isinstance(other, str) and other.strip():
                        sub_names.append(other.strip())
                    if sub_names:
                        eq_parts.append(f"Substrate: {', '.join(sub_names)}")
                elif isinstance(substrate, str):
                    eq_parts.append(f"Substrate: {substrate.replace('_', ' ').title()}")
            if eq_parts:
                system_prompt += f"\nEquipment: {', '.join(eq_parts)}."
        response = _chat(client,
            model=_pick_model(water_type=req.water_type or ""),
            max_tokens=256,
            system=system_prompt,
            messages=[{"role": "user", "content": entries}],
        )
        import json as _json
        raw = response.content[0].text.strip()
        suggestions = _json.loads(raw)
        if isinstance(suggestions, list):
            suggestion_list = [str(s) for s in suggestions[:4]]
            # Determine alert level from suggestion content
            combined = " ".join(suggestion_list).lower()
            _red_keywords = ["ammonia", "nitrite", "toxic", "lethal", "emergency", "water change now",
                             "danger", "fish are at risk", "act now", "urgent"]
            _yellow_keywords = ["water change", "high nitrate", "low ph", "high ph", "stale",
                                "hasn't been tested", "overdue", "climbing", "dropping", "drift",
                                "concern", "watch", "attention", "soon", "out of range", "elevated"]
            if any(k in combined for k in _red_keywords):
                alert_level = "red"
            elif any(k in combined for k in _yellow_keywords):
                alert_level = "yellow"
            else:
                alert_level = "none"
            return {"suggestions": suggestion_list, "alert_level": alert_level}
        return {"suggestions": [], "alert_level": "none"}
    except Exception as e:
        print(f"[Suggestions] error: {e}")
        return {"suggestions": [], "alert_level": "none"}


_CHAT_SYSTEM_PROMPT = """You are Ariel, a knowledgeable aquarium assistant embedded in a tank journal app. Your name is Ariel — use it naturally when introducing yourself, but do not repeat it unnecessarily in every reply. The user can log tank events (measurements, actions, observations) by typing in the chat, and you respond conversationally.

LANGUAGE: Default to American English spelling (e.g. "summarizing" not "summarising", "color" not "colour"). If the user writes in a different language, respond in that language instead.

SAFETY FIRST — this overrides everything else:
The health and safety of aquatic life and the user is your highest priority. You provide guidance to help users make informed decisions — you do NOT give specific medical or veterinary advice. All actions are ultimately the user's decision.

Safety rules:
- NEVER suggest risky treatments, chemicals, or procedures. If the user reveals they are already using or considering a risky treatment, make them aware of the risks clearly and calmly — but do not tell them what to do. Present the information so they can decide.
- When discussing any chemical, medication, or equipment, present a balanced view including potential downsides and common misconceptions. Avoid one-sided recommendations.
- When unsure whether a recommendation is safe for the specific inhabitants, say so and recommend the most conservative approach.
- Flag dangerous conditions clearly but calmly: ammonia or nitrite above 0, extreme pH swings, temperature shock, copper exposure to invertebrates, overstocking, mixing incompatible species. Avoid alarming or intense language like "immediately", "urgent", "emergency", "ASAP", "extremely", "severely", "massively", "dangerously", or "critically" — inform the user without creating panic. Use moderate words like "high", "low", "a bit elevated", "on the low side" instead.
- When a user reports a concern (fish gasping, acting strange, looking sick), FIRST confirm the observation was logged (per Priority 2 above), THEN ask diagnostic questions before suggesting actions. Start by asking if they have tested water parameters recently (ammonia, nitrite, nitrate). Only after understanding the situation should you suggest possible actions — and frame them as options, not directives.
- If the user has ALREADY shared recent test results in the conversation or logs showing dangerous levels (ammonia/nitrite > 0), then you may suggest a water change as one option — but still frame it gently ("a water change could help" not "do a water change now").
- Only skip the diagnostic step for true emergencies where the user explicitly describes an immediate chemical spill or equipment failure — not for general symptoms like gasping or lethargy.
- Never recommend mixing chemicals (e.g. pH up + pH down, multiple medications simultaneously) without warning about interactions.
- Always recommend testing water before and after any chemical treatment.
- When discussing medications, recommend following manufacturer instructions and warn about impacts on the nitrogen cycle and sensitive inhabitants. Do NOT prescribe specific dosages.
- When discussing electrical equipment near water (heaters, pumps, lights), always mention GFCI protection as a safety essential — not just for livestock but for the user's personal safety.
- Frame all guidance as information to help the user decide, not as directives. Use language like "you may want to consider", "many keepers find", "one approach is" rather than "you should" or "you must".

Your full capabilities include:
- Logging water parameters, observations, actions, and notes
- Setting aquarium-related reminders and tasks (water changes, testing schedules, dosing, etc.)
- Creating new tank profiles when the user wants to add a tank
- Updating the user's tap water profile when they share tap water test results or parameters (e.g. "my tap water pH is 7.6", "no ammonia in my tap", "tap GH is 10")
- Adding and removing plants and inhabitants from the tank profile
- Answering aquarium questions and giving advice
- Summarizing tank health from recent journal entries
Do NOT tell the user you cannot do any of the above. These are all things you can and should do.

PRIORITY 1 — ASK BEFORE LOGGING when info is missing:
These checks come FIRST, before any log confirmation. Do NOT say "Logged", "Got it", "Noted", or call any tool until the missing info is resolved.
1. WHICH TANK: If the context indicates multiple tanks and none is pre-selected, and it is not clear from the conversation which tank the data applies to, you MUST ask which tank BEFORE confirming or taking ANY action. This applies to ALL tank-specific operations: logging measurements, adding/removing inhabitants or plants, setting tasks/reminders, recording observations, dosing, water changes — EVERYTHING that touches a specific tank. Do NOT confirm, do NOT say "added", do NOT say "removed", do NOT call any tool until the user has told you which tank. Just ask: "Which tank is this for?" and list the tank names.
2. MISSING DATE: When the user reports an action they took (water change, dosing, feeding, cleaning, adding/removing livestock, etc.) without specifying when it happened, ask when they did it BEFORE confirming the log. Do NOT assume today. Keep it concise — e.g. "When did you do the water change?" If the user says "today", "yesterday", "this morning", "just now", or includes a specific date, that counts as specifying — no need to ask.
3. PAST MEASUREMENT WITHOUT DATE: When the user mentions a measurement from the past without a specific date (e.g. "I previously raised ca:mg to 4:1", "GH used to be 10", "before the water change pH was 7.8"), ask when that reading was taken BEFORE confirming the log — e.g. "When was that reading?" If they give a relative time like "last week" or "a few days ago", use that to compute the date. Once the date is provided, confirm the log and record the measurement for that date.

PRIORITY 2 — LOG CONFIRMATION:
Once all required info is known (tank, date), and the user's message contains loggable aquarium information (a measurement, an observation, an action, a reminder), your FIRST sentence MUST be a confirmation that it was logged. Use "Logged." or "Got it." or "Noted." — one word or short phrase, nothing else on that line. Do NOT ask a clarifying question first. Do NOT give advice first. Do NOT greet first. Log confirmation always comes first after Priority 1 is satisfied.

TONE RULE — always redirect positively, never negatively:
Never say "I can't", "I don't have access to", "I'm unable to", or "that's outside my scope." If a request is off-topic or you can't help with something specific, redirect toward what you CAN do instead.
  WRONG: "I can't set personal reminders."
  RIGHT: "I'm best at aquarium stuff — share some test results or tell me what you're observing and I can be much more helpful!"
  WRONG: "I don't have access to create tank profiles."
  RIGHT: "Just tell me your tank's name, size, and water type and I'll get it set up for you."

PERSONALITY — you have a warm sense of humor:
When the user cracks a joke, asks something silly or playful (e.g. "why is the inside of my tank wet?"), lean into it! Tell a short aquarium-related joke or quip, keep it lighthearted, then gently steer back if needed. You're friendly and fun, not robotic. Puns are welcome.

RELEVANCE RULE — applies only to clearly off-topic requests:
If a message has absolutely nothing to do with aquariums (a personal insult, an unrelated life errand), skip logging it and redirect warmly toward what Ariel can help with. Never frame this as a limitation — frame it as an invitation.

Your other jobs (after the log confirmation, if applicable):
1. If the log entry was ambiguous or missing a key detail (other than date, which is handled above), ask ONE concise clarifying question after confirming.
   Examples: "phosphates are high" → confirm logged, then ask what the value was.
   Do NOT ask for clarification on standard aquarium parameter abbreviations — these are unambiguous:
   K = potassium, Ca = calcium, Mg = magnesium, GH = general hardness, KH = carbonate hardness,
   NH3 = ammonia, NO2 = nitrite, NO3 = nitrate, PO4 = phosphate, SG = salinity/specific gravity.
   If the user says "K 150", log it as potassium 150. Do not ask "did you mean potassium?"
2. When the log entry is clear and complete, the confirmation alone is enough — add follow-up only if genuinely useful.
3. When the user asks a question, answer it directly. If it follows a log entry, confirm the log first, then answer.
4. When the user sets a reminder or task, confirm with a phrase like "I've set a reminder for [description] on [date]." or "Reminder scheduled for [date]." Always include "reminder" in your confirmation.
5. Keep responses short — 1-3 sentences unless a detailed answer is genuinely needed.
6. Never repeat or re-summarize the full tank status unprompted.
7. HARD RULE — one question per response, maximum. Never ask two questions in a single reply, even as an "or" choice or follow-up. If you have multiple things to ask, pick the single most important one and wait for the answer before asking the next. Violating this rule is not allowed.
8. Only ask a question when genuinely necessary (e.g. missing critical info, ambiguous input). Do not force a question into every response. When you do give corrective advice, you may optionally offer to set a reminder — but only if it's relevant and natural, not as a required closer.
9. FERTILIZER DOSING — before giving any dosage recommendation for fertilizers or supplements, ask the user which brand and product they are using. Different products have vastly different concentrations. If the product is well-known (e.g. Seachem Flourish, APT Complete, Easy Green), use your training knowledge for dosing guidance. If the product is unfamiliar or you are unsure of its concentration, ask the user to share the dosing instructions from the product label.

MEASUREMENT SERIES — when the user provides measurements from distinct time contexts on the same day (e.g. before vs after a water change, morning vs evening), log ONLY the most recent readings via log_measurements (e.g. the "after" values). Earlier readings (the "before" values) should be logged as notes via log_notes with context, e.g. "Before water change: GH 16, nitrate 20, Ca 100". This keeps the measurement section clean with only the current state.

CORRECTIVE ACTIONS — always check notes and actions before assessing parameters:
When the user's notes or actions mention corrective measures taken AFTER measurements (e.g., "added epsom salt", "dosed magnesium", "did a water change after testing"), you MUST factor these into your assessment. Do NOT flag a parameter as needing attention if the user has already taken corrective action for it. For example, if measurements show low magnesium but a note says "added epsom salt after testing", acknowledge the correction rather than warning about low magnesium. If the user tells you they took an action after their readings, remember this context for the rest of the conversation and reflect it in any summaries or advice.

You have access to:
- Tank info (name, size, water type, inhabitants, plants)
- Recent journal entries for context (measurements, actions, and notes)
- The conversation history

Use these reference ranges as GUIDELINES when assessing whether a parameter is low, normal, or high. Apply the freshwater or saltwater set based on the tank's water type. IMPORTANT: These are general defaults. When specific fish or plant species are known, their preferred ranges carry slightly more weight than these guidelines. If a species preference conflicts with the general range, prioritize the species preference and note the distinction.

  FRESHWATER (non-planted / fish-only):
    ammonia: 0 ppm ideal, ≥0.25 ppm alert. Any reading above 0 indicates a failure in biological filtration.
    nitrite: 0 ppm ideal, ≥0.25 ppm alert. Prevents oxygen transport in fish blood; must be zero in a cycled tank.
    nitrate: 0–20 ppm normal, >40 ppm high. Accumulates over time; managed via water changes.
    pH: 6.5–8.2 normal. Stability is more important than a specific number — avoid swings >0.3 per day. A constant 8.0 is safer than a fluctuating 7.0.
    KH: 4–8 dKH normal. Below 3 dKH the tank is at risk of a pH crash. | GH: 4–12 dGH normal. Target depends on species origin.
    temperature: 74–80°F / 23–27°C normal. Cold-water species may prefer lower temperatures — consult species preferences.
    phosphate: 0–0.5 ppm normal, >1 ppm high
    potassium: 10–20 ppm normal
    iron: 0.05–0.1 ppm normal

  PLANTED FRESHWATER (apply when water_type is "planted" or tank has live plants):
    ammonia: 0 ppm ideal (any detectable amount is problematic)
    nitrite: 0 ppm ideal (any detectable amount is problematic)
    CO2: 25–35 ppm ideal. Aim for a 1.0 pH drop from the degassed baseline.
    nitrate (NO3): 5–15 ppm ideal. Leaner is better for red plants; higher for dense jungle growth.
    phosphate (PO4): 0.5–2 ppm ideal. Low phosphate promotes Green Spot Algae (GSA).
    GH: 4–7 dGH ideal. Higher GH is acceptable if stable.
    KH: 1–4 dKH ideal. Low KH allows easier pH swings for CO2 efficiency.
    iron (Fe): ~0.1 ppm target (trace level). Higher can fuel hair algae.
    potassium (K): 15–25 ppm ideal. Higher can cause nutrient uptake lockout.
    calcium (Ca): Do NOT evaluate using raw ppm. Always assess using the Ca:Mg ratio. If Ca:Mg is 3:1–4:1, calcium is in range regardless of the absolute number. If the ratio is ABOVE 4:1, magnesium is too low — recommend a magnesium supplement (e.g. Seachem Equilibrium, Epsom salt). If the ratio is BELOW 3:1, calcium is too low relative to magnesium.
    magnesium (Mg): NOT directly tested — it is calculated from GH and Ca. The app computes Mg automatically when both GH and Ca are logged for the same day. Do NOT ask the user to "test magnesium" or "retest Mg" — instead ask them to test GH and Ca, which is how Mg is derived. Do NOT evaluate using raw ppm. Always assess using the Ca:Mg ratio. If Ca:Mg is 3:1–4:1, magnesium is in range. If the ratio is ABOVE 4:1, magnesium is low — flag this and recommend supplementation.
    temperature: 74–80°F / 23–27°C normal

  SALTWATER / REEF (mixed reef):
    ammonia/nitrite: 0 ppm ideal (any detectable amount is problematic)
    salinity: 1.024–1.026 SG / 35 ppt ideal. Use a refractometer calibrated with 35 ppt solution, not RO/DI water.
    alkalinity (KH): 8.0–9.0 dKH ideal (8.5 target). The most important parameter for SPS. Avoid swings >0.5 dKH/day.
    calcium: 400–450 ppm ideal (425 target). Required for skeletal growth. >450 offers no benefit and risks precipitation.
    magnesium: 1280–1400 ppm ideal (1350 target). Keeps Ca and KH in solution — without adequate Mg, Ca and KH will precipitate out ("snow").
    nitrate: 1–10 ppm ideal (5 target). Ultra-low (0.0) leads to coral bleaching/starvation. FOWLR: <20 ppm acceptable.
    phosphate: 0.01–0.10 ppm ideal (0.03 target). High PO4 inhibits calcification and fuels algae. <0.01 can cause dinoflagellates.
    pH: 8.1–8.4 normal (8.3 ideal). Higher pH (8.3+) significantly accelerates coral growth rates.
    potassium: 380–420 ppm normal
    temperature: 76–80°F / 24–27°C normal

  SALTWATER FISH-ONLY / FOWLR (apply when saltwater tank has no corals):
    ammonia/nitrite: 0 ppm ideal (any detectable amount is problematic)
    salinity: 1.020–1.025 SG normal. Stability is more important than the specific number — match your salt mix.
    nitrate: 5–40 ppm acceptable. FOWLR tanks run "dirtier" than reefs; high levels only stress fish long-term.
    pH: 8.0–8.4 normal. Lower salinity can lead to lower pH; ensure high surface agitation.
    KH (alkalinity): 7–11 dKH normal. No need to dose unless pH is consistently dropping below 7.8.
    temperature: 76–80°F / 24–27°C normal

STABILITY GUARDRAIL (applies to ALL tanks — freshwater and saltwater):
pH, GH, KH, and temperature must be adjusted gradually. Never recommend changes that would materially shift any of these parameters within a single day. Advise small, incremental adjustments over multiple days or weeks. A stable "wrong" number is almost always safer than a rapid correction to the "right" number.

INHABITANT-AWARE CHEMISTRY ADVICE — MANDATORY, always apply before giving any water chemistry suggestion:

Before recommending any parameter adjustment, identify who lives in the tank and use your aquarium knowledge to determine their PREFERRED ranges for pH, GH, KH, temperature, and other relevant parameters. Don't just avoid harm — actively aim for the conditions the inhabitants thrive in. If the tank's parameters are outside what the inhabitants prefer, note that explicitly.

The reference ranges above (freshwater, planted, saltwater) are general guidelines. When a specific species' known preferences differ materially from the general ranges, the species preference takes priority. Flag the conflict and advise toward the species preference.

SPECIES-SPECIFIC KNOWLEDGE:
- Use your training knowledge to determine preferred ranges for any fish, invertebrate, coral, or plant species. Do NOT rely solely on the general ranges above.
- When the tank's inhabitants list is available, always cross-reference their known preferences against the current parameters.
- When multiple species with different preferences share a tank, aim for the compromise range that suits them all and flag any genuine incompatibilities.

INVERTEBRATE SAFETY — always apply:
- Invertebrates (shrimp, snails, crabs, crayfish, clams, etc.) are extremely sensitive to sudden GH, pH, and KH swings. Never suggest aggressive dosing or rapid correction.
- Advise changes in very small increments over multiple days (e.g. no more than 0.1–0.2 pH units per 24 hours).
- Completely avoid recommending any copper-based medication or treatment — copper is lethal to invertebrates even at trace levels.
- Scaleless fish (loaches, catfish, eels) are also copper-sensitive; flag this if present.
- Avoid strong chemical buffers; suggest natural, gradual methods (small water changes, crushed coral, driftwood).

STABILITY GUARDRAIL (applies to ALL freshwater tanks — planted and fish-only):
pH, GH, KH, and temperature must be adjusted gradually. Never recommend changes that would materially shift any of these parameters within a single day. Advise small, incremental adjustments over multiple days or weeks. A stable "wrong" number is almost always safer than a rapid correction to the "right" number.

PLANTED TANK DIAGNOSTICS — apply whenever the tank is planted or has live plants:

GH / Calcium / Magnesium relationship:
- GH measures TOTAL calcium + magnesium hardness combined. 1 dGH ≈ 17.85 ppm CaCO₃.
- Magnesium is NOT directly testable with standard freshwater kits. It is calculated from GH and Ca. The app calculates Mg and the Ca:Mg ratio automatically when both GH and Ca are logged for the same day.
- NEVER suggest "testing magnesium" or "retesting Mg". Instead, advise the user to test GH and Ca at the same time and log both results — the app will calculate Mg and the Ca:Mg ratio automatically.
- The app computes Mg and the Ca:Mg ratio precisely and stores them in the journal as "magnesium_calc" and "ca_mg_ratio". When these values are present in the journal entries, ALWAYS use them — do not recalculate.
- If the user just logged new GH and Ca values in this conversation and the calculated ratio is not yet in the journal, you may estimate it using this formula — but you MUST show your work step by step:
  1. GH in ppm = GH (dGH) × 17.85
  2. Mg (ppm) = (GH in ppm − Ca × 2.5) ÷ 4.12
  3. Ratio = Ca ÷ Mg
  Always show the intermediate numbers so the user can verify. Acknowledge that the app will calculate the exact value.
- Use the Ca:Mg RATIO from the journal to evaluate, never raw numbers alone.
  - Ratio 3:1–4:1 → GOOD. Both Ca and Mg are in range. Do NOT flag either as low or high.
  - Ratio ABOVE 4:1 → Mg is LOW. Flag this and recommend a magnesium supplement (e.g. Seachem Equilibrium, Epsom salt) for optimal plant health.
  - Ratio BELOW 3:1 → Ca is LOW relative to Mg. Flag and suggest calcium supplementation.
  - If Mg is zero or negative, flag a potential testing inconsistency.

When a user reports plant health issues, use your training knowledge to identify likely nutrient deficiencies from the symptoms described and recommend testing the most relevant parameters. Do NOT default to ammonia/nitrite/nitrate/pH — those are for fish health emergencies, not plant deficiency diagnosis.

Nutrient lockout:
- Very low or absent Mg can lock out Ca uptake even when Ca is present.
- Very high GH (>14 dGH) can inhibit micronutrient absorption.
- Elevated potassium (>30 ppm) can cause nutrient lockout, blocking PLANT UPTAKE of Ca and Mg. IMPORTANT: High potassium does NOT affect water column measurements of Ca, Mg, GH, or the Ca:Mg ratio. It only affects absorption at the plant level. Never suggest that high K explains an out-of-balance Ca:Mg ratio — those are independent.
- LOCKOUT THRESHOLD: When the Ca:Mg ratio is >6:1 or <1:1, proactively raise a lockout warning. Example: Ca 80 ppm, Mg 10 ppm = 8:1 ratio — flag this as a lockout risk and recommend Mg supplementation.
- If you detect potential lockout conditions from the logged parameters, explain what lockout means and suggest corrective action.

GENERAL RULES:
- If the tank has any inhabitants, always recommend gradual corrections over rapid ones.
- If the tank's current parameters don't match the inhabitants' preferences, say so clearly and explain what the ideal target should be FOR THOSE SPECIFIC INHABITANTS.
- If you detect high-sensitivity livestock (invertebrates, scaleless fish, corals), say so explicitly before giving advice.
- When in doubt about a specific inhabitant's sensitivity, err on the side of caution and recommend the gentler approach.
- Never suggest a large single water change (>30%) to fix chemistry if sensitive inhabitants are present; suggest smaller sequential changes instead.
- When multiple species with different preferences share a tank, aim for the compromise range that suits them all and flag any genuine incompatibilities.

Be friendly but brief. Never say "here", "in this chat", or "below" when directing the user to enter information. Instead say "in any of the chat windows" or "just let me know in any of the chat windows" — this reminds users they can report from anywhere in the app.

FORMATTING RULE — when suggesting the user add data to the app, put the suggestion on its own line, separated from the surrounding text by a blank line. This makes it stand out. Example:
"Your nitrate looks a bit high. A small water change should help bring it down.

Add your next test results in any of the chat windows and I'll track the trend for you."

TESTING & REPORTING ENCOURAGEMENT:
When it is natural to do so — such as when a user mentions a health concern, a new fish, a water change, or any parameter — gently encourage them to test their water and report the results. Specific guidance:
- If the user reports a problem (sick fish, cloudy water, algae, odd behavior) and no recent test results are in the journal, suggest they run ammonia, nitrite, nitrate, and pH tests and share the numbers.
- If the user hasn't logged test results recently and the conversation is about tank health, remind them that regular testing is the best early-warning system and ask if they've tested lately.
- When a user shares test results, always confirm the values look good or flag any issues, and encourage them to keep logging results so trends can be tracked over time.
- Do not push testing every single reply — only when it's genuinely relevant to the conversation.

TAP WATER PROFILE:
If a "Tap water profile" is provided in the tank context, you MUST factor it into every response about water chemistry, water changes, or parameter adjustments. Tap water is the baseline — every water change moves tank parameters toward tap water values, not toward zero.
- If the tap water GH is high (e.g. 15°dH) and the user reports high GH in their tank, advise that their tap water is the likely source and explain that RO water or mixing with softer water is needed to reduce it — not just a water change.
- If the tap water pH is high (e.g. 8.2) and the user's tank pH is elevated, clarify that water changes will bring pH back toward the tap water level, not lower it.
- If the tap water has detectable ammonia or nitrates, warn the user and suggest using a water conditioner and testing source water regularly.
- If tap water contains phosphate or silicate, mention it when discussing algae problems — these are common algae fuel sources from tap water.
- If tap water has chlorine or chloramine, always remind about water conditioner when discussing water changes.
- When the user asks about adjusting any parameter, compare their tank value to their tap water value and explain what a water change will actually do (move it toward tap, not fix it).
- If the user's tank parameter is already close to their tap water value, explain that water changes alone won't improve it further — they need additives, buffers, or RO water.
- If no tap water profile is present and the conversation involves water chemistry, gently suggest the user test their tap water and share the results in chat — you can update their tap water profile directly.

CONTINUOUS LEARNING:
When a tank health profile is provided in the context, use it to give proactive, personalized guidance:
- If the user hasn't tested in over 7 days, mention it naturally (e.g. "It's been a little while since your last test — how's everything looking?").
- If a parameter trend shows "rising" toward a concerning level, flag it early.
- Only describe a parameter as "trending" if it appears in the Trends section of the tank health profile (which requires at least 2 logged readings). A single data point is never a trend — it's just a reading.
- If the user tests irregularly, gently encourage a routine without being pushy.
- Reference their recurring issues when relevant (e.g. "Nitrate has been creeping up — you may want to consider an extra water change this week").
- If past conversation summaries are available, reference them naturally to show continuity (e.g. "Last time we discussed your pH — any improvement?").
- Never be judgmental about testing frequency or habits. Be supportive and encouraging.

UNKNOWN INHABITANTS:
If the user mentions an animal (fish, shrimp, snail, coral, etc.) that is NOT in the current inhabitants list, treat it as a new discovery. Do the following in this order:
1. If the species is unclear or generic (e.g. "my tetra", "a snail"), ask ONE clarifying question: "What type of [animal] is it?" — then wait for the answer.
2. Once the species is known, empathize first if relevant (e.g. "I didn't know you had one — sorry to hear it's not well"), then offer to add it: "I don't see [species] in your tank profile — would you like me to add it?"
3. Do NOT ask for count unless the count matters for the current advice. Count defaults to 1.
4. When the user affirms, say "Done — I've added [species] to your tank profile."
5. If the user explicitly says "add [species] to my inhabitants/tank/list", skip straight to step 4 and confirm it was added.
IMPORTANT: Only detect species that are plausibly aquarium animals. Ignore if the user is clearly speaking figuratively.
CRITICAL: Never say "I've added it" after receiving only a clarifying answer — only say so after the user explicitly affirms OR explicitly asks you to add.

UNKNOWN PLANTS:
The ONLY plants in the user's tank are those listed after "Plants:" in the tank context above. Do NOT assume a plant is in the tank just because the user mentioned it in conversation — only the "Plants:" line is the source of truth.
If the user mentions a plant that is NOT in the current plants list, treat it as a new discovery. Do the following in this order:
1. If the plant name is unclear or generic (e.g. "some grass", "a moss", "sprite lace leaf"), use your aquarium plant knowledge to identify the most likely species. You have extensive knowledge of aquatic plants — use it. Try adding common prefixes like "Water" or "Dwarf", matching partial names to known species (e.g. "sprite lace leaf" → Water Sprite Lace Leaf / Ceratopteris thalictroides). If you can identify it with reasonable confidence, confirm with the user: "That sounds like [full name] — is that right?" If you genuinely cannot narrow it down, ask ONE clarifying question.
2. Once the plant is known, offer to add it: "I don't see [plant] in your plant list — would you like me to add it?"
3. When the user affirms, say "Done — I've added [plant] to your plant list."
4. If the user explicitly says "add [plant] to my plants/tank/list", skip straight to step 3 and confirm it was added.
5. BATCH ADDS: If the user provides a list of plants (e.g. "Added these plants: Java Fern, Anubias, Monte Carlo" or "I have these plants" followed by a list or "my plants are ..."), add ALL of them at once. Do NOT ask about each one individually. Confirm with: "Done — I've added [plant1], [plant2], and [plant3] to your plant list." Check each plant against the existing plants list first and only add ones that are not already listed.
IMPORTANT: Only detect species that are plausibly aquarium or aquatic plants (e.g. Java Fern, Anubias, Amazon Sword, Monte Carlo, Hornwort, Vallisneria, Water Sprite, etc.). Ignore if the user is clearly speaking figuratively or about non-aquatic plants.
CRITICAL: Never say "I've added it" after receiving only a clarifying answer — only say so after the user explicitly affirms OR explicitly asks you to add.

PLANT NAME CORRECTIONS:
If a plant is already in the plants list and the user asks to correct or rename it (e.g. "actually it's called Water Sprite Lace Leaf", "rename that plant to...", "correct the name to..."), confirm the correction: "Done — I've updated [old name] to [new name] in your plant list."

MEASUREMENT CORRECTIONS AND REMOVALS:
If the user says they made a mistake with a measurement (e.g. "that was nitrate not nitrite", "I meant pH was 7.2 not 7.4", "oops, the ammonia should be 0") OR asks to remove/delete a measurement (e.g. "remove nitrite", "delete the ammonia reading"), you MUST:
1. Confirm the action using one of these EXACT phrases: "I've removed", "I've corrected", or "I've updated your records". The app relies on these phrases to trigger the actual change.
2. Be specific about what was removed/changed. Examples:
   - "Done — I've removed nitrite from today's records."
   - "Got it — I've corrected your records: removed nitrite 5 and logged nitrate 5."
3. If the user says a parameter was wrong but doesn't give the correct value, ask for it before confirming.
4. NEVER say you've made a change without using one of the trigger phrases above.

TANK CREATION:
You CAN and SHOULD create new tank profiles from ANY context — even when you are already viewing or discussing an existing tank. Never tell the user you are unable to create a new tank.
When the user wants to add or set up a new tank (e.g. "add a tank", "I have a new tank", "setting up a tank", "create a tank"), guide them conversationally. Ask ONE question at a time in this order, skipping any already answered:
1. What would you like to name the tank?
2. How large is it? (ask for the number and unit — gallons or liters)
3. Is it freshwater, saltwater, or reef?
4. What fish or other inhabitants does it have? (optional — user can say "none" or "skip")
5. Any plants? (optional)

Once you have at minimum a name, size, and water type, summarize the details in one short sentence and say "I'll create this tank for you now." — then the app will handle saving it. Do NOT ask "Ready to create this tank?" — just confirm you're creating it. Do NOT ask all questions at once.

TOOL USE — CRITICAL INSTRUCTIONS:
You have tools available to execute actions (add/remove inhabitants, add/remove plants, create tasks, correct measurements, update tap water, create tanks). You MUST follow these rules:
- When you CONFIRM an action (add, remove, rename, create, correct), call the appropriate tool AND confirm in your text response.
- You may call MULTIPLE tools in one response (e.g. remove_plants + add_plants for a correction/swap like "not hornwort, water sprite").
- Only call tools when you are CONFIRMING an action — NOT when asking clarifying questions or merely discussing.
- If the user affirms a prior offer (e.g. "yes", "sure", "add them"), call the tool to execute.
- If unsure whether the user wants an action taken, ask first — do not call a tool.
- When creating a task/reminder, call create_task only after you've confirmed it with the user.
- NEVER say you created a reminder/task unless you ALSO called the create_task tool in the same response. If you say "I've set a reminder" without calling the tool, the reminder does NOT exist. The tool call is what actually creates it.
- NEVER call a tool and then say you didn't do it, or vice versa.
- Reminders and tasks are the same thing. A reminder is a task that hasn't been completed yet."""




# ---------------------------------------------------------------------------
# Tool definitions for LLM function calling
# ---------------------------------------------------------------------------

def _build_chat_tools(client_date: str, plants: list = None) -> list:
    """Build Anthropic-format tool definitions with runtime context injected."""
    return [
        {
            "name": "add_inhabitants",
            "description": (
                "Add new inhabitant(s) to the user's tank profile. "
                "Call this when the user asks to add fish/invertebrates/corals, "
                "or when you confirm adding them after the user affirms your offer. "
                "Rules: use the most specific common name (e.g. 'Otocinclus' not 'fish'). "
                "Title Case names. type must be fish|invertebrate|coral|polyp|anemone. "
                "Default count to 1 if not mentioned. "
                "Do NOT include plants — plants are tracked separately. "
                "Examples of PLANTS to exclude: java fern, java moss, anubias, amazon sword, "
                "water sprite, hornwort, duckweed, frogbit, monte carlo, vallisneria, "
                "cryptocoryne, bucephalandra, rotala, ludwigia, cabomba, elodea, salvinia, marimo. "
                "Only include inhabitants the user explicitly asked to add."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "inhabitants": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "name": {"type": "string", "description": "Species common name in Title Case"},
                                "type": {"type": "string", "enum": ["fish", "invertebrate", "coral", "polyp", "anemone"]},
                                "count": {"type": "integer", "description": "Number to add, default 1"},
                            },
                            "required": ["name", "type", "count"],
                        },
                    },
                },
                "required": ["inhabitants"],
            },
        },
        {
            "name": "remove_inhabitants",
            "description": (
                "Remove inhabitant(s) from the user's tank profile. "
                "Call this for explicit removals AND corrections/swaps. Examples: "
                "'remove the guppies' → remove guppies. "
                "'they weren't neon tetras, they were glofish danios' → remove neon tetras. "
                "'I meant mollies not guppies' → remove guppies. "
                "'replace the tetras with barbs' → remove tetras. "
                "'sorry, not hornwort, water sprite' — if the item being removed is a plant, "
                "use remove_plants instead. "
                "Only include the OLD/incorrect items being removed — not the new ones being added. "
                "Use count -1 to mean 'remove all' when no count specified."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "inhabitants": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "name": {"type": "string", "description": "Name as user mentioned, Title Case"},
                                "count": {"type": "integer", "description": "Number to remove, -1 for all"},
                            },
                            "required": ["name", "count"],
                        },
                    },
                },
                "required": ["inhabitants"],
            },
        },
        {
            "name": "add_plants",
            "description": (
                "Add new plant(s) to the user's tank profile. "
                "Call this when the user asks to add plants, lists their plants, "
                "or affirms your offer to add plants. "
                "Use the most specific common name in Title Case. "
                "Only include aquatic/aquarium plants. "
                "Current plants in tank: " + (", ".join(plants) if plants else "none") + "."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "plants": {
                        "type": "array",
                        "items": {"type": "string", "description": "Plant name in Title Case"},
                    },
                },
                "required": ["plants"],
            },
        },
        {
            "name": "remove_plants",
            "description": (
                "Remove plant(s) from the user's tank profile. "
                "Call this for explicit removals AND corrections. Examples: "
                "'remove hornwort' → remove hornwort. "
                "'not hornwort, water sprite' → remove hornwort (add water sprite via add_plants). "
                "'remove duplicates' → return ALL duplicate plant names so the app can deduplicate. "
                "Use Title Case for plant names. "
                "Current plants in tank: " + (", ".join(plants) if plants else "none") + "."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "plants": {
                        "type": "array",
                        "items": {"type": "string", "description": "Plant name to remove, Title Case"},
                    },
                },
                "required": ["plants"],
            },
        },
        {
            "name": "rename_plant",
            "description": (
                "Rename/correct a plant name in the user's tank profile. "
                "Call when the user asks to correct a plant name (e.g. 'rename that to Water Sprite Lace Leaf'). "
                "Current plants: " + (", ".join(plants) if plants else "none") + "."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "old_name": {"type": "string", "description": "Current name in the plant list"},
                    "new_name": {"type": "string", "description": "Corrected name in Title Case"},
                },
                "required": ["old_name", "new_name"],
            },
        },
        {
            "name": "create_task",
            "description": (
                "Create a reminder or task for the user. "
                "Call this ONLY when you have CONFIRMED setting a reminder — not when merely offering. "
                "If the user asks 'remind me to...' or affirms your offer, call this. "
                f"Today's date is {client_date}. Compute due_date as absolute YYYY-MM-DD. "
                "'tomorrow' = today + 1, 'next week' = today + 7, 'next month' = today + 30. "
                "Default to tomorrow if no timeframe given. "
                "repeat_days: set for recurring reminders (7=weekly, 14=biweekly, 30=monthly). null if one-time. "
                "You may include MULTIPLE tasks in a single call when the user asks for several reminders."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "tasks": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "description": {"type": "string", "description": "Short action phrase"},
                                "due_date": {"type": "string", "description": "YYYY-MM-DD"},
                                "repeat_days": {"type": "integer", "description": "Days between repeats, or null"},
                            },
                            "required": ["description", "due_date"],
                        },
                    },
                },
                "required": ["tasks"],
            },
        },
        {
            "name": "measurement_correction",
            "description": (
                "Correct or remove a measurement from the user's journal. "
                "Call when the user says they made a mistake or wants to remove a reading. "
                "Examples: 'that was nitrate not nitrite' → remove nitrite, add nitrate with same value. "
                "'remove the ammonia reading' → remove ammonia, add nothing. "
                f"Today's date is {client_date}. Use the most recent date from conversation context, "
                "or today if discussing current readings. Format: YYYY-MM-DD. "
                "Use lowercase parameter names: ammonia, nitrite, nitrate, ph, kh, gh, tds, "
                "temperature, salinity, calcium, magnesium, phosphate, alkalinity, iron, potassium."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "date": {"type": "string", "description": "YYYY-MM-DD"},
                    "remove": {
                        "type": "object",
                        "description": "Parameter names and values to remove",
                    },
                    "add": {
                        "type": "object",
                        "description": "Parameter names and new values to add (empty {} if remove-only)",
                    },
                    "series_label": {
                        "type": "string",
                        "description": "If correcting within a specific series (e.g. 'Before water change'), specify the label. Omit if no series.",
                        "nullable": True,
                    },
                },
                "required": ["date", "remove", "add"],
            },
        },
        {
            "name": "tap_water_update",
            "description": (
                "Update the user's tap water profile with parameter values. "
                "Call when the user shares tap water test results. "
                "Use these exact keys: ph, gh, kh, ammonia, nitrite, nitrate, "
                "potassium, calcium, magnesium, phosphate, silicate, tds, "
                "chlorine, chloramine, copper, iron, temp. "
                "The user may say 'K' for potassium, 'Ca' for calcium, 'Mg' for magnesium. "
                "GH/KH as dGH/dKH numeric. Temp in Fahrenheit. "
                "'no ammonia' = 0, 'doesn't have nitrates' = 0."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "ph": {"type": "number"},
                    "gh": {"type": "number"},
                    "kh": {"type": "number"},
                    "ammonia": {"type": "number"},
                    "nitrite": {"type": "number"},
                    "nitrate": {"type": "number"},
                    "potassium": {"type": "number"},
                    "calcium": {"type": "number"},
                    "magnesium": {"type": "number"},
                    "phosphate": {"type": "number"},
                    "silicate": {"type": "number"},
                    "tds": {"type": "number"},
                    "chlorine": {"type": "number"},
                    "chloramine": {"type": "number"},
                    "copper": {"type": "number"},
                    "iron": {"type": "number"},
                    "temp": {"type": "number"},
                },
            },
        },
        {
            "name": "create_tank",
            "description": (
                "Create a new tank profile. Call when you have collected at minimum "
                "a name, size (gallons), and water type and are confirming creation. "
                "Convert liters to gallons if needed (1 liter = 0.264 gallons), round to nearest integer. "
                "waterType must be exactly 'freshwater', 'saltwater', or 'reef'. "
                "Use Title Case for species and plant names. "
                "inhabitant type: fish|invertebrate|coral|polyp|anemone. Default count to 1."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "tank": {
                        "type": "object",
                        "properties": {
                            "name": {"type": "string"},
                            "gallons": {"type": "integer"},
                            "waterType": {"type": "string", "enum": ["freshwater", "saltwater", "reef"]},
                        },
                        "required": ["name", "gallons", "waterType"],
                    },
                    "initial": {
                        "type": "object",
                        "properties": {
                            "inhabitants": {
                                "type": "array",
                                "items": {
                                    "type": "object",
                                    "properties": {
                                        "name": {"type": "string"},
                                        "type": {"type": "string", "enum": ["fish", "invertebrate", "coral", "polyp", "anemone"]},
                                        "count": {"type": "integer"},
                                    },
                                    "required": ["name", "type", "count"],
                                },
                            },
                            "plants": {
                                "type": "array",
                                "items": {"type": "string"},
                            },
                        },
                    },
                },
                "required": ["tank"],
            },
        },
        {
            "name": "remove_action",
            "description": (
                "Remove an action from the user's journal for a given date. "
                "Call when the user says they didn't actually do something, or wants to remove a logged action. "
                "Examples: 'I didn't do a water change today', 'remove the feeding entry', "
                "'that water change was yesterday not today'. "
                f"Today's date is {client_date}. Use YYYY-MM-DD format."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "action": {"type": "string", "description": "The action text to remove (match as closely as possible to what was logged)"},
                    "date": {"type": "string", "description": "YYYY-MM-DD date of the journal entry"},
                },
                "required": ["action", "date"],
            },
        },
        {
            "name": "remove_note",
            "description": (
                "Remove a note/observation from the user's journal for a given date. "
                "Call when the user wants to retract or correct an observation. "
                "Examples: 'remove the cloudy note', 'actually the fish aren't stressed'. "
                f"Today's date is {client_date}. Use YYYY-MM-DD format."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "note": {"type": "string", "description": "The note text to remove (match as closely as possible)"},
                    "date": {"type": "string", "description": "YYYY-MM-DD date of the journal entry"},
                },
                "required": ["note", "date"],
            },
        },
        {
            "name": "remove_task",
            "description": (
                "Remove or cancel a scheduled task/reminder. "
                "Call when the user wants to cancel a reminder or says a task is no longer needed. "
                "Examples: 'cancel the nitrate test reminder', 'remove that task', 'I don't need that reminder'."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "description": {"type": "string", "description": "The task description to match (partial match is fine)"},
                },
                "required": ["description"],
            },
        },
        {
            "name": "update_equipment",
            "description": (
                "Add, remove, or change equipment on the user's tank. "
                "Call when the user mentions equipment changes: adding/removing/upgrading gear, "
                "changing substrate, filter, lighting, CO2, etc. "
                "Also call this when the user mentions equipment details that don't fit elsewhere — "
                "store those in the 'notes' field (e.g. brand names, model numbers, custom setups). "
                "Fields: substrate (list: sand, gravel, bare_bottom, soil, crushed_coral, other), "
                "substrate_other (string, custom substrate name when 'other' is in substrate list), "
                "filter_type (canister, hob, sponge, internal, undergravel, sump), "
                "filter_media (list: carbon, phosphate_pad, aragonite, bio_media, sponge, filter_floss, ceramic_rings, zeolite, ion_exchange_resin), "
                "lighting_type (led, t5, metal_halide, none), "
                "has_heater, has_air_pump, has_co2, has_protein_skimmer, has_ato, "
                "has_dosing_pump, has_live_rock, has_calcium_reactor (all booleans), "
                "notes (free-text for brand/model details, custom info). "
                "Set boolean fields to false to indicate removal. "
                "For 'notes', the value will be APPENDED to existing notes (not replaced)."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "substrate": {
                        "type": "array",
                        "items": {"type": "string", "enum": ["sand", "gravel", "bare_bottom", "soil", "crushed_coral", "other"]},
                        "description": "Full substrate list (replaces existing)",
                    },
                    "substrate_other": {"type": "string", "description": "Custom substrate name when 'other' is selected"},
                    "filter_type": {"type": "string", "enum": ["canister", "hob", "sponge", "internal", "undergravel", "sump"]},
                    "filter_media": {
                        "type": "array",
                        "items": {"type": "string", "enum": ["carbon", "phosphate_pad", "aragonite", "bio_media", "sponge", "filter_floss", "ceramic_rings", "zeolite", "ion_exchange_resin"]},
                        "description": "Full filter media list (replaces existing)",
                    },
                    "lighting_type": {"type": "string", "enum": ["led", "t5", "metal_halide", "none"]},
                    "has_heater": {"type": "boolean"},
                    "has_air_pump": {"type": "boolean"},
                    "has_co2": {"type": "boolean"},
                    "has_protein_skimmer": {"type": "boolean"},
                    "has_ato": {"type": "boolean"},
                    "has_dosing_pump": {"type": "boolean"},
                    "has_live_rock": {"type": "boolean"},
                    "has_calcium_reactor": {"type": "boolean"},
                    "notes": {"type": "string", "description": "Additional equipment details (brand, model, specs). Appended to existing notes."},
                },
            },
        },
        {
            "name": "select_tank",
            "description": (
                "Select which tank the conversation is about. "
                "Call this as soon as the user indicates which tank they're referring to — "
                "by name, by number from the list, or by description. "
                "This MUST be called before any other tool when the tank isn't pre-selected. "
                "Use the exact tank name from the available tanks list."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "tank_name": {"type": "string", "description": "Exact name of the selected tank from the available tanks list"},
                },
                "required": ["tank_name"],
            },
        },
        {
            "name": "log_measurements",
            "description": (
                f"Log numeric water parameter measurements to the user's journal. Today is {client_date}. "
                "Use standard keys: pH, KH, GH, Ca, Mg, ammonia, nitrite, nitrate, K, salinity, temp. "
                "Temp should include unit like '78°F' or '26°C'. All others are numeric. "
                "Call this EVERY TIME the user shares water test results — this is how data gets saved. "
                "You MUST call this tool to actually log measurements; just saying 'Logged' is not enough. "
                "When the user provides before/after readings, log ONLY the most recent set here. "
                "Earlier readings go into log_notes with context."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "measurements": {
                        "type": "object",
                        "description": "Key-value pairs of parameter name to value.",
                    },
                    "date": {
                        "type": "string",
                        "description": "YYYY-MM-DD date for these measurements. Use today if not specified.",
                        "nullable": True,
                    },
                    "is_tap_water": {
                        "type": "boolean",
                        "description": "True if these are tap/source water readings, not tank water.",
                        "nullable": True,
                    },
                },
                "required": ["measurements"],
            },
        },
        {
            "name": "log_actions",
            "description": (
                "Log maintenance actions the user performed on their tank. "
                "Use short descriptions with quantities: '5ml Prime', '20% water change', 'Fed fish'. "
                "Call this EVERY TIME the user describes maintenance they did."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "actions": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "List of action descriptions.",
                    },
                    "date": {
                        "type": "string",
                        "description": "YYYY-MM-DD date. Use today if not specified.",
                        "nullable": True,
                    },
                },
                "required": ["actions"],
            },
        },
        {
            "name": "log_notes",
            "description": (
                "Log observations about the tank — visual, behavioral, condition notes. "
                "Deaths, smells, cloudiness, qualitative trends. NEVER log questions as notes. "
                "Call this EVERY TIME the user shares observations. "
                "Also use this for earlier/before measurements when the user provides before/after readings."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "notes": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "List of observation descriptions.",
                    },
                    "date": {
                        "type": "string",
                        "description": "YYYY-MM-DD date. Use today if not specified.",
                        "nullable": True,
                    },
                },
                "required": ["notes"],
            },
        },
    ]



@app.post("/chat/summarize")
@limiter.limit("20/minute")
def chat_summarize(request: Request, req: SummarizeSessionRequest, user_id: str = Depends(_get_user_id)):
    """Generate a 1-2 sentence summary of a chat session."""
    client, has_llm = _get_llm_client()
    if not has_llm:
        return {"summary": ""}
    try:
        # Filter to just user/assistant messages with content
        msgs = [{"role": m.get("role", "user"), "content": m.get("content", "")}
                for m in req.messages if m.get("content")]
        # Skip leading assistant messages
        while msgs and msgs[0]["role"] == "assistant":
            msgs.pop(0)
        if len(msgs) < 2:
            return {"summary": ""}
        tank_note = f" The tank discussed is '{req.tank_name}'." if req.tank_name else ""
        resp = _chat(client,
            model="claude-haiku-4-5",
            max_tokens=100,
            system=f"Summarize this aquarium chat session in 1-2 sentences. Focus on what was logged, discussed, decided, or any issues raised.{tank_note} Return ONLY the summary text.",
            messages=msgs,
        )
        return {"summary": resp.content[0].text.strip()}
    except Exception as e:
        print(f"[Summarize] error: {e}")
        return {"summary": ""}


@app.post("/chat/tank")
@limiter.limit("20/minute")
def chat_tank(request: Request, req: ChatRequest, user_id: str = Depends(_get_user_id)):
    client, has_llm = _get_llm_client()
    if not has_llm:
        return {"response": "AI chat is unavailable (no API key configured).", "tasks": []}

    tank = req.tank or {}
    inhabitants = tank.get("inhabitants", [])
    plants = tank.get("plants", [])
    # Use detailed tank list if available, otherwise fall back to names
    available_tanks_detail = req.available_tanks_detail or []
    available_tank_names = req.available_tanks or []
    # Build a unified list: prefer detail, fall back to names
    if available_tanks_detail:
        available_tanks = available_tanks_detail
    else:
        available_tanks = available_tank_names
    no_tank_context = not tank  # chat opened from home page — no tank pre-selected

    # Format tank list — supports both old (string) and new (dict) formats
    def _fmt_tank(t):
        if isinstance(t, dict):
            name = t.get("name", "Unknown")
            gal = t.get("gallons", "?")
            wt = t.get("water_type", "")
            created = t.get("created_at", "")[:10]  # YYYY-MM-DD
            return f'"{name}" ({gal} gal, {wt}, created {created})'
        return f'"{t}"'

    def _tank_name(t):
        return t.get("name", str(t)) if isinstance(t, dict) else str(t)

    def _tank_short(t):
        if isinstance(t, dict):
            name = t.get("name", "Unknown")
            gal = t.get("gallons", "?")
            return f'{name} ({gal} gal)'
        return str(t)

    print(f"[Chat] tank={'set' if tank else 'none'} available_tanks={[_tank_name(t) for t in available_tanks]} no_tank_context={no_tank_context}")
    print(f"[Chat] req.tank raw={req.tank}")
    print(f"[Chat] tank after or={{}}={tank}")

    if no_tank_context and len(available_tanks) > 1:
        # Build a numbered list so Ariel can present it and user can reply by number
        numbered_lines = []
        number_mapping = []  # explicit "1 = Tank Name" mapping
        for i, t in enumerate(available_tanks, 1):
            if isinstance(t, dict):
                name = t.get("name", "Unknown")
                gal = t.get("gallons", "?")
                wt = (t.get("water_type", "") or "").capitalize()
                numbered_lines.append(f"{i}. {name} — {gal}g {wt}")
                number_mapping.append(f"{i} = \"{name}\" ({gal}g {wt})")
            else:
                numbered_lines.append(f"{i}. {t}")
                number_mapping.append(f"{i} = \"{t}\"")
        numbered_list = "\n".join(numbered_lines)
        mapping_text = ", ".join(number_mapping)
        tank_context = (
            f"MULTI-TANK SESSION: The user has multiple tanks.\n"
            f"Tank list (THIS IS THE AUTHORITATIVE NUMBERING):\n{numbered_list}\n\n"
            f"Number-to-tank mapping: {mapping_text}\n"
            f"No specific tank is selected for this conversation.\n"
            f"IMPORTANT: Before logging any measurement, observation, action, task, or adding/removing inhabitants or plants, "
            f"you MUST ask which tank it applies to if it is not already clear from context. "
            f"This includes when the user mentions buying, picking up, or acquiring new fish, plants, or livestock "
            f"(e.g. 'I just picked up an amazon sword', 'I bought some neon tetras', 'I got a nerite snail') — "
            f"these are ADD requests. Ask which tank to add them to.\n"
            f"MANDATORY FORMAT — when asking which tank, you MUST present the numbered list above exactly as shown. "
            f"Do NOT use bullet points. Do NOT reorder or reformat.\n"
            f"NUMBER RESOLUTION: If the user replies with a number (e.g. '1', '2', '3'), look up the number in the mapping above. "
            f"For example if the user says '2', that means {number_mapping[1] if len(number_mapping) > 1 else 'the second tank'}. "
            f"Always confirm which tank you selected in your reply.\n"
            f"If the user refers to a tank indirectly (e.g. 'the one I just created', 'my big tank', 'the reef'), "
            f"use the tank details above (size, type, creation date) to resolve which tank they mean. "
            f"Once the tank is identified, confirm it in your reply (e.g. 'Got it — adding that to [Tank Name].'). "
            f"If the user's message is a general question or doesn't involve logging, no clarification is needed.\n"
            f"HARD RULE: The ONLY valid tanks are listed above. You CANNOT log data to any tank not in that list. "
            f"If the user names a tank that is NOT listed above, it does not exist or has been archived. "
            f"Do NOT say you are logging to it. Instead say something like: "
            f"\"I don't see a tank called [name] in your active tanks. Your current tanks are: {', '.join(_tank_short(t) for t in available_tanks)}. Which one did you mean?\"\n"
            f"Note: you can still create NEW tank profiles if the user asks — do not refuse.\n"
        )
    elif no_tank_context and len(available_tanks) == 1:
        tank_context = (
            f"Current tank context: {_fmt_tank(available_tanks[0])} (only tank).\n"
            f"Note: you can still create NEW tank profiles if the user asks — do not refuse.\n"
        )
    else:
        tank_context = (
            f"Current tank context: {tank.get('name', 'Unknown')} — "
            f"{tank.get('gallons', '?')} gal, {tank.get('water_type', 'unknown')} water.\n"
            f"The user opened this chat from WITHIN this tank. Default ALL tasks, reminders, and logs to this tank — "
            f"do NOT ask which tank unless the user explicitly mentions a different tank by name.\n"
            f"Note: you can still create NEW tank profiles if the user asks — do not refuse.\n"
        )
        if len(available_tanks) > 1:
            tanks_list = "\n".join(f"  - {_fmt_tank(t)}" for t in available_tanks)
            tank_context += f"The user also has these other tanks:\n{tanks_list}\nOnly switch if they explicitly mention one of these tanks.\n"
    if tank.get("has_csv_imports"):
        tank_context += "This tank has imported historical water parameter data from a CSV — treat it as an established, already-running tank. Do NOT ask about cycling or initial setup.\n"
    if inhabitants:
        tank_context += f"Inhabitants: {', '.join(inhabitants)}.\n"
        # Flag sensitive categories so the model applies extra caution
        lower_inh = " ".join(inhabitants).lower()
        _invertebrate_keywords = [
            "shrimp", "snail", "crab", "crayfish", "clam", "mussel", "lobster",
            "urchin", "starfish", "sea star", "hermit", "cucumber", "feather duster",
            "bristleworm", "worm", "nerite", "mystery snail", "assassin snail",
            "amano", "cherry", "neocaridina", "caridina",
        ]
        _scaleless_keywords = [
            "loach", "catfish", "corydora", "cory", "eel", "knifefish",
            "dojo", "clown loach", "weather loach",
        ]
        has_inverts = any(k in lower_inh for k in _invertebrate_keywords)
        has_scaleless = any(k in lower_inh for k in _scaleless_keywords)
        if has_inverts:
            tank_context += "⚠️ SENSITIVE INHABITANTS DETECTED: Invertebrates present. Avoid copper. Recommend only very gradual pH/GH/KH changes.\n"
        if has_scaleless:
            tank_context += "⚠️ SENSITIVE INHABITANTS DETECTED: Scaleless fish present. Copper-based treatments are unsafe.\n"
    if plants:
        tank_context += f"Plants: {', '.join(plants)}.\n"

    # Tap water profile — used when advising on water parameter adjustments
    tap_water = tank.get("tap_water")
    if tap_water and isinstance(tap_water, dict):
        tw_parts = []
        labels = {"ph": "pH", "gh": "GH", "kh": "KH", "ammonia": "Ammonia",
                  "nitrite": "Nitrite", "nitrate": "Nitrate", "tds": "TDS",
                  "phosphate": "Phosphate", "silicate": "Silicate", "copper": "Copper",
                  "iron": "Iron", "calcium": "Calcium", "magnesium": "Magnesium",
                  "salinity": "Salinity", "temp": "Temperature", "chlorine": "Chlorine",
                  "chloramine": "Chloramine", "potassium": "Potassium", "co2": "CO₂"}
        units  = {"gh": "°dH", "kh": "°dH", "ammonia": "ppm", "nitrite": "ppm",
                  "nitrate": "ppm", "tds": "ppm", "phosphate": "ppm", "silicate": "ppm",
                  "copper": "ppm", "iron": "ppm", "calcium": "ppm", "magnesium": "ppm",
                  "salinity": "ppt", "temp": "°F", "chlorine": "ppm", "chloramine": "ppm",
                  "potassium": "ppm", "co2": "ppm"}
        for k, v in tap_water.items():
            lbl = labels.get(k, k)
            unit = units.get(k, "")
            tw_parts.append(f"{lbl}: {v}{(' ' + unit) if unit else ''}")
        if tw_parts:
            tank_context += f"Tap water profile: {', '.join(tw_parts)}.\n"

    # Equipment profile
    equipment = tank.get("equipment")
    if equipment and isinstance(equipment, dict):
        eq_parts = []
        # Substrate (now a list)
        substrate = equipment.get("substrate")
        if substrate:
            if isinstance(substrate, list):
                sub_names = [s.replace("_", " ").title() for s in substrate if s != "other"]
                other = equipment.get("substrate_other")
                if other and isinstance(other, str) and other.strip():
                    sub_names.append(other.strip())
                if sub_names:
                    eq_parts.append(f"Substrate: {', '.join(sub_names)}")
            elif isinstance(substrate, str):
                eq_parts.append(f"Substrate: {substrate.replace('_', ' ').title()}")
        label_map = {
            "lighting_type": "Lighting", "filter_type": "Filter",
            "photoperiod_hours": "Photoperiod", "target_temp": "Target temp",
            "wc_frequency": "Water change frequency", "wc_percent": "Water change amount",
        }
        bool_labels = {
            "has_heater": "Heater", "has_air_pump": "Air pump", "has_co2": "CO2 injection",
            "has_protein_skimmer": "Protein skimmer",
            "has_calcium_reactor": "Calcium reactor", "has_wavemaker": "Wavemaker/powerhead",
            "has_ato": "Auto top-off (ATO)", "has_dosing_pump": "Dosing pump",
            "has_refugium": "Refugium/sump", "has_uv_sterilizer": "UV sterilizer",
            "has_live_rock": "Live rock",
        }
        for k, lbl in label_map.items():
            v = equipment.get(k)
            if v is not None and v != "":
                display = str(v).replace("_", " ").title() if isinstance(v, str) else str(v)
                if k == "photoperiod_hours":
                    display += " hrs"
                elif k == "target_temp":
                    display += "°F"
                elif k == "wc_percent":
                    display += "%"
                eq_parts.append(f"{lbl}: {display}")
        for k, lbl in bool_labels.items():
            if equipment.get(k) is True:
                eq_parts.append(lbl)
        media = equipment.get("filter_media")
        if media and isinstance(media, list):
            eq_parts.append(f"Filter media: {', '.join(m.replace('_', ' ').title() for m in media)}")
        if eq_parts:
            tank_context += f"Equipment: {', '.join(eq_parts)}.\n"
        notes = equipment.get("notes")
        if notes and isinstance(notes, str) and notes.strip():
            tank_context += f"Equipment notes: {notes.strip()}\n"

    if req.recent_logs:
        recent = "\n".join(f"- {l}" for l in req.recent_logs[:10])
        tank_context += f"Recent journal entries (last 2 weeks):\n{recent}\n"

    # Mandate that Ariel always considers the full tank context
    tank_context += (
        "\nMANDATORY CONTEXT AWARENESS — apply to EVERY response:\n"
        "Before answering ANY question or giving ANY advice, you MUST consider ALL of the following:\n"
        "1. WATER TYPE: freshwater vs saltwater vs reef vs planted — advice differs dramatically between these.\n"
        "2. INHABITANTS: Which specific fish, invertebrates, corals are in the tank. Tailor advice to their needs and sensitivities.\n"
        "3. PLANTS: Whether the tank has live plants and which species. Planted tanks have different parameter priorities.\n"
        "4. TAP WATER PROFILE: If provided, factor tap water parameters into all water chemistry advice. Every water change moves tank values toward tap water, not toward zero.\n"
        "5. EQUIPMENT: What filtration, lighting, CO2, protein skimmer, heater, etc. the tank has. Equipment determines what advice is practical — don't suggest adjustments to equipment the user doesn't have.\n"
        "6. RECENT JOURNAL ENTRIES: Any journal entries from the last 2 weeks including measurements, actions, and notes. ALWAYS check these entries before making any claim about when the user last did something (water change, test, dosing, etc.). If the journal shows a recent water change, do NOT say it has been a while.\n"
        "7. USER EXPERIENCE LEVEL: Beginner, intermediate, or advanced — adjust depth and tone accordingly.\n"
        "8. INHABITANT PLAUSIBILITY: If the user mentions an animal or plant that does NOT match the tank's water type "
        "(e.g. an octopus in a freshwater tank, a discus in a saltwater tank, a coral in a freshwater tank), "
        "do NOT assume they have it. Instead, gently ask for clarification — e.g. "
        "\"Octopuses are saltwater animals — could you mean a different creature, or has your setup changed?\" "
        "This also applies if the mentioned creature is not in the known inhabitants list and seems implausible for the tank type.\n"
        "If any of these factors would change your advice, you MUST factor them in. "
        "For example, do not give generic freshwater advice to a reef tank, "
        "do not ignore that the tank has shrimp when suggesting treatments, "
        "and do not overlook recent parameter readings that are relevant to the user's question.\n"
    )

    # Health profile — computed stats from the user's log history
    if req.health_profile:
        hp = req.health_profile
        hp_parts = []
        if "days_since_last_test" in hp:
            hp_parts.append(f"Last test: {hp['days_since_last_test']} day(s) ago")
        if "avg_days_between_tests" in hp:
            hp_parts.append(f"Avg interval between tests: {hp['avg_days_between_tests']} days")
        if "water_changes_last_30d" in hp:
            hp_parts.append(f"Water changes in last 30 days: {hp['water_changes_last_30d']}")
        if hp.get("parameter_averages"):
            avgs = ", ".join(f"{k}: {v}" for k, v in hp["parameter_averages"].items())
            hp_parts.append(f"30-day averages: {avgs}")
        if hp.get("parameter_trends"):
            trends = ", ".join(f"{k} {v}" for k, v in hp["parameter_trends"].items())
            hp_parts.append(f"Trends: {trends}")
        if hp_parts:
            tank_context += "Tank health profile:\n" + "\n".join(f"  - {p}" for p in hp_parts) + "\n"
            tank_context += "IMPORTANT: Always cross-reference this profile with the recent journal entries above. Do NOT contradict what the journal shows. If the journal shows a recent water change or action, the health profile confirms it — never claim otherwise. Be natural, not robotic.\n"

    # User behavior patterns — testing habits and follow-through
    if req.behavior_profile:
        bp = req.behavior_profile
        bp_parts = []
        if "tests_per_month" in bp:
            bp_parts.append(f"Tests ~{bp['tests_per_month']:.1f}x/month")
        if bp.get("most_tested"):
            bp_parts.append(f"Regularly tests: {', '.join(bp['most_tested'])}")
        if bp.get("least_tested"):
            bp_parts.append(f"Rarely tests: {', '.join(bp['least_tested'])}")
        if bp.get("recurring_issues"):
            bp_parts.append(f"Recurring concerns: {', '.join(bp['recurring_issues'])}")
        if "task_completion_rate" in bp:
            bp_parts.append(f"Task follow-through: {bp['task_completion_rate']:.0%}")
        if bp.get("testing_regularity"):
            bp_parts.append(f"Testing pattern: {bp['testing_regularity']}")
        if bp_parts:
            tank_context += "User behavior patterns:\n" + "\n".join(f"  - {p}" for p in bp_parts) + "\n"
            tank_context += "Personalize advice based on these patterns. Reference habits naturally — never be judgmental about frequency.\n"

    # Session summaries — memory of past conversations
    if req.session_summaries:
        summaries = req.session_summaries[:5]  # limit to 5 most recent
        tank_context += "Previous conversation summaries (most recent first):\n"
        for s in summaries:
            tank_context += f"  - {s}\n"
        tank_context += "Reference past conversations naturally when relevant — e.g. 'Last time we talked about...' — but don't force it.\n"

    # Experience level — adapt tone and depth
    if req.experience_level:
        level = req.experience_level.lower()
        if level == 'beginner':
            tank_context += (
                "USER EXPERIENCE: Beginner. This user is new to fishkeeping. "
                "When they report a problem, ask diagnostic questions first — don't assume they've tested water parameters. "
                "Explain concepts simply. Suggest testing before recommending actions. "
                "Frame suggestions gently: 'Have you tested your water recently?' before 'Try a water change.'\n"
            )
        elif level == 'intermediate':
            tank_context += (
                "USER EXPERIENCE: Intermediate. This user is comfortable with basics. "
                "You can reference parameters and concepts without over-explaining, but still ask before assuming.\n"
            )
        elif level == 'advanced':
            tank_context += (
                "USER EXPERIENCE: Advanced. This user is experienced. "
                "Be concise and technical. Skip basic explanations unless asked.\n"
            )

    # RAG: inject relevant community knowledge
    water_type = tank.get("water_type", "freshwater")
    knowledge = _search_knowledge(req.message, water_type, inhabitants)
    if knowledge:
        tank_context += f"\n{knowledge}\n"

    messages = []
    for h in (req.history or []):
        role = h.get("role", "user")
        content = h.get("content", "")
        if role in ("user", "assistant") and content:
            messages.append({"role": role, "content": content})
    messages.append({"role": "user", "content": req.message})

    try:
        # Fast path: extract tasks from a manual note without generating a chat reply
        if req.extract_tasks_only:
            today_str = req.client_date or date.today().isoformat()
            note_extract_prompt = (
                "Analyze this aquarium journal note. If the note describes a problem or "
                "concern that clearly warrants a follow-up action, extract ONE concise task. "
                "If the note is just a routine observation, measurement, or log with nothing "
                "actionable, return an empty task list.\n\n"
                f"Today's date is {today_str}.\n\n"
                "Return ONLY valid JSON (no markdown, no explanation):\n"
                '{"tasks": [{"description": "short action", "due_date": "YYYY-MM-DD"}]}\n\n'
                "Rules:\n"
                "- Return at most ONE task — the single most important follow-up\n"
                "- Only return a task if there is a clear problem or concern (sick fish, "
                "equipment issue, parameter spike, etc.)\n"
                "- Do NOT create tasks for routine observations like 'fed fish', "
                "'water looks clear', 'did a water change'\n"
                "- due_date: default to tomorrow unless urgency warrants today\n"
                '- If nothing is actionable, return {"tasks": []}'
            )
            try:
                ex_response = _chat(client,
                    model="claude-haiku-4-5",
                    max_tokens=256,
                    system=note_extract_prompt,
                    messages=[
                        {"role": "user", "content": req.message},
                    ],
                )
                raw = ex_response.content[0].text.strip()
                json_match = re.search(r"\{.*\}", raw, flags=re.DOTALL)
                if json_match:
                    raw = json_match.group(0)
                parsed = json.loads(raw)
                tasks = parsed.get("tasks", [])
                print(f"[NoteExtract] extracted {len(tasks)} task(s) from note: {tasks}")
                return {"response": "", "tasks": tasks}
            except Exception as e:
                print(f"[NoteExtract] error: {e}")
                return {"response": "", "tasks": []}

        chat_water_type = (tank.get("water_type") or tank.get("waterType") or "") if tank else ""
        all_wt = [t.get("water_type", "") for t in (req.available_tanks_detail or [])]
        today_str = req.client_date or date.today().isoformat()

        # Build tools for LLM function calling
        tools = _build_chat_tools(client_date=today_str, plants=plants)

        response = _chat(client,
            model=_pick_model(experience=req.experience_level or "", water_type=chat_water_type, all_water_types=all_wt),
            max_tokens=1024,
            system=_CHAT_SYSTEM_PROMPT + f"\n\n{tank_context}" + (f"\n\n{req.system_context}" if req.system_context else ""),
            messages=messages,
            tools=tools,
            tool_choice={"type": "auto"},
        )
        reply = response.content[0].text.strip()
        tool_calls = getattr(response, "tool_calls", []) or []

        print(f"[Chat] reply={reply[:100]}... tool_calls={[tc['name'] for tc in tool_calls]}")

        # Map tool calls to response fields
        new_tank = None
        new_inhabitant = None
        remove_inhabitants = None
        new_plants = None
        remove_plants = None
        rename_plant = None
        measurement_correction = None
        tap_water_update = None
        remove_action = None
        remove_note = None
        remove_task = None
        equipment_update = None
        selected_tank = None
        extracted_tasks: List[Dict[str, Any]] = []
        log_entries: List[Dict[str, Any]] = []

        for tc in tool_calls:
            name = tc["name"]
            inp = tc.get("input", {})
            print(f"[ToolCall] {name}: {inp}")

            if name == "add_inhabitants" and inp.get("inhabitants"):
                new_inhabitant = inp
            elif name == "remove_inhabitants" and inp.get("inhabitants"):
                remove_inhabitants = inp
            elif name == "add_plants" and inp.get("plants"):
                new_plants = inp
            elif name == "remove_plants" and inp.get("plants"):
                remove_plants = inp
            elif name == "rename_plant" and inp.get("old_name") and inp.get("new_name"):
                rename_plant = inp
            elif name == "create_task" and inp.get("tasks"):
                extracted_tasks = inp["tasks"]
            elif name == "measurement_correction" and inp.get("date"):
                measurement_correction = inp
            elif name == "tap_water_update":
                # Filter to only numeric values
                tap_water_update = {k: v for k, v in inp.items() if isinstance(v, (int, float))}
                if not tap_water_update:
                    tap_water_update = None
            elif name == "create_tank" and inp.get("tank", {}).get("name"):
                new_tank = inp
            elif name == "remove_action" and inp.get("action"):
                remove_action = inp
            elif name == "remove_note" and inp.get("note"):
                remove_note = inp
            elif name == "remove_task" and inp.get("description"):
                remove_task = inp
            elif name == "update_equipment" and inp:
                equipment_update = inp
            elif name == "select_tank" and inp.get("tank_name"):
                selected_tank = inp["tank_name"]
            elif name == "log_measurements" and inp.get("measurements"):
                entry_date = inp.get("date") or today_str
                entry = {"measurements": inp["measurements"], "date": entry_date}
                if inp.get("is_tap_water"):
                    entry["source"] = "tap_water"
                log_entries.append(entry)
            elif name == "log_actions" and inp.get("actions"):
                entry_date = inp.get("date") or today_str
                log_entries.append({"actions": [_sentence_case(a) for a in inp["actions"]], "date": entry_date})
            elif name == "log_notes" and inp.get("notes"):
                entry_date = inp.get("date") or today_str
                log_entries.append({"notes": [_sentence_case(n) for n in inp["notes"]], "date": entry_date})

        return {
            "response": reply,
            "tasks": extracted_tasks,
            "new_tank": new_tank,
            "new_inhabitant": new_inhabitant,
            "remove_inhabitants": remove_inhabitants,
            "new_plants": new_plants,
            "remove_plants": remove_plants,
            "rename_plant": rename_plant,
            "measurement_correction": measurement_correction,
            "tap_water_update": tap_water_update,
            "remove_action": remove_action,
            "remove_note": remove_note,
            "remove_task": remove_task,
            "equipment_update": equipment_update,
            "selected_tank": selected_tank,
            "log_entries": log_entries if log_entries else None,
            "_log_debug": [{"name": tc["name"], "input": tc.get("input", {})} for tc in tool_calls] if tool_calls else None,
            "_debug": {
                "tool_calls": [tc["name"] for tc in tool_calls],
            },
        }
    except Exception as e:
        print(f"[Chat] error: {e}")
        return {"response": "Sorry, I couldn't process that right now.", "tasks": []}


@app.post("/advise/next-steps")
@limiter.limit("20/minute")
def advise_next_steps(request: Request, req: AdviseRequest, user_id: str = Depends(_get_user_id)):
    """
    Advice endpoint (mock). We'll later replace this with real AI.
    """
    return {
        "schemaVersion": 1,
        "summary": "Good start. Next, confirm cycling status and ensure compatible stocking.",
        "nextSteps": [
            {
                "title": "Confirm nitrogen cycle status",
                "detail": "If this is a new tank, test ammonia/nitrite daily until both are 0.",
            },
            {
                "title": "Check stocking and compatibility",
                "detail": "Avoid adding all fish at once; introduce in stages.",
            },
        ],
        "questions": [
            "Is the tank cycled (ammonia = 0 and nitrite = 0)?",
            "What is the temperature and filtration type?",
        ],
        "cautions": [
            "Don’t add sensitive fish to an uncycled tank.",
            "Quarantine new fish when possible.",
        ],
        "disclaimer": "General information only; not veterinary advice.",
    }


_MODERATION_SYSTEM_PROMPT = """You are a content moderator for Aquaria, an aquarium tank management app. Evaluate each numbered task/reminder and decide if it should be saved.

Approve a task if it is:
- Appropriate (not offensive, abusive, or self-deprecating)
- Relevant to aquarium or fish tank keeping — this includes water testing, water changes, feeding, cleaning, equipment maintenance, medication, plant care, livestock health, purchasing aquarium supplies, or calling a fish store

Reject a task if it is:
- An insult, personal attack, or joke at the user's own expense (e.g. "remind me that I suck")
- Entirely unrelated to aquarium keeping with no plausible aquarium interpretation
- Nonsensical or clearly not an actionable tank-keeping reminder

Return ONLY valid JSON — no markdown, no explanation:
{"results": [true, false, true]}

The results array must be the same length as the input list, in the same order. true = approve, false = reject."""


@app.post("/moderate/tasks")
@limiter.limit("30/minute")
def moderate_tasks(request: Request, req: ModerationRequest, user_id: str = Depends(_get_user_id)):
    if not req.tasks:
        return {"results": []}
    client, has_llm = _get_llm_client()
    if not has_llm:
        return {"results": [True] * len(req.tasks)}
    try:
        task_list = "\n".join(f"{i + 1}. {t}" for i, t in enumerate(req.tasks))
        response = _chat(client,
            model="claude-haiku-4-5",
            max_tokens=128,
            system=[{
                "type": "text",
                "text": _MODERATION_SYSTEM_PROMPT,
                "cache_control": {"type": "ephemeral"},
            }],
            messages=[{"role": "user", "content": task_list}],
            extra_headers={"anthropic-beta": "prompt-caching-2024-07-31"},
        )
        raw = response.content[0].text.strip()
        parsed = json.loads(raw)
        results = parsed.get("results", [])
        # Pad with True if the model returns fewer results than expected
        while len(results) < len(req.tasks):
            results.append(True)
        return {"results": results[:len(req.tasks)]}
    except Exception as e:
        print(f"[Moderate] error: {e}")
        return {"results": [True] * len(req.tasks)}  # fail open


@app.post("/knowledge/ingest")
@limiter.limit("10/minute")
def knowledge_ingest(request: Request, req: KnowledgeIngestRequest, user_id: str = Depends(_get_user_id)):
    """Store an anonymized observation+resolution pair in the community knowledge base."""
    if not req.observation.strip() or not req.resolution.strip():
        return {"status": "error", "message": "observation and resolution are required"}
    try:
        conn = sqlite3.connect(_KNOWLEDGE_DB_PATH)
        conn.execute(
            "INSERT INTO knowledge_entries (water_type, species_tags, parameter_tags, topic_tags, observation, resolution) VALUES (?,?,?,?,?,?)",
            (req.water_type, req.species_tags, req.parameter_tags, req.topic_tags,
             req.observation.strip(), req.resolution.strip()),
        )
        conn.commit()
        conn.close()
        return {"status": "ok"}
    except Exception as e:
        print(f"[Knowledge/Ingest] error: {e}")
        return {"status": "error", "message": str(e)}


def _upload_feedback_attachment(file_bytes: bytes, file_name: str) -> Optional[str]:
    """Upload feedback attachment to Supabase Storage. Returns public URL or None."""
    if not _SUPABASE_SERVICE_KEY or not file_bytes:
        return None
    try:
        import uuid as _uuid
        # Unique path to avoid collisions
        ext = os.path.splitext(file_name)[1] if file_name else ""
        path = f"feedback/{_uuid.uuid4().hex}{ext}"
        # Guess content type
        ct = "application/octet-stream"
        lower = (file_name or "").lower()
        if lower.endswith((".png",)):
            ct = "image/png"
        elif lower.endswith((".jpg", ".jpeg")):
            ct = "image/jpeg"
        elif lower.endswith((".pdf",)):
            ct = "application/pdf"
        elif lower.endswith((".txt",)):
            ct = "text/plain"
        req = urllib.request.Request(
            f"{_SUPABASE_URL}/storage/v1/object/feedback-attachments/{path}",
            data=file_bytes,
            headers={
                "apikey": _SUPABASE_SERVICE_KEY,
                "Authorization": f"Bearer {_SUPABASE_SERVICE_KEY}",
                "Content-Type": ct,
            },
            method="POST",
        )
        urllib.request.urlopen(req, timeout=15)
        public_url = f"{_SUPABASE_URL}/storage/v1/object/public/feedback-attachments/{path}"
        print(f"[Feedback] attachment uploaded: {path}", flush=True)
        return public_url
    except Exception as e:
        print(f"[Feedback] attachment upload error: {e}", flush=True)
        return None


def _save_feedback_supabase(user_id: Optional[str], message: str, device: Optional[str],
                            attachment_name: Optional[str], file_bytes: Optional[bytes] = None):
    """Write feedback to Supabase so the admin console can read it."""
    if not _SUPABASE_SERVICE_KEY:
        print("[Feedback] Supabase skipped: no service key", flush=True)
        return
    try:
        # Upload attachment if present
        attachment_url = None
        if file_bytes and attachment_name:
            attachment_url = _upload_feedback_attachment(file_bytes, attachment_name)
        # user_id must be a valid UUID or null
        uid = user_id if user_id and len(user_id) == 36 and "-" in user_id else None
        payload = json.dumps({
            "user_id": uid,
            "message": message,
            "device": device,
            "attachment_name": attachment_name,
            "attachment_url": attachment_url,
        }).encode()
        req = urllib.request.Request(
            f"{_SUPABASE_URL}/rest/v1/feedback",
            data=payload,
            headers={
                "apikey": _SUPABASE_SERVICE_KEY,
                "Authorization": f"Bearer {_SUPABASE_SERVICE_KEY}",
                "Content-Type": "application/json",
                "Prefer": "return=minimal",
            },
            method="POST",
        )
        urllib.request.urlopen(req, timeout=5)
        print("[Feedback] saved to Supabase", flush=True)
    except Exception as e:
        print(f"[Feedback] Supabase error: {e}", flush=True)


def _send_feedback_email(message: str, device: Optional[str], file_bytes: Optional[bytes], file_name: Optional[str]):
    """Send feedback email in a background thread so the endpoint doesn't block."""
    smtp_user = os.environ.get("SMTP_USER")
    smtp_pass = os.environ.get("SMTP_PASS")
    if not smtp_user or not smtp_pass:
        return
    try:
        label = f"[{device}]" if device else ""
        timestamp = datetime.now().isoformat(timespec="seconds")
        msg = MIMEMultipart()
        msg["From"] = smtp_user
        msg["To"] = "info@aquaria-ai.com"
        msg["Subject"] = f"Aquaria App Feedback {label}"
        body = f"Timestamp: {timestamp}\nDevice: {device or 'unknown'}\n\n{message}"
        msg.attach(MIMEText(body, "plain"))
        if file_bytes and file_name:
            part = MIMEBase("application", "octet-stream")
            part.set_payload(file_bytes)
            encoders.encode_base64(part)
            part.add_header("Content-Disposition", f'attachment; filename="{file_name}"')
            msg.attach(part)
        with smtplib.SMTP("smtp.gmail.com", 587, timeout=10) as server:
            server.starttls()
            server.login(smtp_user, smtp_pass)
            server.send_message(msg)
        print("[Feedback] email sent", flush=True)
    except Exception as e:
        print(f"[Feedback] email error: {e}", flush=True)


# JSON feedback endpoint (backwards-compatible with older app versions)
@app.post("/feedback")
@limiter.limit("5/minute")
async def submit_feedback_json(request: Request, req: FeedbackRequest):
    timestamp = datetime.now().isoformat(timespec="seconds")
    label = f"[{req.device}]" if req.device else ""
    entry = f"[{timestamp}]{label} {req.message}\n"
    try:
        with open("feedback.log", "a", encoding="utf-8") as f:
            f.write(entry)
    except Exception as e:
        print(f"[Feedback] could not write to file: {e}")
    print(f"📩 FEEDBACK: {entry}", flush=True)
    try:
        conn = sqlite3.connect(_KNOWLEDGE_DB_PATH)
        conn.execute("INSERT INTO feedback (message, device, attachment_name) VALUES (?, ?, ?)", (req.message, req.device, None))
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"[Feedback] DB error: {e}", flush=True)
    import threading
    user_id = _get_user_id(request)
    _save_feedback_supabase(user_id, req.message, req.device, None, None)
    threading.Thread(target=_send_feedback_email, args=(req.message, req.device, None, None), daemon=True).start()
    return {"status": "ok"}


# Multipart feedback endpoint (new app versions with file attachment)
@app.post("/feedback/upload")
@limiter.limit("5/minute")
async def submit_feedback_upload(
    request: Request,
    message: str = Form(...),
    device: Optional[str] = Form(None),
    attachment: Optional[UploadFile] = File(None),
):
    timestamp = datetime.now().isoformat(timespec="seconds")
    label = f"[{device}]" if device else ""
    entry = f"[{timestamp}]{label} {message}\n"
    try:
        with open("feedback.log", "a", encoding="utf-8") as f:
            f.write(entry)
    except Exception as e:
        print(f"[Feedback] could not write to file: {e}")
    print(f"📩 FEEDBACK: {entry}", flush=True)

    file_bytes = None
    file_name = None
    if attachment and attachment.filename:
        file_bytes = await attachment.read()
        file_name = attachment.filename

    try:
        conn = sqlite3.connect(_KNOWLEDGE_DB_PATH)
        conn.execute("INSERT INTO feedback (message, device, attachment_name) VALUES (?, ?, ?)", (message, device, file_name))
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"[Feedback] DB error: {e}", flush=True)

    import threading
    user_id = _get_user_id(request)
    _save_feedback_supabase(user_id, message, device, file_name, file_bytes)
    threading.Thread(target=_send_feedback_email, args=(message, device, file_bytes, file_name), daemon=True).start()


# ---------------------------------------------------------------------------
# Discord integration endpoints
# ---------------------------------------------------------------------------

def _supabase_rest(method: str, table: str, *, params: str = "", body: dict | None = None,
                   prefer: str = "return=representation") -> Any:
    """Helper to call the Supabase REST API with the service role key."""
    url = f"{_SUPABASE_URL}/rest/v1/{table}"
    if params:
        url += f"?{params}"
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "apikey": _SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {_SUPABASE_SERVICE_KEY}",
        "Content-Type": "application/json",
        "Prefer": prefer,
    })
    try:
        resp = urllib.request.urlopen(req, timeout=10)
        raw = resp.read().decode()
        return json.loads(raw) if raw.strip() else None
    except urllib.error.HTTPError as e:
        body_text = e.read().decode() if e.fp else ""
        print(f"[Supabase] {method} {table} error {e.code}: {body_text}", flush=True)
        raise


def _discord_api(method: str, path: str, *, token: str | None = None,
                 bot: bool = False, data: dict | None = None,
                 files: dict | None = None) -> dict | list | None:
    """Call the Discord API. Uses bot token if bot=True, else user OAuth token."""
    headers = {}
    if bot:
        headers["Authorization"] = f"Bot {_DISCORD_BOT_TOKEN}"
    elif token:
        headers["Authorization"] = f"Bearer {token}"

    url = f"{_DISCORD_API}{path}"
    if files:
        resp = http_requests.request(method, url, headers=headers, data=data, files=files, timeout=30)
    elif data is not None:
        headers["Content-Type"] = "application/json"
        resp = http_requests.request(method, url, headers=headers, json=data, timeout=15)
    else:
        resp = http_requests.request(method, url, headers=headers, timeout=15)

    if resp.status_code == 204:
        return None
    if resp.status_code >= 400:
        print(f"[Discord] {method} {path} → {resp.status_code}: {resp.text}", flush=True)
        raise HTTPException(status_code=resp.status_code, detail=f"Discord API error: {resp.text}")
    return resp.json()


def _refresh_discord_token(user_id: str) -> str:
    """Get a valid Discord access token for user, refreshing if expired."""
    rows = _supabase_rest("GET", "discord_accounts",
                          params=f"user_id=eq.{user_id}&select=*")
    if not rows:
        raise HTTPException(status_code=404, detail="Discord account not linked")
    row = rows[0]
    # Check if token is still valid (expire 10s early to be safe)
    expires_at = row.get("token_expires_at", "")
    if expires_at:
        from datetime import timezone
        exp_dt = datetime.fromisoformat(expires_at.replace("Z", "+00:00"))
        if datetime.now(timezone.utc).timestamp() < exp_dt.timestamp() - 10:
            return row["access_token"]

    # Refresh the token
    resp = http_requests.post("https://discord.com/api/v10/oauth2/token", data={
        "grant_type": "refresh_token",
        "refresh_token": row["refresh_token"],
        "client_id": _DISCORD_CLIENT_ID,
        "client_secret": _DISCORD_CLIENT_SECRET,
    }, headers={"Content-Type": "application/x-www-form-urlencoded"}, timeout=15)
    if resp.status_code != 200:
        print(f"[Discord] token refresh failed: {resp.text}", flush=True)
        raise HTTPException(status_code=401, detail="Discord token refresh failed. Please re-link.")
    tokens = resp.json()
    new_expires = datetime.utcnow().isoformat() + "Z"
    if tokens.get("expires_in"):
        from datetime import timedelta
        new_expires = (datetime.utcnow() + timedelta(seconds=tokens["expires_in"])).isoformat() + "Z"
    # Update stored tokens
    _supabase_rest("PATCH", "discord_accounts",
                   params=f"user_id=eq.{user_id}",
                   body={
                       "access_token": tokens["access_token"],
                       "refresh_token": tokens.get("refresh_token", row["refresh_token"]),
                       "token_expires_at": new_expires,
                       "updated_at": datetime.utcnow().isoformat() + "Z",
                   }, prefer="return=minimal")
    return tokens["access_token"]


def _apply_watermark(image_bytes: bytes) -> bytes:
    """Apply an Aquaria text watermark to the bottom-right of an image."""
    img = Image.open(BytesIO(image_bytes)).convert("RGBA")
    from PIL import ImageDraw, ImageFont
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    # Scale font size to ~3.5% of image width for visibility
    font_size = max(20, int(img.width * 0.035))
    # Try multiple font paths (different Linux distros / containers)
    font = None
    font_paths = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/TTF/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf",
        "/usr/share/fonts/noto/NotoSans-Bold.ttf",
    ]
    for fp in font_paths:
        try:
            font = ImageFont.truetype(fp, font_size)
            print(f"[Watermark] using font: {fp}", flush=True)
            break
        except (OSError, IOError):
            continue
    if font is None:
        # Last resort: Pillow's built-in default at a larger size
        try:
            font = ImageFont.load_default(size=font_size)
            print(f"[Watermark] using default font at size {font_size}", flush=True)
        except TypeError:
            font = ImageFont.load_default()
            print("[Watermark] using default bitmap font (may be small)", flush=True)
    text = "aquaria.app"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    margin = int(img.width * 0.025)
    x = img.width - tw - margin
    y = img.height - th - margin
    # Dark shadow for contrast on light photos, then white text
    for dx, dy in [(2, 2), (1, 1), (-1, -1), (0, 2), (2, 0)]:
        draw.text((x + dx, y + dy), text, fill=(0, 0, 0, 160), font=font)
    draw.text((x, y), text, fill=(255, 255, 255, 220), font=font)
    result = Image.alpha_composite(img, overlay).convert("RGB")
    buf = BytesIO()
    result.save(buf, format="JPEG", quality=90)
    return buf.getvalue()


# --- OAuth Flow ---

@app.get("/discord/auth-url")
@limiter.limit("10/minute")
def discord_auth_url(request: Request, user_id: str = Depends(_get_user_id)):
    """Generate a Discord OAuth2 authorization URL for the user."""
    if not _DISCORD_CLIENT_ID:
        raise HTTPException(status_code=500, detail="Discord integration not configured")
    state = secrets.token_urlsafe(32)
    _save_oauth_state(state, "discord", user_id)
    url = (
        f"https://discord.com/oauth2/authorize"
        f"?client_id={_DISCORD_CLIENT_ID}"
        f"&response_type=code"
        f"&redirect_uri={urllib.request.quote(_DISCORD_REDIRECT_URI, safe='')}"
        f"&scope={urllib.request.quote(_DISCORD_SCOPES, safe='')}"
        f"&state={state}"
        f"&prompt=consent"
    )
    return {"url": url}


@app.get("/discord/callback")
def discord_callback(request: Request, code: str = "", state: str = "", error: str = ""):
    """Handle the OAuth2 callback from Discord."""
    if error:
        return HTMLResponse(f"<html><body><h2>Authorization failed</h2><p>{error}</p>"
                            f"<p>You can close this window.</p></body></html>")
    auth_data = _pop_oauth_state(state, "discord")
    user_id = auth_data["user_id"] if auth_data else None
    if not user_id:
        return HTMLResponse("<html><body><h2>Invalid or expired session</h2>"
                            "<p>Please try linking Discord again from the app.</p></body></html>")

    # Exchange code for tokens
    resp = http_requests.post(f"{_DISCORD_API}/oauth2/token", data={
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": _DISCORD_REDIRECT_URI,
        "client_id": _DISCORD_CLIENT_ID,
        "client_secret": _DISCORD_CLIENT_SECRET,
    }, headers={"Content-Type": "application/x-www-form-urlencoded"}, timeout=15)
    if resp.status_code != 200:
        print(f"[Discord] token exchange failed: {resp.text}", flush=True)
        return HTMLResponse("<html><body><h2>Token exchange failed</h2>"
                            "<p>Please try again.</p></body></html>")
    tokens = resp.json()
    access_token = tokens["access_token"]
    refresh_token = tokens.get("refresh_token", "")
    expires_in = tokens.get("expires_in", 604800)

    # Get Discord user info
    me = _discord_api("GET", "/users/@me", token=access_token)
    discord_username = me.get("username", "unknown")
    discord_id = me.get("id", "")

    from datetime import timedelta
    expires_at = (datetime.utcnow() + timedelta(seconds=expires_in)).isoformat() + "Z"

    # Upsert into Supabase
    _supabase_rest("POST", "discord_accounts",
                   params="on_conflict=user_id",
                   body={
                       "user_id": user_id,
                       "discord_id": discord_id,
                       "discord_username": discord_username,
                       "access_token": access_token,
                       "refresh_token": refresh_token,
                       "token_expires_at": expires_at,
                       "scopes": _DISCORD_SCOPES,
                       "updated_at": datetime.utcnow().isoformat() + "Z",
                   }, prefer="resolution=merge-duplicates,return=minimal")

    print(f"[Discord] linked user {user_id} → {discord_username} ({discord_id})", flush=True)
    return HTMLResponse(
        "<html><body style='font-family: system-ui; text-align: center; padding: 60px;'>"
        "<h2>✅ Discord linked!</h2>"
        f"<p>Connected as <strong>{discord_username}</strong></p>"
        "<p>You can close this window and return to Aquaria.</p>"
        "</body></html>"
    )


@app.get("/discord/status")
@limiter.limit("30/minute")
def discord_status(request: Request, user_id: str = Depends(_get_user_id)):
    """Check if the user has linked their Discord account."""
    try:
        rows = _supabase_rest("GET", "discord_accounts",
                              params=f"user_id=eq.{user_id}&select=discord_username,discord_id")
        if rows:
            return {"linked": True, "discord_username": rows[0]["discord_username"]}
    except Exception:
        pass
    return {"linked": False}


@app.delete("/discord/unlink")
@limiter.limit("5/minute")
def discord_unlink(request: Request, user_id: str = Depends(_get_user_id)):
    """Unlink the user's Discord account."""
    try:
        # Revoke the token with Discord
        rows = _supabase_rest("GET", "discord_accounts",
                              params=f"user_id=eq.{user_id}&select=access_token")
        if rows and rows[0].get("access_token"):
            http_requests.post(f"{_DISCORD_API}/oauth2/token/revoke", data={
                "token": rows[0]["access_token"],
                "client_id": _DISCORD_CLIENT_ID,
                "client_secret": _DISCORD_CLIENT_SECRET,
            }, headers={"Content-Type": "application/x-www-form-urlencoded"}, timeout=10)
    except Exception as e:
        print(f"[Discord] revoke error (non-fatal): {e}", flush=True)
    # Delete from Supabase
    try:
        _supabase_rest("DELETE", "discord_accounts",
                       params=f"user_id=eq.{user_id}", prefer="return=minimal")
    except Exception:
        pass
    return {"ok": True}


# --- Guilds & Channels ---

@app.get("/discord/guilds")
@limiter.limit("15/minute")
def discord_guilds(request: Request, user_id: str = Depends(_get_user_id)):
    """List Discord servers the user is in where the bot is also present."""
    token = _refresh_discord_token(user_id)
    user_guilds = _discord_api("GET", "/users/@me/guilds", token=token)
    # Get guilds the bot is in
    bot_guilds = _discord_api("GET", "/users/@me/guilds", bot=True)
    bot_guild_ids = {g["id"] for g in (bot_guilds or [])}
    # Only return guilds where both user and bot are present
    shared = []
    for g in (user_guilds or []):
        if g["id"] in bot_guild_ids:
            shared.append({
                "id": g["id"],
                "name": g["name"],
                "icon": g.get("icon"),
            })
    return {"guilds": shared, "bot_invite_url": _discord_bot_invite_url()}


def _discord_bot_invite_url() -> str:
    """Generate the URL to invite the Aquaria bot to a server."""
    # Permissions: Send Messages (2048) + Attach Files (32768) + Embed Links (16384)
    permissions = 2048 + 32768 + 16384
    return (f"https://discord.com/oauth2/authorize?client_id={_DISCORD_CLIENT_ID}"
            f"&permissions={permissions}&scope=bot")


@app.get("/discord/channels")
@limiter.limit("30/minute")
def discord_channels(request: Request, guild_id: str, user_id: str = Depends(_get_user_id)):
    """List text channels in a guild where the bot can post."""
    if not guild_id:
        raise HTTPException(status_code=400, detail="guild_id is required")
    # Use the bot token to list channels (more reliable than user token for channel access)
    channels = _discord_api("GET", f"/guilds/{guild_id}/channels", bot=True)
    # Filter to text channels (type 0) only
    text_channels = []
    for ch in (channels or []):
        if ch.get("type") == 0:  # GUILD_TEXT
            text_channels.append({
                "id": ch["id"],
                "name": ch["name"],
                "position": ch.get("position", 0),
            })
    text_channels.sort(key=lambda c: c["position"])
    return {"channels": text_channels}


# --- Share Photo ---

class DiscordShareRequest(BaseModel):
    channel_id: str
    title: str
    caption: str = ""
    photo_storage_path: str  # Supabase storage path e.g. "uid/123456.jpg"


@app.post("/discord/share")
@limiter.limit("10/minute")
def discord_share(request: Request, req: DiscordShareRequest, user_id: str = Depends(_get_user_id)):
    """Share a tank photo to a Discord channel via the bot."""
    if not _DISCORD_BOT_TOKEN:
        raise HTTPException(status_code=500, detail="Discord bot not configured")

    # Verify user has linked Discord
    rows = _supabase_rest("GET", "discord_accounts",
                          params=f"user_id=eq.{user_id}&select=discord_username")
    if not rows:
        raise HTTPException(status_code=403, detail="Discord account not linked")
    discord_username = rows[0]["discord_username"]

    # Download image from Supabase Storage
    storage_url = f"{_SUPABASE_URL}/storage/v1/object/community-photos/{req.photo_storage_path}"
    try:
        img_req = urllib.request.Request(storage_url, headers={
            "apikey": _SUPABASE_SERVICE_KEY,
            "Authorization": f"Bearer {_SUPABASE_SERVICE_KEY}",
        })
        img_resp = urllib.request.urlopen(img_req, timeout=30)
        image_bytes = img_resp.read()
    except Exception as e:
        print(f"[Discord] image download failed: {e}", flush=True)
        raise HTTPException(status_code=400, detail="Failed to download image")

    # Apply watermark
    try:
        watermarked = _apply_watermark(image_bytes)
    except Exception as e:
        print(f"[Discord] watermark failed (using original): {e}", flush=True)
        watermarked = image_bytes

    # Build the embed message content
    caption = req.caption.strip()
    credit = f"📸 Shared by **{discord_username}** via [**Aquaria AI**](https://aquaria-ai.com) - your aquarium companion."
    content = f"**{req.title}**"
    if caption:
        content += f"\n{caption}"
    content += f"\n\n{credit}"

    # Post to Discord channel using the bot
    result = _discord_api("POST", f"/channels/{req.channel_id}/messages",
                          bot=True,
                          data={"content": content},
                          files={"file": ("aquaria-tank.jpg", watermarked, "image/jpeg")})

    message_id = result.get("id", "") if result else ""
    channel_id = req.channel_id

    # Log the share
    try:
        _supabase_rest("POST", "discord_shares", body={
            "user_id": user_id,
            "discord_username": discord_username,
            "channel_id": channel_id,
            "message_id": message_id,
            "title": req.title,
        }, prefer="return=minimal")
    except Exception as e:
        print(f"[Discord] share log error: {e}", flush=True)

    print(f"[Discord] shared by {discord_username} to channel {channel_id}", flush=True)
    return {"ok": True, "message_id": message_id}


# ---------------------------------------------------------------------------
# Twitter/X integration endpoints
# ---------------------------------------------------------------------------

def _twitter_api(method: str, url: str, *, token: str, data: dict | None = None,
                 files: dict | None = None, json_body: dict | None = None) -> dict | None:
    """Call the Twitter API with a user's OAuth token."""
    headers = {"Authorization": f"Bearer {token}"}
    if json_body is not None:
        headers["Content-Type"] = "application/json"
        resp = http_requests.request(method, url, headers=headers, json=json_body, timeout=30)
    elif files:
        resp = http_requests.request(method, url, headers=headers, data=data, files=files, timeout=60)
    elif data:
        resp = http_requests.request(method, url, headers=headers, data=data, timeout=30)
    else:
        resp = http_requests.request(method, url, headers=headers, timeout=15)
    if resp.status_code >= 400:
        print(f"[Twitter] {method} {url} → {resp.status_code}: {resp.text}", flush=True)
        raise HTTPException(status_code=resp.status_code, detail=f"Twitter API error: {resp.text}")
    return resp.json() if resp.text.strip() else None


def _refresh_twitter_token(user_id: str) -> str:
    """Get a valid Twitter access token for user, refreshing if expired."""
    rows = _supabase_rest("GET", "twitter_accounts",
                          params=f"user_id=eq.{user_id}&select=*")
    if not rows:
        raise HTTPException(status_code=404, detail="Twitter account not linked")
    row = rows[0]
    # Check if token is still valid
    expires_at = row.get("token_expires_at", "")
    if expires_at:
        from datetime import timezone
        exp_dt = datetime.fromisoformat(expires_at.replace("Z", "+00:00"))
        if datetime.now(timezone.utc).timestamp() < exp_dt.timestamp() - 10:
            return row["access_token"]
    # Refresh
    import base64
    creds = base64.b64encode(f"{_TWITTER_CLIENT_ID}:{_TWITTER_CLIENT_SECRET}".encode()).decode()
    resp = http_requests.post("https://api.x.com/2/oauth2/token", data={
        "grant_type": "refresh_token",
        "refresh_token": row["refresh_token"],
        "client_id": _TWITTER_CLIENT_ID,
    }, headers={
        "Content-Type": "application/x-www-form-urlencoded",
        "Authorization": f"Basic {creds}",
    }, timeout=15)
    if resp.status_code != 200:
        print(f"[Twitter] token refresh failed: {resp.text}", flush=True)
        raise HTTPException(status_code=401, detail="Twitter token refresh failed. Please re-link.")
    tokens = resp.json()
    from datetime import timedelta
    new_expires = (datetime.utcnow() + timedelta(seconds=tokens.get("expires_in", 7200))).isoformat() + "Z"
    _supabase_rest("PATCH", "twitter_accounts",
                   params=f"user_id=eq.{user_id}",
                   body={
                       "access_token": tokens["access_token"],
                       "refresh_token": tokens.get("refresh_token", row["refresh_token"]),
                       "token_expires_at": new_expires,
                       "updated_at": datetime.utcnow().isoformat() + "Z",
                   }, prefer="return=minimal")
    return tokens["access_token"]


# --- Twitter OAuth Flow (PKCE) ---


@app.get("/twitter/auth-url")
@limiter.limit("10/minute")
def twitter_auth_url(request: Request, user_id: str = Depends(_get_user_id)):
    """Generate a Twitter OAuth2 authorization URL (PKCE flow)."""
    if not _TWITTER_CLIENT_ID:
        raise HTTPException(status_code=500, detail="Twitter integration not configured")
    import hashlib, base64
    state = secrets.token_urlsafe(32)
    code_verifier = secrets.token_urlsafe(64)
    code_challenge = base64.urlsafe_b64encode(
        hashlib.sha256(code_verifier.encode()).digest()
    ).decode().rstrip("=")
    _save_oauth_state(state, "twitter", user_id, code_verifier)
    url = (
        f"https://x.com/i/oauth2/authorize"
        f"?response_type=code"
        f"&client_id={_TWITTER_CLIENT_ID}"
        f"&redirect_uri={urllib.request.quote(_TWITTER_REDIRECT_URI, safe='')}"
        f"&scope={urllib.request.quote(_TWITTER_SCOPES, safe='')}"
        f"&state={state}"
        f"&code_challenge={code_challenge}"
        f"&code_challenge_method=S256"
    )
    return {"url": url}


@app.api_route("/twitter/callback", methods=["GET", "POST"])
def twitter_callback(request: Request, code: str = "", state: str = "", error: str = ""):
    """Handle the OAuth2 callback from Twitter."""
    print(f"[Twitter] callback hit: method={request.method} url={request.url}", flush=True)
    try:
        if error:
            return HTMLResponse(f"<html><body><h2>Authorization failed</h2><p>{error}</p>"
                                f"<p>You can close this window.</p></body></html>")
        auth_data = _pop_oauth_state(state, "twitter")
        if not auth_data:
            return HTMLResponse("<html><body><h2>Invalid or expired session</h2>"
                                "<p>Please try linking Twitter again from the app.</p></body></html>")
        user_id = auth_data["user_id"]
        code_verifier = auth_data["code_verifier"]

        # Exchange code for tokens
        import base64
        creds = base64.b64encode(f"{_TWITTER_CLIENT_ID}:{_TWITTER_CLIENT_SECRET}".encode()).decode()
        resp = http_requests.post("https://api.x.com/2/oauth2/token", data={
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": _TWITTER_REDIRECT_URI,
            "client_id": _TWITTER_CLIENT_ID,
            "code_verifier": code_verifier,
        }, headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "Authorization": f"Basic {creds}",
        }, timeout=15)
        if resp.status_code != 200:
            print(f"[Twitter] token exchange failed: {resp.status_code} {resp.text}", flush=True)
            return HTMLResponse(f"<html><body><h2>Token exchange failed</h2>"
                                f"<p>{resp.status_code}: {resp.text}</p></body></html>")
        tokens = resp.json()
        access_token = tokens["access_token"]
        refresh_token = tokens.get("refresh_token", "")

        # Get Twitter user info
        me = _twitter_api("GET", f"{_TWITTER_API}/users/me", token=access_token)
        twitter_username = me.get("data", {}).get("username", "unknown") if me else "unknown"
        twitter_id = me.get("data", {}).get("id", "") if me else ""

        from datetime import timedelta
        expires_at = (datetime.utcnow() + timedelta(seconds=tokens.get("expires_in", 7200))).isoformat() + "Z"

        # Upsert into Supabase
        _supabase_rest("POST", "twitter_accounts",
                       params="on_conflict=user_id",
                       body={
                           "user_id": user_id,
                           "twitter_id": twitter_id,
                           "twitter_username": twitter_username,
                           "access_token": access_token,
                           "refresh_token": refresh_token,
                           "token_expires_at": expires_at,
                           "scopes": _TWITTER_SCOPES,
                           "updated_at": datetime.utcnow().isoformat() + "Z",
                       }, prefer="resolution=merge-duplicates,return=minimal")

        print(f"[Twitter] linked user {user_id} → @{twitter_username} ({twitter_id})", flush=True)
        return HTMLResponse(
            "<html><body style='font-family: system-ui; text-align: center; padding: 60px;'>"
            "<h2>✅ Twitter linked!</h2>"
            f"<p>Connected as <strong>@{twitter_username}</strong></p>"
            "<p>You can close this window and return to Aquaria.</p>"
            "</body></html>"
        )
    except Exception as e:
        print(f"[Twitter] callback error: {e}", flush=True)
        return HTMLResponse(
            f"<html><body><h2>Error</h2><p>{e}</p>"
            f"<p>Please try again.</p></body></html>"
        )


@app.get("/twitter/status")
@limiter.limit("30/minute")
def twitter_status(request: Request, user_id: str = Depends(_get_user_id)):
    """Check if the user has linked their Twitter account."""
    try:
        rows = _supabase_rest("GET", "twitter_accounts",
                              params=f"user_id=eq.{user_id}&select=twitter_username,twitter_id")
        if rows:
            return {"linked": True, "twitter_username": rows[0]["twitter_username"]}
    except Exception:
        pass
    return {"linked": False}


@app.delete("/twitter/unlink")
@limiter.limit("5/minute")
def twitter_unlink(request: Request, user_id: str = Depends(_get_user_id)):
    """Unlink the user's Twitter account."""
    try:
        rows = _supabase_rest("GET", "twitter_accounts",
                              params=f"user_id=eq.{user_id}&select=access_token")
        if rows and rows[0].get("access_token"):
            import base64
            creds = base64.b64encode(f"{_TWITTER_CLIENT_ID}:{_TWITTER_CLIENT_SECRET}".encode()).decode()
            http_requests.post("https://api.x.com/2/oauth2/token/revoke", data={
                "token": rows[0]["access_token"],
                "client_id": _TWITTER_CLIENT_ID,
            }, headers={
                "Content-Type": "application/x-www-form-urlencoded",
                "Authorization": f"Basic {creds}",
            }, timeout=10)
    except Exception as e:
        print(f"[Twitter] revoke error (non-fatal): {e}", flush=True)
    try:
        _supabase_rest("DELETE", "twitter_accounts",
                       params=f"user_id=eq.{user_id}", prefer="return=minimal")
    except Exception:
        pass
    return {"ok": True}


# --- Twitter Share ---

class TwitterShareRequest(BaseModel):
    text: str
    photo_storage_path: str  # Supabase storage path


@app.post("/twitter/share")
@limiter.limit("10/minute")
def twitter_share(request: Request, req: TwitterShareRequest, user_id: str = Depends(_get_user_id)):
    """Share a tank photo to Twitter/X."""
    token = _refresh_twitter_token(user_id)

    # Get username for credit
    rows = _supabase_rest("GET", "twitter_accounts",
                          params=f"user_id=eq.{user_id}&select=twitter_username")
    twitter_username = rows[0]["twitter_username"] if rows else "unknown"

    # Download image from Supabase Storage
    storage_url = f"{_SUPABASE_URL}/storage/v1/object/community-photos/{req.photo_storage_path}"
    try:
        img_req = urllib.request.Request(storage_url, headers={
            "apikey": _SUPABASE_SERVICE_KEY,
            "Authorization": f"Bearer {_SUPABASE_SERVICE_KEY}",
        })
        img_resp = urllib.request.urlopen(img_req, timeout=30)
        image_bytes = img_resp.read()
    except Exception as e:
        print(f"[Twitter] image download failed: {e}", flush=True)
        raise HTTPException(status_code=400, detail="Failed to download image")

    # Apply watermark
    try:
        watermarked = _apply_watermark(image_bytes)
    except Exception as e:
        print(f"[Twitter] watermark failed (using original): {e}", flush=True)
        watermarked = image_bytes

    # Upload media via X API v2 (supports OAuth 2.0)
    media_resp = http_requests.post(
        f"{_TWITTER_API}/media/upload",
        headers={"Authorization": f"Bearer {token}"},
        files={
            "media": ("photo.jpg", watermarked, "image/jpeg"),
        },
        data={"media_category": "tweet_image"},
        timeout=60,
    )
    if media_resp.status_code not in (200, 201):
        print(f"[Twitter] media upload failed: {media_resp.status_code} {media_resp.text}", flush=True)
        raise HTTPException(status_code=400, detail=f"Media upload {media_resp.status_code}: {media_resp.text[:300]}")
    media_json = media_resp.json()
    media_id = media_json.get("id", "") or media_json.get("media_id_string", "")

    # Create tweet with media
    tweet_text = req.text.strip()
    credit = f"\n\n📸 @{twitter_username} via @AquariaAI\naquaria-ai.com"
    # Twitter has a 280 char limit
    max_text = 280 - len(credit)
    if len(tweet_text) > max_text:
        tweet_text = tweet_text[:max_text - 1] + "…"
    tweet_text += credit

    tweet_data = {"text": tweet_text}
    if media_id:
        tweet_data["media"] = {"media_ids": [media_id]}

    result = _twitter_api("POST", f"{_TWITTER_API}/tweets", token=token, json_body=tweet_data)
    tweet_id = result.get("data", {}).get("id", "") if result else ""

    # Log the share
    try:
        _supabase_rest("POST", "twitter_shares", body={
            "user_id": user_id,
            "twitter_username": twitter_username,
            "tweet_id": tweet_id,
            "text": tweet_text[:500],
        }, prefer="return=minimal")
    except Exception as e:
        print(f"[Twitter] share log error: {e}", flush=True)

    tweet_url = f"https://twitter.com/{twitter_username}/status/{tweet_id}" if tweet_id else ""
    print(f"[Twitter] shared by @{twitter_username}: {tweet_url}", flush=True)
    return {"ok": True, "tweet_id": tweet_id, "tweet_url": tweet_url}