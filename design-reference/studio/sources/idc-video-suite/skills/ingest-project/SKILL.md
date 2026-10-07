# ingest-project

Walk the **entire workdir**, not one HTML file.

## Hunt (use what exists; skip the rest)
```
index.html, *.html, landing pages
*.css, tailwind, :root { --* }
README.md, STATUS, truth.json
stills/, images/, assets/, imagine_images/, public/
raw/, video/, videos/, footage/
broll/, b-roll/, garage-broll/, screen/
audio/, voice/, listen-along/, *.m4a, *.wav
theme.lock.json, project.lock.json (previous)
last YouTube / X copy if present
```

Name folders as you find them. Do not require Jon’s layout. Map:
- A-roll = longest talking-head or first `raw/*.mp4`
- B-roll = every other clip under broll / screen / garage
- Still preferred = hero, gem, terminal capture, last thumb
- Tokens = CSS variables first; if none, sample dominant still; if none, IDC default

## Write `project.lock.json`
```
project          Garnet | Forge 50 | Uncle Bob | listen-along | other
workdir
wordmark         exact string + ruby letter
palette          hex map
type
stills_preferred []
a_roll           path or null
broll            [{path, seconds, note}]
audio_master     path or null
claims_allowed   sentences true on the public page today
banned
phrase_fix       garnett→Garnet, MEPR→METR, diff caps→diff-caps
lime_detected    true only if this tree actually uses #CFFF05
```

HTML tokens win color. A real gem still wins the object.
If lime_detected, record it — do **not** apply it to Garnet / Forge / Uncle Bob jobs.
