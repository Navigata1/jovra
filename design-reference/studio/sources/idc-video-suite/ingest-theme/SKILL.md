# ingest-theme

Build `theme.lock.json` from whatever Jon points at. Do not invent a palette if tokens exist.

## Inputs (use what is present; skip the rest)
- Landing HTML (`garnet-lang.org`, `islanddevcrew.com/forge-50`, local `index.html`)
- CSS variables: `--void --garnet --gold --ink --ruby --jade`
- Existing stills: `GARNET_HERO_COMPOSITE_Oz5T7.jpg`, last listen-along thumb
- Last shipped copy (YouTube description, X post)
- Repo README origin lines (signed tag vs source on main)

## Extract
```
project        Garnet | Forge 50 | listen-along | other
wordmark       exact string + which letter is ruby
palette        hex list from CSS or from this fallback:
               void #0A0A0F  slate #12121A  ink #E9E7E4
               garnet #9B1B30  gold #C9A227  ruby #C41E3A  jade #3DDC97
type           titles: Instrument Serif / Fraunces
               commands: IBM Plex Mono
stills         paths that MUST be preferred over generated art
claims         only sentences that are true on the public page today
banned         lime, extra CTAs, readiness percents, unsigned presented as signed
phrase_fix     garnett→Garnet  granite language→Garnet language
               diff caps→diff-caps  MEPR→METR
```

## Output
Write `theme.lock.json` next to the work folder. Every later skill reads it and stops if it is absent.

If HTML and a still disagree, HTML tokens win for color; the still wins for the gem.
