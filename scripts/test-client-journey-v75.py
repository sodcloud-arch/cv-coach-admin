from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / "client-portal" / "stable" / "index.html"
ADMIN = ROOT / "index.html"
FEEDBACK = ROOT / "supabase" / "migrations" / "202609110800_simplify_workout_feedback_v2.sql"
HISTORY = ROOT / "supabase" / "migrations" / "202609110900_training_history_feedback_v3.sql"
BACKFILL = ROOT / "supabase" / "migrations" / "202609121820_workout_duration_backfill_v75.sql"

for path in (CLIENT, ADMIN, FEEDBACK, HISTORY, BACKFILL):
    if not path.exists():
        raise SystemExit(f"V75 required artifact missing: {path.relative_to(ROOT)}")

client = CLIENT.read_text(encoding="utf-8")
admin = ADMIN.read_text(encoding="utf-8")
feedback = FEEDBACK.read_text(encoding="utf-8")
history = HISTORY.read_text(encoding="utf-8")
backfill = BACKFILL.read_text(encoding="utf-8")


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise SystemExit(f"V75 contract missing [{label}]: {needle}")


# Athlete lifecycle: hydration -> workout -> feedback -> completion -> rehydrate/history.
for needle, label in [
    ("CVWorkoutSetGuardV74", "V74 single-flight guard retained"),
    ("cv-workout-set-guard-v74: single-flight-set-toggle + hydration-guard", "V74 hydration marker retained"),
    ("save_workout_feedback_v2", "feedback v2 persistence"),
    ("functions.invoke('complete-workout'", "workout completion edge function"),
    ("await loadReal();view='home';render();cvShowWorkoutResult", "post-completion rehydrate/render"),
    ("get_client_training_history", "authoritative training history RPC"),
    ("['completed','partial'].includes(s.status)", "next-session terminal sequencing"),
    ("functions.invoke('log-habit'", "habit logging"),
    ("functions.invoke('log-nutrition-day'", "nutrition logging"),
    ("submit_weekly_checkin", "weekly recovery check-in"),
    ("progress_photos", "progress photo persistence"),
]:
    require(client, needle, label)

# Coach lifecycle: terminal workout data must be readable in Ficha 360 and reports.
for needle, label in [
    ("table('workout_sessions','client_id=eq.'", "coach session history query"),
    ("workoutSessionFeedbackHtml", "coach session feedback rendering"),
    ("completion_pct,total_volume,client_effort,fatigue_score,pain_score,pain_notes,session_notes", "coach report workout metrics"),
    ("weekly_checkins", "coach weekly recovery visibility"),
    ("nutrition_daily_logs", "coach nutrition visibility"),
    ("habit_logs", "coach habit visibility"),
    ("progress_photos", "coach progress photo visibility"),
]:
    require(admin, needle, label)

# Database contracts that connect athlete completion to history.
for needle, label in [
    ("create or replace function public.save_workout_feedback_v2", "feedback v2 RPC definition"),
    ("difficulty_level=p_difficulty_level", "difficulty persistence"),
    ("had_pain=p_had_pain", "pain flag persistence"),
    ("client_effort=p_difficulty_level*2", "legacy coach feedback compatibility"),
]:
    require(feedback.lower(), needle.lower(), label)

for needle, label in [
    ("create or replace function public.get_client_training_history", "training history RPC definition"),
    ("ws.status::text in ('completed','partial','abandoned')", "terminal session history"),
    ("sl.completed=true", "records only from completed sets"),
    ("duration_records", "timed exercise history"),
]:
    require(history.lower(), needle.lower(), label)

# V75 data repair must remain narrowly deterministic and terminal-only.
for needle, label in [
    ("finished_at - started_at", "duration derived from persisted timestamps"),
    ("status::text in ('completed','partial','abandoned')", "terminal-only backfill"),
    ("duration_seconds is null", "missing-only backfill"),
    ("CV Coach V75 duration backfill incomplete", "post-backfill invariant"),
]:
    require(backfill, needle, label)

print("CV_CLIENT_JOURNEY_V75_OK")
