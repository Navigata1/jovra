# Tennis rules and stat definitions: implementation reference

Status: synthesized reference, 2026-10-07. Audience: whoever writes the scoring state machine, the stat engine and the
conformance fixtures in `spec/` (ADR-0001, ADR-0003). Built from `raw/tennis-rules-stats.md`, cross-checked against
`raw/community.md`, `raw/review-mining.md`, `raw/gap-finder.md` and the brief (`design-reference/brief/*`,
`docs/handoff/CLAUDE-BUILD-PROMPT.md`).

**Labels.** **OBSERVED** = stated in a cited primary source (ITF, USTA, LTA, MCP documentation) or computed by a
reproducible script from stated inputs. **INFERRED** = a design rule or derivation. **UNVERIFIED** = not confirmed
from a primary source; treat as a parameter, not a constant. Rule numbers refer to the ITF *Rules of Tennis 2026*
(English text prevails over translations) unless another body is named.

**Editions in force on 2026-10-07:** ITF Rules of Tennis 2026 (PDF modified 2025-12-23) plus the ITF 2026
Amendments sheet; USTA *Friend at Court 2026*; ITF Masters World Tennis Tour Regulations 2026 (Code of Conduct and
penalty schedule).

---

## 0. Ten rules a builder must not get wrong

1. **The score is a pure fold over an append-only event log.** Server, side, end, game/set/match state and every stat
   are derived from: the format, the toss facts (`firstServer`, `startingEnd`), doubles order choices, and the
   sequence of observed point facts. Never store a score as truth (ADR-0003). INFERRED from Rules 5, 10, 14, 15, 17.
2. **Singles game server depends only on game index parity**, counting a set tie-break as one game:
   `server(g) = firstServer if g is even else opponent` (g = 0-based match game index). Only game *boundaries* depend
   on who won points, which is why one correction can move later points into a different service game. INFERRED.
3. **Corrections never mutate history.** A user edit `Supersede`s an event; the automatic suggestion survives for
   benchmarking (CLAUDE.md hard rule 4). Points already played stand (Rule 27), so the app must be able to show an
   **"as called on court"** score next to the **rules-derived** score when they diverge.
4. **One integer rounding function for both platforms:** `pct(n, d) = (200·n + d) div (2·d)` (half-up, no floats);
   `d = 0` displays "—"; valid for n ≥ 0, d > 0 (it equals floor(100n/d + ½)). Platform formatters round half-even once
   set to zero fraction digits (`NumberFormatter` `.percent` does so by default; plain `FormatStyle` `.percent` does
   **not** round to an integer and shows "12.5%") and disagree with Kotlin/Swift `round` (§7). OBSERVED (computed;
   re-verified 2026-10-07). Android ICU `DecimalFormat`'s default is UNVERIFIED — the shared `pct` avoids depending on it.
5. **Second-serve points include double faults in the denominator.** OBSERVED (MCP data structure).
6. **Rally length convention:** the serve counts as a shot, the final error does not (DF = 0, ace/missed return = 1).
   OBSERVED (MCP, Tennis Abstract, Fitzpatrick et al. 2021). "Shots" on screen 9 must be defined separately (§6.9).
7. **An ad game never has exactly 7 points;** legal final splits are 4–0, 4–1, 4–2, then (k+2)–k for k ≥ 3. Use this
   as a fixture and correction validator. INFERRED from Rule 5a.
8. **Tie-break service and sides:** point 1 by the player whose turn it is, then blocks of two; side alternates every
   point; ends change every 6 points; the tie-break's first server receives first in the next set (Rule 5b).
9. **"Advantage" is overloaded.** Screen 4's "Best of 3 · Advantage" means ad *game* scoring, but the ITF "Advantage
   set" (Rule 6a) is a set with no tie-break. Use separate labels: games **"Ad / No-Ad"**; sets **"Tie-break at 6–6 /
   Advantage set"**. INFERRED.
10. **Unknown is a first-class outcome.** If a point's winner is not recorded, every later score is **provisional**
   until reviewed, never guessed. Precedent: MCP charters record S/R and unknown codes (OBSERVED).

---

## 1. Scoring units

### 1.1 Standard ("ad") game — Rule 5a (OBSERVED)

- Calls: Love, 15, 30, 40, Game; the **server's score is called first**.
- At 3–3 points: **Deuce**. Next point gives **Advantage**; winning the following point wins the game, losing it
  returns to deuce. After deuce a player needs two consecutive points.
- Display mapping (INFERRED): counts 0/1/2/3 → 0/15/30/40; at ≥3–≥3 equal counts show "Deuce", a one-point lead shows
  "Ad-[name]".
- Game lengths: 4, 5, 6, 8, 10, … points. Never 7.

### 1.2 No-Ad game — ITF Appendix VI (OBSERVED)

- At 3–3 a single **deciding point**; its winner wins the game. Game lengths 4–7 points.
- Singles: the **receiver** chooses to receive in the right (deuce) or left (ad) half.
- Doubles: the receiving **team** chooses the side; players may not change positions for that point.
- Mixed doubles: the player of the same gender as the server receives; positions still may not change.
- Engine consequence (INFERRED): store `decidingPointSide` as an observed fact. It cannot be derived.

### 1.3 Tie-break game — Rule 5b (OBSERVED)

- Calls: Zero, 1, 2, …; first to **7 with a 2-point margin**, no upper limit. Wins the game **and** the set.
- The set is recorded **7–6**; the tie-break counts as one game for its winner.

### 1.4 Set types

| Set type | Win condition | Tie-break trigger | Recorded as | Source |
|---|---|---|---|---|
| Tie-break set | 6 games, margin 2 | 6–6 → 7-point TB | 6–x, 7–5, 7–6(x) | Rule 6b (OBSERVED) |
| Advantage set | 6 games, margin 2 | none (e.g. 12–10) | 6–x, 7–5, 8–6, … | Rule 6a (OBSERVED) |
| Short set | 4 games, margin 2 | 4–4 → TB; or **3–3** at the sanctioning body's discretion | 4–2, 5–3, 5–4(x); 4–3(x) | App VI.1; USTA I.E.3 (OBSERVED) |
| Short-set TB (option) | first to **5**, deciding point at 4–4 | — | 5–4(x) / 4–3(x) | App VI.2 (OBSERVED); ends change only after the first 4 points |
| Pro set (USTA) | **8 games**, margin 2 | 8–8 → 7-point TB (10-point may be announced) | 9–8(x) | USTA I.E.4 (OBSERVED) |
| Fast4 | 4 games | 3–3 → TB to 5, sudden death at 4–4; No-Ad; No-Let | 4–x, 4–3(x) | **UNVERIFIED** (Wikipedia only; tennis.com.au returned 403) |

Fast4 is not a separate engine: it is the Short Set with the 3–3 trigger, the short-set TB, No-Ad and No-Let. Its
tie-break serve order and match-tie-break details must be format **parameters** until confirmed from Tennis Australia.

### 1.5 Match formats — Rule 7, Appendix VI (OBSERVED unless marked)

- **Best of 3** (first to 2 sets) or **best of 5** (first to 3).
- **Match tie-break in lieu of the deciding set:** at one set all (two all in best of 5), one tie-break game to **7**
  (App VI.3) or **10** (App VI.4), win by 2. USTA sanctioned play uses the 10-point version unless authorised
  otherwise (USTA I.E.1.b). Original service order continues; doubles teams may re-order (USTA Comments 14.1, 15.2); a
  120 s set break precedes it; no ball change.
- **Final-set 10-point tie-break at 6–6:** App VI.5. Adopted jointly by the four Grand Slams on **2022-03-16**,
  starting at Roland-Garros 2022 (ausopen.com, OBSERVED). Historical imports: AO 10-point TB at 6–6 from 2019;
  Wimbledon 7-point TB at 12–12 (2019–2021); US Open 7-point TB at 6–6; Roland-Garros none (secondary press,
  OBSERVED-secondary).
- Tour doubles (No-Ad + 10-point match TB): **UNVERIFIED**; make it a preset only after checking the tour rulebook.

**Format presets to ship (INFERRED; the Grand Slam row is OBSERVED):**

| Preset id | Sets | Games | Set TB | Deciding set | Lets |
|---|---|---|---|---|---|
| `club_bo3` (default) | best of 3 | Ad | 7-pt at 6–6 | full set | Let |
| `usta_mtb` | best of 3 | Ad | 7-pt at 6–6 | 10-pt match TB | Let |
| `noad_mtb` | best of 3 | No-Ad | 7-pt at 6–6 | 10-pt match TB | Let |
| `slam_bo5` / `slam_bo3` | 5 / 3 | Ad | 7-pt at 6–6 | 10-pt TB at 6–6 | Let |
| `pro_set_8` | 1 | Ad | 7-pt at 8–8 | — | Let |
| `short_sets` | best of 3 | No-Ad | 7-pt at 4–4 (param) | 10-pt match TB | Let |
| `fast4` | best of 3/5 | No-Ad | 5-pt at 3–3, sudden death 4–4 | param | No-Let |
| `tb_only_7` / `tb_only_10` | standalone tie-break (community ask, F13) | — | — | — | Let |
| `practice_set` | free count, no match end | Ad | none | — | Let |

Community evidence for flexible formats: 37 authors / 16 threads asked for standalone tie-breaks, no-ad, Canadian
and Australian doubles, practice sets (raw/community.md §4 rank 10). Session type and format must be **editable after
the match** with a full recompute (Rule 27f–h precedent; SwingVision users could not change session type after
starting, raw/community.md F13).

### 1.6 Recording conventions (OBSERVED, USTA I.E and Table 10)

- Set tie-break: `7-6(x)` where x is the **loser's** tie-break points (`7-6(4)` = 7–4; `6-7(14)` = 14–16).
  **Store both totals** (INFERRED); render x from them. Winner's total = `max(target, x + 2)`.
- Match tie-break in lieu of the final set: `1-0(x)` or bracketed `[10-8]`. For standings it counts as one set and
  one game (USTA FAC Comment II.B-6).
- Short sets `5-4(x)`; pro set `9-8(x)`.
- Terminations:

| Situation | Code | Engine state |
|---|---|---|
| Retirement | `Score Ret [inj/ill/pc]` | `Retirement(player, atEvent)`; stats over completed points only |
| Default (point penalty system) | `Score Def [pps]` | `Default(player, reason)` |
| Default, late on resumption | `Score Def [late]` | same |
| Pre-match default | `Def [ns/late/refsl/…]` | no points |
| Walkover | `Wo [inj/ill/pc/tae]` | no score; all denominators 0 → "—" |
| Double walkover | `Wo/Wo` | no winner |
| Incomplete / Abandoned / Cancelled | as named | **no winner**; keep the session (raw/landscape.md: Smashpoint's "No winner" save is a good precedent) |

Display (INFERRED): `6–4 3–1 ret.`, `w/o`.

---

## 2. Serving order, sides and ends

### 2.1 Toss — Rule 9 (OBSERVED)

The toss winner chooses serve/receive, an end, or to make the opponent choose first. Store `firstServer` and
`startingEnd` as setup facts; the engine cannot derive them.

### 2.2 Standard games — Rules 14, 17, 20 (OBSERVED), formulas INFERRED

- Service alternates **every game**, across set boundaries.
- Each standard game's first point is served from the **right (deuce) half**; then halves alternate.
- A second serve comes from the same half as the faulted first serve.
- `j` = 1-based index of completed points within the game:
  `side(j) = right if j odd else left` (exception: No-Ad deciding point → `decidingPointSide`).
- Singles: `server(g) = firstServer if g even else opponent` (g counts set tie-breaks as one game). This reproduces
  Rule 5b's "tie-break first server receives first in the next set".

### 2.3 Tie-break games — Rules 5b, 10, 17; USTA Comment 5.3; App VI (OBSERVED), formulas INFERRED

- `n` = 1-based tie-break point. Singles: `server(n) = A if floor(n/2) even else B` → 1:A, 2–3:B, 4–5:A, 6–7:B, …
- Doubles: `server(n) = rotation[(start + floor(n/2)) mod 4]`, continuing the set's rotation.
- `side(n) = right if n odd else left`; each new server therefore starts from the left (ad) side.
- **Ends:** change after every 6 points (6, 12, 18, …) and at the end of the tie-break, **without rest** (Rule 29a).
  **Coman** option: after point 1 then every 4 (5, 9, 13, …) — ITF App VI, USTA I.E.1.c. Short-set TB: ends change
  only after the first 4 points.
- Match tie-break: original service order continues; ends every 6 points.

### 2.4 Doubles — Rules 14, 15; USTA Comments 14.1, 15.1, 15.2 (OBSERVED)

- At the start of **each set** the serving team picks who serves game 1; before game 2 the other team picks.
  Rotation `[s1, s2, partner(s1), partner(s2)]`. Order may change at each set and at a match tie-break.
- Receiving: before its first receiving game in a set, each team picks who receives the first point (from the
  right). Partners alternate every point for the whole set. Model as fixed `deuceReceiver` / `adReceiver` per team per
  set (INFERRED); in a tie-break the receiver is whoever covers the side served to.
- Australian/Canadian doubles and 2-on-1: community requests (raw/community.md F12/F13). Model as format flags that
  alter rotation; **UNVERIFIED** rule text — parameters only.

### 2.5 Change of ends and rest — Rules 10, 29a (OBSERVED)

- Change ends after games 1, 3, 5, … **of each set**, and at the end of a set with an odd number of games; if even,
  after game 1 of the next set.
- **One-condition implementation (INFERRED, equivalent):** change ends after every completed game whose **index within
  its set is odd** (set tie-break = game 13), plus the in-tie-break changes of §2.3.
- Maximum rest: **25 s** between points (measured from the end of a point to the strike of the next first serve);
  **90 s** at a change of ends; **no rest** after game 1 of a set or within a tie-break; **120 s** set break. For club
  play these are ceilings, not targets.
- Match duration (Rule 29): starts at the first serve put in play, ends when the match is won. **Session/video
  duration is a separate field** (warm-up, stoppages). INFERRED.

---

## 3. Lets, faults, penalties and errors in play

Rows OBSERVED from the cited rule; the "engine" column is INFERRED.

| Event | Rule | Score effect | Engine / stat treatment |
|---|---|---|---|
| Service let (net cord otherwise good; touches receiver after net; receiver not ready) | 22 | Serve replayed; a let does **not** cancel an earlier fault | Store as `ServeAttempt(result: let)`; not an attempt in stats |
| No-Let format | App VI | Net-clipping serve is live | Format flag `lets: let/noLet` |
| Rally let (hindrance outside control, unintentional opponent hindrance, overrule = hindrance) | 23, 26, App VII Case 7 | **Whole point replayed from the first serve**, even after a fault | `RallyLet`; partial serves of the voided point are voided (MCP also deletes replayed points) |
| Deliberate hindrance | 26 | Point to the hindered player | End type `hindrance` |
| Fault (foot fault, wrong position, miss, hits fixture/singles stick/post, hits server or partner) | 16–19 | 1st → 2nd serve same half; 2nd → **double fault**, point to receiver | Each fault is an attempt with stored `type`; foot fault = ordinary fault |
| Serve hits receiver before bounce | 24 Case 7 | Server wins (unless a let) | Classify as **service winner, not ace** (LTA: ace is untouched) |
| Time violation | ITF Masters III.D | 1st warning; then server → fault, receiver → point penalty | Server's = fault `cause=timeViolation` (counts as an attempt; can make a DF) |
| Point penalty | USTA IV.D.13–14 | As if the penalised player lost the next point; between games → first point of next game | Occupies a point slot (advances side and TB rotation); counts in **total points**, **not** in service or return points |
| Game penalty | USTA Table 14 | Opponent awarded the game; in a set TB the penalised player loses the set; in a match TB, the match | Excluded from service-game counts |
| Penalty schedule | ITF Masters III.Q; USTA PPS | ITF: warning → point → game (referee decides default after 3rd). USTA PPS: point, game, default for listed delays | Per-format setting; club play = logging, not automation |
| Retirement / default | USTA Table 10 | Match ends, opponent wins | Interrupted point excluded from stats |
| Suspension (rain, dark) | App VII | Score and positions stand | Exclude clock gap from point durations |
| Served from wrong half | 27a | Correct when discovered; points stand; a fault before discovery **stands** | Store actual side; raise `sideMismatch` |
| Wrong ends | 27b (**2026 amendment**, extended to tie-breaks) | Correct when discovered; a fault before discovery **does not stand** | Void the open fault |
| Served out of turn, standard game | 27c | Mid-game: correct server takes over. After a completed game: **order stays as altered**. Opponent's fault before discovery does not stand (doubles: partner's fault stands) | `ServerOverride` permanently shifts rotation |
| Served out of turn, tie-break | 27d | Even number of points played → correct now; odd → order stays altered | Same mechanism |
| Doubles receiving-order error | 27e | Stays until end of game, then reverts | `ReceiverOverride` scoped to the game |
| Wrong set format started | 27f–h | One point played → correct; otherwise continue (advantage set ↔ TB set at 8–8 rules; MTB set → short set) | Allow a post-hoc format edit with recompute; warn when results change |
| Disputed score, no officials | The Code §31–32 | Server announces game score before a game and point score before each point; disputes: count agreed points and replay disputed ones, else agreed score, else toss | Show "as called" vs "rules-derived" when they diverge |

---

## 4. Event model, undo and the correction cascade (ADR-0003)

### 4.1 Observed facts (append-only; each carries provenance and source)

Provenance values per CLAUDE.md hard rule 1 / ADR-0004: `manual`, `estimated`, `reviewed`, `validated`; source =
`user` or `model:<name>@<version>`.

- `MatchSetup` (format preset + overrides, players, handedness, doubles teams, `firstServer`, `startingEnd`)
- `DoublesOrder(set, servingOrder, receivers)`
- `ServeAttempt(result: in | fault(type, cause) | let, side?, t)`
- `PointOutcome(winner, endType, t_start, t_end, strokeCount?, rallyLength?)`
  - `endType ∈ {ace, serviceWinner, doubleFault, winner, forcedError, unforcedError, penalty, hindrance, unknown}`
- `RallyLet`, `ServerOverride`, `ReceiverOverride`, `DecidingPointSide`
- `Penalty(kind, player)`, `Retirement`, `Default`, `Suspension(t0, t1)`
- `Void(eventId)`, `Supersede(eventId, newFacts)`
- `Checkpoint(setIndex, games: (a, b), t)` — **NEW** (changeover score entry; raw/gap-finder.md #2)

### 4.2 Derived state (pure; always refold from event 1)

Per point: pre-point score, server, receiver, side, serve number, ends, changeover flag, game/break/set/match-point
flags. Per set and match: summaries and every stat in §6. A full refold of 120–250 points is trivial; incremental
folding adds risk for no benefit (INFERRED).

Game, set and match point detection uses **hypothetical folding**: apply "X wins this point" and test whether the
unit closes. The same method yields break points.

### 4.3 Undo

`Undo = Void(lastEvent)` + refold. Undoing a game-winning point reopens the game, reverts the server and the
change-of-ends flag automatically because state is derived.

### 4.4 Correction cascade — conflict types the UI must show

Changing point *k* can:

| Conflict | Trigger | UI |
|---|---|---|
| `serverMismatch` | A game boundary shifts, so the **recorded** server of later points (from video or manual tag) differs from the rules-derived server | Banner on affected points; choose Rules mode or As-played mode |
| `tiebreakAppeared` / `tiebreakVanished` | e.g. 6–5 becomes 6–6 | Serve pattern changes from games to 1-2-2 blocks; highlight affected points |
| `pointsAfterMatchEnd` | The match now ends earlier | Points after the final point are flagged, not deleted |
| `matchIncomplete` | The match no longer ends | Show provisional result |
| `checkpointConflict` (**NEW**) | A user-entered changeover score cannot be reached from the point log | Flag only the stretch between the two checkpoints |
| `recalculated` | Any flag or stat changed | "Recalculated" badge (implementation-states.md) |

**Resolution modes.** *Rules mode* (default) recomputes strictly. *As-played mode* keeps recorded server overrides and
re-anchors later games to the observed server, following Rule 27c ("order stays as altered").

### 4.5 Checkpoint scoring (NEW; raw/gap-finder.md #2)

During play the user may enter only the **game score at changeovers** (about 10 taps a match). Between two
checkpoints, the engine searches point-winner assignments consistent with (a) the checkpoint game counts, (b) legal
game lengths (§1.1), and (c) any detected point boundaries, then auto-fills where the assignment is unique and flags
ambiguous stretches for Fast Point Review. The search is small (games end at ≥4 points with a margin of 2), so it is
a bounded enumeration, not ML (INFERRED). Auto-filled points carry provenance `estimated` until reviewed.

---

## 5. Inputs the engine needs from capture and review

| Fact | Source in v1 | Provenance |
|---|---|---|
| Point start/end time | Manual "Mark point" bookmark, Fast Point Review, or (if gated) audio/motion segmentation | manual / estimated |
| Point winner | Live manual score, checkpoint auto-fill, swipe review | manual / estimated → reviewed |
| End type | Optional review chip; default `unknown` | manual |
| Serve result (in/fault/let) | Optional live taps or review; serve detection later | manual |
| strokeCount | Review count or (if gated) audio hit count | manual / estimated |
| Placement | Manual tap on court diagram (P1); video-derived later | manual / estimated |

---

## 6. Stat definitions

Notation: `SP(p)` = service points of player p; `opp` = opponent; "std game" = non-tie-break game. All values are
computed from events; every displayed rate keeps its fraction one tap away.

### 6.1 Serve

| Stat | Numerator | Denominator | Notes | Label |
|---|---|---|---|---|
| Service points `SP` | — | — | Points where p served ≥1 serve; excludes replayed points and penalty-awarded points | INFERRED; MCP deletes replayed points (OBSERVED) |
| First-serve attempts | = SP | — | A let is not an attempt | INFERRED |
| **1st serve in %** | 1st serves in | SP | Fixture Jon 40/60 → **67%** | OBSERVED (LTA) |
| **1st-serve points won %** | points won when 1st serve in | 1st serves in | Fixture 28/40 → **70%**; aces count | OBSERVED (LTA) |
| 2nd-serve points | SP − 1stIn | — | **Includes double faults** | OBSERVED (MCP `serve_pts = first_in + second_in`, DFs inside `second_in`) |
| **2nd-serve points won %** | points won on 2nd serve | 2nd-serve points (incl. DF) | Label: "points after a 1st-serve fault" | OBSERVED structure, INFERRED label |
| 2nd serve in % | 2nd-serve points − DF | 2nd-serve points | | INFERRED |
| Aces | serves in, untouched by receiver | — | 1st or 2nd serve; Ace% = aces / SP | OBSERVED (LTA); denominator INFERRED |
| Unreturned serves | aces + service winners + return errors | SP | MCP "Unret%" | OBSERVED (Tennis Abstract) |
| Double faults | points lost to two faults | — | DF% = DF / SP (label if DF / 2nd-serve points is used) | OBSERVED (Rule 24a; LTA) |
| Service points won % | 1stWon + 2ndWon | SP | | INFERRED |
| Service games played | std games p served | — | **Exclude tie-breaks** | INFERRED; TA keeps TB serve stats separate (OBSERVED) |
| Hold % | service games won | service games played | | INFERRED |

### 6.2 Return and totals

| Stat | Numerator | Denominator | Notes |
|---|---|---|---|
| Return points | — | SP(opp) | |
| **Return points won %** | SP(opp) − SPW(opp) | SP(opp) | Split by opponent 1st serve (`1stIn(opp) − 1stWon(opp)` / `1stIn(opp)`) and 2nd serve |
| Return in play % | returns in play | return points excluding opponent DFs | MCP "RiP%" (OBSERVED) |
| **Total points won %** | points won **incl. penalty points awarded** | all points | Fixture 72/124 → **58%**. Invariants: TPW(A)+TPW(B)=total; TPW = SPW + RPW + penalties awarded |
| Dominance ratio (optional) | RPW% | 1 − SPW% | Formula UNVERIFIED from a primary page |

### 6.3 Break points

- **Break point:** a point in a **std game** where the **receiver wins the game by winning the point** (LTA,
  OBSERVED): receiver has ≥3 points and leads, or the No-Ad deciding point (simultaneously a server game point,
  INFERRED). Tie-break points are never break points.
- BP faced / saved / saved% (server); BP opportunities / converted / converted% (returner). OBSERVED (LTA, TA).
- **Invariants (test oracles, INFERRED):** `BPconverted(p) = breaks(p) = returnGamesWon(p)`;
  `BPfaced(p) − BPsaved(p) = timesBroken(p)`.

### 6.4 Point endings

- Exactly one end type per completed point (list in §4.1).
- Winner rule: ace, service winner, winner → hitter wins; forced/unforced error → hitter's opponent wins; double fault
  → receiver wins.
- Attribute each error to the player who hit it; show "induced forced errors" as a separate credit (MCP FH Wnr%
  precedent, OBSERVED).
- **Winners exclude aces by default** (MCP `isRallyWinner`, OBSERVED). Whether ATP/WTA/Slam "Winners" include aces is
  UNVERIFIED (JS-rendered pages); if a combined total is shown, label it.
- Forced vs unforced is a judgement (MCP: 1st-serve return errors usually forced, 2nd-serve return errors often
  unforced). Automatic labels read **"Error (unclassified)"** with `estimated` provenance until reviewed.
- Smashpoint and MatchTrack users repeatedly asked for **service winner** and **error direction** (long, wide, net)
  (raw/review-mining.md §7.2, §7.4). Store `errorDirection ∈ {net, long, wide, unknown}` as optional review detail.

### 6.5 Net points

MCP: share of points where the player comes to net, including serve-and-volley, including approaches answered by a
lob, excluding points ending in an approach-shot winner (OBSERVED). Net points won % = won / net points. Requires
court-position evidence → `manual` until a detector is validated.

### 6.6 Rally length

- Serve counts; final error does not. DF = 0; ace/missed return = 1; serve + 4 shots + error on the 6th = 5.
- Buckets on screen: **ATP 0–4 / 5–8 / 9+** (O'Shannessy, ATP 2024-11-17, OBSERVED). Keep MCP 1–3/4–6/7–9/10+ available
  for export. Store raw length per point.

### 6.7 Streaks and momentum

- Point streak and game streak (longest and current) across game and set boundaries; order-dependent.
- Momentum (INFERRED proposal): rolling share of points won over the last k = 10 points, or EWMA with α = 2/(k+1).
  The chart **prints its window and denominator**. Descriptive, not predictive. Importance-weighted variants need a
  win-probability model → `estimated`.

### 6.8 Doubles and practice

- Doubles: stats per team; serve stats also per server (INFERRED).
- Practice sessions have no score: serve practice shows in/out counts and placement, never "points won".

### 6.9 "Shots" on Match overview — decision required

| Metric | Definition | Use |
|---|---|---|
| `strokeCount` (**recommended for "Shots"**) | Every racket–ball contact in live play: the serve that started the rally, returns, groundstrokes, the final winner or error. Excludes faulted serves and replayed lets. DF = 0, ace = 1, missed return = 2 | Screen 9 "Shots", shots per hour |
| `rallyLength` | §6.6 convention | Buckets, averages, filters ("points of 5 shots or fewer") |

They differ by about one per error-ending point; the screen must say which it shows.

### 6.10 Cross-session aggregation

- **Pool numerators and denominators**; never average per-session percentages (INFERRED).
- Compare only within the same session type (a 2023 SwingVision review asked for this; raw/review-mining.md §8).
- Show sample size; hide trends below a minimum (e.g. 3 sessions and 100 points per comparison) for setup-vs-setup
  equipment comparisons (raw/equipment-stringing.md §11).

---

## 7. Rounding and display (OBSERVED, computed: Swift 6.3.3, macOS 26.6.2)

| Platform behaviour | Result for 0.125 |
|---|---|
| `NumberFormatter` default `.halfEven`, `.percent` (0 fraction digits by default) | "12%" |
| `0.125.formatted(.percent)` (plain FormatStyle) | "12.5%" (no integer rounding) |
| `0.125.formatted(.percent.precision(.fractionLength(0)))` | "12%" |
| `(12.5).rounded()` (Swift) | 13 |
| Java `DecimalFormat` default `HALF_EVEN` (Oracle docs) | 12 |
| Kotlin `Double.roundToInt()` (ties toward +∞) | 13 |
| Android `android.icu.text.DecimalFormat` default | UNVERIFIED (reference page does not state it; ICU convention is half-even) |

Rules (INFERRED):
1. `pct(n, d) = (200·n + d) div (2·d)` in integers (n ≥ 0, d > 0); format the integer with the locale's percent symbol.
   Never pass a fraction to a platform percent formatter. "Must use" is a design choice: it is the cross-platform
   oracle because integer maths has no binary floating-point tie artifacts.
2. `d = 0` → "—" (detail view "0/0"); never "0%".
3. Fraction one tap away ("28 / 40").
4. Deltas in **percentage points**, computed from the two **displayed** integers (67 − 63 = "+4 percentage points").
5. Composition rows (screen 11 Deep/Short/Out) may not sum to 100 after rounding; either say so or use largest-
   remainder for that display only.
6. Units convert data, never relabel it (CLAUDE-BUILD-PROMPT); store tension as entered (raw/equipment-stringing.md §4).

**Conformance test vectors:**

| n/d | Exact | `pct` (half-up) | Half-even |
|---|---|---|---|
| 72/124 | 58.065 | 58 | 58 |
| 40/60 | 66.667 | 67 | 67 |
| 28/40 | 70.000 | 70 | 70 |
| 116/124 | 93.548 | 94 | 94 |
| 1/8 | 12.5 | **13** | **12** |
| 5/8 | 62.5 | **63** | **62** |
| 3/8 | 37.5 | 38 | 38 |
| 0/0 | — | "—" | "—" |

Valid denominators that make screen 11's 62/24/14 exact under `pct`: 21 (13/5/3), 29 (18/7/4), 42 (26/10/6),
**50 (31/12/7)**, 58 (36/14/8). OBSERVED (computed).

---

## 8. The sample fixture: coherence constraints

Fixture (CLAUDE-BUILD-PROMPT.md): Jon beats Alex 6–4, 6–3; 54 min; 124 points, Jon wins 72; Jon 60 first-serve
attempts, 40 in, wins 28 of those; 386 shots; displays 58%, 67%, 70%.

### 8.1 Arithmetic (OBSERVED, computed)

72/124 = 58.06% → 58; 40/60 = 66.67% → 67; 28/40 = 70.00% → 70. None is a .5 case. Alex wins 52. 19 games, no
tie-break (format may be TB sets or advantage sets). 124/19 = 6.53 points per game. 386/124 = 3.11 shots per point —
plausible for club singles (elite means 3.9–4.1 strokes per rally, Pluim et al. 2023; junior girls 2.7,
Fernandez-Fernandez 2007); club baselines are thin, so "plausible, not validated" (UNVERIFIED for recreational).

### 8.2 First server decides the break algebra

Set 1 has 10 games, so the match's first server also serves game 1 of set 2 and serves 10 games to 9.

| Case | Jon's service games (pts/game) | Alex's (pts/game) | Jon breaks − Alex breaks | Last game |
|---|---|---|---|---|
| **A: Jon serves first (recommended)** | 10 (6.00) | 9 (7.11) | +1 in each set | Jon serves out |
| B: Alex serves first | 9 (6.67) | 10 (6.40) | +1 set 1, **+2** set 2 | Jon breaks to win |

Expected i.i.d. ad-game length: 6.75 at p = 0.50, 6.48 at 0.60, 5.83 at 0.70 (closed form, OBSERVED computed). Both
cases are within one standard error; Case A fits the story (stronger player has shorter service games).

### 8.3 Hard constraints C1–C14 and soft C15–C16

| ID | Constraint |
|---|---|
| C1 | Format stored explicitly: best of 3, ad games, TB at 6–6 (not triggered), lets on |
| C2 | Sets 6–4, 6–3 to Jon; match ends on point 124; **no observed point after it** |
| C3 | Set 1 is 5–4 before game 10 and Jon wins game 10; set 2 is 5–3 before game 9 and Jon wins game 9; no earlier closure |
| C4 | `firstServer` declared; every recorded server equals the derived server (no overrides) |
| C5 | Jon serves exactly 60 points, Alex 64 |
| C6 | Every game's final split ∈ {4–0, 4–1, 4–2, (k+2)–k, k≥3}; no 7-point games |
| C7 | Jon wins 72, Alex 52; no penalty points (or counted in TPW only) |
| C8 | Jon's serve: 60 attempts, 40 in, 28 won on 1st; 20 second-serve points with y won (incl. all DFs in the losses). Jon SPW = 28 + y; Jon RPW = 44 − y of 64 |
| C9 | Case A: (Jon breaks − Alex breaks) = +1 per set. Case B: +1, +2. Breaks = BP converted |
| C10 | Σ chosen "Shots" metric = 386; DF = 0, ace = 1, other points ≥ 2 (`strokeCount`) or ≥ 1 (rally length) |
| C11 | Exactly one end type per point, consistent with its winner |
| C12 | `matchEnd − firstServeStrike` = 3240 s; no overlapping points; no rest after game 1 of a set; gaps ≤ ITF maxima if rule compliance is claimed |
| C13 | Displayed values via `pct()` on integer counts |
| C14 | If the fixture drives screens 9 and 16: 116 points reviewed, 8 flagged (116 + 8 = 124; 116/124 → 94%) |
| C15 (soft, screens 6, 10) | Point 42 is set 1 game 8, pre-point games 4–3 Jon and points 30–15 Jon, Alex serving, 8 shots, `needsReview`, starts at 766 s (12:46) |
| C16 (soft, screen 12) | "Review 12 serves" and "104 mph · Estimated" belong to a serve-practice subset with `estimated` provenance; **never** derived from this match without speed evidence |

**Free parameters to pin with a fixed seed:** first server; y; Alex's serve split; aces and DFs per player; point
order within games (drives BP counts and streaks); end types; per-point shot counts; timestamps.

### 8.4 A verified construction (Case A; OBSERVED: generated, then checked by an independent fold)

```
G1(J):JJJJ  G2(A):JJAAAA  G3(J):JJJJ  G4(A):JAAJAA  G5(J):JJAJJ  G6(A):AAJJAJAA  G7(J):JJAJJ
G8(A):JAJAJAJJ  G9(J):JAJJAAAA  G10(A):JJJJ                                  -> set 1: 6-4
G11(J):JJAJJ  G12(A):AAJJAJAA  G13(J):JJAJJ  G14(A):JJAAJAJJ  G15(J):JJAAAJJJ  G16(A):JAJAAJAA
G17(J):AJAAJJAA  G18(A):JJAJAAJJ  G19(J):AAJJJAJJ                            -> set 2: 6-3
```

The fold reproduced: final [(6,4),(6,3)] at point 124; zero server mismatches; changeovers after points 4, 14, 25, 38,
54 | 63, 76, 92, 108; point 42 pre-point = set 1, games 4–3, points 2–1 (Jon 30–15), Alex serving, not a break point.

| | Jon | Alex |
|---|---|---|
| Service points | 60 | 64 |
| 1st in | 40 (**67%**) | 38 (59%) |
| 1st won | 28 (**70%**) | 21 (55%) |
| 2nd-serve points won (incl. DF) | 12/20 (60%) | 11/26 (42%) |
| Aces / DF | 4 / 3 | 2 / 5 |
| Service points won | 40/60 (67%) | 32/64 (50%) |
| Return points won | 32/64 (50%) | 20/60 (33%) |
| Total points won | 72/124 (**58%**) | 52/124 (42%) |
| BP faced / saved | 5 / 3 | 8 / 4 |
| BP converted | 4/8 | 2/5 |
| Longest point / game streak | 6 / 3 | 4 / 2 |

Σ strokeCount = 386 (3.113 per point); point 42 = 8 shots. Point 42 at 766 s and match end at 3240 s are feasible
with 60 s changeovers and a 120 s set break, but imply a **front-loaded pace** (14.3 s cycle for points 1–41, 25.5 s
after). With even pacing point 42 would start around 17:50–17:53 (the raw note reports both figures; the difference
is how changeover time is spread).

### 8.5 Other copy cross-checks (OBSERVED in screens.json, INFERRED analysis)

- "+4 percentage points" (67 vs prior 63) is consistent if the prior pooled fraction rounds to 63 (e.g. 38/60).
- Shot map 62/24/14: use n = 50 forehands → 31/12/7.
- "6h 42m since restring" (screen 18) and "6h 42m on court" (screens 3, 16) must be **computed** from sessions linked
  to the string job, never copied (raw/equipment-stringing.md §11).
- "Estimated space: 3.2 GB" (screen 4) ≈ 36 min at 90 MB/min; the 54-min match would be ≈ 4.9 GB. Compute, never
  hard-code (implementation-states.md).

---

## 9. Decisions required (owner: Jon / build lead)

1. **"Shots"**: `strokeCount` for display, rally length for buckets (recommended).
2. **First server in the fixture**: Case A, Jon serves first (recommended).
3. **Point 42 timestamp**: keep 12:46 with a front-loaded generated pace, move to ≈17:50, or treat the replay as a
   separate illustrative clip.
4. **Setup labels**: "Ad / No-Ad" + "Tie-break at 6–6 / Advantage set" instead of bare "Advantage".
5. **Policies**: penalty points count in total points only; tie-break games excluded from service games; winners
   exclude aces.
6. **Fast4 and tour-doubles presets**: ship only after confirming primary rule text (both UNVERIFIED).
7. **Licensing**: Match Charting Project data is CC BY-NC-SA 4.0 (non-commercial). JOVRA must not ship MCP data or
   benchmarks derived from it; using common definitions and notation ideas needs counsel confirmation (UNVERIFIED legal
   point).

---

## Sources

All accessed 2026-10-07. Primary rule documents were read by the tennis-rules researcher; this synthesis relies on
`raw/tennis-rules-stats.md` for their content.

| URL | What it supports |
|---|---|
| https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf | Rules 5–10, 14–27, 29, Appendix VI and VII: game, tie-break, set, match, toss, ends, service order, faults, lets, hindrance, correcting errors, rest maxima, alternative formats |
| https://www.itftennis.com/media/7224/2026-amendments-to-the-rules-of-tennis-and-beach-tennis.pdf | Rule 27 tie-break wrong-ends clarification; Rule 18 doubles position |
| https://www.usta.com/content/dam/usta/2026-pdfs/2026-friend-at-court.pdf | Score notation 7-6(x), 1-0(x)/[ ], Coman TB, short and pro sets, MTB standings, Comments 5.3/14.1/15.1/15.2, The Code §31–32, Point Penalty System, Tables 10 and 14 |
| https://www.itftennis.com/media/16908/2026-itf-masters-world-tennis-tour-regulations-final-december-2025.pdf | Time violations, penalty schedule, defaults |
| https://ausopen.com/articles/news/grand-slams-jointly-adopt-10-point-final-set-tiebreak | 2022-03-16 adoption of the 10-point final-set tie-break |
| https://ausopen.com/articles/news/guide-scoring-tennis | Tie-break notation variants; AO 2019 final-set TB |
| https://www.lta.org.uk/fan-zone/tennis-stats-explained/ | Definitions of ace, DF, serve percentages, break points, winners, forced/unforced errors, net points, total points won |
| https://github.com/JeffSackmann/tennis_MatchChartingProject | Rally-count convention, `serve_pts = first_in + second_in`, end codes, unknown codes, replayed-point deletion, CC BY-NC-SA 4.0 licence |
| https://tennisabstract.com/blog/?p=3716 and https://www.tennisabstract.com/blog/2019/08/17/match-charting-project-serve-stats-glossary/ | Rally buckets, Unret%, RiP% |
| https://www.tennisabstract.com/blog/2019/08/17/match-charting-project-tactics-stats-glossary/ | Net point definition |
| https://www.tennisabstract.com/blog/?p=3727 | BP saved/converted, TB serve stats, BLR, DR+ |
| https://www.atptour.com/en/news/brain-game-sinner-fritz-turin-final-2024 | ATP 0–4 / 5–8 / 9+ rally buckets |
| https://doi.org/10.1177/1747954121999593 | Rally length classes (Fitzpatrick et al. 2021) |
| https://doi.org/10.1007/s40279-022-01807-8 | Strokes per rally 4.1 / 3.9 (Pluim et al. 2023, via PubMed) |
| https://doi.org/10.1136/bjsm.2007.036210 | 2.7 strokes per rally, junior girls (via PubMed) |
| https://docs.oracle.com/javase/8/docs/api/java/text/DecimalFormat.html | Java DecimalFormat HALF_EVEN default |
| https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.math/round-to-int.html | Kotlin `roundToInt` tie behaviour |
| https://developer.android.com/reference/android/icu/text/DecimalFormat | Fetched page does not state the default rounding mode (Android ICU default UNVERIFIED) |
| https://en.wikipedia.org/wiki/Fast4_Tennis | Fast4 rules (secondary; UNVERIFIED) |
| /Users/IDC2.5/jv/docs/research/raw/tennis-rules-stats.md | All computed results (rounding runs, fixture construction and fold, game-length expectations) |
| /Users/IDC2.5/jv/docs/research/raw/community.md, raw/review-mining.md, raw/gap-finder.md, raw/equipment-stringing.md | Format-flexibility and correction demand; checkpoint scoring; service-winner/error-direction asks; equipment hour computation |
| /Users/IDC2.5/jv/design-reference/brief/screens.json, implementation-states.md; /Users/IDC2.5/jv/docs/handoff/CLAUDE-BUILD-PROMPT.md; /Users/IDC2.5/jv/docs/adr/0003-points-are-events-scores-are-derived.md | Fixture text, screen copy, percentage-point rule, event-sourcing decision |
