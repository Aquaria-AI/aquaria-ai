import json
import os
import re
import sqlite3
import time
from datetime import date, datetime
from typing import Any, Dict, List, Optional

import anthropic
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


_MODEL_HAIKU = "claude-haiku-4-5"
_MODEL_SONNET = "claude-sonnet-4-20250514"


def _pick_model(experience: str = "", water_type: str = "", all_water_types: list = None) -> str:
    """Route to Sonnet for advanced users or complex tank types, Haiku otherwise."""
    exp = (experience or "").lower()
    wt = (water_type or "").lower()
    _complex = {"planted", "saltwater", "reef"}
    has_complex_tank = wt in _complex or any(
        (t or "").lower() in _complex for t in (all_water_types or [])
    )
    if exp == "advanced":
        model = _MODEL_SONNET
    elif exp == "intermediate" and has_complex_tank:
        model = _MODEL_SONNET
    elif not exp and wt in _complex:
        # Summary endpoint: no experience level, route by water type alone
        model = _MODEL_SONNET
    else:
        model = _MODEL_HAIKU
    print(f"[ModelRouter] exp={exp or 'none'} wt={wt or 'none'} complex_any={has_complex_tank} → {model}")
    return model


def _chat(client: anthropic.Anthropic, **kwargs):
    """Call client.messages.create with retry on 529 overloaded errors."""
    for attempt in range(4):
        try:
            return client.messages.create(**kwargs)
        except anthropic.APIStatusError as e:
            if e.status_code == 529 and attempt < 3:
                time.sleep(2 ** attempt)
                continue
            raise


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
     "Gold or rust-colored dust on fish skin (velvet)", "Velvet is more dangerous than ich. Dim the lights immediately (parasite is photosensitive). Treat with a copper-based medication in a hospital tank if invertebrates are present."),
    ("any", "fish", "fin rot,fin damage", "fin rot treatment",
     "Fins appear ragged, discolored, or deteriorating", "Often stress or bacterial infection. Improve water quality first — do a 25% water change. Add aquarium salt (1 tsp/gallon) for freshwater fish. If worsening, treat with an antibacterial medication."),
    ("any", "fish", "bloat,dropsy,pinecone scales", "dropsy treatment",
     "Fish bloated with raised scales (pinecone appearance)", "Dropsy is usually organ failure — very difficult to treat. Isolate the fish immediately to reduce stress. Epsom salt (1 tbsp/5 gal) can reduce fluid retention. Antibiotics sometimes help if caught early."),
    ("any", "fish", "swim bladder,floating,sinking", "swim bladder issue",
     "Fish floating upside-down or struggling to maintain depth", "Fast the fish for 2-3 days. If constipation is the cause, feeding a peeled, cooked pea often helps. Avoid overfeeding going forward."),
    # Compatibility
    ("freshwater", "betta", "aggression,fighting", "betta compatibility",
     "Betta attacking or fin-nipping tank mates", "Bettas are territorial. Remove long-finned or brightly colored fish immediately. Bottom-dwellers and fast-moving schooling fish fare best. Only one male betta per tank."),
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
     "Temperature dropped suddenly or heater appears to have failed", "Replace the heater immediately. When reheating, do it slowly — no more than 2°F per hour. Cold shock stresses fish as much as heat shock does."),
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


class AdviseRequest(BaseModel):
    tank: Optional[Dict[str, Any]] = None
    initial: Optional[Dict[str, Any]] = None


class SummaryRequest(BaseModel):
    logs: List[Dict[str, Any]]
    water_type: Optional[str] = None  # 'freshwater', 'saltwater', 'reef', etc.
    gallons: Optional[int] = None


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
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        return None
    try:
        client = anthropic.Anthropic(api_key=api_key)
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
def parse_tank_note(req: ParseRequest):
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


_LOG_SYSTEM_PROMPT = """You parse aquarium tank journal entries into three categories. Return ONLY valid JSON — no explanation, no markdown, no code fences.

RELEVANCE RULE — apply before anything else:
Only log content that is directly related to the aquarium hobby: water parameters, fish/plant/coral/invertebrate health and behavior, tank equipment, feeding, maintenance, dosing, or scheduling aquarium-related tasks. If the user's message has nothing to do with their aquarium (e.g. personal reminders, jokes, unrelated life events), return all-empty output immediately.

CATEGORY RULES — read carefully:

"actions" — Things the user physically did to the tank. Must involve the user performing an activity.
  When a quantity is provided, include it concisely: "added 5ml of Prime" → "5ml Prime", "20% water change" → "20% water change".
  When NO quantity is given, still log the action in short form: "did a water change" → "Water change", "cleaned the filter" → "Cleaned filter", "moved plants" → "Moved plants", "fed fish" → "Fed fish", "trimmed plants" → "Trimmed plants".
  YES: "5ml Prime", "20% water change", "Water change", "Cleaned filter", "Fed fish", "Trimmed plants", "Moved plants", "Topped off with RO water"
  NO: general condition statements, descriptions of what the tank looks/smells like, things the user noticed

"notes" — Anything the user noticed: visual, olfactory, behavioral, or general condition. Includes deaths, smells, appearances, and qualitative trends described. When a qualitative statement is made with a number, record the qualitative part as an observation and the number as a measurement (see below).

  YES: "everything looks bad", "fish seem stressed", "green algae on glass", "oily film on surface", "plant leaves yellowing", "tank looks cloudy", "debris floating", "fish looks pale"
  YES: "tank smells bad", "tank smells off", "sulfur smell", "foul odor"
  YES: "fish dead", "found a dead fish", "shrimp dying", "snail not moving"
  YES: "hardness spiked", "pH crashed", "ammonia spike", "parameters look off" — qualitative trend statements with NO numeric value go here
  YES: "GH went crazy", "GH went wild", "pH spiked", "ammonia shot up to" — phrases that combine a qualitative description AND a number: put the qualitative part in notes AND extract the number into measurements
  NO: things the user did (those go in actions).
  NO: number measurements (those go in measurements).
  NO: questions, requests for advice, or anything phrased as a question directed at the assistant — never put a question into notes.

"measurements" — Numeric values for known parameters. A number must be explicitly present in the text.
  Do not log a measurement where the input indicated it was from prior memory. Simply add it to the notes. Example: "plants look good after previously raising ca:mg ratio to 4:1". Log that as a note.
  Look for keys like: pH, KH, GH, Ca, Mg, ammonia, nitrite, nitrate, K, salinity
  Keys may be separated from their number. Example "GH went wild to 10" should extract GH 10 (GH went wild should be an observation, and GH 10 should be a measurement). Example: "pH: 7.4", "KH is 3", "nitrate 20", "ammonia spiked to 5", "NO2 at 1.5", "calcium 400 ppm".
  For temperature use key "temp" with value like "78°F" or "26°C".
  "General Hardness" or hardness is GH, "carbonate hardness" is KH. Ammonia can be "ammonia" or "NH3", nitrite can be "nitrite" or "NO2", nitrate can be "nitrate" or "NO3". Potassium can be "potassium" or "K".
  Magnesium can be "magnesium" or "Mg". Calcium can be "calcium" or "Ca". Salinity can be "salinity".
  IMPORTANT: if a sentence mentions a parameter name and a number — even phrased as "GH went wild to 10" — extract the measurement of GH 10. Do not ignore measurements just because the sentence is phrased qualitatively. The qualitative part should be logged as an observation.

Return this exact shape — always a "logs" array, even for a single entry:
{
  "logs": [
    {
      "measurements": { "pH": 7.4, "temp": "78°F" },
      "actions": ["added 5ml of Prime", "20% water change"],
      "notes": ["everything looks bad", "fish seem stressed", "GH went wild"],
      "tasks": [{"description": "check nitrates", "due_date": "2026-03-12"}],
      "date": "2026-02-21"
    }
  ]
}

SINGLE-ENTRY RULE: Combine ALL measurements, actions, and notes from a single message into ONE log object. Do NOT split a single message into multiple log entries unless the user explicitly references different dates.

MULTI-DATE ENTRIES: If the user mentions measurements or events across multiple distinct dates (e.g. "ca was 50ppm 2.22.26 next day 65 next day 75", or "on Monday pH was 7.2, Tuesday pH was 7.4"), create a SEPARATE log object for each date inside the "logs" array. Each entry should only contain the measurements/actions/notes relevant to that specific date. Relative day references like "next day" mean +1 day from the preceding date.

"tasks" — scheduling or reminder requests from the user, ONLY if they relate to aquarium care.
  YES: "remind me to check nitrates next week", "test phosphates tomorrow", "schedule water change in 3 days", "remind me to add fertilizer Friday"
  NO: anything unrelated to the aquarium hobby — personal reminders, self-deprecating jokes, random life tasks, or anything that has nothing to do with fish, water, plants, equipment, or tank maintenance. If the reminder is not about aquarium care, return an empty tasks array.
  Extract a short description and compute the absolute due date as YYYY-MM-DD using today's date (injected below).
  Conversions: "tomorrow" = today+1, "next week"/"in 1 week" = today+7, "in 2 weeks" = today+14, "in N days" = today+N, "in N months" ≈ today+N*30.
  If no time is given or it is vague (e.g. "soon"), set due_date to null.

"date" — If the user specifies a past or present date for this entry (e.g. "2.21.26", "2/21/26", "Feb 21", "February 21 2026", "last Tuesday"), return it as YYYY-MM-DD. Today's date will be provided. Return null if no date is mentioned. IMPORTANT: task due dates (e.g. "next week", "tomorrow", "in 3 days") are NOT log dates — always return null for the date field when the only time reference is a future task due date.

IMPORTANT — do NOT log questions or requests for advice:
- Never put a question or advisory request into "notes". Questions are not observations.
- If the entire message is a question or request for guidance directed at the assistant (with no tank observations, measurements, or actions), return empty arrays/objects for all categories.
- If a message mixes a tank observation WITH a question (e.g. "my fish looks stressed, what should I do?"), log only the factual observation ("Fish looks stressed") — not the question part.
- Short affirmative replies ("yes", "sure", "ok", "no") with no tank data should also produce all-empty output.
- Requests to create/name/set up a new tank, add inhabitants, or manage app settings are NOT loggable — return all-empty output silently.
  Examples that produce all-empty output:
    "what should my next steps be?"
    "is that normal?"
    "what do I do now?"
    "create a new tank"
    "I want to add a tank called Betta"
    "set up a new aquarium"

CRITICAL: You MUST ALWAYS return valid JSON matching the shape above. NEVER return an explanation, error message, or any prose — even if the message is off-topic or not loggable. Return the all-empty JSON structure instead.
    "any suggestions?"
    "should I be worried?"
    "what would you recommend?"
    "yes"
    "sure"
    "no"

Empty categories should be empty objects/arrays. Never omit a key."""


_MONTH_NAMES = {
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
    "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    "january": 1, "february": 2, "march": 3, "april": 4, "june": 6,
    "july": 7, "august": 8, "september": 9, "october": 10, "november": 11, "december": 12,
}


def _extract_date_regex(text: str) -> Optional[str]:
    """Extract a date from common formats like 2.21.26, 2/21/2026, Feb 21, etc."""
    today = date.today()

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


def _parse_with_llm(text: str, today: str) -> Optional[List[Dict[str, Any]]]:
    """Call Claude to parse the log entry. Returns a list of log dicts, or None on failure."""
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("[LLM] ANTHROPIC_API_KEY not set — using regex fallback")
        return None
    try:
        client = anthropic.Anthropic(api_key=api_key)
        response = _chat(client,
            model="claude-haiku-4-5",
            max_tokens=1024,
            system=_LOG_SYSTEM_PROMPT + f"\n\nToday's date is {today}.",
            messages=[{"role": "user", "content": text}],
        )
        raw = response.content[0].text.strip()
        raw = re.sub(r"^```(?:json)?\s*", "", raw)
        raw = re.sub(r"\s*```$", "", raw).strip()
        # If the model returned prose instead of JSON, treat as no loggable content
        if not raw.startswith("{") and not raw.startswith("["):
            print(f"[LLM] non-JSON response (ignored): {raw[:120]}")
            return None
        parsed = json.loads(raw)
        # Support both new {"logs": [...]} and legacy single-entry format
        entries = parsed.get("logs") if isinstance(parsed.get("logs"), list) else [parsed]
        result = []
        for entry in entries:
            result.append({
                "schemaVersion": 1,
                "measurements": entry.get("measurements", {}),
                "actions": [_sentence_case(a) for a in entry.get("actions", [])],
                "notes": [_sentence_case(n) for n in entry.get("notes", [])],
                "tasks": entry.get("tasks", []),
                "date": entry.get("date"),
            })
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
def parse_tank_log(req: ParseRequest):
    text = (req.text or "").strip()
    today = date.today().isoformat()
    logs = _parse_with_llm(text, today)
    if logs is None:
        logs = _parse_with_regex(text)
        logs[0]["date"] = _extract_date_regex(text)
    return {"logs": logs}


_SUMMARY_SYSTEM_PROMPT = """You are a concise aquarium assistant. Given recent tank journal entries, write a 2-3 sentence summary of the tank's current status. Focus on the most recent measurements, any logged concerns (deaths, high parameters, unusual smells), and recent maintenance. Be direct. Return ONLY the summary text — no JSON, no bullet points, no formatting. Always use American English spelling.

Rules:
- Summarize only. Do NOT ask questions. Do NOT request clarification. Do NOT prompt the user for more information.
- Do NOT describe yourself, your capabilities, or your limitations. Never say what you can or cannot do.
- Do NOT invite the user to share data or explain how to use the app.
- If the logs contain no useful aquarium data, return exactly: "No data logged yet."
- Do not provide advice or suggest next steps.
- keep the summary to 3-4 sentences max. Focus on the most important points.
- You may indicate whether measurements are high, low, or in range using words like "extremely" or "very" to indicate severity.
- Do not make statements inferring accuracy.
- If the logs indicate a recent unresolved problem, mention it without speculating on causes or solutions.
- Use these reference ranges when characterizing parameter levels as low, normal, or high. The tank's water type determines which set applies:

  FRESHWATER:
    ammonia: 0 ppm ideal (any detectable amount is problematic)
    nitrite: 0 ppm ideal (any detectable amount is problematic)
    nitrate: 0–20 ppm normal, >40 ppm high
    pH: 6.5–7.5 normal
    KH (carbonate hardness): 4–8 dKH normal
    GH (general hardness): 4–12 dGH normal
    temperature: 74–80°F / 23–27°C normal
    phosphate: 0–0.5 ppm normal, >1 ppm high
    potassium: 5–20 ppm normal, >30 ppm high
    iron: 0.05–0.1 ppm normal for planted tanks, >0.3 ppm high
    calcium: for planted tanks, ideal Ca depends on GH (Ca:Mg ratio should be 3:1–4:1)
    magnesium: for planted tanks, can be estimated from GH and Ca (see planted tank rules below)

  PLANTED TANK NUTRIENT ANALYSIS (apply when water_type is planted):
  When GH and Ca are both logged, deduce approximate Mg:
    Mg (ppm) ≈ (GH_in_dGH × 17.85 - Ca_ppm × 2.5) / 4.12
  If the calculated Mg is zero or negative, note a potential testing inconsistency or magnesium deficiency.
  Check the Ca:Mg ratio — ideal is 3:1 to 4:1. If significantly off, mention the imbalance.
  If K is low (<5 ppm) alongside Ca/Mg issues, note the risk of multiple nutrient deficiencies.
  Low or absent Mg can cause nutrient lockout — meaning plants cannot absorb Ca even when Ca is present.
  Include these findings naturally in the summary (e.g. "Calculated magnesium appears very low based on GH and calcium readings, suggesting possible nutrient lockout.").

  SALTWATER / REEF:
    ammonia: 0 ppm ideal (any detectable amount is problematic)
    nitrite: 0 ppm ideal (any detectable amount is problematic)
    nitrate: 0–5 ppm normal for reef, <20 ppm for FOWLR, >20 ppm high
    pH: 8.1–8.3 normal
    salinity: 1.024–1.026 SG normal
    alkalinity: 8–12 dKH normal
    calcium: 380–450 ppm normal
    magnesium: 1250–1350 ppm normal
    phosphate: 0.03–0.5 ppm normal for saltwater/reef, >0.5 ppm high
    potassium: 380–420 ppm normal
    temperature: 76–80°F / 24–27°C normal
- When measurements are provided in ml, treat them as actions (dosing), not tank parameter measurements.
- When measurements are provided in ppm, degrees, or similar units, treat them as tank parameters.
- If the user logged something vague (e.g. "phosphates are high" with no number), simply note it was logged as an observation — do not ask for a number.
"""


@app.post("/summary/tank-logs")
def summarize_tank_logs(req: SummaryRequest):
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

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        return {"summary": None}

    try:
        client = anthropic.Anthropic(api_key=api_key)
        system_prompt = _SUMMARY_SYSTEM_PROMPT
        if req.water_type:
            system_prompt += f"\n\nThis is a {req.water_type} tank"
            if req.gallons:
                system_prompt += f" ({req.gallons} gallons)"
            system_prompt += ". Use the corresponding reference ranges above to evaluate parameters."
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


_CHAT_SYSTEM_PROMPT = """You are Ariel, a knowledgeable aquarium assistant embedded in a tank journal app. Your name is Ariel — use it naturally when introducing yourself, but do not repeat it unnecessarily in every reply. The user can log tank events (measurements, actions, observations) by typing in the chat, and you respond conversationally.

LANGUAGE: Always use American English spelling (e.g. "summarizing" not "summarising", "color" not "colour", "behavior" not "behaviour").

SAFETY FIRST — this overrides everything else:
The health and safety of aquatic life and the user is your highest priority. You provide guidance to help users make informed decisions — you do NOT give specific medical or veterinary advice. All actions are ultimately the user's decision.

Safety rules:
- NEVER suggest risky treatments, chemicals, or procedures. If the user reveals they are already using or considering a risky treatment, make them aware of the risks clearly and calmly — but do not tell them what to do. Present the information so they can decide.
- When discussing any chemical, medication, or equipment, present a balanced view including potential downsides and common misconceptions. Avoid one-sided recommendations.
- When unsure whether a recommendation is safe for the specific inhabitants, say so and recommend the most conservative approach.
- Flag dangerous conditions immediately and clearly: ammonia or nitrite above 0, extreme pH swings, temperature shock, copper exposure to invertebrates, overstocking, mixing incompatible species.
- When a user reports a concern (fish gasping, acting strange, looking sick), FIRST confirm the observation was logged (per the ABSOLUTE RULE above), THEN ask diagnostic questions before suggesting actions. Start by asking if they have tested water parameters recently (ammonia, nitrite, nitrate). Only after understanding the situation should you suggest possible actions — and frame them as options, not directives.
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
- Answering aquarium questions and giving advice
- Summarizing tank health from recent logs
Do NOT tell the user you cannot do any of the above. These are all things you can and should do.

ABSOLUTE RULE — always follow this first, before anything else:
If the user's message contains any loggable aquarium information (a measurement, an observation, an action, an aquarium-related reminder), your FIRST sentence MUST be a confirmation that it was logged. Use "Logged." or "Got it." or "Noted." — one word or short phrase, nothing else on that line. Do NOT ask a clarifying question first. Do NOT give advice first. Do NOT greet first. Log confirmation always comes first, no exceptions.
EXCEPTIONS — ask BEFORE confirming the log in these cases:
1. MULTI-TANK SESSION: If the context indicates multiple tanks and none pre-selected, and it is not clear from the conversation which tank the data applies to, ask which tank BEFORE confirming the log.
2. MISSING DATE: When the user reports an action they took (water change, dosing, feeding, cleaning, adding/removing livestock, etc.) without specifying when it happened, ask when they did it BEFORE confirming the log. Do NOT assume today. Keep it concise — e.g. "When did you do the water change?" If the user says "today", "yesterday", "this morning", "just now", or includes a specific date, that counts as specifying — no need to ask.
Once the missing info is provided, confirm the log normally.

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
8. When you give guidance or corrective advice, end with a single short question asking if the user would like to schedule a reminder. Example: "Would you like me to set a reminder for any of these?" Keep it to one line.

You have access to:
- Tank info (name, size, water type, inhabitants, plants)
- Recent log entries for context
- The conversation history

Use these reference ranges when assessing whether a parameter is low, normal, or high. Apply the freshwater or saltwater set based on the tank's water type:

  FRESHWATER:
    ammonia: 0 ppm ideal (any detectable amount is problematic)
    nitrite: 0 ppm ideal (any detectable amount is problematic)
    nitrate: 0–20 ppm normal, >40 ppm high
    pH: 6.5–7.5 normal
    KH: 4–8 dKH normal | GH: 4–12 dGH normal
    temperature: 74–80°F / 23–27°C normal
    phosphate: 0–0.5 ppm normal, >1 ppm high
    potassium: 5–20 ppm normal, >30 ppm high
    iron: 0.05–0.1 ppm normal for planted, >0.3 ppm high
    calcium: not typically tracked separately (GH covers total Ca+Mg), but for planted tanks ideal Ca is derived from GH at a 3:1–4:1 Ca:Mg ratio
    magnesium: not typically tracked separately, but for planted tanks target Mg so that Ca:Mg ≈ 3:1–4:1

  SALTWATER / REEF:
    ammonia/nitrite: 0 ppm ideal (any detectable amount is problematic)
    nitrate: 0–5 ppm normal for reef, <20 ppm for FOWLR
    pH: 8.1–8.3 normal
    salinity: 1.024–1.026 SG normal
    alkalinity: 8–12 dKH normal
    calcium: 380–450 ppm normal
    magnesium: 1250–1350 ppm normal
    phosphate: 0.03–0.5 ppm normal for saltwater/reef, >0.5 ppm high
    potassium: 380–420 ppm normal
    temperature: 76–80°F / 24–27°C normal

INHABITANT-AWARE CHEMISTRY ADVICE — MANDATORY, always apply before giving any water chemistry suggestion:

Before recommending any parameter adjustment, identify who lives in the tank and what their PREFERRED ranges are. Don't just avoid harm — actively aim for the conditions the inhabitants thrive in. If the tank's parameters are outside what the inhabitants prefer, note that explicitly.

INVERTEBRATES (shrimp, snails, crabs, crayfish, clams, mussels, lobsters, sea urchins, starfish, etc.):
- Preferred: stable pH 6.8–7.5 (freshwater shrimp), stable salinity 1.023–1.026 (marine inverts).
- Extremely sensitive to sudden GH, pH, and KH swings. Never suggest aggressive dosing or rapid correction.
- Advise changes in very small increments over multiple days (e.g. no more than 0.1–0.2 pH units per 24 hours).
- Completely avoid recommending any copper-based medication or treatment — copper is lethal to invertebrates even at trace levels.
- Avoid strong chemical buffers; suggest natural, gradual methods (small water changes, crushed coral, driftwood).

FISH SPECIES PREFERENCES (tailor advice to what the tank actually holds):
- Betta: prefer pH 6.5–7.5, GH 3–10 dGH, KH 3–6 dKH, 76–82°F. Warn against hard water or large swings.
- Discus: prefer pH 5.5–7.0, very soft water (GH 1–8 dGH), 82–88°F. Emphasize soft, warm, acidic conditions.
- Cardinal/neon tetras, South American dwarf cichlids: prefer soft, mildly acidic water (pH 6.0–7.0, GH 2–8 dGH).
- African cichlids (Lake Malawi/Tanganyika): prefer pH 7.6–8.6, GH 10–20 dGH, KH 8–14 dKH. High hardness is desirable.
- Livebearers (guppies, mollies, platies, swordtails): prefer pH 7.0–8.0, GH 8–16 dGH, moderate to hard water.
- Goldfish: prefer pH 7.0–8.0, GH 5–15 dGH, KH 5–10 dKH, cooler water 65–75°F.
- Corydoras/catfish: prefer soft, slightly acidic water similar to their South American habitat; avoid salt and copper.
- Scaleless fish (loaches, catfish, eels): copper-sensitive like invertebrates; flag this if present.
- Marine fish and corals: prefer pH 8.1–8.3, stable alkalinity 8–12 dKH, Ca 380–450 ppm, Mg 1250–1350 ppm. Even small swings are stressful.
- Planted tanks with CO2: slight pH drop (6.8–7.2) is normal and safe; use CO2 levels rather than buffers to manage pH.

PLANTED TANK DIAGNOSTICS — apply whenever the tank is planted or has live plants:

GH / Calcium / Magnesium relationship:
- GH measures TOTAL calcium + magnesium hardness combined. 1 dGH ≈ 17.85 ppm CaCO₃.
- If you have both GH and Ca readings, you can estimate Mg: Mg (ppm) ≈ (GH in ppm CaCO₃ - Ca in ppm × 2.5) / 4.12
- If the calculated Mg is zero or negative, FLAG THIS — it means either the Ca test or GH test is inaccurate, or there is genuinely no magnesium, which causes nutrient lockout.
- Ideal Ca:Mg ratio for planted tanks is roughly 3:1 to 4:1. If the ratio is far off, note it.

Plant deficiency symptoms → what to test:
- Twisted, stunted, or deformed new growth → calcium or boron deficiency. Test Ca and GH.
- Yellow edges with pinholes in older leaves → potassium deficiency. Test K.
- Pale/yellowing new leaves (interveinal chlorosis) → iron deficiency. Test Fe.
- Stunted growth, dark/purple leaves → phosphate deficiency. Test PO4.
- General poor growth with good light/CO2 → check K, Ca, Mg, Fe, and macronutrient balance.

CRITICAL: When a user reports plant health issues, recommend testing the parameters MOST LIKELY to cause that specific symptom. Do NOT default to ammonia/nitrite/nitrate/pH — those are for fish health emergencies, not plant deficiency diagnosis. Match the test recommendation to the symptom.

Nutrient lockout:
- Very low or absent Mg can lock out Ca uptake even when Ca is present.
- Very high GH (>14 dGH) can inhibit micronutrient absorption.
- If you detect potential lockout conditions from the logged parameters, explain what lockout means and suggest corrective action.

GENERAL RULES:
- If the tank has any inhabitants, always recommend gradual corrections over rapid ones.
- If the tank's current parameters don't match the inhabitants' preferences, say so clearly and explain what the ideal target should be FOR THOSE SPECIFIC INHABITANTS.
- If you detect high-sensitivity livestock (invertebrates, scaleless fish, corals), say so explicitly before giving advice. Example: "Since you have shrimp, avoid any copper treatments and adjust pH slowly."
- When in doubt about a specific inhabitant's sensitivity, err on the side of caution and recommend the gentler approach.
- Never suggest a large single water change (>30%) to fix chemistry if sensitive inhabitants are present; suggest smaller sequential changes instead.
- When multiple species with different preferences share a tank, aim for the compromise range that suits them all and flag any genuine incompatibilities.

Be friendly but brief. Never say "here", "in this chat", or "below" when directing the user to enter information. Instead say "in any of the chat windows" or "just let me know in any of the chat windows" — this reminds users they can report from anywhere in the app.

FORMATTING RULE — when suggesting the user add data to the app, put the suggestion on its own line, separated from the surrounding text by a blank line. This makes it stand out. Example:
"Your nitrate looks a bit high. A small water change should help bring it down.

Add your next test results in any of the chat windows and I'll track the trend for you."

TESTING & REPORTING ENCOURAGEMENT:
When it is natural to do so — such as when a user mentions a health concern, a new fish, a water change, or any parameter — gently encourage them to test their water and report the results. Specific guidance:
- If the user reports a problem (sick fish, cloudy water, algae, odd behavior) and no recent test results are in the log, suggest they run ammonia, nitrite, nitrate, and pH tests and share the numbers.
- If the user hasn't logged test results recently and the conversation is about tank health, remind them that regular testing is the best early-warning system and ask if they've tested lately.
- When a user shares test results, always confirm the values look good or flag any issues, and encourage them to keep logging results so trends can be tracked over time.
- Do not push testing every single reply — only when it's genuinely relevant to the conversation.

TAP WATER PROFILE:
If a "Tap water profile" is provided in the tank context, use it when giving advice about water parameter adjustments. Examples:
- If the tap water GH is high (e.g. 15°dH) and the user reports high GH in their tank, advise that their tap water is the likely source and explain that RO water or mixing with softer water is needed to reduce it — not just a water change.
- If the tap water pH is high (e.g. 8.2) and the user's tank pH is elevated, clarify that water changes will bring pH back toward the tap water level, not lower it.
- If the tap water has detectable ammonia or nitrates, warn the user and suggest using a water conditioner and testing source water regularly.
- If no tap water profile is present and it would be helpful, gently suggest the user test their tap water and add the results on the tank details page so advice can be more accurate.

CONTINUOUS LEARNING:
When a tank health profile is provided in the context, use it to give proactive, personalized guidance:
- If the user hasn't tested in over 7 days, mention it naturally (e.g. "It's been a little while since your last test — how's everything looking?").
- If a parameter trend shows "rising" toward a concerning level, flag it early.
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

TANK CREATION:
You CAN and SHOULD create new tank profiles from ANY context — even when you are already viewing or discussing an existing tank. Never tell the user you are unable to create a new tank.
When the user wants to add or set up a new tank (e.g. "add a tank", "I have a new tank", "setting up a tank", "create a tank"), guide them conversationally. Ask ONE question at a time in this order, skipping any already answered:
1. What would you like to name the tank?
2. How large is it? (ask for the number and unit — gallons or liters)
3. Is it freshwater, saltwater, or reef?
4. What fish or other inhabitants does it have? (optional — user can say "none" or "skip")
5. Any plants? (optional)

Once you have at minimum a name, size, and water type, summarize the details in one short sentence and say "I'll create this tank for you now." — then the app will handle saving it. Do NOT ask "Ready to create this tank?" — just confirm you're creating it. Do NOT ask all questions at once."""


def _quick_extract_task(message: str, today: date) -> Optional[Dict[str, Any]]:
    """Try to extract a task directly from a user message."""
    from datetime import timedelta
    msg = message.strip()
    msg_lower = msg.lower()

    # Prefix patterns: "remind me to", or bare actions
    prefix = r"(?:remind\s+me\s+to\s+|set\s+(?:a\s+)?reminder\s+to\s+)?"

    # Match "<action> in N days/weeks/months"
    m = re.search(prefix + r"(.+?)\s+in\s+(\d+)\s+(day|week|month)s?", msg_lower, re.IGNORECASE)
    if m:
        desc = m.group(1).strip().rstrip(".,!?")
        n = int(m.group(2))
        unit = m.group(3)
        if unit == "day":
            due = today + timedelta(days=n)
        elif unit == "week":
            due = today + timedelta(weeks=n)
        else:
            due = today + timedelta(days=n * 30)
        return {"description": desc.capitalize(), "due_date": due.isoformat()}

    # Match "<action> tomorrow"
    m = re.search(prefix + r"(.+?)\s+tomorrow", msg_lower, re.IGNORECASE)
    if m:
        desc = m.group(1).strip().rstrip(".,!?")
        if desc and len(desc) > 2:
            due = today + timedelta(days=1)
            return {"description": desc.capitalize(), "due_date": due.isoformat()}

    # Match "<action> next week/month"
    m = re.search(prefix + r"(.+?)\s+next\s+(week|month)", msg_lower, re.IGNORECASE)
    if m:
        desc = m.group(1).strip().rstrip(".,!?")
        unit = m.group(2)
        due = today + (timedelta(weeks=1) if unit == "week" else timedelta(days=30))
        return {"description": desc.capitalize(), "due_date": due.isoformat()}

    # Match "remind me to <action>" (no timeframe — default 1 week)
    m = re.search(r"remind\s+me\s+to\s+(.+?)(?:\s*[.!?]?\s*$)", msg_lower, re.IGNORECASE)
    if m:
        desc = m.group(1).strip().rstrip(".,!?")
        if desc and len(desc) > 3:
            due = today + timedelta(days=7)
            return {"description": desc.capitalize(), "due_date": due.isoformat()}

    return None


_TASK_EXTRACT_PROMPT = """Extract ONLY confirmed reminders/tasks from this conversation.

Today's date is {today}.

Return ONLY valid JSON (no markdown, no explanation):
{{"tasks": [{{"description": "short action description", "due_date": "YYYY-MM-DD", "repeat_days": null}}]}}

Rules:
- Extract ONLY tasks that the assistant has EXPLICITLY CONFIRMED as set/scheduled in its FINAL message
- If the assistant merely OFFERED or SUGGESTED a reminder but the user hasn't confirmed yet, return {{"tasks": []}}
- If the assistant is asking a follow-up question, return {{"tasks": []}}
- Extract at most ONE task — the single most recent confirmed task
- Do NOT re-extract tasks that were already confirmed in earlier turns
- due_date must be an absolute date (YYYY-MM-DD), computed from today's date
- "tomorrow" = today + 1 day, "in N days" = today + N days, "next week" = today + 7 days
- If no specific timeframe was mentioned, default to tomorrow
- description should be a short, clear action phrase (e.g. "Check ammonia", "Water change")
- repeat_days: if the user asked for a RECURRING reminder (e.g. "every week", "every 3 days", "weekly", "biweekly"), set this to the number of days between repeats (7 for weekly, 14 for biweekly, 30 for monthly, etc.). If not recurring, set to null.
- When in doubt, return {{"tasks": []}} — it's better to miss a task than create a duplicate"""


_NEW_INHABITANT_EXTRACT_PROMPT = """Based on this conversation, extract the new inhabitant(s) the user wants to add to their tank profile.

Return ONLY valid JSON — no markdown, no explanation:
{"inhabitants": [{"name": "Otocinclus", "type": "fish", "count": 3}]}

Rules:
- name: use the most specific common name mentioned (e.g. "Otocinclus" not just "fish"). Capitalize properly.
- type: "fish" | "invertebrate" | "coral" | "polyp" | "anemone"
- count: integer. Use the count the user specified. Default to 1 if not mentioned.
- Only include inhabitants the user explicitly said to add — not ones already in the tank profile.
- If the conversation is just a question or clarification with no clear species to add, return {"inhabitants": []}"""


_NEW_TANK_EXTRACT_PROMPT = """Based on this conversation, extract the new tank details into JSON.

Return ONLY valid JSON — no markdown, no explanation:
{
  "tank": {
    "name": "Tank Name",
    "gallons": 20,
    "waterType": "freshwater"
  },
  "initial": {
    "inhabitants": [
      {"name": "Neon Tetra", "type": "fish", "count": 6}
    ],
    "plants": ["Java Fern"]
  }
}

Rules:
- gallons: integer. Convert liters to gallons if needed (1 liter = 0.264 gallons), round to nearest whole number.
- waterType: must be exactly "freshwater", "saltwater", or "reef"
- inhabitant type: "fish" | "invertebrate" | "coral" | "polyp" | "anemone"
- If no inhabitants mentioned, use empty array. If no plants, use empty array.
- Use Title Case for all species and plant names (e.g. "Neon Tetra", "Java Fern").
- count: integer, default to 1 if not specified.
- If the conversation is NOT about creating a new tank (e.g. the user is asking about an existing tank), return {"tank": {}, "initial": {}}"""


def _is_affirmation(text: str) -> bool:
    t = text.lower().strip().rstrip("!.")
    affirmations = ["yes", "yeah", "sure", "ok", "okay", "please", "yep", "yup",
                    "go ahead", "do it", "set it", "sounds good", "that would be great",
                    "yes please", "sure thing", "absolutely"]
    return any(t == a or t.startswith(a + " ") or t.startswith(a + ",") for a in affirmations)


def _history_has_tank_creation_offer(history: list) -> tuple[bool, str]:
    """Returns (has_offer, full_conversation_text) if the last AI message was a tank creation confirmation."""
    for msg in reversed(history or []):
        if msg.get("role") == "assistant":
            content = msg.get("content", "").lower()
            if any(k in content for k in [
                "ready to create", "create this tank", "shall i create",
                "want me to create", "go ahead and create",
                "i'll create", "i will create", "creating this tank", "creating your tank",
                "set this up", "set it up for you",
            ]):
                return True, msg.get("content", "")
            return False, ""
    return False, ""


def _history_has_reminder_offer(history: list) -> tuple[bool, str]:
    """Returns (has_offer, ai_message_text) if a recent AI message explicitly offered to set a reminder."""
    # Only check the last 4 messages (2 exchanges) for an explicit AI offer
    recent = (history or [])[-4:]
    for msg in reversed(recent):
        if msg.get("role") != "assistant":
            continue
        content = msg.get("content", "")
        lower = content.lower()
        # Must be an explicit offer from the AI to set/create a reminder
        if any(k in lower for k in [
            "would you like me to set",
            "would you like a reminder",
            "want me to set a reminder",
            "shall i set a reminder",
            "i can set a reminder",
            "i can remind you",
            "want me to remind",
            "shall i remind",
        ]):
            return True, content
    return False, ""


def _history_has_inhabitant_add_offer(history: list) -> tuple[bool, str]:
    """Returns (has_offer, ai_message_text) if the last AI message offered to add an inhabitant."""
    for msg in reversed(history or []):
        if msg.get("role") == "assistant":
            content = msg.get("content", "")
            lower = content.lower()
            if any(k in lower for k in [
                "add it to your", "add them to your", "add to your tank profile",
                "want me to add", "shall i add", "add your", "update your profile",
                "log it as", "add it as",
            ]):
                return True, content
            return False, ""
    return False, ""


@app.post("/chat/summarize")
def chat_summarize(req: SummarizeSessionRequest):
    """Generate a 1-2 sentence summary of a chat session."""
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        return {"summary": ""}
    try:
        client = anthropic.Anthropic(api_key=api_key)
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
def chat_tank(req: ChatRequest):
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
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

    if no_tank_context and len(available_tanks) > 1:
        tanks_list = "\n".join(f"  - {_fmt_tank(t)}" for t in available_tanks)
        tank_context = (
            f"MULTI-TANK SESSION: The user has multiple tanks:\n{tanks_list}\n"
            f"No specific tank is selected for this conversation.\n"
            f"IMPORTANT: Before logging any measurement, observation, action, or task, "
            f"you MUST ask which tank it applies to if it is not already clear from context. "
            f"If the user refers to a tank indirectly (e.g. 'the one I just created', 'my big tank', 'the reef'), "
            f"use the tank details above (size, type, creation date) to resolve which tank they mean. "
            f"Once the tank is identified, confirm it in your reply (e.g. 'Got it — logging that for [Tank Name].'). "
            f"If the user's message is a general question or doesn't involve logging, no clarification is needed.\n"
            f"When asking which tank, ALWAYS include the tank name AND size (e.g. 'Reef Tank (75 gal)') to help the user identify them.\n"
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
                  "nitrite": "Nitrite", "nitrate": "Nitrate", "tds": "TDS"}
        units  = {"gh": "°dH", "kh": "°dH", "ammonia": "ppm", "nitrite": "ppm",
                  "nitrate": "ppm", "tds": "ppm"}
        for k, v in tap_water.items():
            lbl = labels.get(k, k)
            unit = units.get(k, "")
            tw_parts.append(f"{lbl}: {v}{(' ' + unit) if unit else ''}")
        if tw_parts:
            tank_context += f"Tap water profile: {', '.join(tw_parts)}.\n"

    if req.recent_logs:
        recent = "\n".join(f"- {l}" for l in req.recent_logs[:10])
        tank_context += f"Recent log entries (last 2 weeks):\n{recent}\n"

    # Mandate that Ariel always considers the full tank context
    tank_context += (
        "\nMANDATORY CONTEXT AWARENESS — apply to EVERY response:\n"
        "Before answering ANY question or giving ANY advice, you MUST consider ALL of the following:\n"
        "1. WATER TYPE: freshwater vs saltwater vs reef vs planted — advice differs dramatically between these.\n"
        "2. INHABITANTS: Which specific fish, invertebrates, corals are in the tank. Tailor advice to their needs and sensitivities.\n"
        "3. PLANTS: Whether the tank has live plants and which species. Planted tanks have different parameter priorities.\n"
        "4. RECENT MEASUREMENTS & OBSERVATIONS: Any log entries from the last 2 weeks. Reference specific values when relevant.\n"
        "5. USER EXPERIENCE LEVEL: Beginner, intermediate, or advanced — adjust depth and tone accordingly.\n"
        "6. INHABITANT PLAUSIBILITY: If the user mentions an animal or plant that does NOT match the tank's water type "
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
            tank_context += "Use this to proactively mention if the user hasn't tested recently or if a trend is concerning. Be natural, not robotic.\n"

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
        client = anthropic.Anthropic(api_key=api_key)

        # Fast path: extract tasks from a manual note without generating a chat reply
        if req.extract_tasks_only:
            today_str = date.today().isoformat()
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
        response = _chat(client,
            model=_pick_model(experience=req.experience_level or "", water_type=chat_water_type, all_water_types=all_wt),
            max_tokens=256,
            system=_CHAT_SYSTEM_PROMPT + f"\n\n{tank_context}" + (f"\n\n{req.system_context}" if req.system_context else ""),
            messages=messages,
        )
        reply = response.content[0].text.strip()
        reply_lower = reply.lower()

        # Extract tasks — three triggers:
        # 1. User affirmed a prior reminder offer
        # 2. AI reply confirms it scheduled/set a reminder
        # 3. User explicitly requested a reminder/task
        extracted_tasks: List[Dict[str, Any]] = []

        # Only match phrases that confirm a task/reminder WAS set (past tense / done),
        # NOT future offers like "I'll remind you" or "would you like a reminder?"
        reply_confirms_task_set = any(k in reply_lower for k in [
            "i've set", "i have set", "reminder set", "reminder scheduled",
            "scheduled a reminder", "added a reminder", "task set",
            "i've added a reminder", "i've created a reminder", "i have created a reminder",
            "i've scheduled", "i have scheduled", "done! i'll remind",
            "all set", "reminder added", "task added", "task created",
        ])

        user_explicit_task_request = bool(re.search(
            r"\b(remind me|remind .*(tomorrow|next|monday|tuesday|wednesday|thursday|friday|saturday|sunday|week|month|day)|"
            r"set (a |an )?reminder|schedule (a |an )?reminder|"
            r"daily reminder|weekly reminder|monthly reminder|create (a |an )?reminder|"
            r"add (a |an )?reminder|set (a |an )?task|"
            r"reminder (for |to |tomorrow|next))\b",
            req.message, re.IGNORECASE,
        ))

        # Also trigger if the AI reply confirms a reminder AND history had a reminder discussion
        history_has_reminder = _history_has_reminder_offer(req.history or [])[0]
        # Only extract tasks when the AI reply confirms a reminder was set.
        # Don't extract on the first turn if AI is asking a follow-up question.
        reply_is_question = reply.rstrip().endswith("?")
        should_extract_tasks = (
            (_is_affirmation(req.message) and history_has_reminder)
            or reply_confirms_task_set
            or (user_explicit_task_request and not reply_is_question)
        )

        print(f"[TaskExtract] should_extract={should_extract_tasks} reply_confirms={reply_confirms_task_set} user_explicit={user_explicit_task_request} is_affirmation={_is_affirmation(req.message)} user_msg='{req.message[:80]}' reply_snippet='{reply_lower[:80]}'")
        print(f"[TaskExtract] history_len={len(req.history or [])}")

        if should_extract_tasks:
            today_str = date.today().isoformat()
            extraction_prompt = _TASK_EXTRACT_PROMPT.format(today=today_str)
            # Build conversation for extraction — skip leading assistant messages
            # (Anthropic API requires first message to be 'user')
            convo_parts = []
            for h in (req.history or []):
                role = h.get("role", "user")
                content = h.get("content", "")
                # Skip assistant messages before the first user message
                if not convo_parts and role == "assistant":
                    continue
                convo_parts.append({"role": role, "content": content})
            convo_parts.append({"role": "user", "content": req.message})
            convo_parts.append({"role": "assistant", "content": reply})
            # Ensure we have at least a user message
            if not any(m["role"] == "user" for m in convo_parts):
                convo_parts.insert(0, {"role": "user", "content": req.message})
            extraction_error = None
            extraction_raw = None
            try:
                print(f"[TaskExtract] convo_parts: {convo_parts}")
                ex_response = _chat(client,
                    model="claude-haiku-4-5",
                    max_tokens=256,
                    system=extraction_prompt,
                    messages=convo_parts,
                )
                raw = ex_response.content[0].text.strip()
                extraction_raw = raw
                # Strip everything before the first { and after the last }
                json_match = re.search(r"\{.*\}", raw, flags=re.DOTALL)
                if json_match:
                    raw = json_match.group(0)
                parsed = json.loads(raw)
                extracted_tasks = parsed.get("tasks", [])
                print(f"[TaskExtract] AI raw response: {raw}")
                print(f"[TaskExtract] AI extracted {len(extracted_tasks)} task(s): {extracted_tasks}")
            except Exception as e:
                import traceback
                extraction_error = str(e)
                print(f"[Chat/TaskExtract] error: {e}")
                traceback.print_exc()

        # Extract new tank — three triggers:
        # 1. User affirmed a prior offer ("yes, create it")
        # 2. AI reply itself claims to have created the tank (AI skipped the offer step)
        # 3. User explicitly asked to create ("create a tank called X")
        new_tank = None

        reply_confirms_tank_created = any(k in reply_lower for k in [
            "tank has been created", "i've created", "i have created", "created your tank",
            "tank is ready", "added to your tanks", "set up your tank",
            "tank has been set up", "tank has been added",
            "i'll create this tank", "i will create this tank",
            "creating this tank", "creating your tank",
        ])

        user_explicit_tank_create = bool(re.search(
            r"\b(create|add|set up|setup)\b.{0,60}(tank|aquarium)",
            req.message, re.IGNORECASE,
        ))

        should_extract_tank = (
            (_is_affirmation(req.message) and _history_has_tank_creation_offer(req.history or [])[0])
            or reply_confirms_tank_created
            or user_explicit_tank_create
        )

        print(f"[TankExtract] should_extract={should_extract_tank} reply_confirms={reply_confirms_tank_created} user_explicit={user_explicit_tank_create} is_affirmation={_is_affirmation(req.message)}")
        if should_extract_tank:
            # Build full conversation for extraction context
            convo = "\n".join(
                f"{m['role'].upper()}: {m['content']}"
                for m in (req.history or [])
                if m.get("role") in ("user", "assistant")
            )
            convo += f"\nUSER: {req.message}\nASSISTANT: {reply}"
            try:
                ex_response = _chat(client,
                    model="claude-haiku-4-5",
                    max_tokens=512,
                    system=_NEW_TANK_EXTRACT_PROMPT,
                    messages=[{"role": "user", "content": convo}],
                )
                raw = ex_response.content[0].text.strip()
                raw = re.sub(r"^```(?:json)?\s*", "", raw)
                raw = re.sub(r"\s*```$", "", raw).strip()
                print(f"[TankExtract] raw={raw}")
                parsed_tank = json.loads(raw)
                # Only use result if it has at least a tank name
                if parsed_tank.get("tank", {}).get("name"):
                    new_tank = parsed_tank
                    print(f"[TankExtract] extracted tank: {new_tank}")
                else:
                    print(f"[TankExtract] no tank name in parsed result: {parsed_tank}")
            except Exception as e:
                print(f"[Chat/TankExtract] error: {e}")

        # Extract new inhabitants — three triggers:
        # 1. User affirmed a prior offer ("yes, add it")
        # 2. AI reply itself claims to have added something (AI skipped the offer step)
        # 3. User explicitly asked to add ("add 3 otocinclus to my inhabitants")
        new_inhabitant = None

        reply_confirms_added = any(k in reply_lower for k in [
            "added to your", "i've added", "i have added", "added it to your",
            "added them to your", "added the otocinclus", "added the fish",
            "added to the tank", "adding to your",
        ])

        user_explicit_add = bool(re.search(
            r"\badd\b.{0,50}(to (my|the) (tank|inhabitants|list|profile)|to your (tank|list))",
            req.message, re.IGNORECASE,
        ))

        should_extract = (
            (_is_affirmation(req.message) and _history_has_inhabitant_add_offer(req.history or [])[0])
            or reply_confirms_added
            or user_explicit_add
        )

        if should_extract:
            convo = "\n".join(
                f"{m['role'].upper()}: {m['content']}"
                for m in (req.history or [])
                if m.get("role") in ("user", "assistant")
            )
            convo += f"\nUSER: {req.message}\nASSISTANT: {reply}"
            try:
                inh_response = _chat(client,
                    model="claude-haiku-4-5",
                    max_tokens=256,
                    system=_NEW_INHABITANT_EXTRACT_PROMPT,
                    messages=[{"role": "user", "content": convo}],
                )
                raw = inh_response.content[0].text.strip()
                raw = re.sub(r"^```(?:json)?\s*", "", raw)
                raw = re.sub(r"\s*```$", "", raw).strip()
                parsed = json.loads(raw)
                if parsed.get("inhabitants"):
                    new_inhabitant = parsed
            except Exception as e:
                print(f"[Chat/InhabitantExtract] error: {e}")

        return {
            "response": reply,
            "tasks": extracted_tasks,
            "new_tank": new_tank,
            "new_inhabitant": new_inhabitant,
            "_debug": {
                "should_extract": should_extract_tasks,
                "reply_confirms": reply_confirms_task_set,
                "user_explicit": user_explicit_task_request,
                "is_affirmation": _is_affirmation(req.message),
                "history_has_reminder": history_has_reminder,
                "extraction_raw": extraction_raw if should_extract_tasks else None,
                "extraction_error": extraction_error if should_extract_tasks else None,
            },
        }
    except Exception as e:
        print(f"[Chat] error: {e}")
        return {"response": "Sorry, I couldn't process that right now.", "tasks": []}


@app.post("/advise/next-steps")
def advise_next_steps(req: AdviseRequest):
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
def moderate_tasks(req: ModerationRequest):
    if not req.tasks:
        return {"results": []}
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        return {"results": [True] * len(req.tasks)}
    try:
        client = anthropic.Anthropic(api_key=api_key)
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
def knowledge_ingest(req: KnowledgeIngestRequest):
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


@app.post("/feedback")
def submit_feedback(req: FeedbackRequest):
    timestamp = datetime.now().isoformat(timespec="seconds")
    label = f"[{req.device}]" if req.device else ""
    entry = f"[{timestamp}]{label} {req.message}\n"
    try:
        with open("feedback.log", "a", encoding="utf-8") as f:
            f.write(entry)
    except Exception as e:
        print(f"[Feedback] could not write to file: {e}")
    print(f"📩 FEEDBACK: {entry}", flush=True)
    return {"status": "ok"}