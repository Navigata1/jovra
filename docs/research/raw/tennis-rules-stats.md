# Tennis rules and stat definitions: JOVRA scoring-engine reference

Researcher notes, 2026-10-07. Scope: the rules a scoring state machine must implement, the stat definitions the app
displays, and a validation of the sample fixture in the brief. The prior research (`design-reference/brief/research.md`)
did not cover any of this, so most of what follows is new.

**Labels.**
- **OBSERVED**: I saw it in a cited source. The URL is in brackets or in `## Sources`.
- **OBSERVED (computed)**: I computed it in a scratch script from the stated inputs, and anyone can reproduce it. The
  scripts are not in the repo.
- **INFERRED**: my reasoning or a design recommendation.
- **UNVERIFIED**: I could not confirm it from a primary source.

**Editions used.** These are the editions in force on 2026-10-07.
- ITF *Rules of Tennis 2026* (English, 47 pp., PDF modified 2025-12-23), plus the ITF *2026 Amendments* sheet.
- USTA *Friend at Court 2026* (212 pp., PDF modified 2026-02-12).
- ITF Masters World Tennis Tour *Regulations 2026* (December 2025 final), used for the Code of Conduct and the penalty
  schedule.

The English ITF text prevails over its translations (OBSERVED, ITF Foreword). I paraphrase the rules below. Rule numbers
let a developer go back to the text.

---

## 0. What a builder needs to know first

1. **The score is a pure fold over a point log.** Who serves, from which side and at which end can all be derived from
   four things: the format, the result of the toss, the doubles order choices and the sequence of point winners
   (INFERRED, following from ITF Rules 5, 10, 14, 15 and 17).
   - In singles, the server of every *game* follows from the parity of the game's index in the match, counting a set
     tie-break as one game. It does **not** depend on who won earlier points. Only game *boundaries* depend on outcomes.
     This is why a correction can move later points into a different service game (§4.3).
2. **Corrections never mutate history.** Store the *observed facts* of each point and recompute the derived score.
   - Observed facts are the recorded server, side, serve number, winner, ending type and timestamps.
   - The ITF principle for correcting errors is that points already played stand (Rule 27, OBSERVED). The UI must
     therefore be able to say that the score players called on court differed from the rules-derived score (§4.3).
3. **There is one rounding function, and it is specified, not inherited.** Swift `NumberFormatter`, Swift `FormatStyle`
   percent and Java/Android `DecimalFormat` all default to **half-even**: 12.5% displays as "12%". Swift `rounded()` and
   Kotlin `roundToInt()` round half-up or toward +∞: 12.5 becomes 13. I observed the Swift behaviour by running it (§6).
   Compute integer percentages in the shared domain spec with `(200·n + d) div (2·d)`.
4. **Second-serve points won includes double faults in its denominator.** It is the share of points won after a first
   serve fault. The Match Charting Project data is built this way: `serve_pts = first_in + second_in`, with double
   faults inside `second_in` (OBSERVED, §5).
5. **Rally length has a de facto standard.** The serve counts as a shot and the final error does not. A double fault is
   therefore 0, and an ace or a missed return is 1 (OBSERVED: MCP data dictionary, Tennis Abstract, Fitzpatrick et al.
   2021).
   - The brief's "386 Shots" needs an explicit definition. I recommend `strokeCount` (racket contacts in live play), with
     rally length kept as a separate metric (§5.9).
6. **The sample fixture is arithmetically and structurally coherent.** I built a complete 124-point sequence that
   reproduces every number in it and checked it with an independent scoring fold (§7).
   - One soft tension: the replay copy puts Point 42 at 12:46. That point would sit near 17:50 if the pace were even. The
     timestamp is feasible but implies a front-loaded pace.
7. **Label collision.** The setup copy "Best of 3 · Advantage" (screens.json #4) means ad *game* scoring. In the ITF
   rules, "Advantage Set" means a set **without** a tie-break (Rule 6a). The UI needs separate labels: "Ad / No-Ad" for
   games and "Tie-break at 6–6 / Advantage set" for sets (INFERRED).

---

## 1. Scoring

### 1.1 Standard ("ad") game: ITF Rule 5a (OBSERVED)
- Points are called Love, 15, 30, 40, Game, with the **server's score called first**.
- At 3–3 the score is **Deuce**. The next point gives **Advantage** to its winner. If that player also wins the
  following point, they win the game; otherwise the score returns to deuce. After deuce a player needs two consecutive
  points.
- **Legal final point splits** (winner–loser): 4–0, 4–1, 4–2, then (k+2)–k for k ≥ 3. A game therefore has 4, 5, 6, 8, 10
  or more points. **An ad game never has exactly 7 points.** The fixture generator and the correction validator can both
  use this as a check (INFERRED, follows from the rule).
- Display mapping: 0, 1, 2, 3 points → 0/15/30/40. At ≥3–≥3, equal counts show "Deuce" and a one-point lead shows
  "Ad-[player]" (INFERRED).

### 1.2 No-Ad game: ITF Appendix VI (OBSERVED)
- At 3–3 (Deuce) a single **deciding point** is played, and its winner wins the game.
- **Singles:** the receiver chooses whether to receive in the right half or the left half.
- **Doubles:** the receiving team chooses the side. Its players **may not change positions** for the deciding point, so
  whoever is standing on the chosen side receives.
- **Mixed doubles:** the player of the **same gender as the server** receives, and positions still may not change.
- Game lengths are 4 to 7 points.
- Engine consequence (INFERRED): record `decidingPointSide` as an observed fact. It is a receiver choice, so the
  side-alternation formula cannot derive it.

### 1.3 Tie-break game: ITF Rule 5b (OBSERVED)
- Points are called Zero, 1, 2, 3 and so on. The first to **7 with a 2-point margin** wins the game **and** the set. The
  game continues without limit until that margin is reached.
- The set is recorded **7–6** because the tie-break counts as one game for its winner (OBSERVED: USTA set notation,
  §1.6).
- Serving order and ends are covered in §2.3.

### 1.4 Sets: ITF Rule 6 and Appendix VI, USTA I.E (OBSERVED unless marked)

| Set type | Win condition | Tie-break trigger | Recorded as | Source |
|---|---|---|---|---|
| Tie-break set | 6 games, margin 2 | 6–6 → 7-point TB | 6–x, 7–5, 7–6(x) | ITF Rule 6b |
| Advantage set | 6 games, margin 2, no TB | none (e.g. 12–10) | 6–x, 7–5, 8–6 … | ITF Rule 6a |
| Short set | 4 games, margin 2 | 4–4 → TB, or **3–3** at the sanctioning body's discretion | 4–2, 5–3, 5–4(x); 4–3(x) with the 3–3 variant | ITF App VI.1; USTA I.E.3 |
| Short-set TB (optional) | first to **5** points, **deciding point at 4–4** | n/a | 5–4(x) or 4–3(x) | ITF App VI.2. Serve order and count are set by the sanctioning body; ends change only after the first 4 points |
| Pro set (USTA) | **8 games**, margin 2 | 8–8 → 7-point TB (a 10-point TB may be announced instead) | 9–8(x) | USTA I.E.4 |
| Fast4 (Tennis Australia) | 4 games | 3–3 → TB to 5, sudden death at 4–4 | 4–x, 4–3(x) | **Secondary sources only.** Wikipedia summary. tennis.com.au returned 403. Also No-Ad and No-Let |

- **Fast4 is not a separate engine.** It equals the ITF Short Set with the 3–3 trigger, plus the Short-set TB, No-Ad and
  No-Let.
- The Fast4 match tie-break details (10 points, sudden death at 9–9, ends every 6) come only from Wikipedia and are
  **UNVERIFIED**.
- The Fast4 tie-break serve order ("2 points each, starting from the deuce side") is also **UNVERIFIED**. Make it a
  format parameter.

### 1.5 Match: ITF Rule 7 and Appendix VI (OBSERVED)
- **Best of 3** (first to 2 sets) or **best of 5** (first to 3).
- **Match tie-break in place of the deciding set:** at one set all (or two sets all in best of 5), a single tie-break
  game decides the match. It is first to **7** (App VI.3) or **10** (App VI.4), win by 2. USTA sanctioned events use the
  10-point version unless authorised otherwise (USTA I.E.1.b). During it:
  - the original order of service continues;
  - doubles teams may re-order servers and receivers (USTA Comments 14.1 and 15.2);
  - a 120-second set break precedes it;
  - no ball change takes place.
- **Final-set tie-break (10 points):** at one set all (or two sets all) **and 6–6 in the final set**, a 10-point
  tie-break (win by 2) decides the match. ITF App VI.5 now lists it as an approved alternative.
  - The four Grand Slams jointly adopted it on **2022-03-16**, starting at **Roland-Garros 2022**. It covers qualifying,
    men's and women's singles and doubles, wheelchair, and junior singles (OBSERVED, ausopen.com).
  - Earlier finals for historical imports: the AO used a 10-point TB at 6–6 from 2019; Wimbledon used a 7-point TB at
    12–12 in 2019–2021; the US Open used a 7-point TB at 6–6; Roland-Garros had no final-set TB (OBSERVED via
    secondary press coverage of the 2022 announcement, AO article).
- **Common presets.** These are INFERRED, except that the Grand Slam preset is OBSERVED.
  - Club or USTA default: best of 3 tie-break sets, ad scoring.
  - USTA "match TB in lieu of third set".
  - Grand Slam: best of 5 or best of 3, final-set 10-point TB at 6–6.
  - Pro set to 8.
  - Short sets.
  - Fast4.
  - ATP/WTA tour doubles (No-Ad with a 10-point match TB) is **UNVERIFIED**. I did not fetch a tour rulebook.

### 1.6 Recording conventions (OBSERVED unless marked)
- **Set tie-break:** write `7-6(x)` or `6-7(x)`, where x is the **loser's** tie-break points. `7-6(4)` means the
  tie-break ended 7–4, and `6-7(14)` means it ended 14–16 (USTA I.E.1.d).
  - Broadcasters also print the full tie-break score, for example `7-6(36-34)` or `7-6[22-20]` (AO scoring guide).
  - INFERRED: **store both tie-break point totals**. Rendering x alone needs the target (7 or 10): the winner's total
    is `max(target, x+2)`.
- **Match tie-break in lieu of a final set:** record `1-0(x)`, x being the loser's points, **or** put the tie-break score
  in brackets, `[10-8]` (USTA I.E.1.e).
  - For standings it counts as **one set and one game**, even if the players mistakenly played out a full set (USTA FAC
    Comment II.B-6).
- **Short sets:** 4–2, 5–3, 5–4(x) (USTA I.E.3). **Pro set:** 9–8(x) (USTA I.E.4).
- **Retirements, defaults and walkovers** (USTA draw-sheet codes, Table 10):

  | Situation | Code |
  |---|---|
  | Retirement | `Score + Ret [inj/ill/pc]` |
  | Default under the Point Penalty System | `Score + Def [pps]` |
  | Default for lateness on resumption | `Score + Def [late]` |
  | Pre-match default | `Def [ns/late/refsl/…]` |
  | Walkover | `Wo [inj/ill/pc/tae]` (no score) |
  | Double walkover | `Wo/Wo` |
  | Incomplete, abandoned or cancelled | `Incomplete` / `Abandoned` / `Cancelled`. Abandoned and cancelled matches have **no winner** |

  - INFERRED display: `6–4 3–1 ret.` and `w/o`.

---

## 2. Serving order, sides and ends

### 2.1 Toss and first server: Rule 9 (OBSERVED)
- The toss winner chooses one of three things: serve or receive, an end, or to make the opponent choose first. The
  opponent then takes the remaining choice.
- Store `firstServer` and `startingEnd` as observed match-setup facts. The engine cannot derive them.

### 2.2 Standard games (OBSERVED: Rules 14, 17, 20)
- Service alternates **every game**, across sets as well (Rule 14).
- In every standard game the first point is served from the **right half** (the deuce court), and later points
  alternate halves (Rule 17).
- The second serve comes from the same half as the faulted first serve (Rule 20).
- **Formulas** (INFERRED from the rules; `j` = 1-based index of the point within the game, counting only completed
  points):
  - `side(j) = right if j is odd else left`. The No-Ad deciding point is the exception: its side is the receiver's
    choice.
  - Singles server of match game `g` (0-based, set tie-breaks counted as games):
    `server(g) = firstServer if g is even else opponent`.
  - Rule 5b's instruction that the first server of a tie-break receives first in the next set is exactly what this
    parity rule produces. The tie-break is one game served "by" the player whose turn it was (INFERRED equivalence).

### 2.3 Tie-break game (OBSERVED: Rules 5b, 10, 17; USTA Comment 5.3; App VI)
- **Server.** The player whose turn it is serves point 1. The opponent serves points 2–3, then serving alternates in
  blocks of two.
  - Formula (INFERRED, `n` = 1-based tie-break point): `server(n) = A if floor(n/2) is even else B`, so points
    1:A, 2–3:B, 4–5:A, 6–7:B.
  - In **doubles** the four-player rotation continues in the same order as the set: `server(n) = rotation[(start +
    floor(n/2)) mod 4]`.
- **Side.** Point 1 is served from the right, and then the side alternates **every point**:
  `side(n) = right if n is odd else left`. Each new server therefore starts from the left (ad) side.
- **Ends.** Players change ends **after every 6 points** (6, 12, 18…) and at the end of the tie-break. There is no rest
  for these changes (Rule 29a).
  - The **Coman** alternative changes ends after point 1 and then after every 4 points (5, 9, 13…). ITF App VI lists it
    and USTA I.E.1.c allows it.
  - The Short-set TB changes ends **only after the first 4 points** (App VI.2).
- **Next set.** The first server of the tie-break **receives** in the first game of the next set (Rule 5b).
- **Match tie-break.** The original order of service continues, and ends change every 6 points (App VI note; USTA
  Comment 5.3).

### 2.4 Doubles (OBSERVED: Rules 14, 15; USTA Comments 14.1, 15.1, 15.2)
- **Serving.** At the start of **each set** the team serving first decides which partner serves game 1. Before game 2
  the other team decides its server.
  - Rotation for the set: `[s1, s2, partner(s1), partner(s2)]`, repeating.
  - Teams may change their order at the start of every set, and of a match tie-break.
- **Receiving.** Before the first game it receives in a set, each team decides who receives the first point. That
  player receives from the right (deuce) side. Partners alternate every point for the whole set.
  - INFERRED: model this as a fixed `deuceReceiver` / `adReceiver` per team per set. In a tie-break the receiver is
    whoever covers the side served to.
  - USTA Comment 15.1: both players may *stand* on one side, but the server is entitled to know who will receive.
- **Change of ends** follows the same rules as singles.

### 2.5 Change of ends and breaks (OBSERVED: Rules 10, 29a)
- **The rule:** change ends after the 1st, 3rd and every later odd game *of each set*. Also change at the end of a set
  when its total number of games is odd. When the total is even, the change happens after game 1 of the next set.
- **One-line implementation** (INFERRED equivalence): change ends after every completed game whose **index within its
  set is odd**, where a set tie-break is game 13. Add the in-tie-break changes from §2.3. This single condition
  reproduces every clause of Rule 10. The USTA note that ends change at the end of a tie-break is game 13 being odd.
- **Maximum rest times (Rule 29a):**
  - 25 s between points;
  - 90 s at a change of ends;
  - **no rest** after game 1 of a set or during a tie-break;
  - 120 s set break.
  - The time is measured from the end of one point to the strike of the next first serve. For recreational play these
    are ceilings, not targets.
- **Match start and end** (Rule 29): the match starts when the first serve is put in play and ends when the match is
  won.
  - INFERRED: define **match duration** on this basis. **Session/video duration** is a separate field because a
    recording may include warm-up.

---

## 3. Lets, faults and penalties: what the state machine must model

All rows are OBSERVED from the cited rule. The engine effects are INFERRED unless marked.

| Event | Rule | Score effect | Stat effect (recommended) |
|---|---|---|---|
| **Service let**: serve clips the net and is otherwise good, or touches the receiver after clipping the net, or receiver not ready | 22 | That serve is replayed. A let **does not cancel an earlier fault**: a let on the second serve stays a second serve | Not a serve attempt. Stored as an observed event, for evidence only |
| **No-Let mode** | App VI | A net-clipping serve is live. In some doubles formats either receiver may return it | Format flag `lets: let/noLet` |
| **Rally let**: hindrance by something outside the player's control, unintentional hindrance by the opponent, overrule judged to be a hindrance | 23, 26, App VII Case 7 | **Whole point replayed from the first serve**, even if the server had faulted (Rule 23 Case 1) | The replayed point's partial serves are voided. MCP charting also deletes replayed points |
| **Deliberate hindrance** by the opponent | 26 | Point to the hindered player | End type `hindrance` (or `penalty`); not a rally outcome |
| **Fault**: foot fault, wrong position, missed ball, ball hits a fixture, singles stick or net post, ball hits the server or partner | 16–19 | First fault → second serve from the same half. Second fault → **double fault**, point to the receiver | Each counts as a serve attempt; fault `type` is stored. **A foot fault is an ordinary fault** |
| **Serve hits the receiver** before bouncing | 24 Case 7 | Server wins the point, unless it is a let | INFERRED: classify as an unreturned serve (service winner), **not an ace**. The LTA defines an ace as untouched by the receiver |
| **Time violation** (code-of-conduct events) | ITF Masters Regs 2026 III.D | First violation: warning. Later violations: **server → a fault**, **receiver → a point penalty** | A server time violation is a fault with `cause=timeViolation`. INFERRED: it counts toward first-serve attempts and can produce a double fault |
| **Point penalty** | USTA IV.D.13–14 | Scored as though the penalised player played and **lost the next point**. If imposed between games or before the match, it applies to the **first point of the next game** | INFERRED: it occupies a point slot (so it advances side and tie-break serve rotation) but counts in **neither** service nor return points. It does count in total points. MCP uses separate codes `P`/`Q` |
| **Game penalty** | USTA Table 14 | The opponent is awarded the game. **During a set tie-break the penalised player loses the set; during a match tie-break, the match** | Excluded from service-game counts (INFERRED) |
| **Penalty schedule** | ITF Masters III.Q; USTA PPS | ITF: 1st offence warning, 2nd point penalty, 3rd and later game penalty (the referee decides on default after the 3rd). USTA PPS uses **point, game, default** for listed delay offences | Make the schedule a per-format setting. Most recreational matches have no umpire, so this is logging rather than automation |
| **Retirement** | USTA Table 10 | Match ends; the opponent wins; score shown with `ret.` | Stats cover **completed points only**. INFERRED: a point interrupted by retirement is excluded |
| **Default** | USTA Table 10 | Match ends; the opponent wins; `Score + Def [...]` | Same as retirement |
| **Walkover** | USTA Table 10 | Winner, no score | Every denominator is 0, so every stat displays "—" |
| **Suspension** (rain, darkness) | App VII | On resumption the score and player positions stand | Keep the clock gap out of point durations |
| **Abandoned or cancelled** | USTA Table 10 | No winner | Keep the session; no result |
| **Served from the wrong half** | 27a | Fix once discovered; points stand; **a fault served before discovery stands** | Store the actual side; flag a `sideMismatch` |
| **Players at the wrong ends** | 27b (2026 amendment) | Fix once discovered; **a fault served before discovery does not stand**. The 2026 amendment extends this to tie-breaks | Void the open fault |
| **Served out of turn**, standard game | 27c | If discovered mid-game, the correct server takes over. If a game was completed, **the order stays as altered**. An opponent's fault before discovery does not stand (in doubles, a partner's out-of-turn fault stands) | INFERRED: the engine must accept a **recorded server override** that permanently shifts the rotation |
| **Served out of turn**, tie-break | 27d | If discovered after an even number of points, correct it immediately. After an odd number, the order stays as altered | Same mechanism |
| **Doubles receiving-order error** | 27e | Keeps until the end of the game, then reverts | `receiverOverride` scoped to the game |
| **Wrong set format started** | 27f–h | If only one point has been played, correct it. Otherwise continue: an advantage set becomes a TB set; a TB set becomes an advantage set to 8–8 and then a TB; a match-TB set becomes a short set to 3 (or a TB at 2–2) or continues as a TB set | INFERRED: the app is usually used after the fact, so allow a format edit with recompute and warn when it changes results |
| **Disputed score** (no officials) | The Code §31–32 | The server announces the game score before a game's first point and the point score before every later point. Disputes are settled in this order: count the agreed points and games and replay only the disputed ones; play from a mutually agreed score; spin or toss | INFERRED product rule: the app shows an **"as called on court"** score separately from the **rules-derived** score whenever they diverge (§4.3) |

**Charting precedent for unknowns (OBSERVED, MCP instructions).** When a point's details were not seen, MCP charters
record `S` (server won) or `R` (returner won), and use unknown codes for direction or shot type.
- INFERRED: JOVRA needs an `outcome: unknown` state. Every later score is then shown as **provisional** until the point
  is reviewed, rather than guessed.

---

## 4. State-machine design notes (INFERRED, grounded in the rules above)

### 4.1 Event model
- **Observed facts (append-only).** Each one carries provenance (`manual`, `estimated`, `reviewed`, `validated`) and
  a source (`model vN` or `user`), as CLAUDE.md hard rules 1 and 4 require.
  - `MatchSetup`
  - `ServeAttempt`, with result in, fault(type) or let
  - `PointOutcome`, with winner and endType from: ace, serviceWinner, doubleFault, winner, forcedError, unforcedError,
    penalty, hindrance, unknown
  - `RallyLet`
  - `ServerOverride`, `ReceiverOverride`, `DecidingPointSide`
  - `Penalty`, `Retirement`, `Default`, `Suspension`
  - `Void(eventId)`, `Supersede(eventId, newFacts)`
- **Derived state (pure):** for every point, the pre-point score, server and receiver, side, serve number, the
  game-point, break-point, set-point and match-point flags, the ends, and whether the point is a changeover point.
  Also the per-set and per-match summaries and every stat in §5.
- A full recomputation of about 120–250 points is trivial, so **always refold from the first event**. Incremental
  folding adds risk for no benefit at this size.
- Set point and match point can be computed by **hypothetical folding**: apply "player X wins this point" and check
  whether the set or match closes. The same method generalises the break-point and game-point flags.

### 4.2 Undo
- Undo means `Void(lastEvent)`, followed by a refold.
- Undoing a game-winning point must reopen the game, revert the server and revert the change-of-ends flag. Because the
  state is derived, this happens automatically.
- Keep the original automatic result. A user edit `Supersede`s it and never deletes it (CLAUDE.md rule 4).

### 4.3 Correction cascade: the subtle part
Changing the winner of point *k* can do any of the following, and each needs its own UI conflict type.

1. **Game boundaries shift.** A game that ended at *k* no longer ends, or a game ends earlier. Later points are then
   attributed to different games.
   - In singles the rules-derived server of a game is fixed by its parity, but the **recorded** server of each later
     point (from video or a manual tag) is a fact.
   - A shift can make the recorded server differ from the derived one. Raise a **`serverMismatch`**.
2. **A tie-break appears or disappears.** For example, 6–5 becomes 6–6. The serve pattern changes from game blocks to
   1-2-2 blocks.
3. **The match ends earlier**, leaving points after the final point. Raise **`pointsAfterMatchEnd`**.
4. **The match no longer ends.** Raise **`matchIncomplete`**.
5. **Break-point, set-point and match-point flags and every stat change.** These recompute silently but must show a
   "recalculated" badge, per implementation-states.md.

**Resolution modes.**
- **Rules mode** (default) recomputes strictly from the rules.
- **As-played mode** follows the ITF principle that points played stand and the on-court order stays as altered once a
  game is completed (Rule 27c). Recorded server overrides are kept and later games are re-anchored to the observed
  server.

This addresses a dated competitor complaint. Reviews of SwingVision v11.5–v11.9 (2024-04 to 2026-09) describe:
- being unable to edit scores after a match;
- the edit-point screen having no control to switch the point winner;
- users wanting to keep or edit the score while watching afterwards.

(OBSERVED, App Store reviews RSS, paraphrased. These are user reports and may since have been fixed.)

---

## 5. Stat definitions

**Notation:** `SP(p)` = service points of player p. `opp` = the opponent. All counts come from observed and derived
events. "Std game" means a non-tie-break game.

### 5.1 Serve

| Stat | Numerator | Denominator | Notes / edge cases | Label |
|---|---|---|---|---|
| Service points `SP` | — | — | Points where p served and at least one serve was struck. **Excludes** replayed points (rally lets) and penalty-awarded points | INFERRED; MCP deletes replayed points (OBSERVED) |
| First-serve attempts | — | — | Equal to `SP`. A let on a first serve is not an attempt | INFERRED |
| **1st serve in %** | 1st serves in | 1st-serve attempts (= SP) | Fixture: Jon **40/60 → 67%** | OBSERVED (LTA: how often the first serve lands in) |
| **1st-serve points won %** | points won by the server when the 1st serve went in | 1st serves in | Fixture: **28/40 → 70%**. Aces on the 1st serve count as won | OBSERVED (LTA) |
| 2nd-serve points | — | — | `SP − 1stIn`. **Includes double faults** | OBSERVED (computed from MCP `charting-m-stats-Overview.csv`: `serve_pts = first_in + second_in` holds for sample rows, e.g. 48 + 32 = 80 with `dfs = 4` inside `second_in`) |
| **2nd-serve points won %** | points won by the server on the 2nd serve | 2nd-serve points (incl. DF) | The LTA wording ("after a player lands a second serve") is ambiguous. Use the MCP/ATP-style denominator and label it "points after a 1st-serve fault" | OBSERVED structure, INFERRED label |
| 2nd serve in % | 2nd-serve points − DF | 2nd-serve points | | INFERRED |
| **Aces** | count of serves that landed in and were **not touched** by the receiver | — | Possible on the 1st or 2nd serve. Ace% = aces / SP | OBSERVED (LTA definition); denominator INFERRED (MCP style) |
| Unreturned serves | aces + service winners (receiver touched but did not return in play) + return errors | SP | MCP "Unret%". MCP "unreturnables" means the receiver failed to get a full racket on the ball, failed to reach the net, or wildly missed | OBSERVED (Tennis Abstract serve glossary; MCP instructions) |
| **Double faults** | points lost by two consecutive faults | — | DF% = DF / SP. An alternative is DF / 2nd-serve points; label whichever is used | OBSERVED (ITF Rule 24a; LTA) |
| **Service points won %** | 1stWon + 2ndWon | SP | Fixture (my construction): Jon 40/60 | INFERRED composition |
| Service games played | std games p served | — | **Exclude tie-breaks.** Nobody "serves" a tie-break; Tennis Abstract keeps separate TB serve-point and return-point stats | INFERRED; TB SPW/RPW separation OBSERVED (TA glossary) |
| Hold % | service games won | service games played | | INFERRED |

### 5.2 Return and totals

| Stat | Numerator | Denominator | Notes | Label |
|---|---|---|---|---|
| Return points | — | `SP(opp)` | | INFERRED |
| **Return points won %** | `SP(opp) − SPW(opp)` | `SP(opp)` | Also split by opponent serve: on the opponent's 1st serve, `1stIn(opp) − 1stWon(opp)` over `1stIn(opp)`; on the 2nd, `2ndPts(opp) − 2ndWon(opp)` over `2ndPts(opp)` | INFERRED (follows from §5.1) |
| Return in play % | returns put in play | return points excluding the opponent's DFs | MCP "RiP%" | OBSERVED (TA return glossary) |
| **Total points won %** | points won, **including** penalty points awarded | all points | Fixture: **72/124 → 58%**. Invariant: TPW(A) + TPW(B) = total points, and TPW = SPW + RPW + penalties awarded | OBSERVED (LTA); invariant INFERRED |
| Dominance ratio (optional) | RPW% | 1 − SPW% | A Tennis Abstract convention; its glossary references it under "DR+" | Formula UNVERIFIED from a primary page |

### 5.3 Break points and pressure points
- **Break point.** A point in a **standard game** where the **receiver wins the game by winning this point** (OBSERVED,
  LTA definition). This happens when:
  - the receiver has ≥3 points and leads (40–0, 40–15, 40–30, or Ad-receiver); or
  - it is the No-Ad deciding point, which is simultaneously a game point for the server (INFERRED).
  - Tie-break points are never break points (INFERRED, §5.1).
- **BP faced** (server) = count of break points on p's serve. **BP saved** = those won by p. **BP saved %** =
  saved / faced (OBSERVED: LTA, TA glossary).
- **BP opportunities** (returner) = break points p had as receiver. **BP converted** = those p won. **BP converted %** =
  converted / opportunities (OBSERVED: TA glossary).
- **Invariants** (INFERRED; they make good test oracles):
  - `BP converted(p) = breaks(p) = return games won(p)`.
  - `BP faced(p) − BP saved(p) = times p was broken`.
  - Fixture construction: Jon 4/8 converted; Alex saved 4 of the 8 he faced; Jon broken 2 times (5 faced, 3 saved).
- Game, set and match points are computed by hypothetical fold (§4.1). TA also defines "BP games", "BreakBack%" and
  set-point and match-point conversion (OBSERVED, TA point-by-point glossary). These are optional later.

### 5.4 Point endings, winners and errors
- **Partition.** Every completed point has exactly one end type:
  - ace
  - service winner (unreturnable)
  - double fault
  - **winner** (a rally shot the opponent could not reach or touch; OBSERVED, LTA)
  - **forced error** (an error caused by opponent pressure or a difficult hitting position; OBSERVED, LTA)
  - **unforced error** (an error from the player's own mistake without significant pressure; OBSERVED, LTA)
  - penalty
  - hindrance
  - unknown
- **Point-winner rule:** ace, service winner and winner → the hitter wins. Forced or unforced error → the hitter's
  opponent wins. Double fault → the receiver wins.
- **Attribution** (INFERRED): count each error against the player who **hit** it. Show "induced forced errors" as a
  separate credit to the opponent, as MCP's FH Wnr% ("winners or induced forced errors") does.
- **Winners exclude aces by default.** MCP's `isRallyWinner` excludes aces (OBSERVED). Whether ATP/WTA or Grand Slam
  "Winners" lines include aces is **UNVERIFIED**, because those pages are JS-rendered. If a "winners incl. aces" total is
  shown, label it.
- **The forced/unforced split is a judgement.** The MCP guidance is that first-serve return errors are usually forced
  and second-serve return errors often unforced, with exceptions (OBSERVED). MCP's notation uses `*` winner, `#` forced,
  `@` unforced.
  - INFERRED: until a human reviews them, automatic labels should read **"Error (unclassified)"** with `estimated`
    provenance.

### 5.5 Net points
- **MCP definition (OBSERVED, TA tactics glossary):** the share of points in which the player comes to net, including
  serve-and-volley points. This includes approach shots answered by a lob, but **excludes points ending in an
  approach-shot winner**. Volleys, half-volleys and smashes are assumed to be hit at the net.
- **Net points won %** = net points won / net points.
- LTA wording: points won when a player comes into the net (OBSERVED).
- Detection needs court-position evidence. Label this stat `manual` until a validated detector exists (INFERRED).

### 5.6 Rally length (OBSERVED convention)
- **Rule:** the serve counts as a shot and the final error does not.
  - Double fault = 0. Ace or unreturned serve = 1.
  - Serve, four more shots, then an error on the attempted sixth = 5.
  - Sources: MCP `rallyCount`; TA rally glossary (2019-08-17).
- Fitzpatrick et al. (2021, Wimbledon 2015–17) use the same classes: 0 = double faults, 1 = aces and missed returns.
- **Buckets:**
  - ATP/Infosys "Brain Game": **0–4, 5–8, 9+**. Used in Craig O'Shannessy, ATP, 2024-11-17.
  - MCP/Tennis Abstract: **1–3, 4–6, 7–9, 10+**.
  - INFERRED: use the ATP buckets on screen because they are better known, and keep the raw length per point.

### 5.7 Streaks and momentum
- **Point streak:** the longest run of consecutive points won, crossing games and sets. Also track the current streak.
- **Game streak:** the same over games. Fixture construction: Jon 6 points and 3 games; Alex 4 points and 2 games. These
  depend on point order (OBSERVED, computed).
- **Momentum (proposal, INFERRED):** a rolling share of points won over the last *k* = 10 points, or an exponentially
  weighted mean with α = 2/(k+1). Plot it at every point index and **print the window and denominator**.
  - Momentum is descriptive, not predictive.
  - A later option is importance weighting, Tennis Abstract style. TA's BLR ratio weighs points won and lost by their
    importance (OBSERVED, TA glossary). It needs a point-win-probability model, which makes it `estimated`.

### 5.8 Doubles and practice
- Report doubles stats per team, with serve stats also per server (INFERRED).
- Practice sessions have no match score, so present serve stats as serve-practice counts (in/out, placement), never as
  "points won" (INFERRED).

### 5.9 "Shots" on the Match overview (decision needed)
`386 Shots` (screen 9) is undefined. Two candidates:
- **`strokeCount`** (recommended for display): every racket–ball contact in live play.
  - It **includes** the serve that put the ball in play, every return and groundstroke, and the final error or winner.
  - It **excludes** faulted serves (counted separately as serve attempts) and replayed lets.
  - Double fault = 0, ace = 1, missed return = 2.
- **`rallyLength`** (the convention in §5.6): used for buckets and averages.

These differ by about one shot per point that ends in an error, so the screen must say which one it shows. INFERRED;
§7 checks plausibility under both.

---

## 6. Rounding and display conventions

**Platform defaults: OBSERVED (computed), 2026-10-07, Swift 6.3.3 on macOS 26.6.2.**
- `NumberFormatter().roundingMode` defaults to `.halfEven` (raw value 4). With `.percent`, 0.125 formats as "12%".
- `0.125.formatted(.percent.precision(.fractionLength(0)))` also gives "12%" (half-even).
- `(12.5).rounded()` gives 13 (half away from zero).
- 0.145 shows as "14%" under every method, because 14.5 is stored as 14.4999…
- Oracle documents Java `DecimalFormat` as defaulting to `RoundingMode.HALF_EVEN` (OBSERVED).
- Kotlin documents `Double.roundToInt()` as rounding ties toward +∞ (OBSERVED).
- **Result: iOS and Android disagree unless the rule is pinned.**

**Recommendations** (INFERRED unless marked):
1. Every percentage is `pct(n, d) = (200·n + d) div (2·d)` in integer arithmetic. That is half-up, with no
   floating-point error. Format the resulting **integer** with the locale's percent symbol. Never let a formatter round a
   fraction.
2. `d = 0` displays as **"—"** with "0/0" available in the detail view, never "0%".
3. Always keep the fraction one tap away ("28 / 40"), as the reference screens do ("28 of 40 first-serve points won",
   "116 / 124 points").
4. **Never compute from rounded values.** Pool numerators and denominators across sessions for trends. Never average
   per-session percentages.
5. **Deltas** are in **percentage points**, as implementation-states.md requires: "+4 percentage points". To avoid a
   visible contradiction such as 66.5 → 67 and 63.4 → 63 with an exact delta of 3.1 rounding to 3, compute the shown
   delta from the two **displayed** integers, and show the exact value in the detail view.
6. **Composition rows** such as screen 11's Deep/Short/Out may not sum to 100 after rounding. Either accept that and say
   so, or use the largest-remainder method for that display only. Valid denominators for 62/24/14 (OBSERVED, computed):
   - n = 21 (13/5/3)
   - n = 29 (18/7/4)
   - n = 42 (26/10/6)
   - n = **50 (31/12/7)**, which gives the exact values
   - n = 58 (36/14/8)
7. **Test vectors** (OBSERVED, computed; "half-even" means a platform's default formatter rounding):

| n/d | Exact | `pct` (half-up) | Half-even |
|---|---|---|---|
| 72/124 | 58.065 | 58 | 58 |
| 40/60 | 66.667 | 67 | 67 |
| 28/40 | 70.0 | 70 | 70 |
| 116/124 | 93.548 | 94 | 94 |
| 1/8 | 12.5 | **13** | **12** |
| 5/8 | 62.5 | **63** | **62** |
| 3/8 | 37.5 | 38 | 38 |
| 0/0 | — | "—" | "—" |

---

## 7. Validating the sample fixture

The fixture: "Jon beats Alex 6–4, 6–3; 54 minutes; 124 points, Jon wins 72; Jon's 60 first-serve attempts with 40 in;
Jon wins 28 of those 40; 386 shots; displayed 58%, 67%, 70%."

The source is `docs/handoff/CLAUDE-BUILD-PROMPT.md`. The prompt itself says the fixture must be validated before it is
used as a test oracle.

### 7.1 Arithmetic (OBSERVED, computed)

| Display | Fraction | Exact | Half-up | Matches screen? |
|---|---|---|---|---|
| Points won | 72/124 | 58.0645% | **58%** | yes (screen 9 "58% Points won") |
| 1st serves in | 40/60 | 66.667% | **67%** | yes (screens 3, 9, 12, 16) |
| 1st-serve points won | 28/40 | 70.000% | **70%** | yes (screen 12; screen 15 "28 / 40") |

None of these is an exact .5 case, so they are robust to the half-up versus half-even choice. Alex wins 52 points.

### 7.2 Games and service split (OBSERVED, computed; INFERRED where marked)
- **Games:** 6+4+6+3 = **19**. No set reached 6–6, so there are no tie-breaks and the format can be either tie-break
  sets or advantage sets.
- **First server.** Set 1 has 10 games (even), so the player who served game 1 of the match also serves game 1 of set 2.
  That player serves match games 1, 3, …, 19: **10 service games against 9**.
- **Jon's service points** are 60, because each service point has exactly one first-serve attempt. Alex's are
  124 − 60 = **64**.

| Case | Jon's games (pts/game) | Alex's games (pts/game) | Break algebra (Jon breaks − Alex breaks) | Last game |
|---|---|---|---|---|
| A: Jon serves first | 10 (6.00) | 9 (7.11) | set 1: +1, set 2: +1 | Jon serves out the match |
| B: Alex serves first | 9 (6.67) | 10 (6.40) | set 1: +1, set 2: **+2** | Jon breaks to win the match |

- **Points per game:** 124/19 = **6.53**.
- **Expected game length** for an i.i.d. ad game (OBSERVED, computed from the closed form):
  - 6.75 when the server's point-win probability p = 0.50;
  - 6.48 at p = 0.60;
  - 6.30 at p = 0.633;
  - 5.83 at p = 0.70.
- **Both cases are plausible.** Case A's 7.11 points per game for Alex is above the i.i.d. mean of about 6.7. The
  standard deviation of game length is about 2.6–2.8 (simulated, 200k games at p = 0.47–0.6), so the standard error of
  a 9-game mean is about 0.9, and 7.11 is well inside one SE (OBSERVED, computed; INFERRED judgement).
- **Case A fits the story better.** The stronger player has the shorter service games (INFERRED).
- **The fixture must state the first server**, because the case changes the break count.

### 7.3 Shots per point (OBSERVED sources, INFERRED judgement)
- 386 / 124 = **3.11 shots per point**.
- According to PubMed, Pluim et al. 2023 (Sports Med meta-analysis) report mean **strokes per rally** of 4.1 [3.4–5.0]
  for international men and 3.9 [2.4–6.2] for international women.
  - Fernandez-Fernandez et al. 2007 report 2.7 ± 1.7 for elite junior girls.
  - Prieto-Lage et al. 2023 found that 65–77% of men's Grand Slam points ended within 1–4 shots, depending on surface.
- **3.11 is plausible for adult club singles under either definition in §5.9.** In my construction, `strokeCount`
  bucketed as 0 / 1 / 2–4 / 5–8 / 9+ gives 8 / 6 / 85 / 20 / 5 points.
- Club-level baseline data is thin. The value is plausible, not validated (UNVERIFIED for recreational players).

### 7.4 Duration (OBSERVED rules, INFERRED arithmetic)
- 54:00 = 3240 s, or 26.1 s per point gross.
- **Rest opportunities:**
  - changeovers **with rest** after set 1 games 3, 5, 7, 9 and set 2 games 3, 5, 7: 7 in total;
  - after game 1 of each set: changes without rest;
  - one set break.
- At ITF maxima (7 × 90 s + 120 s = 750 s) this leaves 2490 s, or 20.1 s per point for rally plus the between-point
  interval.
- With a more typical 60 s per changeover and a 120 s set break, the point cycle is **21.8 s**. Both are comfortably
  plausible.

### 7.5 Cross-checks against screens.json copy (OBSERVED in local file, INFERRED analysis)
- **Live capture and replay** show "REC 12:46", "Jon 4 30 / Alex 3 15", "Point 42 · 8 shots" and "12:46 / 54:00".
  - Point 42 at 4–3 and 30–15 **is reachable**: the first 7 games hold 38 points (5.43 per game), and point 42 is the 4th
    point of game 8 with the pre-point score Jon 30–15.
  - **Soft tension:** reaching point 42 by 12:46 means a 14.3 s point cycle for the first 41 points, then 25.5 s for the
    remaining 83. With even pacing, point 42 would start near **17:53**.
  - Options: (a) keep the copy and generate a front-loaded pace, which is feasible; (b) move the replay timestamp to
    about 17:50; (c) mark the replay as a separate illustrative clip.
- **Review completion "116 / 124 points"** (screen 16) plus **"Review 8 flagged points"** (screen 9) makes 124. This is
  consistent, and 116/124 displays as 94%.
- **"First serves in 67%, prior 63%, +4 percentage points"** (screen 16) is consistent if the prior period's pooled
  fraction rounds to 63. Example: 38/60 = 63.3%.
- **Shot map 62/24/14:** use a denominator from §6 item 6, for example 50 forehands split 31/12/7.

### 7.6 Constraints a generated event sequence must satisfy to reproduce the fixture exactly
These are machine-checkable. C1–C14 are hard constraints; C15–C16 are soft (screen copy).

1. **C1 Format:** best of 3, ad scoring, tie-break at 6–6 (never triggered), lets on. Store the format explicitly.
2. **C2 Result:** completed sets 6–4 and 6–3, both won by Jon. The match ends on the 124th point and **no observed
   point exists after it**.
3. **C3 Set closure:** set 1 is 5–4 before game 10 and Jon wins game 10. Set 2 is 5–3 before game 9 and Jon wins game 9.
   No set satisfies its win condition earlier.
4. **C4 Serving:** `firstServer` is declared. The server of match game g (0-based) is `firstServer` if g is even.
   Every point's recorded server equals the derived server (no overrides).
5. **C5 Service points:** Jon serves exactly 60 points and Alex 64. Equivalently:
   - Case A: Σ points in Jon's 10 service games = 60.
   - Case B: Σ points in Jon's 9 service games = 60.
6. **C6 Game legality:** each game's final split is in {4–0, 4–1, 4–2, (k+2)–k for k≥3}, and the winner first meets the
   win condition on that game's last point. There are no 7-point games.
7. **C7 Points:** Jon wins 72 of the 124 points and Alex 52. There are no penalty points (or, if any, they are
   counted consistently in TPW only).
8. **C8 Jon's serve:** 60 first-serve attempts, with lets excluded:
   - 40 first serves in, of which Jon wins 28 (aces included) and loses 12;
   - 20 second-serve points, of which Jon wins `y` and loses `20−y`, the losses including all of Jon's double faults.
   - Therefore Jon's service points won = 28 + y, and Jon's return points won = 44 − y out of 64.
9. **C9 Break algebra:**
   - Case A: (Jon breaks − Alex breaks) = +1 in each set.
   - Case B: +1 in set 1 and +2 in set 2.
   - Breaks = BP converted (§5.3).
10. **C10 Shots:** Σ `strokeCount` (or whichever metric is chosen in §5.9) over the 124 points = 386. Per point:
    - DF = 0 (`strokeCount`) or 0 (rally length);
    - ace = 1;
    - any other point ≥ 2 under `strokeCount` or ≥ 1 under rally length.
11. **C11 End-type partition:** every point has exactly one end type (§5.4), consistent with its winner.
12. **C12 Duration:** `matchEnd − firstServeStrike` = 3240 s. Points do not overlap. Gaps respect "no rest after game 1
    of a set". Changeover and set-break gaps are ≥ 0, and ≤ ITF maxima if the fixture claims rule compliance.
13. **C13 Rounding:** displayed values come from `pct()` on the integer counts (58, 67, 70).
14. **C14 Reviewed state:** 116 points reviewed and 8 flagged, if the fixture also drives screens 9 and 16.
15. **C15 (soft, screens 6 and 10):** point 42 is in set 1 game 8, with pre-point score games 4–3 Jon and points 30–15
    Jon. Point 42 has 8 shots, is `needsReview`, and starts at 766 s.
16. **C16 (soft, screen 12):** "Review 12 serves" and "104 mph · Estimated" belong to a serve-practice or Serve Lab
    subset with `estimated` provenance. They must not be derived from this match unless speed evidence exists.

**Free parameters the generator must pin, with a fixed seed:**
- first server;
- `y`;
- Alex's serve split;
- aces and double faults per player;
- point order inside each game, which determines the break-point counts and streaks;
- end types;
- per-point shot counts;
- timestamps.

### 7.7 A verified construction (OBSERVED, computed: generated, then checked by an independent scoring fold)
Case A, Jon serves first. Notation: `G#(server):` followed by point winners in order (J = Jon, A = Alex).

```
G1(J):JJJJ  G2(A):JJAAAA  G3(J):JJJJ  G4(A):JAAJAA  G5(J):JJAJJ  G6(A):AAJJAJAA  G7(J):JJAJJ
G8(A):JAJAJAJJ  G9(J):JAJJAAAA  G10(A):JJJJ                                    -> set 1: 6-4
G11(J):JJAJJ  G12(A):AAJJAJAA  G13(J):JJAJJ  G14(A):JJAAJAJJ  G15(J):JJAAAJJJ  G16(A):JAJAAJAA
G17(J):AJAAJJAA  G18(A):JJAJAAJJ  G19(J):AAJJJAJJ                              -> set 2: 6-3
```

**What the fold reproduced:**
- Final score [(6,4),(6,3)], match over at point 124.
- Zero server mismatches.
- Changeovers after points 4, 14, 25, 38, 54 | 63, 76, 92, 108.
- Point 42 pre-point state: set 1, games 4–3, points 2–1 (Jon 30–15), Alex serving, not a break point.

**Derived stat lines.** Alex's serve split, aces, double faults and shots are my chosen free parameters.

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
| Breaks (= BP converted) | 4 | 2 |
| Longest point / game streak | 6 / 3 | 4 / 2 |

- Σ `strokeCount` = **386** (mean 3.113). Point 42 = 8 shots.
- Timeline: point 42 at 766 s and match end at 3240 s are feasible with 60 s changeovers and a 120 s set break. The
  point cycle is 14.3 s before point 42 and 25.5 s after it (§7.5).

**Verdict.** The fixture is coherent. Before it becomes the test oracle, the build should:
- pin the first server;
- define "Shots";
- decide the Point 42 timestamp;
- commit a seeded generator together with the fold-based verifier.

---

## 8. Open questions for Jon / the build

1. **"Shots" (§5.9):** display `strokeCount` or rally length? My recommendation is `strokeCount` for "Shots" and rally
   length for buckets.
2. **First server in the fixture:** case A (Jon serves first) is recommended.
3. **Replay timestamp for Point 42:** keep 12:46 with a front-loaded pace, or move it to about 17:50?
4. **Setup labels:** use "Ad / No-Ad" plus "Tie-break at 6–6 / Advantage set" instead of the bare "Advantage".
5. **Policies to confirm:**
   - penalty points count in total points but not in service or return points;
   - tie-break games are excluded from service games;
   - winners exclude aces.
6. **Fast4 primary rules:** tennis.com.au blocked automated fetches (HTTP 403). Confirm the tie-break serve order and
   match-tie-break details by hand before shipping a Fast4 preset.
7. **ATP/WTA official stat glossaries** were not retrievable because the pages are JS-rendered. The serve and return
   definitions above rest on the LTA, MCP data structure, IPTC and Tennis Abstract.
8. **Licensing caution:** MCP data is **CC BY-NC-SA 4.0**, non-commercial only (OBSERVED, repo README).
   - JOVRA must not ship MCP data or benchmarks derived from it.
   - Using common definitions and notation ideas is a different matter, but have counsel confirm (UNVERIFIED legal
     point).
   - I read only the documentation and the CSV headers and structure, to confirm denominators.

---

## Sources
All accessed 2026-10-07.

- ITF, *Rules of Tennis 2026* (English PDF): https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf
  - Rules 5–10 (game, tie-break, set, match, toss, ends), 14–27 (service order, doubles, faults, lets, losing a point,
    hindrance, correcting errors), 29 (continuous play and rest maxima), Appendix VI (No-Ad incl. doubles and mixed,
    short sets, short-set TB, match TB 7 and 10, final-set TB 10, alternative ends change, No-Let), Appendix VII
    (officials, suspension, overrules).
- ITF, *2026 Amendments to the Rules of Tennis*:
  https://www.itftennis.com/media/7224/2026-amendments-to-the-rules-of-tennis-and-beach-tennis.pdf
  - Rule 18 Case 1 (doubles position) and the Rule 27 tie-break wrong-ends fault clarification.
- USTA, *Friend at Court 2026*: https://www.usta.com/content/dam/usta/2026-pdfs/2026-friend-at-court.pdf
  - 7-6(x) notation (I.E.1.d), match TB 1-0(x)/[ ] (I.E.1.e), Coman TB (I.E.1.c), short-set and pro-set recording
    (I.E.3–4), FAC Comment II.B-6 (MTB = one set and one game).
  - USTA Comments 5.3, 14.1, 15.1, 15.2.
  - The Code §31–32 (score announcing and dispute resolution).
  - Point Penalty System IV.D.13–14 and Table 14 (point and game penalties, TB and MTB consequences).
  - Table 10 (ret/def/w/o codes).
- ITF, *Masters World Tennis Tour Regulations 2026* (final, December 2025):
  https://www.itftennis.com/media/16908/2026-itf-masters-world-tennis-tour-regulations-final-december-2025.pdf
  - Code of Conduct III.D (time violations: warning, then server fault or receiver point penalty), III.Q (point penalty
    schedule), III.R (defaults).
- Australian Open, "Grand Slams jointly adopt 10-point final-set tiebreak" (2022-03-16):
  https://ausopen.com/articles/news/grand-slams-jointly-adopt-10-point-final-set-tiebreak
  - Date, scope and start event (Roland-Garros 2022) of the final-set 10-point TB.
- Wimbledon news (same announcement, AMP page; content truncated on fetch):
  https://www.wimbledon.com/amp/en_GB/news/articles/2022-03-16/grand_slam_tournaments_jointly_announce_10point_final_set_tiebreak_at_six_games_all.html
  - Corroborates the date.
- Australian Open, "A guide to scoring in tennis" (2024-12-19): https://ausopen.com/articles/news/guide-scoring-tennis
  - Full tie-break score notation variants; AO final-set 10-point TB from 2019.
- Secondary press on the 2022 announcement and prior Slam final-set rules:
  https://www.businesslive.co.za/bd/sport/other-sport/2022-03-16-all-four-grand-slams-trial-10-point-tiebreak-in-final/
  and https://prod.tennis.com/news/articles/all-grand-slams-to-use-10-point-tiebreaker-in-final-set
  - Historical final-set formats (secondary).
- LTA, "Tennis stats explained": https://www.lta.org.uk/fan-zone/tennis-stats-explained/
  - Definitions of ace, DF, 1st serve %, 1st/2nd serve points won, break point, BP saved/converted, winners,
    forced/unforced errors, net points won, total points won, average rally length.
- Match Charting Project repository (README, license, `data_dictionary.txt`, CSV headers, `MatchChart 0.3.2.xlsm`
  Instructions tab): https://github.com/JeffSackmann/tennis_MatchChartingProject
  - `rallyCount` convention; `serve_pts = first_in + second_in` structure; point-ending codes `* # @`; let `c`; penalty
    codes `P`/`Q`; unknown `S`/`R`; replayed-point deletion; forced/unforced guidance; CC BY-NC-SA 4.0. Last push
    2026-09-18.
- Tennis Abstract, "The Match Charting Project: Quick Start Guide" (2015-09-23):
  https://www.tennisabstract.com/blog/2015/09/23/the-match-charting-project-quick-start-guide/
  - Notation basics.
- Tennis Abstract, "MCP Rally Stats: Glossary" (2019-08-17): https://tennisabstract.com/blog/?p=3716
  - Rally length convention and 1–3/4–6/7–9/10+ buckets.
- Tennis Abstract, "MCP Serve Stats: Glossary" (2019-08-17):
  https://www.tennisabstract.com/blog/2019/08/17/match-charting-project-serve-stats-glossary/
  - Unret%, <=3 W%, RiP W%.
- Tennis Abstract, "MCP Tactics Stats: Glossary" (2019-08-17):
  https://www.tennisabstract.com/blog/2019/08/17/match-charting-project-tactics-stats-glossary/
  - Net point definition, Net W%, SnV.
- Tennis Abstract glossary index: https://tennisabstract.com/blog/category/glossaries
  - Return glossary items (RiP%, RetWnr%).
- Tennis Abstract, "Point-by-Point Stats: Glossary": https://www.tennisabstract.com/blog/?p=3727
  - BP saved/converted, GP/SP/MP conversion, TB SPW/RPW, BLR, DR+.
- Tennis Abstract, "Winners, Errors, and Misinformation" (2016-01-12):
  https://www.tennisabstract.com/blog/2016/01/12/winners-errors-and-misinformation/
  - Limits of official point-ending data; MCP rally length separates return errors from later errors.
- IPTC Sport tennis statistics vocabulary: https://cv.iptc.org/newscodes/sptenstat
  - Standard stat code names (used as a naming cross-check; its definitions are loose).
- ATP Tour, Craig O'Shannessy, "Brain Game: Sinner vs Fritz, Turin final" (2024-11-17):
  https://www.atptour.com/en/news/brain-game-sinner-fritz-turin-final-2024
  - ATP 0–4 / 5–8 / 9+ buckets; 74% of points in 0–4 in that match.
- Fitzpatrick, Stone, Choppin & Kelley (2021), *Int J Sports Sci Coach*, "Investigating the most important aspect of
  grass court tennis: short points", https://doi.org/10.1177/1747954121999593 (repository page
  https://shura.shu.ac.uk/28141)
  - Rally length classes: 0 = DF, 1 = ace or missed return.
- According to PubMed: Pluim et al. (2023), *Sports Med* 53(4):807–836, https://doi.org/10.1007/s40279-022-01807-8
  - Strokes per rally 4.1 (int'l men), 3.9 (int'l women); effective playing time about 18–20%.
- According to PubMed: Fernandez-Fernandez et al. (2007), *Br J Sports Med* 41(11):711–716,
  https://doi.org/10.1136/bjsm.2007.036210
  - 2.7 strokes per rally, junior female.
- According to PubMed: Prieto-Lage et al. (2023), *PLoS One* 18(9):e0286076, https://doi.org/10.1371/journal.pone.0286076
  - 65–77% of Grand Slam men's points end in 1–4 shots.
- Oracle, `java.text.DecimalFormat` API docs: https://docs.oracle.com/javase/8/docs/api/java/text/DecimalFormat.html
  - Default `RoundingMode.HALF_EVEN`.
- Kotlin stdlib, `roundToInt`: https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.math/round-to-int.html
  - Ties rounded toward positive infinity.
- Local run, Swift 6.3.3 / macOS 26.6.2 (scratch script, not committed)
  - `NumberFormatter` default `.halfEven`; FormatStyle percent half-even; `rounded()` half away from zero.
- Wikipedia, "Fast4 Tennis": https://en.wikipedia.org/wiki/Fast4_Tennis
  - Fast4 rules (secondary; Tennis Australia pages returned HTTP 403).
- App Store lookup API, SwingVision 989461317 (v11.9.67, released 2026-09-27, 4.71 from 4,928 ratings), SevenSix
  1505604446 (v4.0.2), Onform 1490334045 (v4.7.3): https://itunes.apple.com/lookup?id=989461317&country=us (and the
  other IDs)
  - SwingVision advertises tracking of rally length and automated scoring.
- App Store customer reviews RSS, SwingVision, pages 1–10 (490 reviews, 2016-10 to 2026-10):
  https://itunes.apple.com/us/rss/customerreviews/page=1/id=989461317/sortby=mostrecent/json
  - Dated user reports (2024–2026) of score-edit and point-winner-switch friction and requests for post-hoc scoring.
    Paraphrased.
- Local files: `docs/handoff/JON-ORIGINAL-PROMPT.md`, `docs/handoff/CLAUDE-BUILD-PROMPT.md` (fixture text),
  `design-reference/brief/screens.json` (screen copy: "Best of 3 · Advantage", Point 42, 12:46, 116/124, 62/24/14),
  `design-reference/brief/implementation-states.md` ("percentage points"), `design-reference/brief/research.md` (prior
  research baseline).
