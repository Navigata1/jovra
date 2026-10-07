# IDC Video Suite

A theme-aware video studio for Island Development Crew.

One conductor. Named seats. The first seat reads the **whole project folder** — HTML, CSS tokens, stills, `raw/`, `broll/`, `garage-broll/`, landing pages, last ship copy — and writes `project.lock.json`. Every later seat reads that lock.

This is not a fork of BuildLoop. Lime is not the default. Oracle here is an **edit spec**, not a World Cup recipe.

```
Load IDC Video Suite.
Ingest this project folder.
Then run the warehouse pipeline.
```

Or call a seat by name: `Run hook.` `Run oracle-spec.` `Run cutdowns.`

## Seats

| Seat | Does |
|---|---|
| `ingest-project` | Walk the tree. Palette, wordmark, stills, A-roll, B-roll, banned claims. |
| `cut` | Keepers from talking-head or listen-along. Speed voice **once** at 1.25× if Jon says so. |
| `ingest-broll` | Catalog usable B-roll against the spine. Prefer real captures over generated art. |
| `oracle-spec` | Write the edit spec *before* pixels move. Beats, proof, gaps. |
| `hook` | 16:9 still + 8–10s motion from that still. 9:16 is a rerun, not a crop. |
| `assemble` | Hook + freeze last frame + full audio → one YouTube warehouse file. Optional grade. |
| `cutdowns` | X / Shorts / LinkedIn / Whatnot from the same master. Posts, no posting. |

## How a session actually runs

1. Agent loads `SKILL.md` (the conductor).
2. `ingest-project` walks `WORKDIR` (or the path Jon names). Writes `project.lock.json`.
3. If Jon says **warehouse**, conductor runs cut → ingest-broll → oracle-spec → hook → assemble → cutdowns.
4. If Jon names a seat, only that seat runs. The lock must already exist, or ingest runs first.
5. Nothing posts. Jon uploads.

## What we took from BuildLoop — and what we did not

Useful *moves*: cut keepers, catalog B-roll, write a spec before the edit, grade, assemble.

Not bundled: Luuk’s LUTs, neo-lime `#CFFF05` lock, subscribe-bug card, `oracle-edit` World Cup recipe, his Remotion graph.

If `ingest-project` finds lime in **this** project’s CSS, the lock may record it. Default IDC work uses void / garnet / gold.

## Install

```
git clone https://github.com/Island-Dev-Crew/idc-video-suite.git
# Claude / Codex / Grokbot:
# point the skills path at idc-video-suite/
```

First message:

```
Load IDC Video Suite. Ingest this project folder. Workdir: <path>
```

MIT © 2026 Island Development Crew. See NOTICE.md.
