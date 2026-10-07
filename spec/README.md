# JOVRA cross-platform contracts (`spec/`)

ADR-0001: iOS and Android share **contracts, not code**. This folder is that contract: JSON Schemas for every
persisted record, a dependency-free Python reference engine, and golden conformance fixtures that both
platforms' domain modules (JovraCore in Swift, its Kotlin twin later) must reproduce exactly. A rule change lands
here first, as a fixture change, and then in both apps.

```
spec/
  schemas/      JSON Schema 2020-12, schemaVersion "1.x.y" on every record
  contracts/    shipped data both apps read: capability-registry.v1.json, csv/points.v1.json, csv/stats.v1.json
  reference/    Python 3 standard-library reference engine + fixture generator
  fixtures/     golden cases: scoring/ (S01-S64, E01-E10), stats/ (T01-T04), units/ (U01), sample/, records/
scripts/spec/validate.py      validates everything and re-runs the engine; non-zero exit on any mismatch
```

Run both from the repo root:

```
python3 spec/reference/generate_fixtures.py   # rewrites spec/fixtures (deterministic: same bytes every run)
python3 scripts/spec/validate.py               # schema + engine conformance; add -v for detail
```

## Schemas

| File | Record | Notes |
|---|---|---|
| `common.schema.json` | shared `$defs` | ids, timestamps, provenance, `ratio`, tension/length/area/mass/speed as exact decimal strings |
| `session.schema.json` | `session.json` = Drive sidecar = export (ADR-0002) | players (handedness, backhand), sides, session kind, match format, toss facts, the append-only match log (points with `detected`/`reviewed` outcomes, `supersedes`/`insertBefore`, voids, doubles orders, checkpoints, penalties, terminations, rally lets), recording segments/gaps/media flags, marks, shots, calibrations, annotations, voice notes, comparisons, derived values (provenance mandatory), analysis/review/archive/storage states, equipment use, consent |
| `equipment.schema.json` | `equipment.json` | rackets, frames, string products, inventory, string jobs (mains/crosses, tension **as entered**), measurements, feel ratings, court kit, reminders. User-entered only (D6) |
| `archive-manifest.schema.json` | per-session upload journal | resumable state machine, pre-generated Drive ids, size + MD5 (+ SHA-256) verification; `backedUp` is invalid without a passing verification; no tokens or session URIs (Keychain reference only) |
| `capability-registry.schema.json` | `contracts/capability-registry.v1.json` | status, label, requirements and benchmark gate per capability (ADR-0004, D10) |
| `practice-plan.schema.json` | practice plan | every item carries its evidence row, rule id and availability |
| `export.schema.json` | `export.json` at the root of an export | `includesAudio` false by default (D5) |
| `csv-contract.schema.json` | `contracts/csv/*.v1.json` | column order, nullability, quoting, line endings |
| `engine-output.schema.json` | fold and stats outputs | the exact shape both platforms must produce |
| `fixture-*.schema.json` | the fixtures themselves | |

No schema has an `$id`: references are relative file references (`common.schema.json#/$defs/id`), so any 2020-12
validator resolves them when loading from disk, and no URL appears before it resolves (IDC domain rule 1).
The bundled checker (`scripts/spec/jsonschema_subset.py`) refuses keywords it does not implement, so no schema can
rely on a silently ignored keyword.

## How a platform consumes the fixtures

Both apps add a conformance test target that reads `spec/fixtures` directly from the repository (iOS: a JovraCore
test resolves the path from `#filePath`; Android: a JVM unit test reads `../spec/fixtures`). Nothing is copied, so a
fixture change immediately fails whichever platform has not caught up.

| Fixture kind | What the platform does | Comparison |
|---|---|---|
| `jovra.fixture.scoring` | Decode `input` (format, players, sides, toss, log). For each checkpoint, fold the log events with `seq <= afterSeq`, compute stats, and diff against the previous checkpoint (`fold.changes`). | Deep equality of parsed JSON with `checkpoints[i].expected`. Every output value is an integer, string, boolean or null: no floating point anywhere. |
| … with `expectError` | Folding must throw a typed error whose code equals `expectError.code`. | Code string |
| `jovra.fixture.stats` | Fold the whole log, compute stats. | Deep equality with `expected` |
| `jovra.fixture.pct` | `ratio`, `delta` (percentage points from the displayed integers) and `pool` (sum numerators and denominators) | Deep equality per case |
| `jovra.fixture.units` | `convert` (exact, half-up at `places`), `display` (half-up once to the unit's step; same unit returns the stored text untouched), `gaugeHint` | Deep equality per case |
| `jovra.fixture.sample` | Load `jon-vs-alex.session.json` with the app's real session decoder, build the engine input from it, fold, compute stats, export both CSVs. | Fold + stats deep-equal; **CSV byte-for-byte** with the golden files; `overview` holds the screen-9 numbers |
| records (`equipment`, `practice plan`, `export`, `archive`, registry) | Decode with the app's real model types and re-encode. | Must decode without loss; schema-valid |

`assertions` in each fixture are the hand-derived subset of the expected output that was worked out from
`docs/research/tennis-rules-and-stats.md` before the engine ran. The generator refuses to write a fixture whose
engine output disagrees with them, and the validator re-checks them. Platform tests may print the failing assertion
first: it is the human-readable reason a whole fixture differs.

Implementation notes for the ports:

- **Percentages**: `pct(n, d) = (200n + d) / (2d)` in integer division; `d = 0` gives `null` and display `"—"`.
  Never pass a fraction to `NumberFormatter`/`DecimalFormat` (they round half-even; `1/8` must show 13%).
- **Units**: values are decimal strings. Use `Decimal` (Swift) / `BigDecimal` (Kotlin); multiply by the exact factor,
  divide only once at the end with enough precision (>= 20 digits) and round half-up once. Never write a converted
  value back over the stored one.
- **Identifiers and times**: ids are opaque strings; times are integer milliseconds on the session timeline.
- **Display strings** in fixtures (`"67%"`, `"7-6(4)"`, `"+4 percentage points"`, CSV `score_before`) are the
  en-US canonical forms; the UI localizes from the structured values (`call`, `ratio`) instead.

## The reference engine (`spec/reference/jovra_ref`)

| Module | Responsibility |
|---|---|
| `log.py` | Append-only log resolution: voids (undo; voiding a void is redo; voiding an event also undoes every later correction of it), `supersedes` (replace in place, original kept), `insertBefore` (add a missed point; a voided event keeps its slot as an anchor), doubles orders per set; structural errors with stable codes |
| `scoring.py` | The fold: ad/No-Ad games, tie-break sets at any trigger (6-6, 4-4, 3-3, 8-8), advantage sets, match tie-break in lieu of the final set (recorded as a set), sudden-death tie-breaks, best of 1/3/5; singles and doubles server rotation; deuce/ad court and receiver; ends (odd game in set, every 6 tie-break points, Coman, short-set); rests; lets, faults, double faults, point and game penalties, retirement, default, walkover; unknown winners → provisional; as-called checkpoints vs derived; conflicts; hypothetical folding for game/break/set/match points; `validate_log` (player ids and doubles orders, before the fold); `diff` between checkpoints |
| `stats.py` | Every stat in rules §6 with the shared integer `pct`, pooling and percentage-point deltas |
| `units.py` | Exact factors (lb↔kg↔N, mph↔km/h↔m/s, mm/cm/m/in/ft, cm²/in², g/oz), display steps, gauge help ranges |
| `csv_export.py` | `points.csv` and `stats.csv`, driven by the hand-written contracts |
| `sample_match.py` | The Jon vs Alex generator (seeded SplitMix64, independent of Python's `random`) and the C1-C16 checker |

## Fixture inventory

- **Scoring, 64 cases + 10 rejections**: love/4-2 holds, deuce chains, break via ad-out, No-Ad deciding point (both
  outcomes, side recorded and not), service alternation across sets, end changes for odd and even sets, 7-5,
  tie-break 7-4 serve order and next-set first server, extended tie-breaks, best-of-1 tie-break loss, advantage set,
  advantage final set, match tie-break [10-8] and [12-10], Grand Slam final-set 10-point tie-break, pro set 9-8(5),
  short sets (4-4 and 3-3 triggers), short-set tie-break to 5, Fast4 sudden death (both sides on set point), best of 5,
  standalone tie-break, doubles rotation and alternating receivers, doubles order changed per set, doubles tie-break
  rotation and carry-over, doubles No-Ad side, service lets, double faults incl. a time-violation fault, rally let,
  point penalties mid-game and between games, game penalty, game penalty in a tie-break, retirement, default,
  walkover, correction moving later points into a different service game (serverMismatch), corrections that make a
  tie-break appear / the match end earlier / the match no longer end, undo/redo, unknown outcome then review,
  checkpoints agreeing and conflicting, inserted missed point, detected vs reviewed, set+match break point, Coman
  tie-break, points after the match end, end-type consistency, streaks and momentum, a doubles set point of the other
  parity left unconverted before a per-set order, a correction that flips doubles set parity (`doublesOrderConflict`),
  game penalties ending a tie-break against the leader and ending a match tie-break, a point penalty converting a break
  point, retirement before play, a let in a No-Let format, voiding the original of a corrected point, re-entered doubles receivers reported as
  recalculated, the Fast4 sudden-death point keeping side parity (a recorded side flagged), a short-set tie-break whose
  4-4 point is the receiver's choice; rejections for non-increasing seq, missing supersede target, missing doubles
  order, missing void target, a doubles receiver from the wrong team, an order invalid for a set not yet reached, and
  unknown player ids (penalty, doubles receiver, toss first server, a voided retirement).
- **Stats**: 24 integer-percentage vectors (incl. the §7 table, `1/8 → 13`, `199/200 → 100`, `1/201 → 0`, `0/0 → —`),
  5 delta and 3 pooling cases; every end type (`unknown` included) in one log; doubles per-server stats; a 7-6 set
  whose tie-break is not a service game.
- **Units**: 31 vectors.
- **Sample**: `jon-vs-alex.session.json` (124 points, labelled Sample, synthetic) with expected fold, stats, the
  screen-9 overview, all sixteen constraints (C15 is `partial`: its timestamp clause is waived, decision 18), and golden
  CSVs; `export.json` and `archive.json` whose sizes and hashes
  are checked against those files.
- **Records**: equipment and practice-plan examples (Sample), and the v1 capability registry.

## Decisions taken where the rules doc left room

These are encoded in the engine and pinned by fixtures; change them only through a fixture change.

1. **"Shots" = `strokeCount`** (racket contacts; D4). Rally length is derived: serve counts, final error does not;
   DF 0, ace 1, a touched service winner is 2 contacts / rally 1. A hindrance has no derived rally length.
2. **Unknown winner**: the fold stops deriving at the first unknown point. Later points get no score, server or
   flags (`determined: false`), the match is `provisional`, and stats count only the determined prefix
   (`excludedPoints` says how many were left out). Nothing is guessed, including the server.
3. **Effective outcome** is the `reviewed` block as a whole when present, else `detected`; no field-level merge.
4. **Penalties**: a point penalty occupies a point slot (court side and tie-break rotation advance), counts in total
   points, and is excluded from service and return points and serve stats; a game with a point penalty is still a
   service game. Break-point counts include penalty slots: a point penalty on a break point is a break point faced and
   either saved or converted, so a break completed by a point penalty keeps the §6.3 oracles
   (`BPconverted = breaks = returnGamesWon`, `BPfaced − BPsaved = timesBroken`; S58). A game penalty awards the game,
   is excluded from service/return-game counts and is never a break; in a set tie-break it awards the set with the
   tie-break points as they stood (`6-7(1)`, `6-7(3)` when the penalised side led 3-1: S35, S56); in a match
   tie-break, the match (S57).
5. **Scoreline**: winner first once there is a winner, otherwise side A first; `(x)` is the tie-break loser's points
   (USTA I.E.1.d), even when a game penalty leaves the loser with more; a match tie-break renders `[10-8]`, but one
   ended by a game penalty renders `1-0(x)` (USTA I.E.1.b's other form) so the winner never reads as having fewer
   points; `ret.`, `def.`, `w/o`; a set in progress is shown on retirement or default if any point of it was played
   (`0-0 def.`). A retirement logged before any point is a walkover (USTA Table 10 `Wo [inj/ill/pc]`): status
   `walkover`, scoreline `w/o` (S59). A default before play stays `defaulted` (`Def [ns/late]`, no points).
6. **Tie-break ends**: change after every 6th point except the last, plus the end-of-set change, which falls out of the
   "odd game in the set" rule because a set tie-break is game 13. Coman (1, 5, 9, …) and short-set (after point 4)
   are parameters.
7. **Final-set rule** applies to the set reached at (setsToWin − 1) all; in best of 1 that is the only set.
8. **Doubles orders**: set 0 must have a `doublesOrder` (else `doublesOrderMissing`) whose first server is the toss
   first server; an order naming two servers of one team, or a `deuceReceivers.A`/`.B` who is not a player of side
   A/B, is `doublesOrderInvalid` (Rule 15: each team decides which of *its* players receives, so the receiver is
   always on the team opposite the server; E05). Every active order is checked before the fold, reached or not (E09). Later sets without one carry each
   team's first server and deuce-court receiver forward. Under Rule 14 each team names its own server and the team
   that serves first follows from match-game parity, so a stored order is read as two team choices: if it names the
   other team first (a correction changed the parity, S55), the fold keeps each team's named server, takes the team
   order from the rules and raises `doublesOrderConflict` (`recorded` = the order's first server, `derived` = the
   server used). Hypothetical folding for pressure flags never opens the next set, so an unconverted set point of the
   other parity cannot touch a later order (S54).
9. **No-Ad deciding point side** is never derived; unrecorded means `courtSide: null` (and, in doubles, receiver null).
10. **Serve facts**: lets are not attempts; `[fault]` alone means the second serve went in; a point without serve facts
    is still a service point but is left out of first-serve denominators. A `let` serve in a No-Let format is **not** a
    conflict: App VI's No-Let rule removes only Rule 22.1.a (the net-cord let), while 22.1.b (receiver not ready) still
    gives a let (S60). (Verifier finding D7 asked for `outcomeInconsistent`; rejected for this reason.)
11. **Fast4** uses unverified parameters (`ruleStatus: "unverified"`): tie-break to 5 at 3-3 with sudden death at 4-4,
    ends changing only after tie-break point 4 (`endChange: "after4"`, the short-set tie-break of App VI.2 that rules
    §1.4 says Fast4 uses), No-Ad, No-Let, final set identical.
12. **Checkpoints** compare the as-called games for the named set at their log position; a conflict flags only the
    points since the previous checkpoint. Auto-fill from checkpoints (P0-11) is registered as `estimated` but is
    **not yet in the reference**, so neither app may ship it until it has fixtures.
13. **Conflicts never stop the fold.** `outcomeInconsistent` covers end type vs winner vs stroke parity;
    `doublesOrderConflict` covers a stored doubles order that no longer matches the derived parity. Only structural
    log errors throw (a malformed event, an unknown player id, an invalid doubles order, or a missing set-0 order);
    they are all checked before the fold over the whole log, so correcting, inserting or voiding a point never makes a
    foldable log unfoldable (S54, S55, S61, E09).
14. **Rests** in the sample: a change of ends "without rest" is capped at the 25 s between-point ceiling.
15. **CSV**: UTF-8 without BOM, LF line endings (not RFC 4180's CRLF), minimal quoting; deuce and the No-Ad deciding
    point both read `40-40`, advantage `AD-40` / `40-AD`, server first.
16. **Units**: half-up once to the display step (lb 0.5, kg 0.1, N 1, mph and km/h 1, m/s 0.1, mm 0.01, cm 0.1,
    m 0.01, in 0.01, ft 0.1, cm² 0.1, in² 0.1, g 1, oz 0.1; `units.py` `DISPLAY_STEP` is the source), trailing
    zeros dropped on converted values, the stored text shown untouched when the unit matches (`52.0 lb`). Gauge has no
    exact conversion: `gaugeHint` returns both sources' ranges and diameter in mm stays the stored truth.
17. **Deltas**: `+4 percentage points`, singular for 1, `0 percentage points`, `—` when either side is undefined. The
    canonical negative sign is ASCII hyphen-minus U+002D (`-4 percentage points`, T01), not U+2212; the UI may
    localize from the integer `delta`, but the fixture string compares byte-for-byte.
18. **Sample match**: winners are the verified construction (rules §8.4, Jon serves first, D4); the seed pins serve
    split, aces 4/2, DFs 3/5, end types, shot counts and timestamps. The session has **no media**
    (`recording.mode: "none"`, `storage.originals: "none"`); its timeline starts at the first serve strike and the last
    point ends at exactly 54:00. Point 42 keeps the C15 state (set 1, 4-3, Jon 30-15, Alex serving, 8 shots, needs
    review) but starts at 18:23.7 (`tStartMs` 1,103,730) with even pacing: the 12:46 timestamp is waived by D4
    (illustrative clip moment on the D8 sample video's clock). C15 is therefore recorded with status `partial` and a
    `waived` entry (clause, decision, reason, observed value), never as a plain `pass`.
    The synthetic sample *video* (D8) is a separate artifact; C16 holds because no serve speed is derived here.
19. **ADR-0003 nuance**: ADR-0003 lists "server" among stored point fields. Here the stored value is only the optional
    observed `recordedServer`; the rules-derived server is authoritative and a disagreement is a `serverMismatch`.
20. **Voids and corrections**: voiding an event also undoes every later correction of it. Voiding the first version of
    a corrected point removes the point; voiding the latest correction restores the version before it. A voided
    event keeps its position as a tombstone, so an `insertBefore` aimed at it (or at an undone correction of it) still
    lands in that place (S61). The append-only log therefore stays foldable after any void (ADR-0003).

21. **Structural validation** (`validate_log`, verifier findings D1/D2): `toss.firstServer` and every player field of
    every logged event (penalty/retirement/default/walkover `player`, point `recordedServer`, doubles-order servers
    and receivers) must name a player in `sides`, else `unknownPlayer`; voided events are checked too, like
    `unknownEventType` (E06-E08, E10). The schema types these only as ids, so this check is what keeps the Swift and
    Kotlin ports from trapping on a lookup. Order of checks: `resolve` (ids, seq, types, void/supersede/insert targets),
    then `unknownPlayer`, then doubles-order validity, then `doublesOrderMissing`. Applying D1 exposed one fixture whose
    set-1 order had its receivers swapped across teams (S55, server Ben was receiving from his own partner); the case
    now keys `deuceReceivers` by team and its receivers changed accordingly.
22. **Sudden-death tie-break side** (verifier finding D4, accepted as a parameter): ITF App VI.2 says the short-set
    tie-break has "a deciding point" at four all but leaves the order and number of serves to the sanctioning body,
    while App VI No-Ad defines the deciding point as the receiver's choice of half. The tie-break rule therefore takes
    `suddenDeathSide`: `alternate` (default, the Fast4 preset and S21/S22/S63) keeps the tie-break side parity;
    `receiverChooses` serves the sudden-death point to the recorded `decidingPointSide` (null and, in doubles, receiver
    null until recorded; S64). A `decidingPointSide` recorded on any point where the receiver does not choose is never
    silently dropped: the derived side is used and a `decidingPointSideIgnored` conflict is raised (S63).
23. **Recalculated points** (verifier finding D3): `changes.recalculatedPointIds` lists every point present in both
    folds whose derived state differs in any field: determined, afterMatchEnd, set, game, gameInSet, tiebreak,
    pointInGame, server, receiver, serverSide, courtSide, ends, before, call, pressure, after (rules §4.4 "any flag or
    stat changed"). Re-entering doubles receivers changes only receivers and still marks every point (S62).

## Not yet covered (needs fixtures before either app relies on it)

As-played mode with `ServerOverride` / `ReceiverOverride` (Rule 27c-e), suspensions, wrong-ends and wrong-half
corrections, checkpoint auto-fill, Canadian/Australian doubles, mixed-doubles No-Ad receiver rule, practice sets
without a match end, the manual-assisted serve-speed formula and the court homography. The capability registry lists
the analysis capabilities; none is `validated`, and the audio, rally and camera-moved detectors stay `disabled` until
their benchmark gates pass.
