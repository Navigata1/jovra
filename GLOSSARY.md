# JOVRA Tennis

The language of JOVRA Tennis: recording tennis on your own phone, finding the point that matters, trusting the
numbers, practising with purpose and owning your video. Use these terms in code, tests, tickets and copy; where a
term lists words to _Avoid_, do not use them for that concept.

## Language

### People and sides

**Player**:
A person who plays in sessions, with a name, handedness and backhand type. Exactly one player is *you*, the player
whose stats, trends and goals the library tracks; the person operating the app is the *user*, who need not be a player
(a parent in junior mode).
_Avoid_: Athlete, profile, account, user (for the player)

**Opponent**:
A player on the other side from you in a match.
_Avoid_: Rival, other player, enemy

**Partner**:
The player on your side in a doubles match. Someone you simply hit with in practice is another player in the session,
not a partner.
_Avoid_: Teammate, doubles partner, hitting partner

**Side**:
One of the two competing parties in a match: one player in singles, two in doubles. Points, games, sets and stats
belong to sides; serve stats also belong to the individual server.
_Avoid_: Team (in code), competitor, court side

### Sessions and media

**Session**:
One sitting of tennis kept in the library: its original, event log, marks, analysis results, review state and archive
state. A session exists from the moment recording starts or an import is saved.
_Avoid_: Match (a match is one session kind), video, recording, workout

**Session kind**:
What was played: Singles match, Doubles match, Serve practice or Stroke practice. Only match kinds have a match format,
a score and points won; editable after the session, with everything recomputed.
_Avoid_: Mode, session type, activity

**Session status**:
The four independent states of a session: original (on this iPhone, archive only, missing), analysis (not run,
running, failed, done), review (needs review, reviewed) and archive (none, in progress, verified backup). No state
implies another; failed analysis never hides the video.
_Avoid_: Processing state, sync state, one combined status

**Recording**:
The media timeline of a session: its segments in capture order and the gaps between them, on one session clock. A
recorded session can hold many segments; an imported one holds one.
_Avoid_: Video, capture, footage, take

**Segment**:
One continuous, independently playable media file within a recording. Every interruption ends a segment, and losing
one segment never loses the session.
_Avoid_: Chunk, part, fragment (a fragment is a container detail inside a segment)

**Gap**:
A stretch of session time for which the recording holds no media, with its start, end and cause (call, backgrounding,
heat, crash, pause). Gaps are shown, never silently closed up.
_Avoid_: Hole, missing part, skipped time (that is what rally-only playback hides)

**Original**:
The session's media exactly as captured or imported: every segment, untrimmed and never re-encoded. Clips, reels and
Space Saver copies derive from it; edits never touch it; only an explicit user action deletes it.
_Avoid_: Raw video, master, source file, full video

**Clip**:
A time range of a session's original, with pre-roll and post-roll, that can be played, saved or exported on its own.
A clip references the original and holds no media until exported.
_Avoid_: Snippet, cut, highlight

**Highlight reel**:
An ordered set of clips rendered into one video with the scoreboard state burned in; re-rendered after any correction.
_Avoid_: Montage, recap, highlights video

**Rally-only playback**:
Replay of only the points' time ranges, with the skipped time between them shown as tappable chips and the full
recording one tap away.
_Avoid_: Dead-time removal, auto-edit, condensed video

**Mark**:
A moment the user stamps on the session timeline, live with "Mark point" or during replay, optionally with a note. A
mark says something happened; it is not a point, but marks seed point boundaries and review.
_Avoid_: Bookmark, flag, tag, event

### Capture

**Framing**:
Placing and aiming the phone before recording so the court fills the on-screen guide. Framing is advice; it measures
nothing.
_Avoid_: Calibration, setup, alignment

**Court mode**:
The recording display with the camera preview off: a dark screen showing REC, the timer and "Saved through mm:ss", to
cut heat and battery drain. Recording continues unchanged.
_Avoid_: Screen-off mode, power saving, background recording (recording is always foreground)

**Heat ladder**:
The fixed order in which JOVRA sheds load as the phone heats: live helpers off, then court mode, then 30 fps, then a
cleanly closed segment if the system stops the camera. Each rung reached is logged in the session.
_Avoid_: Thermal throttling (that is the system's), heat mode

### Points and the event log

**Point**:
One contested unit of scoring in a match, from the first serve attempt until the ball is dead, that awards one point to
one side. A point replayed after a let is the same point; practice sessions have no points.
_Avoid_: Rally (the exchange inside a point), exchange

**Point event**:
The stored record of one point: its times, shots, end type, detected outcome and reviewed outcome. Point events are
appended, superseded or voided, never edited in place.
_Avoid_: Point record, score entry

**Event log**:
The ordered, append-only list of everything observed about a match: point events, serve attempts, lets, changeover
checkpoints, server overrides, voids and supersedes. Every score and stat is computed from it.
_Avoid_: Score history, match data, timeline

**Detected outcome**:
A point's winner as suggested automatically (by a capability or by checkpoint fill), stored with its capability,
version and confidence and kept even after the user decides otherwise. Always estimated and needs review in v1.
_Avoid_: AI result, auto score, prediction

**Reviewed outcome**:
A point's winner as the user decided it, tapped live, swiped in review or set by correction, including "unknown". Its
provenance is manual when entered without a suggestion and reviewed when it confirms or corrects one.
_Avoid_: User edit, manual outcome, corrected outcome, override

**Effective outcome**:
The outcome the score uses: the reviewed outcome when there is one, otherwise the detected outcome, otherwise unknown.
Always derived, never stored.
_Avoid_: Final outcome, actual winner, result

**End type**:
How a point ended: ace, service winner, double fault, winner, forced error, unforced error, penalty, hindrance or
unknown. Exactly one per point; winners exclude aces.
_Avoid_: Point type, finish, outcome (outcome means who won)

**Needs review**:
The state of a point, placement or value that rests on an estimate or uncertainty and awaits the user's decision.
Everything a capability suggests starts here.
_Avoid_: Flagged (in code), pending, unverified, low confidence

**Supersede**:
To replace the facts of an earlier event by appending a new event that refers to it. The superseded event stays in the
log, so the automatic result and the user's correction both survive.
_Avoid_: Edit, overwrite, update, delete

**Void**:
To cancel an earlier event by appending a void that refers to it; undo voids the last event.
_Avoid_: Delete, remove, rollback

**Changeover checkpoint**:
The game score the user enters at a change of ends, stored as an observed fact. Point winners between two checkpoints
are filled in only where one legal sequence fits (estimated until reviewed); contradictions are flagged.
_Avoid_: Checkpoint score, game tally, snapshot

### Scores and match formats

**Scoreboard state**:
The score before or after a given point: sets, games, points, server, receiver, end and court half, plus game, set,
match and break point flags. Computed from the event log, never stored.
_Avoid_: Score (as a stored value), current score, scoreline

**Provisional score**:
A scoreboard state that depends on at least one earlier point whose effective outcome is unknown or not yet reviewed.
It stays provisional until those points are reviewed; it is never guessed into certainty.
_Avoid_: Estimated score, approximate score, partial score

**Rules-derived score**:
The scoreboard state computed strictly by the rules of the match format from the event log; the default view.
_Avoid_: Correct score, official score

**As-called score**:
The score as the players called it on court, from live entry and server overrides. When a correction makes it differ
from the rules-derived score, both are shown, because points already played stand.
_Avoid_: Real score, actual score, live score

**Match format**:
The complete scoring rules of a match: number of sets, Ad or No-Ad games, set type and tie-break trigger, deciding set
or match tie-break, and lets on or off. Chosen from presets and editable after the match.
_Avoid_: Scoring, rules, mode, "Advantage" alone

**Ad / No-Ad**:
The game-scoring choice. Ad: from deuce a side needs two points in a row. No-Ad: at three points all a single deciding
point wins the game, and the receiver picks the court half.
_Avoid_: Advantage (alone), deuce / no-deuce, sudden death

**Tie-break**:
A game scored 1, 2, 3… that decides a set at its trigger score (usually 6–6): first to 7 by two, recorded as 7–6(x)
with the loser's points. It counts as one game and is never a service game.
_Avoid_: Tiebreaker, breaker, TB (in copy)

**Match tie-break**:
A tie-break, usually to 10 by two, played instead of a deciding set; it counts as one set.
_Avoid_: Super tie-break, champions tie-break, third-set tie-break

**Advantage set**:
A set with no tie-break, won by two clear games (8–6, 12–10). Unrelated to Ad games.
_Avoid_: Long set, "Advantage" alone, no-tie-break set

**Service game**:
A standard (non-tie-break) game, named for the player who serves all of it. Holds and breaks count service games only.
_Avoid_: Serve game, server's game (when it includes tie-breaks)

**Deuce court / Ad court**:
The right and left halves of the receiver's court; the first point of every standard game is served to the deuce court.
_Avoid_: Side (reserved for the competing party), forehand / backhand court, right / left

**End**:
One of the two halves of the court on either side of the net, from which a side plays; sides change ends after odd
games and every six tie-break points.
_Avoid_: Side, half

### Rallies and shots

**Rally**:
The continuous exchange of shots from the serve put in play (or the first feed in practice) until the ball is dead. A
point holds at most one rally; a double fault has none.
_Avoid_: Point, exchange

**Shot**:
One racket–ball contact in live play: the serve that starts the rally, returns, groundstrokes, volleys and the final
winner or error. Faulted serves and serves before a let are not shots; "Shots" on screen counts these.
_Avoid_: Stroke (a stroke type is the kind of swing), ball, contact (alone)

**Hit**:
A sound in the recording classified by audio hit detection as a probable racket contact. A hit is a shot candidate until
reviewed.
_Avoid_: Shot (until confirmed), impact, onset

**Rally length**:
The number of shots in a point by the statistics convention: the serve counts, the final error does not (double fault
0, ace 1, missed return 1). It differs from the point's shot count on error-ending points, so screens say which they
show.
_Avoid_: Shot count, strokes per rally, rally count

**Stroke type**:
The kind of swing that produced a shot: serve, forehand, backhand, volley, overhead or other. Set by the user in v1.
_Avoid_: Shot type, stroke (for the contact itself)

### Stats and trust

**Stat**:
A number computed from the event log by a named definition, carrying its numerator, denominator, provenance and the
points it came from. Recomputed on every change, never stored as truth.
_Avoid_: Metric, KPI, insight, score

**Denominator**:
The count a rate is taken over, always on screen or one tap away ("28 / 40"). A rate whose denominator is zero shows
"—", never 0%.
_Avoid_: Base, total, sample size (that is a trend's session and point count)

**Percentage points**:
The difference between two displayed percentages, computed from the two displayed whole numbers (67% vs 63% is
+4 percentage points).
_Avoid_: Percent (for a difference of rates), "+4%"

**Provenance**:
How a value came to be: Manual (entered by the user), Estimated (computed by a capability not validated for this
configuration), Reviewed (an estimate the user confirmed or corrected) or Validated (computed by a capability promoted by
a passing benchmark). Sample is not a provenance; it is a separate label on top of one.
_Avoid_: Source, confidence, accuracy, "AI"

**Capability**:
A named, versioned method that produces values, such as audio hit detection, rally segmentation, camera-moved
detection, the 2D pose estimate, the serve speed estimate or court calibration. Every produced value records its
capability and version.
_Avoid_: Feature, model, AI, detector (a detector is one part of a capability)

**Capability status**:
The registry's verdict on a capability: manual, estimated, validated, unsupported (will not ship, such as line calls)
or disabled (built but not yet through its gate). It decides whether and how the capability's values appear.
_Avoid_: Enabled flag, beta, experimental

**Gate**:
The pass thresholds a capability must meet on a benchmark before its status may rise.
_Avoid_: Target, bar, KPI

**Benchmark**:
A recorded run of a capability against footage with ground-truth labels, scored against its gate. Only a passing
benchmark on real footage promotes a capability; synthetic sample media can fail a capability but never validate it.
_Avoid_: Test (generic), evaluation, accuracy claim

**Benchmark binding**:
For one capability, the benchmark task, version and tolerance that measure its gate, and which task metric each gate
metric is (`spec/fixtures/media/benchmark-bindings.json`). A benchmark that names a capability must use its binding.
_Avoid_: Mapping, task config

**Confidence**:
A capability's own certainty for one value, stored and shown as a band. It is never presented as accuracy; low
confidence sends the value to needs review.
_Avoid_: Accuracy, probability, trust score

### Court geometry

**Court model**:
The tennis court in metres from ITF dimensions (doubles and singles sidelines, baselines, service lines, centre service
line and net), with its origin at the near-left doubles corner. Every placement and calibration refers to it.
_Avoid_: Court diagram (a drawing of the model), court template

**Calibration**:
The user-confirmed correspondence between a recording's image and the court model, made from the four doubles corners
and bound to one lens, format and zoom. It is stale from the moment the camera moved.
_Avoid_: Court lock, framing, setup

**Homography**:
The plane-to-plane mapping, derived from a calibration, between video pixels and ground positions on the court model.
Valid only for points on the ground (bounces, feet), never for a ball in the air.
_Avoid_: Transform, projection, perspective matrix

**Shot placement**:
Where a shot bounced, as a position on the court model, marked In, Out or Needs review and binned Deep, Mid or Short.
Entered by tapping in v1; never a line call.
_Avoid_: Bounce map, heat map, line call, landing spot

### Analysis surfaces

**Serve Lab**:
The surface for serves: serve stats split by deuce and ad court, serve placements, serve key moments and the serve
speed estimate.
_Avoid_: Serve analysis, serve tracker

**Serve speed estimate**:
The average ball speed from contact to bounce, computed from contact and bounce frames the user marks and a bounce
position tapped on a calibrated court, shown as "Estimated average speed, contact→bounce". Never a radar or peak speed.
_Avoid_: Serve speed, radar speed, fastest serve (unqualified)

**Stroke Lab**:
The surface for studying selected swings of one stroke type: key moments, a contact strip and an optional 2D pose
estimate, with "Review" statuses instead of scores.
_Avoid_: Swing analysis, technique score, AI coach

**Key moment**:
A named instant in a swing, set or confirmed by the user: Ready, Unit turn, Racket drop, Contact, Finish; for serves
Toss release, Trophy, Racket drop, Contact, Landing.
_Avoid_: Phase, checkpoint, keyframe

**2D pose estimate**:
Body joint positions in the image plane from on-device body-pose detection, drawn only above a confidence threshold and
labelled "2D pose estimate". It supports no biomechanics, 3D or injury claim.
_Avoid_: Skeleton, biomechanics, motion capture, 3D pose

**Comparison**:
A saved pairing of two of your own clips, aligned at a sync point, with its annotations and voice notes. It references
the clips and never copies video.
_Avoid_: Side-by-side, split view, compare project

**Sync point**:
The moment in each clip of a comparison, usually contact, at which the two are aligned; held as media time so clips of
different frame rates stay in step.
_Avoid_: Sync frame, alignment, offset

**Annotation**:
A drawn shape (line, arrow, circle, 2D angle or freehand) attached to a frame range of a clip.
_Avoid_: Drawing, markup, telestration

**Voice note**:
A short audio recording pinned to a frame or sync point of a clip or comparison.
_Avoid_: Voice-over (a narrated export), audio comment

### Practice and progress

**Practice plan**:
A short, editable list of drills suggested by fixed rules over your stats, each with its evidence link, labelled
"Suggested practice".
_Avoid_: Coaching plan, AI coach, programme, prescription

**Drill**:
A named practice activity with a duration, sets and repetitions, and an optional target on the court model.
_Avoid_: Exercise, workout, lesson

**Evidence link**:
The reference from a suggestion to the stat (with its denominator) and the clips that justify it, such as "28 / 40
first-serve points won" with "Watch evidence". A suggestion without one is not shown.
_Avoid_: Reason, insight, source

**Goal**:
A target you set on a stat over a progress window, such as first serves in at least 70% over 4 weeks.
_Avoid_: Target, objective, challenge

**Progress window**:
The span a trend covers: 4 weeks, 3 months or a year.
_Avoid_: Range, period, timeframe

**Comparable sessions**:
Sessions of the same session kind whose numerators and denominators are pooled for a trend. Percentages are never
averaged across sessions, and a trend below its minimum sample is not drawn.
_Avoid_: Similar sessions, all sessions, average

### Equipment

**Racket**:
One physical racket you own, told apart by its nickname, with an optional frame model and customisations.
_Avoid_: Frame (reserved for video frames), stick, racquet

**Frame model**:
The kind of racket as user-entered text: brand, model, variant, year, head size and string pattern. No catalogue and no
logos in v1.
_Avoid_: Racket model, frame (alone)

**String product**:
A string as sold, as user-entered text: brand, model, material, gauge label and nominal diameter.
_Avoid_: String (alone), string type

**String job**:
One restringing of one racket: date, mains and crosses (each a string product and a tension with the unit as entered),
method, who strung it and notes. "Log a restring" creates one.
_Avoid_: Restring (as a noun in code), stringing, string change

**Setup**:
A racket together with its current string job, as played in a session; each session records its setup. Configuring a
session before recording is *session setup*, which is a different thing.
_Avoid_: Gear, kit, loadout

**Court time since restring**:
The summed duration of sessions played with a racket since its current string job; logged, never predicted.
_Avoid_: String hours, string age, string life, tension loss

### Ownership and archive

**Own-your-footage contract**:
The promise that your recordings are never capped, locked, watermarked, advertised against or held behind an account,
and can always be saved out in full.
_Avoid_: Free tier, plan, terms

**Archive**:
Your own copy of a session's original and sidecar, held by an archive provider. Optional; never the database and never
where analysis runs.
_Avoid_: Cloud, sync, cloud storage

**Archive provider**:
The service that holds an archive; Google Drive is the only one in v1.
_Avoid_: Cloud, storage provider, account

**Archive job**:
One persisted unit of archive work for one file (queued, hashing, uploading, verifying, then backed up, failed, needs
reconnect or quota blocked) that survives the app being killed and resumes.
_Avoid_: Upload, task, sync item

**Verified backup**:
An archived file whose size and MD5 checksum reported by the provider equal the local file's, plus SHA-256 when the
provider reports one. Only a verified backup is shown as "Backed up" or allows removing the original from the phone.
_Avoid_: Uploaded, synced, "backed up" for anything unverified

**Sidecar**:
The versioned JSON document describing a session (players, format, event log, annotations, provenance), stored beside
the original in the archive and used for export and restore.
_Avoid_: Metadata file, manifest, JSON

**Space Saver copy**:
A rally-only copy of a session's original, cut without re-encoding, archived in place of or beside the full original
when space is short. It replaces the original only with explicit confirmation and a verified backup.
_Avoid_: Compressed copy, proxy, lite version

**Share pack**:
A private bundle of selected clips, notes and match data made for a coach, partner or opponent who does not use JOVRA.
_Avoid_: Share link, export (generic), coach upload

### Filming people

**Consent**:
The recorded status of agreement from the people filmed in a session: informed, written form attached, or not required.
Withdrawing it stops the recording.
_Avoid_: Permission (that is iOS camera or microphone access), release, waiver

**Junior mode**:
The mode for recording minors: child players kept local and private, consent required, exports without audio and no
posting.
_Avoid_: Parent mode, kids mode, family mode

### Sample and test content

**Sample data**:
Illustrative content, such as the Jon vs Alex sample match and the synthetic sample video, always visibly labelled
"Sample" and never pooled with your stats, trends or goals. Sample is a label on top of provenance, not a provenance.
_Avoid_: Demo data, mock data, fake data, placeholder

**Synthetic sample video**:
A rendered video of a perspective court, simple player figures, a ball on physically plausible paths and hit clicks,
labelled "Sample video (synthetic)", whose exact ground truth makes it a benchmark fixture as well as demo content.
_Avoid_: Demo video, test footage, real footage

**Fixture camera**:
A capture source used only where there is no camera (the Simulator), labelled "Simulator fixture camera", that streams a
fixture video through the real recording pipeline.
_Avoid_: Fake camera, mock camera, demo recording

## Studio

The language of JOVRA Studio, the optional premium layer: building a match from up to six phones, aligning their
recordings, turning them into story films, and linking films to lessons and progress. Decisions behind these terms are
in ADR-0014 to ADR-0023, with the room terms (Camera lobby, Camera slot, Join code) in ADR-0027. The list comes from
the Studio spec's "Domain language" (`docs/spec/studio-v1-spec.md`, Further Notes). Core terms above keep their meaning;
where a Studio term sits next to a core one, the definition says how they differ.

### Projects and cameras

**Studio project**:
The container for one Studio effort, such as a built match or a film from an old match: its sources, source manifest,
sync map, point-event revision, keepers, story plans, films and linked lessons. It is a local folder first and is
linked to the cloud only if the user opts in. A match project usually wraps one session plus its extra angles.
_Avoid_: Session (a session is one sitting of tennis), job, workspace, Studio session

**Camera role**:
The placement a phone fills in a Studio project: Primary baseline, Opposite baseline, or one of the four corners, all
outside the playing area. A camera role is about where the phone stands; what a person may see or do is their
project role.
_Avoid_: Position (alone), angle (the angle is the recorded view), camera slot (the lobby place a phone is invited
into)

**Project role**:
What a person may do in a Studio project: owner, camera uploader, coach/editor or viewer. It is held in database
rows, never in a token or UI flag. Only the owner can accept a quote or publish.
_Avoid_: Permission level, user type, camera role

**Primary angle**:
The source recorded from the Primary baseline. It is the one live analysis feed, it anchors the match clock, and it
supplies the primary audio bed by default. One angle is a complete project.
_Avoid_: Main camera, master angle, host camera (the host is the phone running the lobby, which may differ)

**Camera source**:
One angle's recording within a Studio project, recorded or imported for one camera role and listed in the source
manifest. Its media is a session's original, untouched; proxies are derived from it and never replace it.
_Avoid_: Feed, file, camera (alone), original (the original is the media; the camera source is its place in a project)

**Camera lobby**:
The screen and local room in which the host phone invites phones into camera slots, approves each one and checks that
every camera is ready before recording. It coordinates only: it never synchronizes the recordings (that is the sync
map's job), and capture never waits on it (ADR-0017, ADR-0027).
_Avoid_: Room (alone, in UI copy), session, pairing screen

**Camera slot**:
One place in a camera lobby that one invitation fills with one phone. A slot carries the camera role the phone will
fill and, in the room contract, a slot role (`primary` or `camera`) saying what it records. Neither is a grant: what a
participant may do (view, mark, score, control capture) is granted separately by the host (ADR-0027).
_Avoid_: Seat, position, camera role (where the phone stands), grant

**Join code**:
The single-use invitation to one camera slot, shown as a QR and as a short display code (such as "JVR-482"). It
expires within 10 minutes and is bound to that slot; the QR also pins the host's key. The display code is a lookup
label, never a secret. Joining still needs the host's approval after both phones show the same six-digit comparison
code (ADR-0027).
_Avoid_: Password, PIN, invite link, comparison code (the six-digit code both phones show at approval)

### Sources and synchronization

**Source manifest**:
The trusted record of every source in a Studio project, generated from the actual files: ID, SHA-256, size,
duration, codec, dimensions, rotation, colour/HDR, rational timebase, segments, audio availability and capture
hints. Filenames and labels never fill it. A cloud source counts as verified only after the server re-hashes it.
_Avoid_: File list, media list, inventory

**Match clock**:
The shared timeline of a Studio project: light time anchored to the primary angle's video clock, starting at the
earliest covered instant, stored in integer microseconds. Every source is mapped onto it.
_Avoid_: Session clock (one recording's clock), timecode, wall clock

**Sync map**:
The versioned mapping of each source's time onto the match clock. It holds piecewise maps with offset and drift, the
anchors with their residuals, coverage gaps, discontinuities and a review status. It is not a comparison's sync point.
In code and contracts it is `SyncMap` (`jovra.sync-map/1`).
_Avoid_: Sync point, alignment (alone), timecode sync

**Anchor**:
An instant identifiable in two or more sources and used to fit the sync map: a visible contact or bounce, a
net-centre clap or ball drop, or a manual marker. Audio anchors count only after the speed-of-sound correction for
each phone's distance.
_Avoid_: Sync point, marker (alone), cue

**Offset**:
How far a source's clock sits from the match clock at the start of a map piece: the constant term of its map.
_Avoid_: Delay, lag, latency

**Drift**:
The rate at which a device's clock gains or loses against the match clock, in parts per million. Each device has one
drift, shared across its segments. At 20 ppm an hour drifts 72 ms.
_Avoid_: Skew, slip, desync

**Residual**:
For one anchor, the difference between the match time the fitted map predicts and the time observed. Residuals and
their 95% band decide whether a map is auto-approved or needs review.
_Avoid_: Error (alone), accuracy, sync quality

**Coverage gap**:
A span of match time for which a source has no media, whether before it started, after it stopped or across a
segment gap. Maps never extend into one, and playback shows it rather than inventing continuity. A core gap belongs
to one recording; a coverage gap is per source on the match clock.
_Avoid_: Gap (unqualified, in multi-source code), dropout, missing angle

**Proxy**:
A derived, normalized copy of a source, kept beside the untouched original. An analysis proxy keeps the original
timestamps. A render proxy is constant frame rate, rotation-baked, SDR and zero-start, and carries an explicit table
from original PTS to proxy frame. A proxy is never treated as the original.
_Avoid_: Original, Space Saver copy, transcode, low-res copy

**Analysis proxy**:
A proxy made for alignment and observation that keeps the original's timestamps, so every time read from it is a time
in the original.
_Avoid_: Preview, render proxy

**Render proxy**:
A proxy made for cutting films: constant frame rate, rotation applied once, SDR and starting at zero, with a PTS table
back to the original.
_Avoid_: Export, analysis proxy, Space Saver copy

**PTS table**:
The hashed table, kept with a render proxy, from each original presentation timestamp to the proxy frame made from it.
It is how a frame cut from a proxy is traced back to the exact frame of the original.
_Avoid_: Timecode, frame index (alone), sync map (that maps sources onto the match clock)

### Story and edit

**Keeper**:
A chosen source window on the match clock, bound to the point events it shows and the reason it was chosen. The user
picks it, or the planner proposes it and the user reviews it. Story beats point at keepers. A keeper may come from a
core clip; the same point seen from two angles is still one point.
_Avoid_: Highlight, select, clip (when the match-clock window is meant)

**B-roll**:
Genuine recorded non-rally footage, such as arrival, rackets and strings, warm-up and people, catalogued with its
rights and with whether it depicts this match. Generated imagery is never B-roll.
_Avoid_: Filler, stock footage, cutaways (alone)

**Story profile**:
One of five versioned editing grammars for a film: Coach's Cut, Match Broadcast, Rally Pulse, Progress Story and Court
Memories. Each sets structure, pacing, allowed operations, audio, overlays and Reduce Motion behaviour.
_Avoid_: Template, mode, style, preset, storyline

**Story brief**:
The readable editorial proposal for one film: profile and version, intended feeling, audience, duration and aspect
targets, ordered beats with keeper IDs, audio policy, cue and metric references, and unresolved decisions. Its typed
form is the story plan. Neither is ever executed.
_Avoid_: Script, prompt, treatment (alone)

**Story plan**:
The typed, validated form of a story brief: beats made only of IDs and fixed choices, checked against the project
before anything is compiled. The planner proposes it, the user may change it, and code compiles it into an edit
decision list; it is never executed itself. The shipped contract keeps the name `jovra.story-brief/1`.
_Avoid_: Script, timeline, edit decision list (the compiled form)

**Observation**:
One source-grounded record about a moment in a camera source, such as a cue, a contact, an occlusion or a ball or body
position, with its source and match time, the capability or person that produced it, its provenance and confidence.
A rejected observation stays on record and is never shown as instruction.
_Avoid_: Insight, detection, analysis result, annotation (a drawn shape on a clip)

**Cue**:
A short instruction for the player, taken from an observation or a note. It counts as instruction only when it is
Manual or Reviewed: an Estimated cue must be confirmed first. Lessons keep cues, and Coach's Cut needs a reviewed one.
_Avoid_: Tip, advice, coaching point, key moment (a named instant in a swing)

**Clean alternate**:
The calm version of a film's edit: the same cuts, with dissolves turned into cuts, no shake and static titles. With
Reduce Motion on it is the default output and the effects version is opt-in.
_Avoid_: Lite version, accessible version (alone), no-effects export

**Edit decision list**:
The renderer-facing typed plan (EDL), compiled by code from a validated story plan. It holds exact rational source
windows bound to source hashes, output frame placement, allowlisted operations, audio routes and overlays that
reference stored records. It is bound to the manifest, sync, event and profile revisions.
_Avoid_: Edit spec, timeline, cut list, render script

**Project lock**:
The frozen inputs of one film run: project ID, source manifest revision and hash, point-event revision, story profile
and version, output preference, source and participant rights, access mode, quote authorization and brand tokens.
Every later artifact binds to it.
_Avoid_: Snapshot, config, approval (a lock does not approve anything)

**Planner**:
The component that proposes a story plan from bounded evidence. It is either the deterministic heuristic planner (on
the device, the default and the fallback) or a configurable model planner on the server. It never renders, spends or
publishes.
_Avoid_: AI editor, engine (alone), director, Astra or Opus (those are model choices)

**Renderer**:
The deterministic component that executes a validated EDL into picture and sound. This is either the on-device
AVFoundation renderer or the cloud FFmpeg renderer with Remotion overlays. Every renderer must pass the same
conformance fixtures.
_Avoid_: Exporter (alone), editor, engine

**Film**:
A story rendered from a validated edit decision list and passed by full verification, kept as film revisions. A
highlight reel is the core app's set of clips with the scoreboard burned in; a film follows a story profile and
records what it was built from.
_Avoid_: Highlight reel (the core feature), video (alone), movie, export

### Jobs, money and delivery

**Render job**:
One authorized unit of rendering for one EDL and output spec, on the device or in the cloud. It moves through
explicit states to ready or a terminal state, and is ready only after full-decode verification.
Job, unqualified in Studio, means a render job; the core's archive job and string job are different things.
_Avoid_: Task, export (alone), processing

**Stage**:
One named step of a render job with its own state and progress, shown to the player as Upload, Align angles, Build
film and Verify export. Any percentage belongs to one stage, and a stage's credits are consumed at most once, when an
attempt at it succeeds.
_Avoid_: Step (alone), phase, progress (alone)

**Quote**:
The server-computed preflight estimate for a cloud render job, made from the actual sources, story profile, output
spec, retention and current rates. It has an expiry and a cap (the maximum authorized cost). A quote shown in demo
says "Sample quote".
_Avoid_: Price, estimate (alone), invoice

**Spending limit**:
The player-facing name of a quote's cap: the most a cloud render job may use. A job that would pass it stops and asks;
it is never raised automatically, only by a new explicit entry.
_Avoid_: Budget (alone), maximum price, allowance

**Usage reservation**:
The idempotent hold, up to a quote's cap, placed before cloud work starts. It is keyed by project, plan revision and
output spec, consumed by actual usage and released on failure or cancellation. A retry under the same key never
charges twice. Reservation, unqualified, always means a usage reservation.
_Avoid_: Charge, payment, hold (alone), credit (that is the unit)

**Delivered artifact**:
A verified output of a render job: film file, thumbnail, chapters, genuine captions, source-linked edit manifest or
portable project bundle. It records its hashes and revision bindings and is delivered privately.
_Avoid_: Output, download, upload, post

**Film revision**:
One rendering of a film, bound to its point-event revision, sync revision, profile version, plan hash, renderer
version and result hash. Earlier revisions are kept as labelled history until deliberately deleted.
_Avoid_: Version (alone), draft (a draft is a preview revision), copy

**Stale film**:
A film revision whose bound point-event, sync, calibration or source revision is no longer current. It is labelled
stale and never silently re-rendered or edited.
_Avoid_: Outdated, old film, invalid film

### Lessons

**Lesson**:
A dated record that links notes from you or a coach, sessions, lesson clips, cues, drills, practice-checklist
progress and the next goal. Films can be attached to a lesson, and several lessons can make a Progress Story.
_Avoid_: Coaching session, class, workout

**Lesson clip**:
An exact clip linked to a lesson with its note or cue. Sharing a lesson clip shares that clip only, never the match
or its other sources.
_Avoid_: Lesson video, attachment, highlight

**Practice checklist**:
The items to do before the next lesson, such as drill repetitions and clips to review, each with a done state, entered
by the user or coach. A practice plan is different: it is suggested by rules over stats.
_Avoid_: Practice plan, homework, to-do list

**Focus line**:
A lesson's short line of what to concentrate on, such as "Find the rhythm". The progress journey shows it as the
lesson's caption; it is not the lesson's title.
_Avoid_: Lesson title, goal (the next goal is separate), slogan

**Drill target**:
The count a practice-checklist item aims for, in repetitions, clips or minutes, beside the count done so far. It is
not a drill's target on the court model.
_Avoid_: Goal, quota, court target

### Identity, environments and storage

**Demo profile**:
The offline, in-process identity behind "Use demo profile", which shows fictional Sample data. It has no token,
network, upload or charge, and no cloud API ever accepts it. Its content is Sample data.
_Avoid_: Demo account, test login, guest

**Tester identity**:
A real account in the isolated test backend, signed in by email code from an allow-list seeded through
configuration. No credential is committed, and it cannot reach live.
_Avoid_: Demo account, fake user, test password

**Live account**:
A real JOVRA cloud account in the live environment, created with Sign in with Apple or an email code. It exists only
after activation, it is never required for the core app, and only it can accept a real quote.
_Avoid_: Account (for the demo profile or a tester), login, subscription

**Cloud mode**:
Which environment the Studio cloud is running in, always shown: Local demo, Test or Connected (the live environment),
or unavailable with its reason. It is chosen by build configuration, never by a switch the user can flip (ADR-0014).
_Avoid_: Online/offline, signed in, server mode

**Storage provider**:
A user-owned storage service behind one adapter interface (Files/iCloud Drive, Google Drive, Box, Dropbox). It
reports a truthful capability status and serves archive, import or export. An archive provider is a storage provider
holding an archive. A storage provider is never the database, the analysis engine or cloud render staging.
_Avoid_: Cloud, sync, backend, integration (unless it is wired)

**Signing gateway**:
The Cloudflare Worker that authenticates every cloud request, re-checks membership and grants in Postgres, and issues
short-lived exact-object capabilities for R2 media. It is the only path to stored media.
_Avoid_: Proxy (reserved for media), CDN, API server, backend (alone)
