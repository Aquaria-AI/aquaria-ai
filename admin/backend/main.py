"""
Aquaria Admin Console — Backend API
Standalone FastAPI app. Reads Supabase (service role, bypasses RLS).
Designed to mount under /admin later.
"""

import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from supabase import Client, create_client

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

_ENV_PATH = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(_ENV_PATH)

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
ADMIN_PASSWORD = os.environ.get("ADMIN_PASSWORD", "changeme")

# ---------------------------------------------------------------------------
# Supabase client (service role — bypasses RLS)
# ---------------------------------------------------------------------------

_sb: Optional[Client] = None


def _get_sb() -> Client:
    global _sb
    if _sb is None:
        if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
            raise HTTPException(500, "Supabase credentials not configured")
        _sb = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    return _sb


# ---------------------------------------------------------------------------
# Auth — simple bearer token (admin password)
# ---------------------------------------------------------------------------


def _require_admin(request: Request):
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer ") or auth[7:] != ADMIN_PASSWORD:
        raise HTTPException(401, "Unauthorized")


# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------

app = FastAPI(title="Aquaria Admin Console", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Auth endpoint
# ---------------------------------------------------------------------------


class LoginRequest(BaseModel):
    password: str


@app.post("/api/login")
def login(body: LoginRequest):
    if body.password != ADMIN_PASSWORD:
        raise HTTPException(401, "Invalid password")
    return {"token": ADMIN_PASSWORD}


# ===================================================================
# FLAGGED CONTENT
# ===================================================================


@app.get("/api/flagged-posts", dependencies=[Depends(_require_admin)])
def get_flagged_posts():
    sb = _get_sb()
    # Get posts that have been flagged (hidden or with flags)
    posts = (
        sb.table("community_posts")
        .select("id, user_id, channel, photo_url, caption, is_hidden, admin_action, admin_action_at, created_at")
        .or_("is_hidden.eq.true,admin_action.is.null")
        .order("created_at", desc=True)
        .limit(200)
        .execute()
    )
    # Get all flags
    flags = sb.table("post_flags").select("*").execute()
    # Get profiles for display names
    profiles = sb.table("profiles").select("id, display_name, username").execute()
    profile_map = {p["id"]: p for p in profiles.data}
    # Build flag count map
    flag_map: dict[int, list] = {}
    for f in flags.data:
        flag_map.setdefault(f["post_id"], []).append(f)

    result = []
    for p in posts.data:
        post_flags = flag_map.get(p["id"], [])
        if not post_flags and not p["is_hidden"]:
            continue  # skip posts with no flags and not hidden
        prof = profile_map.get(p["user_id"], {})
        result.append(
            {
                **p,
                "display_name": prof.get("display_name", ""),
                "username": prof.get("username", ""),
                "flag_count": len(post_flags),
                "flag_reasons": [f["reason"] for f in post_flags],
            }
        )
    # Sort by flag count descending
    result.sort(key=lambda x: x["flag_count"], reverse=True)
    return result


class PostActionRequest(BaseModel):
    action: str  # "appropriate", "inappropriate"


@app.post("/api/posts/{post_id}/action", dependencies=[Depends(_require_admin)])
def post_action(post_id: int, body: PostActionRequest):
    sb = _get_sb()
    now = datetime.now(timezone.utc).isoformat()

    if body.action == "appropriate":
        # Unhide the post, mark as reviewed, clear flags
        sb.table("community_posts").update(
            {"is_hidden": False, "admin_action": "approved", "admin_action_at": now}
        ).eq("id", post_id).execute()
        # Delete all flags for this post (except: post stays hidden for users who flagged it)
        sb.table("post_flags").delete().eq("post_id", post_id).execute()
    elif body.action == "inappropriate":
        # Notify the post author, then delete the post
        post = sb.table("community_posts").select("user_id").eq("id", post_id).single().execute()
        if post.data:
            sb.table("user_notifications").insert(
                {
                    "user_id": post.data["user_id"],
                    "title": "Post removed",
                    "message": "Your community post was removed by a moderator for violating community guidelines.",
                }
            ).execute()
        sb.table("community_posts").delete().eq("id", post_id).execute()
    else:
        raise HTTPException(400, f"Unknown action: {body.action}")

    return {"ok": True}


# ===================================================================
# FEEDBACK / TICKETS
# ===================================================================


@app.get("/api/feedback", dependencies=[Depends(_require_admin)])
def get_feedback():
    sb = _get_sb()
    result = (
        sb.table("feedback")
        .select("id, user_id, message, device, attachment_name, attachment_url, ticket_status, admin_notes, created_at")
        .order("created_at", desc=True)
        .limit(500)
        .execute()
    )
    # Resolve user emails from auth.users (admin API)
    user_ids = {item["user_id"] for item in result.data if item.get("user_id")}
    email_map = {}
    for uid in user_ids:
        try:
            user = sb.auth.admin.get_user_by_id(uid)
            email_map[uid] = user.user.email or ""
        except Exception:
            email_map[uid] = ""
    profiles = sb.table("profiles").select("id, display_name, username").execute()
    profile_map = {p["id"]: p for p in profiles.data}
    for item in result.data:
        uid = item.get("user_id")
        prof = profile_map.get(uid, {})
        item["email"] = email_map.get(uid, "")
        item["username"] = prof.get("username", "")
        item["display_name"] = prof.get("display_name", "")
    return result.data


class FeedbackUpdateRequest(BaseModel):
    ticket_status: Optional[str] = None
    admin_notes: Optional[str] = None


@app.patch("/api/feedback/{feedback_id}", dependencies=[Depends(_require_admin)])
def update_feedback(feedback_id: int, body: FeedbackUpdateRequest):
    sb = _get_sb()
    updates = {}
    if body.ticket_status is not None:
        updates["ticket_status"] = body.ticket_status
    if body.admin_notes is not None:
        updates["admin_notes"] = body.admin_notes
    if not updates:
        raise HTTPException(400, "Nothing to update")
    sb.table("feedback").update(updates).eq("id", feedback_id).execute()
    return {"ok": True}


# ===================================================================
# ACTIVITY REPORTS
# ===================================================================


@app.get("/api/activity/summary", dependencies=[Depends(_require_admin)])
def activity_summary():
    sb = _get_sb()
    now = datetime.now(timezone.utc)
    week_ago = (now - timedelta(days=7)).isoformat()
    month_ago = (now - timedelta(days=30)).isoformat()

    # Total counts
    tanks = sb.table("tanks").select("id", count="exact").execute()
    users = sb.table("profiles").select("id", count="exact").execute()
    logs = sb.table("logs").select("id", count="exact").execute()
    posts = sb.table("community_posts").select("id", count="exact").execute()

    # Recent counts (last 7 days)
    new_users_7d = (
        sb.table("profiles").select("id", count="exact").gte("created_at", week_ago).execute()
    )
    new_logs_7d = (
        sb.table("logs").select("id", count="exact").gte("created_at", week_ago).execute()
    )
    new_tanks_7d = (
        sb.table("tanks").select("id", count="exact").gte("created_at", week_ago).execute()
    )
    new_posts_7d = (
        sb.table("community_posts").select("id", count="exact").gte("created_at", week_ago).execute()
    )

    # Feedback stats
    fb_all = sb.table("feedback").select("id", count="exact").execute()
    fb_open_q = (
        sb.table("feedback")
        .select("id", count="exact")
        .in_("ticket_status", ["new", "in_progress"])
        .execute()
    )
    fb_total = fb_all.count or 0
    fb_open = fb_open_q.count or 0

    # DAU today
    today = now.strftime("%Y-%m-%d")
    dau_today = (
        sb.table("app_sessions").select("id", count="exact").eq("date", today).execute()
    )

    return {
        "totals": {
            "users": users.count or 0,
            "tanks": tanks.count or 0,
            "logs": logs.count or 0,
            "posts": posts.count or 0,
            "feedback_total": fb_total,
            "feedback_open": fb_open,
            "dau_today": dau_today.count or 0,
        },
        "last_7_days": {
            "new_users": new_users_7d.count or 0,
            "new_tanks": new_tanks_7d.count or 0,
            "new_logs": new_logs_7d.count or 0,
            "new_posts": new_posts_7d.count or 0,
        },
    }


@app.get("/api/activity/trends", dependencies=[Depends(_require_admin)])
def activity_trends(days: int = 30):
    """Daily counts of logs, tanks, users, and posts over the last N days."""
    sb = _get_sb()
    since = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()

    logs = sb.table("logs").select("created_at").gte("created_at", since).execute()
    tanks = sb.table("tanks").select("created_at").gte("created_at", since).execute()
    users = sb.table("profiles").select("created_at").gte("created_at", since).execute()
    posts = sb.table("community_posts").select("created_at").gte("created_at", since).execute()
    sessions = sb.table("app_sessions").select("date, user_id").gte("date", since[:10]).execute()

    def bucket(rows, key="created_at"):
        counts: dict[str, int] = {}
        for r in rows:
            day = r[key][:10]
            counts[day] = counts.get(day, 0) + 1
        return counts

    def bucket_unique(rows):
        """Count unique user_ids per date."""
        by_day: dict[str, set] = {}
        for r in rows:
            by_day.setdefault(r["date"][:10], set()).add(r["user_id"])
        return {d: len(uids) for d, uids in by_day.items()}

    # Build date range
    dates = []
    for i in range(days):
        d = (datetime.now(timezone.utc) - timedelta(days=days - 1 - i)).strftime("%Y-%m-%d")
        dates.append(d)

    log_b = bucket(logs.data)
    tank_b = bucket(tanks.data)
    user_b = bucket(users.data)
    post_b = bucket(posts.data)
    dau_b = bucket_unique(sessions.data)

    return {
        "dates": dates,
        "logs": [log_b.get(d, 0) for d in dates],
        "tanks": [tank_b.get(d, 0) for d in dates],
        "users": [user_b.get(d, 0) for d in dates],
        "posts": [post_b.get(d, 0) for d in dates],
        "dau": [dau_b.get(d, 0) for d in dates],
    }


# ===================================================================
# API USAGE / COST
# ===================================================================


@app.get("/api/usage/trends", dependencies=[Depends(_require_admin)])
def usage_trends(days: int = 30):
    """Daily API cost and token usage over the last N days."""
    sb = _get_sb()
    since = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()
    rows = sb.table("api_usage").select("model, input_tokens, output_tokens, cost_usd, created_at").gte("created_at", since).execute()

    dates = []
    for i in range(days):
        d = (datetime.now(timezone.utc) - timedelta(days=days - 1 - i)).strftime("%Y-%m-%d")
        dates.append(d)

    cost_by_day: dict[str, float] = {}
    calls_by_day: dict[str, int] = {}
    tokens_by_day: dict[str, int] = {}
    cost_by_model: dict[str, float] = {}
    for r in rows.data:
        day = r["created_at"][:10]
        cost_by_day[day] = cost_by_day.get(day, 0) + float(r["cost_usd"])
        calls_by_day[day] = calls_by_day.get(day, 0) + 1
        tokens_by_day[day] = tokens_by_day.get(day, 0) + r["input_tokens"] + r["output_tokens"]
        model = r["model"]
        cost_by_model[model] = cost_by_model.get(model, 0) + float(r["cost_usd"])

    total_cost = sum(cost_by_day.values())
    total_calls = sum(calls_by_day.values())
    total_tokens = sum(tokens_by_day.values())

    return {
        "dates": dates,
        "daily_cost": [round(cost_by_day.get(d, 0), 4) for d in dates],
        "daily_calls": [calls_by_day.get(d, 0) for d in dates],
        "daily_tokens": [tokens_by_day.get(d, 0) for d in dates],
        "cost_by_model": cost_by_model,
        "totals": {
            "cost": round(total_cost, 2),
            "calls": total_calls,
            "tokens": total_tokens,
        },
    }


# ===================================================================
# FEATURE METRICS
# ===================================================================


@app.get("/api/metrics/overview", dependencies=[Depends(_require_admin)])
def metrics_overview():
    """Aggregate feature usage metrics from existing Supabase data."""
    sb = _get_sb()
    now = datetime.now(timezone.utc)
    thirty_days_ago = (now - timedelta(days=30)).isoformat()

    # ── Tasks ──────────────────────────────────────────
    all_tasks = sb.table("tasks").select("source, is_dismissed, repeat_days, created_at").execute()
    tasks_total = len(all_tasks.data)
    tasks_ai = sum(1 for t in all_tasks.data if t["source"] == "ai")
    tasks_user = tasks_total - tasks_ai
    tasks_dismissed = sum(1 for t in all_tasks.data if t["is_dismissed"])
    tasks_recurring = sum(1 for t in all_tasks.data if t.get("repeat_days") is not None)
    tasks_oneoff = tasks_total - tasks_recurring

    # ── Community ──────────────────────────────────────
    posts = sb.table("community_posts").select("id, user_id, created_at", count="exact").execute()
    reactions = sb.table("post_reactions").select("id, emoji", count="exact").execute()
    flags = sb.table("post_flags").select("id", count="exact").execute()
    blocks = sb.table("blocked_users").select("id", count="exact").execute()

    # Emoji breakdown
    emoji_counts: dict[str, int] = {}
    for r in reactions.data:
        emoji_counts[r["emoji"]] = emoji_counts.get(r["emoji"], 0) + 1

    # Unique posters
    unique_posters = len({p["user_id"] for p in posts.data})

    # ── Tank Setup ─────────────────────────────────────
    tanks = sb.table("tanks").select("id, user_id, tap_water_json, equipment_json, is_archived").execute()
    active_tanks = [t for t in tanks.data if not t.get("is_archived")]
    tanks_with_equipment = sum(1 for t in active_tanks if t.get("equipment_json") and t["equipment_json"] != "{}")
    tanks_with_tap_water = sum(1 for t in active_tanks if t.get("tap_water_json") and t["tap_water_json"] != "{}")

    # ── Inhabitants & Plants ───────────────────────────
    inhabitants = sb.table("inhabitants").select("tank_id, type, name", count="exact").execute()
    plants = sb.table("plants").select("tank_id", count="exact").execute()

    tanks_with_inhabs = len({i["tank_id"] for i in inhabitants.data})
    tanks_without_inhabs = len(active_tanks) - tanks_with_inhabs

    # Inhabitant type breakdown
    inhab_types: dict[str, int] = {}
    for i in inhabitants.data:
        t = i.get("type") or "unknown"
        inhab_types[t] = inhab_types.get(t, 0) + 1

    tanks_with_plants = len({p["tank_id"] for p in plants.data})

    # ── Measurements ───────────────────────────────────
    recent_journals = (
        sb.table("journal_entries")
        .select("tank_id, category, data, date")
        .eq("category", "measurements")
        .gte("date", (now - timedelta(days=30)).strftime("%Y-%m-%d"))
        .execute()
    )
    tanks_with_measurements_30d = len({j["tank_id"] for j in recent_journals.data})
    tanks_without_measurements_30d = len(active_tanks) - tanks_with_measurements_30d

    # Parameter frequency
    param_counts: dict[str, int] = {}
    for j in recent_journals.data:
        try:
            import json as _json
            data = _json.loads(j["data"]) if isinstance(j["data"], str) else j["data"]
            for key in data:
                param_counts[key] = param_counts.get(key, 0) + 1
        except Exception:
            pass

    # ── Notes ──────────────────────────────────────────
    recent_notes = (
        sb.table("journal_entries")
        .select("tank_id, date")
        .eq("category", "notes")
        .gte("date", (now - timedelta(days=30)).strftime("%Y-%m-%d"))
        .execute()
    )
    tanks_with_notes_30d = len({n["tank_id"] for n in recent_notes.data})

    # ── Tank Photos ────────────────────────────────────
    photos = sb.table("tank_photos").select("id", count="exact").execute()

    # ── Logs (raw input) ──────────────────────────────
    recent_logs = (
        sb.table("logs")
        .select("id, tank_id, created_at")
        .gte("created_at", thirty_days_ago)
        .execute()
    )
    tanks_with_logs_30d = len({l["tank_id"] for l in recent_logs.data})

    return {
        "tasks": {
            "total": tasks_total,
            "ai_created": tasks_ai,
            "user_created": tasks_user,
            "dismissed": tasks_dismissed,
            "recurring": tasks_recurring,
            "one_off": tasks_oneoff,
            "dismiss_rate": round(tasks_dismissed / tasks_total * 100, 1) if tasks_total else 0,
        },
        "community": {
            "total_posts": posts.count or 0,
            "unique_posters": unique_posters,
            "total_reactions": reactions.count or 0,
            "emoji_breakdown": emoji_counts,
            "total_flags": flags.count or 0,
            "total_blocks": blocks.count or 0,
        },
        "tank_setup": {
            "active_tanks": len(active_tanks),
            "with_equipment": tanks_with_equipment,
            "without_equipment": len(active_tanks) - tanks_with_equipment,
            "with_tap_water": tanks_with_tap_water,
            "without_tap_water": len(active_tanks) - tanks_with_tap_water,
            "with_inhabitants": tanks_with_inhabs,
            "without_inhabitants": tanks_without_inhabs,
            "with_plants": tanks_with_plants,
            "without_plants": len(active_tanks) - tanks_with_plants,
        },
        "inhabitants": {
            "total": inhabitants.count or 0,
            "type_breakdown": inhab_types,
        },
        "measurements": {
            "tanks_with_measurements_30d": tanks_with_measurements_30d,
            "tanks_without_measurements_30d": tanks_without_measurements_30d,
            "total_entries_30d": len(recent_journals.data),
            "parameter_frequency": param_counts,
        },
        "notes": {
            "tanks_with_notes_30d": tanks_with_notes_30d,
            "total_entries_30d": len(recent_notes.data),
        },
        "photos": {
            "total": photos.count or 0,
        },
        "ai": {
            "suggestions_converted": tasks_ai,
            "tasks_from_ai_rate": round(tasks_ai / tasks_total * 100, 1) if tasks_total else 0,
        },
    }


# ===================================================================
# SECURITY MONITOR
# ===================================================================


@app.get("/api/security/users", dependencies=[Depends(_require_admin)])
def security_users():
    """Users sorted by moderation risk (flags received + flags cast + hidden posts)."""
    sb = _get_sb()

    # Get all profiles
    profiles = sb.table("profiles").select("id, display_name, username, created_at").execute()

    # Get post counts per user
    posts = sb.table("community_posts").select("user_id, is_hidden").execute()
    post_counts: dict[str, dict] = {}
    for p in posts.data:
        uid = p["user_id"]
        if uid not in post_counts:
            post_counts[uid] = {"total": 0, "hidden": 0}
        post_counts[uid]["total"] += 1
        if p["is_hidden"]:
            post_counts[uid]["hidden"] += 1

    # Get flag counts (flags on their posts)
    flags = sb.table("post_flags").select("post_id, user_id").execute()
    post_owners = {p["id"]: p["user_id"] for p in sb.table("community_posts").select("id, user_id").execute().data}
    flags_received: dict[str, int] = {}
    flags_cast: dict[str, int] = {}
    for f in flags.data:
        # flags cast by this user
        flags_cast[f["user_id"]] = flags_cast.get(f["user_id"], 0) + 1
        # flags received by post owner
        owner = post_owners.get(f["post_id"])
        if owner:
            flags_received[owner] = flags_received.get(owner, 0) + 1

    # Blocked users count
    blocked = sb.table("blocked_users").select("blocked_user_id").execute()
    blocked_count: dict[str, int] = {}
    for b in blocked.data:
        blocked_count[b["blocked_user_id"]] = blocked_count.get(b["blocked_user_id"], 0) + 1

    result = []
    for prof in profiles.data:
        uid = prof["id"]
        pc = post_counts.get(uid, {"total": 0, "hidden": 0})
        fr = flags_received.get(uid, 0)
        fc = flags_cast.get(uid, 0)
        bc = blocked_count.get(uid, 0)
        risk_score = fr * 3 + pc["hidden"] * 5 + bc * 2 + fc
        if risk_score == 0 and pc["total"] == 0:
            continue  # skip inactive users with no risk
        result.append(
            {
                "user_id": uid,
                "display_name": prof.get("display_name", ""),
                "username": prof.get("username", ""),
                "created_at": prof["created_at"],
                "total_posts": pc["total"],
                "hidden_posts": pc["hidden"],
                "flags_received": fr,
                "flags_cast": fc,
                "times_blocked": bc,
                "risk_score": risk_score,
            }
        )
    result.sort(key=lambda x: x["risk_score"], reverse=True)
    return result


@app.get("/api/security/blocked", dependencies=[Depends(_require_admin)])
def blocked_users():
    sb = _get_sb()
    blocks = sb.table("blocked_users").select("*").execute()
    profiles = sb.table("profiles").select("id, display_name, username").execute()
    profile_map = {p["id"]: p for p in profiles.data}
    result = []
    for b in blocks.data:
        blocker = profile_map.get(b["user_id"], {})
        blocked = profile_map.get(b["blocked_user_id"], {})
        result.append(
            {
                "blocker": blocker.get("username") or blocker.get("display_name", b["user_id"]),
                "blocked": blocked.get("username") or blocked.get("display_name", b["blocked_user_id"]),
                "created_at": b["created_at"],
            }
        )
    return result


# ===================================================================
# BETA SIGNUPS & CONTACT SUBMISSIONS
# ===================================================================


@app.get("/api/beta-signups", dependencies=[Depends(_require_admin)])
def get_beta_signups():
    sb = _get_sb()
    rows = sb.table("beta_signups").select("*").order("created_at", desc=True).execute()
    return rows.data


@app.get("/api/contact-submissions", dependencies=[Depends(_require_admin)])
def get_contact_submissions():
    sb = _get_sb()
    rows = sb.table("contact_submissions").select("*").order("created_at", desc=True).execute()
    return rows.data


# ---------------------------------------------------------------------------
# Serve frontend
# ---------------------------------------------------------------------------

_FRONTEND = Path(__file__).resolve().parent.parent / "frontend"

app.mount("/assets", StaticFiles(directory=str(_FRONTEND)), name="frontend")


@app.get("/")
def serve_index():
    return FileResponse(str(_FRONTEND / "index.html"))
