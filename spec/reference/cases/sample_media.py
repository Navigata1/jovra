"""The sample media manifest (T02): one entry per sample session (8) plus the three lab clips.

Sources: screens.md §0.6 (Jon vs Alex Oct 6 54 min, Serve practice Oct 4, Forehand session Oct 2, five older
sessions between Sep 9 and Sep 28 with three singles matches in weeks 1-3, the Sep 28 compare clip) and T11 (the
Oct 4 behind-baseline serve practice with 12 serves, the Oct 2 side-on forehand clip, short clips for the older
sessions). The older sessions' dates and kinds are fixed here so T09 and T11 share them; resolutions and clip
lengths are this manifest's choices and change only through a contract-fix PR.
"""

from __future__ import annotations

from jovra_ref.sample_match import uid

ORDER = 60
UPDATED_AT = "2026-10-07T18:00:00Z"
KIND = "jovra.sampleMediaManifest"
LABEL = "Sample video (synthetic)"
JON_VS_ALEX_MS = 3_240_000  # 54:00, Rules C12

# date, kind, session slug, media slug, role, angle, fps, width, height, from ms, duration ms, purpose
ENTRIES = [
    ("2026-10-06", "match", "jon-vs-alex", "jon-vs-alex", "sessionVideo", "behindBaseline", 60, 640, 360,
     0, JON_VS_ALEX_MS, "The whole 54:00 sample match (excerpt mode around Point 42 only via a contract-fix PR)."),
    ("2026-10-04", "servePractice", "2026-10-04-serve-practice", "2026-10-04-serve-practice", "sessionVideo",
     "behindBaseline", 60, 640, 360, 0, 20_000, "Library thumbnail clip for Serve practice."),
    ("2026-10-02", "strokePractice", "2026-10-02-forehand-session", "2026-10-02-forehand-session", "sessionVideo",
     "sideOn", 60, 640, 360, 0, 20_000, "Library thumbnail clip for the Forehand session."),
    ("2026-09-28", "match", "2026-09-28-match", "2026-09-28-match", "sessionVideo", "behindBaseline", 60, 640, 360,
     0, 20_000, "Week-3 singles match: thumbnail clip."),
    ("2026-09-21", "servePractice", "2026-09-21-serve-practice", "2026-09-21-serve-practice", "sessionVideo",
     "behindBaseline", 60, 640, 360, 0, 20_000, "Older serve practice: thumbnail clip (no marked serves)."),
    ("2026-09-17", "match", "2026-09-17-match", "2026-09-17-match", "sessionVideo", "behindBaseline", 60, 640, 360,
     0, 20_000, "Week-2 singles match: thumbnail clip."),
    ("2026-09-13", "strokePractice", "2026-09-13-stroke-practice", "2026-09-13-stroke-practice", "sessionVideo",
     "sideOn", 60, 640, 360, 0, 20_000, "Older stroke practice: thumbnail clip."),
    ("2026-09-09", "match", "2026-09-09-match", "2026-09-09-match", "sessionVideo", "behindBaseline", 60, 640, 360,
     0, 20_000, "Week-1 singles match: thumbnail clip."),
    ("2026-09-28", "match", "2026-09-28-match", "2026-09-28-serve-clip", "practiceClip", "behindBaseline", 60, 1280,
     720, 1_800_000, 8_000, "Compare: the 'Previous · Sep 28' serve clip."),
    ("2026-10-04", "servePractice", "2026-10-04-serve-practice", "2026-10-04-behind-baseline-12-serves",
     "practiceClip", "behindBaseline", 60, 1280, 720, 300_000, 120_000,
     "Serve Lab: 12 serves of known speed (contact and bounce frames in the renderer's ground truth)."),
    ("2026-10-02", "strokePractice", "2026-10-02-forehand-session", "2026-10-02-side-on-forehands", "practiceClip",
     "sideOn", 240, 960, 540, 600_000, 30_000, "Stroke Lab: side-on forehands at 240 fps (swing key moments)."),
]


def session_id(slug: str) -> str:
    return uid(f"session/{slug}")


def manifest() -> dict:
    media = []
    for date, kind, session, slug, role, angle, fps, w, h, start, dur, purpose in ENTRIES:
        media.append({
            "mediaId": f"sample-media.{slug}", "role": role, "sessionId": session_id(session), "sessionDate": date,
            "sessionKind": kind, "fileName": f"sample-{slug}.mp4", "durationMs": dur,
            "frameRate": {"num": fps, "den": 1}, "width": w, "height": h, "hasAudio": True, "angle": angle,
            "coversSessionMs": {"fromMs": start, "toMs": start + dur}, "label": LABEL, "purpose": purpose,
        })
    return {"schemaVersion": "1.0.0", "kind": KIND, "updatedAt": UPDATED_AT,
            "sample": {"label": "Sample", "synthetic": True}, "media": media}


def generate(ctx) -> int:
    ctx.write_json(ctx.fixtures / "sample" / "media-manifest.json", manifest())
    return 1


def check_manifest(path, doc: dict, docs: dict) -> list[str]:
    """Invariants the schema cannot express."""
    problems = []
    media = doc["media"]
    for field in ("mediaId", "fileName"):
        values = [m[field] for m in media]
        if len(values) != len(set(values)):
            problems.append(f"duplicate {field}")
    videos = {}
    for m in media:
        if m["role"] == "sessionVideo":
            if m["sessionId"] in videos:
                problems.append(f"two sessionVideo entries for session {m['sessionId']}")
            videos[m["sessionId"]] = m
    sessions = {d["id"]: d for d in docs.values() if d.get("kind") == "jovra.session"}
    for m in media:
        rng = m["coversSessionMs"]
        if rng["toMs"] - rng["fromMs"] != m["durationMs"]:
            problems.append(f"{m['mediaId']}: coversSessionMs is not durationMs long")
        num, den = m["frameRate"]["num"], m["frameRate"]["den"]
        if (m["durationMs"] * num) % (den * 1000):
            problems.append(f"{m['mediaId']}: durationMs is not a whole number of frames")
        if m["role"] == "practiceClip" and m["sessionId"] not in videos:
            problems.append(f"{m['mediaId']}: practice clip names a session with no sessionVideo")
        video = videos.get(m["sessionId"])
        for field in ("sessionDate", "sessionKind", "angle"):  # one session, one date, kind and camera position
            if video is not None and m[field] != video[field]:
                problems.append(f"{m['mediaId']}: {field} {m[field]!r} disagrees with its session video "
                                f"({video[field]!r})")
        session = sessions.get(m["sessionId"])
        if session is not None and rng["toMs"] > session["recording"].get("durationMs", 0):
            problems.append(f"{m['mediaId']}: covers time past the end of session {session['title']}")
    jon_vs_alex = session_id("jon-vs-alex")
    if jon_vs_alex not in sessions:
        problems.append("the Jon vs Alex sample session fixture is missing")
    elif jon_vs_alex not in videos:
        problems.append("no sessionVideo for the Jon vs Alex sample session")
    return problems


CHECKS = {KIND: check_manifest}
