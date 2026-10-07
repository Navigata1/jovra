# JOVRA Tennis — iOS v1 product spec

Status: ready-for-agent · Date: 2026-10-07 · Platform: iOS (iPhone first, iPad review layouts) · Tagline: **See your game.**

Sources this spec synthesizes: `docs/handoff/JON-ORIGINAL-PROMPT.md` (founder intent), `docs/handoff/CLAUDE-BUILD-PROMPT.md`,
`design-reference/brief/*` (20 screens, exact copy in `screens.json`, auxiliary states), `docs/adr/0001`–`0006`,
`docs/research/*` (backlog IDs P0-xx / P1-xx are cited in brackets), and the lead decisions D1–D12 (listed in Further Notes).
Studio (references 21–40) has its own prompt and is not part of this spec.

## Problem Statement

Jon plays club tennis and wants to film his matches and practice on his own iPhone, find the exact point or swing that
matters, understand numbers he can trust, turn them into something to practise, and keep the video in storage he owns
(his Google Drive), not in somebody else's cloud.

The apps that do this today let players down in predictable ways (`docs/research/competitive-analysis.md` §5–6):

- **Recordings get lost.** Reliability is one of the two largest complaint groups in low-star reviews (≈37–44%): crashes,
  interrupted recordings with no playable video, heat shutdowns, uploads stuck for days, sessions stuck "analyzing".
- **The numbers are not trustworthy and are hard to fix.** AI accuracy complaints are rising (speed outliers, cut-off
  points, wrong winners), and correcting a missed point "takes as long as my own editor". Corrections do not always
  flow through to later scores, stats and exports.
- **Players do not own their footage.** Hour caps, ads on personal video, a 7-day lock on free tiers, lapsed-subscriber
  lockouts, forced logins and review-only-after-upload flows.
- **Review tools fight the user.** Scrubbers collide with system gestures, compare-sync is "hit or miss", drawing
  hijacks scrubbing, left-handers get right-handed stats, formats are rigid and cannot be changed after the match.
- **Nobody connects equipment to play.** No mainstream app links the racket and string job to the sessions played with it.
- **Accessibility is an afterthought.** The leading app does not declare VoiceOver support.

From Jon's side: he wants to record, replay, analyse and compare "how the swing or the serve" looks, back the sessions
up to his Google Drive, and get all the on-screen visuals and metrics, with anything he forgot filled in.

## Solution

JOVRA Tennis is a native SwiftUI app that puts reliable capture and honest review first:

- **Record without fear.** Capture writes short fragmented segments behind a write-ahead journal. An interruption,
  crash or heat shutdown costs seconds, never the session. Recording never waits for analysis, network, microphone or
  an account. The screen always says what is saved ("Saved through 41:12").
- **Score it right, fix it fast.** A rules engine derives every scoreboard, stat and export from stored point events.
  Live manual scoring, Mark point bookmarks, changeover checkpoints and a swipe-per-point Fast Point Review turn a
  match into a correct record in minutes. Any correction recomputes everything after it; the original automatic
  suggestion and the user's decision are kept separately.
- **Replay like a pro tool.** Frame-accurate three-tier scrubbing, slow motion, rally-only playback with visible
  gaps, synced two-recording comparison with drawing and voice notes, and clip, highlight and condensed-match exports
  with a burned-in score.
- **Honest analysis.** Every number carries its provenance (Manual, Estimated, Reviewed, Validated) and a denominator
  one tap away. v1 automatic analysis is limited to what can be checked: audio hit detection and rally segmentation
  that only *suggest* points for review, camera-moved detection, an on-demand 2D pose estimate, and a manual-assisted
  serve speed estimate with a stated method and range. Sample content is always labelled "Sample".
- **Your video, your choice.** Everything is free and local. No JOVRA account, no server, no ads, no caps, no
  tracking. Originals stay on the iPhone ("Only on this iPhone") until the player chooses to archive them, verified by
  size and checksum, to their own Google Drive with a `drive.file`-only connection.
- **Practise with purpose.** Evidence-linked practice suggestions, progress trends with pooled denominators, and a
  Racket Vault and String Journal that link equipment to the sessions played with it.
- **Built for everyone.** VoiceOver-first review, Dynamic Type, 44 pt targets, Reduce Motion, increased contrast and
  meaning never carried by colour alone.

## User Stories

Actors: **player** (Jon, the app's owner), **opponent** (Alex), **doubles partner**, **coach** (receives a Share Pack,
does not need the app), **parent** of a junior player. "Player" is the default actor. Story groups are for navigation;
numbering is continuous.

### First run, onboarding and profile (screens 1–2)

1. As a player, I want a welcome screen with the JOVRA mark, the headline "See your game." and "Every point. Every detail. Your vision.", so that I know what the app is for before I commit to anything.
2. As a player, I want a primary "Get started" button that takes me to a short profile setup, so that I can start without an account.
3. As a player, I want an optional "Continue with Apple" button, so that I can personalise my profile with my Apple ID name without creating a JOVRA account.
4. As a player, I want a cancelled or failed Apple sign-in to return me to the welcome screen with a plain message and the "Get started" path still available, so that sign-in problems never block me.
5. As a returning player who signs in with Apple again, I want JOVRA to recognise my stored Apple user identifier and keep my existing local profile, so that I do not set up twice.
6. As a returning player on a fresh install, I want to be offered "Restore from your Google Drive archive" after sign-in when no local sessions exist, so that I can get my history back from storage I own.
7. As a player, I want an understated "Explore a demo" option on the welcome screen, so that I can see a full match, replay and stats before recording anything.
8. As a player, I want onboarding to be three steps with a visible progress rail ("Step 2 of 3"), so that I know how long setup takes.
9. As a player, I want to enter my name and see my initial in a circular avatar, so that the app feels like mine.
10. As a player, I want to choose right- or left-handed and a one- or two-handed backhand, so that forehand/backhand stats, filters and diagrams are correct for me.
11. As a player, I want to choose a skill level (for example "Club player"), so that suggestions are pitched at my level.
12. As a player, I want to choose goals as selectable chips (for example "Serve consistency", "Match strategy"), so that the practice plan reflects what I care about.
13. As a player, I want onboarding to tell me "Change these anytime", so that I do not agonise over choices.
14. As a player, I want the third onboarding step to state the own-your-footage promise ("Your videos stay yours: no hour limits, no ads") and where my originals live, so that I understand JOVRA's storage model before I record.
15. As a player, I want onboarding to disclose that originals are excluded from iCloud device backup by default and that I can change it in Settings, so that a multi-gigabyte video never silently breaks my iCloud backup.
16. As a player, I want to edit my name, handedness, backhand, level and goals later from Profile, so that my profile stays accurate as my game changes.
17. As a player, I want onboarding never to ask for camera, microphone or Photos permission, so that I am only asked when the permission is actually needed.

### Demo and sample content

18. As a player exploring the demo, I want a sample "Jon vs Alex" match (6–4 6–3, 54 min, 124 points) with a coherent point-by-point record, so that every screen shows realistic, internally consistent data.
19. As a player exploring the demo, I want the sample match's video to be a synthetic rendering labelled "Sample video (synthetic)", so that I never mistake it for real footage or a real person.
20. As a player, I want every sample value, card and chart to carry a visible "Sample" badge, so that I never confuse demo numbers with my own.
21. As a player, I want sample sessions excluded from my real Home tiles, Progress trends, head-to-head records, practice plan and equipment hours, so that demo data never contaminates my statistics.
22. As a player, I want sample serve-practice and forehand sessions alongside the sample match, so that the library, Serve Lab and Stroke Lab have something to show in the demo.
23. As a player, I want the sample serve tile to read as an illustrative estimate clearly marked "Sample", so that the reference "104 mph" is never presented as a measurement of me.
24. As a player, I want the demo's processing and archive screens to label their states "Demo processing state" and "Sample state — nothing is uploaded", so that demo progress bars are never mistaken for real uploads.
25. As a player, I want to remove all sample content from Settings with one confirmation, so that my library holds only my own sessions.
26. As a player, I want to re-open the demo later from Settings or Help, so that I can show a friend what JOVRA does.
27. As a player, I want sample sessions to be fully interactive (replay, correction, export), so that I can learn the tools on safe data without affecting my own sessions.
28. As a player, I want edits I make to sample sessions to be resettable, so that the demo can be restored to its original state.

### Home (screen 3)

29. As a player, I want Home to greet me by name ("Good morning, Jon.") with the subtitle "Your game, in focus.", so that the app opens on my game.
30. As a player, I want a "Ready for your next session?" card with a "Record a session" button, so that recording is one tap from launch.
31. As a player, I want three stat tiles (sessions, time on court, first serves in) computed from my stored sessions, so that the dashboard reflects real data.
32. As a player, I want the first-serve tile to pool numerators and denominators across sessions and show its fraction one tap away, so that a small session does not distort the figure.
33. As a player, I want a "Latest session" card (players, score, duration, type, court thumbnail) that opens the session, so that I can get straight back to my last match.
34. As a player, I want a "This week" compact chart of first serves in, annotated with the change in percentage points ("+4 percentage points"), so that I can see the trend without misleading percent-of-percent changes.
35. As a new player with no sessions, I want Home to show an inviting empty state instead of zero-filled tiles, so that I am not shown meaningless numbers.
36. As a player, I want Home tiles to show "—" when a denominator is zero, so that I never see a fake "0%".
37. As a player, I want Home to surface the next useful action (finish reviewing a match, back up a local-only session, resume an interrupted recording), so that nothing important is forgotten.

### Session setup (screen 4)

38. As a player, I want to choose a session mode — "Singles match", "Doubles match", "Serve practice" or "Stroke practice" — so that scoring and analysis fit what I am doing.
39. As a player, I want a players row ("Jon · Alex") that opens a player editor, so that I can name my opponent or pick a previous one.
40. As a player, I want to record my opponent's handedness and backhand type, so that their strokes and stats are labelled correctly too.
41. As a player, I want a scoring row (for example "Best of 3 · Ad · Tie-break at 6–6"), so that the scoreboard follows the format we are actually playing.
42. As a player, I want format presets — club best of 3, match tie-break in lieu of a third set, No-Ad with match tie-break, best of 5, pro set to 8, short sets, standalone 7- and 10-point tie-breaks and a free-count practice set — so that I can play the formats people really play.
43. As a player, I want separate, unambiguous labels for game scoring ("Ad / No-Ad") and set scoring ("Tie-break at 6–6 / Advantage set"), so that "Advantage" never means two different things.
44. As a player, I want to record who serves first and which end we start at, so that the engine derives the server and change of ends correctly.
45. As a player in a No-Ad game, I want to record which side the receiver chose for the deciding point, so that the side shown is what actually happened.
46. As a doubles player, I want to set each team's players, the serving order and who receives in the deuce and ad courts for each set, so that server rotation and receiving sides are correct.
47. As a doubles partner, I want to be named on the team, so that team stats and shared clips include me.
48. As a player, I want a gear row that picks the racket and string job I am using (for example "Head Prestige · Hyper-G / Ghost Wire"), so that the session is linked to my setup.
49. As a player, I want a camera preset row that offers only resolutions and frame rates my camera actually supports (for example "1080p · 60 fps"), so that I never choose a setting that will silently fail.
50. As a player, I want an estimated storage need for the planned session computed from the preset's bitrate and my free space, shown as a range, so that I know before the first serve whether the phone has room.
51. As a player, I want to choose a capture purpose (match from behind the baseline, or side-on technique), so that framing guidance and Stroke Lab tools fit the footage.
52. As a player, I want to choose whether the microphone records audio, with the consequence stated inline ("Off: rally detection unavailable; video still records"), so that I make an informed choice.
53. As a player, I want a consent row (everyone informed / written consent attached / not required), so that I record people respectfully.
54. As a player, I want a "Check camera position" button that takes me to framing, so that setup flows straight into calibration.
55. As a player, I want the last setup remembered as the default for the next session, so that a regular weekly match takes seconds to set up.

### Framing and calibration (screen 5)

56. As a player, I want camera permission requested only when I enter framing, with a short explanation first, so that I understand why it is needed.
57. As a player who denied camera access, I want an explanation and an "Open iOS Settings" link instead of a dead screen, so that I can fix it myself.
58. As a player, I want a near-full-height camera preview with the header "Frame your court" and a perspective court guide, so that I can line up the court quickly.
59. As a player, I want a checklist — "Court visible", "Lighting good", "Storage ready" (plus battery and heat) — that updates live, so that I know the setup is sane.
60. As a player, I want specific instructions that say what to move ("raise the phone about 30 cm", "rotate left"), so that I can fix framing without guessing.
61. As a player, I want "All four corners visible" confirmed with a check and the hint "Keep the phone steady and the net centered.", so that I know when framing is good enough.
62. As a player, I want tripod and fence placement profiles that tell me what each placement can deliver, so that I choose a mount knowingly.
63. As a player, I want to tap the four court corners (with a magnifier loupe) to calibrate, so that court-based features such as placement and serve speed work.
64. As a player, I want calibration to be optional before recording and possible later on the recorded footage, so that framing never delays the first serve.
65. As a player, I want a suggested snapped corner when my tap is near a court-line intersection, which I can accept or ignore, so that calibration is quicker without taking control away from me.
66. As a player, I want calibration checked by projecting the lines I did not tap and telling me when the fit is poor, so that a bad calibration is caught before it produces bad numbers.
67. As a player, I want clear warnings for unclear corners, an unsuitable angle, low light and low disk space, so that I can fix each problem before recording.
68. As a player, I want the preset pill (for example "1080p · 60 fps") visible in the preview, so that I can confirm the format at a glance.
69. As a player, I want framing and capture to work in landscape with the controls the right way up, so that a phone on its side on a fence is usable.
70. As a player, I want the ultra-wide lens chosen automatically when the full court needs it, with focus and exposure locked after framing, so that the camera does not hunt or switch lenses mid-match.
71. As a player using the iOS Simulator (or a developer testing), I want a clearly labelled "Simulator fixture camera" that streams a fixture video through the same recording pipeline, so that the whole capture flow can be exercised without a camera.
72. As a player, I want a "Start recording" button on the framing sheet, so that I go straight from framing to recording.

### Recording (screen 6)

73. As a player, I want a persistent red REC indicator and timer ("REC 12:46"), so that I know from the baseline that the phone is recording.
74. As a player, I want a durable save status ("Video saved on this iPhone", "Saved through 41:12"), so that I can see that footage is safe, not merely being recorded.
75. As a player, I want a large stop button that asks for confirmation, so that a stray tap does not end my match.
76. As a player, I want a pause control that closes the current segment and resumes into the same session, so that changeovers and breaks do not create separate sessions.
77. As a player, I want the screen to stay awake only while recording, so that the battery is not drained otherwise.
78. As a player, I want a compact manual scoreboard ("Jon 4 30 / Alex 3 15") badged "Manual score", so that I can keep score on the phone without pretending it was detected.
79. As a player, I want one-tap "point to me" and "point to opponent" buttons with server indication, so that live scoring is quick between points.
80. As a player, I want to undo the last score tap, so that a mis-tap is fixed instantly.
81. As a player, I want a "Mark point" bookmark control, so that I can flag a moment to review or keep, even without scoring.
82. As a player, I want to add a short note to a bookmark, so that I remember why I flagged it.
83. As a player who prefers not to score every point, I want to enter just the game score at changeovers, so that about ten taps a match give the engine enough to reconstruct the points.
84. As a player, I want a "court mode" that blacks out the preview while still showing REC, the timer and the save status, so that the phone stays cooler and the battery lasts longer.
85. As a player, I want the app to step down gracefully under heat — helpers off, then preview off, then 30 fps — with a visible amber "Phone warming · Analysis paused" status, so that the recording finishes instead of shutting down.
86. As a player, I want low-battery and low-storage warnings with the minutes remaining shown as a range, so that I can plug in or stop on my own terms.
87. As a player, I want recording to end cleanly and keep everything when storage runs out, so that a full disk never corrupts the session.
88. As a player, I want no live ball speed, skeleton or line calls on the capture screen, so that the phone stays focused on saving video.
89. As a player, I want a one-tap "Delete this recording" during capture, so that I can honour a withdrawn consent immediately.
90. As a player, I want recording to work with the microphone off or denied, so that audio permission never blocks video.
91. As a player, I want the microphone requested at my first capture with an explanation of what audio is used for, so that I can decline without consequence to the video.

### Interruptions and recovery

92. As a player, I want a phone call, alarm, Siri or another camera app to close the current segment and record the gap, so that an interruption never loses the session.
93. As a player returning after an interruption, I want "Recording stopped at 41:12 — Resume?", so that I can continue the same session.
94. As a player, I want the app to recover a session after a crash, forced quit, jetsam or power loss at next launch, so that at most a few seconds are lost.
95. As a player, I want recovered sessions to be validated by actually decoding the video to the end, so that "recovered" really means playable.
96. As a player, I want a recovered session to show its gaps ("Gap 41:12–41:31 · phone call"), so that I know exactly what is missing.
97. As a player, I want a "Segment saved" confirmation after each interruption, so that I trust the recovery.
98. As a player, I want media services resets and camera errors to rebuild the capture session automatically where possible, so that transient errors do not end recording.
99. As a player, I want the session's thermal and frame-rate changes logged into its metadata, so that later analysis knows the frame rate changed.
100. As a player, I want a recording that could not be fully recovered to keep every playable segment and say what failed, so that partial footage is never thrown away.

### Import and processing (screen 7)

101. As a player, I want a "Bring your game in" screen with "Photos", "Files" and "Google Drive" sources, so that I can analyse footage recorded with the native camera, a GoPro or another phone.
102. As a player, I want the Photos picker to work without granting library access, so that I share only the videos I choose.
103. As a player, I want imported videos to keep their original quality, frame rate and orientation without auto-cropping, so that nothing is lost on import.
104. As a player, I want to rotate an import by 90° manually, so that sideways footage is fixed.
105. As a player, I want the "Google Drive" tile to restore sessions from my JOVRA archive and explain that other Drive videos import through Files, so that both paths are clear.
106. As a player, I want common codecs and frame rates (24–240 fps, HEVC/H.264, HDR) accepted, so that my footage is not rejected for arbitrary reasons.
107. As a player, I want an unsupported codec or resolution to be explained specifically, so that I know what to convert.
108. As a player, I want duplicates detected by content and offered as "Open existing" or "Import anyway", so that my library does not fill with copies.
109. As a player importing several videos, I want partial success reported per file, so that one bad file does not fail the batch.
110. As a player, I want to cancel an import and have the partial copy cleaned up, so that cancelled work leaves nothing behind.
111. As a player, I want iCloud-only or offline files to show "Waiting for download" and resume when available, so that imports do not fail for connectivity.
112. As a player, I want a stage timeline — "Saved locally", "Preparing replay", "Analyzing points" (with progress), "Backing up" — so that I can see each stage separately.
113. As a player, I want "Recording is safe. You can leave this screen.", so that I do not babysit processing.
114. As a player, I want "View session" available as soon as the video is saved, so that I can watch before analysis finishes.
115. As a player, I want to pause and resume analysis, so that I can save battery or heat.
116. As a player, I want analysis to wait for a cool phone (and prefer charging), so that processing never overheats the device.
117. As a player, I want a failed analysis to leave the video fully viewable with a "Retry analysis" action, so that analysis failure never costs me the replay.
118. As a player, I want the "Backing up" stage to say "Queued for your Google Drive archive" or "Backup waits for Wi-Fi", so that I know why the upload has not started.
119. As a player, I want imported sessions labelled with their real date and source metadata, so that the library is accurate.

### Library and session states (screen 8)

120. As a player, I want "Your sessions" with a search field ("Search players, courts, notes"), so that I can find any session fast.
121. As a player, I want "All / Matches / Practice" filters, so that I can narrow the list.
122. As a player, I want each card to show players, score, date and duration with a court thumbnail, so that I can recognise sessions at a glance.
123. As a player, I want independent status labels for the original video, analysis, review and archive (for example "On device · Backed up", "Needs review"), so that one stuck stage never hides the others.
124. As a player, I want local-only sessions to say "Only on this iPhone" until they are archived, so that I know which footage has no second copy.
125. As a player, I want per-session storage size shown, so that I know what is using space.
126. As a player, I want an empty-library state with Record and Import actions, so that a new install is not a dead end.
127. As a player, I want a "No results" state for searches with a clear action, so that I know the search worked.
128. As a player, I want a "+ Import" action in the library header, so that importing is always one tap away.
129. As a player, I want deleting a session to move it to Trash with Undo, so that a mistaken delete is recoverable.
130. As a player, I want permanent deletion to say exactly what is removed (original, analysis, local copies) and whether a verified Drive copy exists, so that I never lose an original by surprise.
131. As a player, I want Trash never to auto-empty originals unless I turn that on in the retention editor, so that nothing irreplaceable disappears silently.
132. As a player, I want sessions restored from my archive to appear marked "Restored from Google Drive", so that I know their origin.
133. As a player, I want sessions whose originals live only in the archive to show "In Google Drive only" with a "Download" action, so that I can review them again.
134. As a player, I want the library rebuilt automatically from session folders if its index is ever lost, so that a corrupt index never hides my sessions.
135. As a player, I want sessions sorted by date with sample sessions visibly badged, so that real and demo content are distinguishable.

### Match overview and stats (screen 9)

136. As a player, I want a match header with players, date, type and a scoreboard (Player / Set 1 / Set 2) with a WIN label, so that the result is clear.
137. As a player, I want match duration (first serve to last point) shown separately from video length, so that warm-up and stoppages do not inflate it.
138. As a player, I want headline metrics — Points, Points won, First serves, Shots — each with its fraction one tap away ("72 / 124"), so that every percentage is checkable.
139. As a player, I want "Shots" defined as racket contacts in live play, with the definition one tap away, so that I know what is counted.
140. As a player, I want percentages rounded by one documented rule (half-up integers) and "—" for empty denominators, so that numbers are consistent everywhere and match Android later.
141. As a player, I want source insights such as "28 of 40 first-serve points won", so that the story behind the numbers is explicit.
142. As a player, I want serve, return, break-point, point-ending and rally-length stats from the event log, so that I get the depth that charting apps provide.
143. As a player, I want second-serve points to include double faults, labelled "points after a 1st-serve fault", so that the stat is defined the standard way.
144. As a player, I want a momentum chart that prints its window and denominator, so that it is descriptive, not a prediction.
145. As a player, I want a point-history list (score before the point, server, how it ended, play button), so that I can jump from any point to its video.
146. As a player, I want head-to-head stat bars comparing me and my opponent, so that I can see where the match was won.
147. As a player, I want "Watch match" and "Review 8 flagged points" actions, so that I can go straight to replay or to the review deck.
148. As a player, I want retirements, defaults, walkovers and incomplete matches saved with an explicit result (including "No winner"), so that unfinished matches are kept honestly.
149. As a player, I want to change the match format or session type after the match, with a warning when results change and a full recompute, so that a setup mistake is fixable.
150. As a player, I want my head-to-head record and history against each opponent, so that I can see patterns over time.
151. As a doubles player, I want team stats plus per-server serve stats, so that each of us sees our own serve.

### Replay (screen 10)

152. As a player, I want a "Match replay" screen with a 16:9 video and a scoreboard overlay derived from the events, so that the score on screen is always right.
153. As a player, I want an event timeline with point markers and a time readout ("12:46 / 54:00"), so that I can navigate the whole match.
154. As a player, I want a frame-quantized jog strip above the transport controls (never at the bottom edge), so that I can scrub precisely without triggering system gestures.
155. As a player, I want ±1-frame buttons with hold-to-repeat, so that I can find the exact contact or bounce frame.
156. As a player, I want 0.25×, 0.5×, 1× and 2× playback, so that I can study technique in slow motion.
157. As a player, I want a frame/time/fps readout, so that I know exactly where I am.
158. As a player, I want 10-second skip, A–B loop and pinch zoom, so that I can study a moment repeatedly and up close.
159. As a player, I want filter chips ("All points", "Serves", "Forehands" and others such as my points, break points, short points), so that I can watch only what matters.
160. As a player, I want a filter that has no matching data to say so ("No tagged forehands yet") rather than show an empty timeline, so that I know why nothing appears.
161. As a player, I want a current-point card ("Point 42 · 8 shots") with a "Needs review" status where applicable, so that I can see the point's state.
162. As a player, I want two equal buttons ("Jon won" / "Alex won") on the point card, so that I can confirm or correct the winner in one tap.
163. As a player, I want "Edit point" and "Save clip" on the point card, so that deeper edits and exports are one tap away.
164. As a player, I want full-video scrubbing to stay available even for stretches with no recognised events, so that nothing in the video is unreachable.
165. As a player, I want a captions control for video with speech and for point captions, so that replay works with the sound off.
166. As a player, I want replay to adapt to landscape, so that I can watch full screen.
167. As a player, I want to draw annotations on a paused frame in an explicit Draw mode where the jog still scrubs, so that drawing never hijacks scrubbing.
168. As a player, I want a sample-video badge when replaying sample content, so that demo footage is always labelled.

### Point correction and Fast Point Review

169. As a player, I want to flip a point's winner and see every later score, stat and overlay recompute immediately, so that one correction fixes everything downstream.
170. As a player, I want to add a missed point at a video time, so that an unscored point can be inserted.
171. As a player, I want to split one detected point into two and merge two into one, so that segmentation mistakes are fixable.
172. As a player, I want to delete a false point (for example a feed between points), so that it stops affecting the score.
173. As a player, I want to nudge a point's start and end, so that its clip is trimmed correctly.
174. As a player, I want to set a point's outcome to "Unknown" and see later scores marked provisional, so that the app never guesses a winner.
175. As a player, I want to record how a point ended (ace, service winner, double fault, winner, forced error, unforced error, penalty, hindrance, unknown), so that point-ending stats are possible.
176. As a player, I want to record serve results (first in, fault, let) and stroke count for a point, so that serve and rally stats are complete.
177. As a player, I want to record error direction (net, long, wide), so that I can see how I miss.
178. As a player, I want to mark any point "Needs review", so that I can come back to it.
179. As a player, I want my original automatic suggestion preserved separately from my correction, so that the app can show what it suggested and what I decided.
180. As a player, I want my corrections to survive re-running analysis, so that reprocessing never undoes my work.
181. As a player, I want conflict banners when a correction moves a game boundary (server mismatch, tie-break appeared or vanished, points after the match ended, match no longer complete), so that I understand the consequences.
182. As a player, I want to choose Rules mode or As-played mode when the recorded server differs from the rules, so that a match where someone served out of turn is scored as it was played.
183. As a player, I want the "as called on court" score shown next to the rules-derived score when they diverge, so that I can reconcile disputes.
184. As a player, I want a "Recalculated" indicator listing what changed after an edit, so that I can trust the recomputation.
185. As a player, I want a Fast Point Review deck with one card per bookmarked or suggested point, playing a short loop, so that I can review a match in minutes.
186. As a player, I want to swipe right for "I won", left for "Opponent won", up for "Let / not a point" and down for "Unsure", so that each decision takes a second.
187. As a player, I want an undo bar and progress ("41 / 124") in the review deck, so that I can fix a swipe and see how far I am.
188. As a player, I want changeover checkpoints to auto-fill the point winners that are uniquely determined, marked Estimated until reviewed, and flag only ambiguous stretches, so that checkpoint scoring saves most of the work.
189. As a player, I want a checkpoint that cannot be reached from the point log to be flagged on just the stretch between checkpoints, so that I know exactly where to look.
190. As a player, I want bulk select and deselect of points in review, so that I can confirm many suggestions at once.
191. As a VoiceOver user, I want review cards to offer custom actions ("I won", "Opponent won", "Not a point", "Unsure"), so that the deck works without swiping.

### Rally-only playback and automatic detection

192. As a player, I want rally-only playback built from my bookmarks, so that I can watch a two-hour match in about twenty minutes without any automatic analysis.
193. As a player, I want collapsed gaps shown as tappable chips ("+0:42"), so that I can always see and expand what was skipped.
194. As a player, I want the full untrimmed video one tap away from rally-only mode, so that nothing is ever hidden.
195. As a player, I want adjustable pre-roll and post-roll per session and per clip, so that points are not cut off.
196. As a player who recorded with audio, I want JOVRA to suggest points from detected racket hits, every suggestion marked "Needs review", so that dead time is trimmed without me trusting an AI result.
197. As a player, I want suggested points to carry "Estimated" provenance until I review them, so that suggestions never count as facts.
198. As a player, I want a capability detail page that says how hit detection was benchmarked (synthetic video only, real-court accuracy not yet measured), so that I know how much to trust it.
199. As a player who recorded without audio, I want automatic point suggestions shown as unavailable with the reason, so that a missing feature is explained.
200. As a player, I want to exclude a noisy side (neighbouring court) from detection, so that other courts' hits do not create false points.

### Clip export, highlights, sharing and data export

201. As a player, I want to save a clip of a point or a range to Photos or Files in seconds, so that I can keep or share a moment.
202. As a player, I want to export the condensed rally-only match as one file with no length limit, so that I can share or archive the whole match compactly.
203. As a player, I want shared exports to strip audio by default with an "Include audio" toggle, so that court conversations are private unless I choose otherwise.
204. As a player, I want a highlight reel of my favourite points with the score burned in from the derived score, so that the overlay is always correct.
205. As a player, I want a highlight reel re-rendered after a correction to show the corrected score, and older exports flagged "Exported before a correction", so that I know which files are stale.
206. As a player, I want vertical crop and captions options for highlights, so that they suit social sharing.
207. As a player, I want exported clips to start and end within one frame of the range I chose, so that exports are precise.
208. As a player, I want long exports to keep going safely with visible progress, so that a long export is not lost when I switch apps.
209. As a player, I want saving to Photos to require only add-only permission, so that JOVRA never reads my library.
210. As a player, I want a "Save original to Photos/Files" action on every session, so that I can always get my full original out.
211. As a coach, I want to receive a Share Pack (selected clips, notes, match stats, a match JSON, a points CSV and a static viewer page) by AirDrop or Files, so that I can review a student's points without installing an app or creating an account.
212. As a coach, I want the Share Pack viewer to open in any browser from the folder, so that I can watch clips and read stats on any device.
213. As an opponent, I want to receive a full copy or selected points of a match I played in, so that I can review it too (and so that junior competition rules requiring an opponent copy can be met).
214. As a doubles partner, I want to receive our team's points as a Share Pack, so that we can review together.
215. As a player, I want to share a pack as an expiring Google Drive link when the Drive API allows it for my archive, so that I can send large packs without attachments.
216. As a player, I want Share Packs private by default and built from 720p proxies or rally-only cuts when I choose, so that packs are small and safe to send.
217. As a player, I want an optional on-device face blur for bystanders in exports, labelled as an estimate that may miss faces, so that I can protect people who did not consent.
218. As a player, I want to export a session's data as the versioned JSON document plus points and stats CSV, so that I can use my data in a spreadsheet or another tool.
219. As a player, I want the export schema published and versioned, so that coaches and future tools can rely on it.

### Shot placement (screen 11)

220. As a player, I want "Where your shots land" on an accurate top-down court (net, service lines, centre service line only through the service boxes, doubles alleys), so that placement is drawn to real dimensions.
221. As a player, I want to tap where a shot bounced, on the court diagram or on the video frame through my calibration, so that I can build a placement map by hand.
222. As a player, I want "All shots / Forehand / Backhand" filters, so that I can see each wing separately.
223. As a player, I want In, Out and Needs-review markers that differ by shape (circle, triangle, diamond) as well as colour, with a legend, so that colour is not the only signal.
224. As a player, I want Deep, Short and Out percentages with their denominators, so that I know how many placements back each number.
225. As a player, I want the provenance row to state what the placements really are ("Manual placements · 50 shots"), so that hand-marked data is never called camera-measured.
226. As a player, I want "Review placements" to edit, move or delete markers, so that mistakes are fixable.
227. As a player, I want a no-data state that explains how to add placements, so that an empty map is useful.
228. As a player with missing or invalid calibration, I want frame taps disabled with an explanation while diagram taps still work, so that I can keep marking.
229. As a player, I want to be told when rounded composition rows do not sum to 100, so that rounding never looks like an error.

### Serve Lab (screen 12)

230. As a player, I want Serve Lab to show first serves in and first-serve points won with fractions, split by deuce and ad, so that I can see my serve by side.
231. As a player, I want to tap serve placements on a mini service box, so that I can see where my serves land.
232. As a player, I want to estimate a serve's speed by marking the contact frame and the bounce frame and tapping the bounce on my calibrated court, so that I get a speed number with a stated method.
233. As a player, I want the result shown as "Estimated average speed, contact→bounce" with a range and "Camera calibration affects speed", so that I know it is an average flight speed with uncertainty, not a radar peak.
234. As a player, I want speed estimation unavailable with an explanation when calibration is missing, invalid or stale, so that I am never shown a number built on a bad calibration.
235. As a player, I want implausible speed estimates flagged as outliers, so that a mis-marked frame does not become my "fastest serve".
236. As a player, I want to mark serve key moments (Toss release, Trophy, Racket drop, Contact, Landing), so that I can study my motion.
237. As a player, I want a toss-to-contact timer computed from my marked frames, so that I can work on rhythm.
238. As a player, I want a toss-consistency overlay of my marked toss peaks from the same camera position, so that I can see whether my toss is repeatable.
239. As a player, I want "One focus for next time" (for example "Build a repeatable toss") linked to its evidence, so that Serve Lab leads to practice.
240. As a player, I want "Review 12 serves" to open the serves in the review deck, so that I can confirm serve data quickly.
241. As a player in a serve-practice session, I want in/out counts and placements without points-won stats, so that practice is measured the right way.

### Stroke Lab and 2D pose (screen 13)

242. As a player, I want Stroke Lab to collect my forehands or backhands from bookmarks and tags as padded clips I can nudge, so that I can study one stroke type.
243. As a player, I want named key moments (Ready, Unit turn, Racket drop, Contact, Finish) that I set and can correct, so that comparisons line up on the right frames.
244. As a player, I want a freeze-frame contact strip with "Contact" selectable, so that I can compare contact points across swings.
245. As a player, I want "Contact timing", "Follow-through" and "Balance" rows with a review status I set, not an invented score, so that the lab is honest.
246. As a player, I want an on-demand 2D pose overlay labelled "2D pose estimate", drawing only joints above a confidence threshold, so that I see body position without fake precision.
247. As a player, I want a one-tap "swap sides" when the pose estimate confuses left and right, so that I can fix the most common pose error.
248. As a player, I want a "No pose detected" state when the person is too small or occluded, so that I am not shown a guessed skeleton.
249. As a left-handed player, I want mirrored diagrams and a mirror option in Stroke Lab, so that comparisons with right-handed references are not confusing.
250. As a player, I want a focus card ("Compare contact position across 5 swings") and a "Compare swings" action, so that the lab leads to comparison.
251. As a player, I want to export a contact strip image, so that I can share a set of contact frames.
252. As a player, I want 2D angles shown without decimals or norms, so that the app never implies biomechanical precision.

### Compare two recordings and annotations (screen 14)

253. As a player, I want to pick two of my own recordings to compare, so that I can see today's serve against last month's.
254. As a player, I want the two videos stacked in portrait and side by side in landscape, labelled with their dates ("Today · Oct 6", "Previous · Sep 28"), so that I know which is which.
255. As a player, I want to align each side independently, lock them "Synced at Contact" and nudge either side by one frame, so that sync is precise and reliable.
256. As a player, I want sync to use time (not frame numbers), so that 60 fps and 240 fps clips line up.
257. As a player, I want to play one side alone without losing the lock, so that I can re-check alignment.
258. As a player, I want 0.25× playback, Draw and Voice note controls on the compare screen, so that I can study and annotate.
259. As a player, I want an overlay mode with opacity and mirror, with a warning when camera positions differ, so that overlays are not misleading.
260. As a player, I want line, arrow, circle, 2D angle and freehand tools whose shapes stay editable with handles, so that annotations can be refined.
261. As a player, I want each drawing to appear for a frame range (default about 12 frames) rather than forever, so that annotations appear only when relevant.
262. As a player, I want to pin a voice note to a frame or sync point and play it back there, so that a spoken note is attached to the exact moment.
263. As a player, I want a text note ("Keep the toss position consistent.") on a comparison, so that I remember the takeaway.
264. As a player, I want "Save comparison" to save a project that references the videos without duplicating them, so that comparisons cost no extra space.
265. As a player, I want a comparison whose video is missing (deleted or archive-only) to say so and offer download or relink, so that saved comparisons do not silently break.
266. As a player, I want the compare screen badged "Your recordings", so that it is clear only my own footage is used.
267. As an iPad player with Apple Pencil, I want Pencil-only drawing so that my finger still scrubs, so that both tools work together.

### Practice plan (screen 15)

268. As a player, I want "Your next advantage" with one weekly focus (for example "This week: a steadier first serve") based on my sessions, so that I leave each session with one useful action.
269. As a player, I want each suggestion to show its evidence row ("28 / 40 first-serve points won") and a "Watch evidence" button that plays the supporting points, so that I can see why it was suggested.
270. As a player, I want suggestions labelled "Suggested practice" and never presented as coaching from a verified coach, so that the app does not overclaim.
271. As a player, I want numbered drills with duration and structure ("01 Toss consistency · 8 min · 3 sets of 10"), so that the plan is practical.
272. As a player, I want a selected drill to expand with a small target graphic, so that I know where to aim.
273. As a player, I want "Start drill" to set up a matching practice session or let me mark the drill done without recording, so that drills fit how I practise.
274. As a player, I want to edit, reorder, remove and add drills, so that the plan is mine.
275. As a player, I want "Evidence unavailable" shown when the supporting video is missing, with the numbers still visible, so that suggestions stay explainable.
276. As a player, I want suggestions to need a minimum sample before they appear, so that one short session does not drive my plan.
277. As a player, I want my goals from onboarding to influence which suggestions are shown first, so that the plan reflects what I care about.

### Progress (screen 16)

278. As a player, I want "See the work pay off" with 4 weeks / 3 months / Year ranges, so that I can choose the time scale.
279. As a player, I want a line chart of first serves in with labelled axes, final and prior values and the change in percentage points, so that progress is concrete.
280. As a player, I want trends pooled from numerators and denominators across sessions, never averaged percentages, so that small sessions do not skew trends.
281. As a player, I want trends limited to similar session types ("Compare similar session types"), so that practice and match numbers are not mixed.
282. As a player, I want a "Too few comparable sessions" state below a minimum sample, so that I am not shown noise as progress.
283. As a player, I want a milestone panel ("8 sessions · 6h 42m on court") computed from my sessions, so that I see my volume of work.
284. As a player, I want "Deep-ball placement" and "Review completion" ("116 / 124 points") rows, so that I see placement and how much of my data is reviewed.
285. As a player, I want "Set a practice goal" to create a goal with a target and date and show completion, so that progress is tied to intent.
286. As a player, I want charts to have Audio Graph descriptions, so that trends are accessible with VoiceOver.
287. As a player, I want changes between setups shown as associations in my sessions ("Association in your sessions — not proof the strings caused it"), with sample sizes and a minimum of 3 sessions and 100 points per setup, so that equipment comparisons are honest.

### Racket Vault and String Journal (screens 17–18)

288. As a player, I want a Racket Vault listing my rackets by the names I enter (for example "Head Prestige", "Wilson Pro Staff 85"), so that I can track my frames without any catalog or logos.
289. As a player, I want to mark one racket and string job as my "Active setup", so that new sessions default to it.
290. As a player, I want pill tags for the current mains and crosses ("Hyper-G mains", "Ghost Wire crosses"), so that my setup is visible at a glance.
291. As a player, I want a "Court kit" row for free-text items (bag, balls), so that I can note the rest of my gear.
292. As a player, I want to add and edit rackets with optional notes and photos, so that I can record what matters to me.
293. As a player, I want "Log a restring" to clone my last string job for that racket, so that logging a restring takes seconds.
294. As a player, I want a string job with mains and crosses products, gauge label, diameter in millimetres, tensions, date, optional machine and method, pre-stretch and notes, so that I can record a job the way stringers do.
295. As a player, I want tension stored exactly as I entered it (52 lb stays 52 lb) and converted only for display, so that units never corrupt my data.
296. As a player, I want a string inventory where I can "Add to inventory" (for example "WeissCANNON"), so that I can track strings I own.
297. As a player, I want the String Journal ("Dial in your feel.") to show the selected racket's setup card (Mains / Crosses) and tensions, so that I can see the current job.
298. As a player, I want "6h 42m since restring" computed from the sessions linked to that string job, labelled as logged court time, so that the number is real.
299. As a player, I want user-entered feel ratings (Control, Comfort, Spin) per string job, so that I can compare setups by feel.
300. As a player, I want optional reminders by hours and/or days since restring, set by me, so that I restring on my schedule without any prediction of string life.
301. As a player, I want to mark "String broke" at a video time, so that the job's history records when it ended.
302. As a player, I want "Save stringing note" to save the job and its notes, so that nothing typed is lost.
303. As a player, I want the String Journal to state that JOVRA does not measure tension, so that I know there is no sensor claim.
304. As a player, I want sessions linked to a racket and string job to list them, so that I can see what I played with.

### Storage, backup and the Google Drive archive (screen 19)

305. As a player, I want "Your video, your choice" with an "On this iPhone" status card ("Originals stay local until you choose backup"), so that I understand where my video is.
306. As a player, I want device capacity, JOVRA's usage and free space computed from the device, so that storage figures are real.
307. As a player before Google Drive is configured for this build, I want the provider row to read "Awaiting Google Drive setup", so that the app never pretends to be connected.
308. As a player, I want to connect Google Drive through Google's own sign-in page with the minimum access (only files JOVRA creates or I open with it), so that JOVRA cannot read the rest of my Drive.
309. As a player, I want a cancelled Google sign-in to return to the storage screen unchanged, so that cancelling is harmless.
310. As a player, I want "Back up originals" and "Wi-Fi only" toggles, so that I control what is uploaded and over which network.
311. As a player, I want an upload queue with per-session status ("Uploading · 62%", "Waiting for Wi-Fi", "Retry backup"), so that I can see each backup.
312. As a player, I want uploads to resume from where they stopped after the app is killed, the phone restarts or the network drops, so that a 5 GB upload never starts over.
313. As a player, I want "Backed up" shown only after Drive reports the same size and checksum as my local file, so that "Backed up" means verified.
314. As a player, I want each archived session to include a versioned JSON sidecar of the session, so that my analysis travels with the video.
315. As a player, I want the archive organised in a "JOVRA" folder by year and session, so that I can browse it in Drive myself.
316. As a player, I want an expired or revoked connection to show "Needs reconnect" without losing queue progress, so that I can fix it in one step.
317. As a player, I want a full Drive to show "Drive storage full" with options (free space, archive a smaller rally-only copy, pause backups) instead of retrying forever, so that quota problems are clear.
318. As a player, I want a Space Saver option that archives a rally-only copy instead of the full original, so that my free 15 GB lasts longer.
319. As a player, I want to restore an archived session (sidecar and original) to the phone with checksum verification, so that my archive is genuinely recoverable.
320. As a player, I want the archive folder found again after reinstalling, so that my history is reconnected automatically.
321. As a player, I want "Free up space" to remove a local original only after a verified backup and an explicit confirmation, so that originals are never deleted on assumption.
322. As a player, I want a retention editor (keep originals locally, remove after verified backup, Trash auto-empty on/off), so that I set the rules.
323. As a player, I want one-tap cleanup of derived caches (thumbnails, proxies, pose caches) with the space each frees, so that I can reclaim space without touching originals.
324. As a player, I want an "Include originals in iCloud device backup" setting (off by default) with the trade-off explained, so that I choose between iCloud safety and backup size.
325. As a player, I want "Disconnect" to revoke JOVRA's Google access and remove its tokens while leaving my files in Drive, so that disconnecting is clean and non-destructive.
326. As a player, I want "Export video + analysis" to produce originals plus JSON for any session, so that I can keep my data outside JOVRA.
327. As a player, I want the note "Backup storage does not run analysis", so that I know Drive is storage only and my videos are not analysed in the cloud.
328. As a player, I want no upload to run while I am recording, so that backup never competes with capture.
329. As a player, I want backup to be entirely optional, so that JOVRA is fully useful with no Google account.

### Settings, permissions and privacy (screen 20)

330. As a player, I want an account row showing my name and how I signed in ("Apple sign-in" or "No account"), so that I know my account state.
331. As a player, I want camera, microphone and Photos rows that show the real permission state and its consequence ("Microphone · Optional · Off: rally detection unavailable; video still records"), so that I understand what each permission does.
332. As a player, I want the Photos row to say "Not needed for import" and "Add-only" when saving to Photos is enabled, so that it describes what JOVRA actually uses.
333. As a player, I want an "Open iOS Settings" link for permissions, so that I can change them where iOS controls them.
334. As a player, I want units for speed, tension and distance (mph/km/h, lb/kg, ft/m) that convert my data rather than relabel it, so that values stay correct.
335. As a player, I want Appearance (System / Light / Dark), so that the app matches my preference.
336. As a player, I want an Accessibility section (larger live scoreboard, haptic and audio confirmations, hands-free button mapping, reduce motion respected), so that I can tune the app to my needs.
337. As a player, I want notifications requested only when I turn on something that needs them (backup finished, analysis done, restring reminder), so that I am not asked up front.
338. As a player, I want "Training data sharing" to state "Off — JOVRA collects nothing in this version", so that privacy is a fact, not a toggle that does nothing.
339. As a player, I want "Export my data" to produce all sessions' JSON, CSV and (optionally) originals, so that I can take everything with me.
340. As a player, I want "Delete account and data" to explain exactly what is deleted (local profile, sessions, equipment, tokens) and what is not (files in my Google Drive), and to require confirmation, so that deletion is never ambiguous.
341. As a player, I want "Recording help" with mounting, framing, heat and battery advice, so that I can get better recordings.
342. As a player, I want "Send diagnostics" to build a log and session-manifest bundle that I review and share myself, so that support can help me without any telemetry.
343. As a player, I want the support contact shown as text ("hello@islanddevcrew.com"), so that I know where to write.
344. As a player, I want the settings footer to show the app version, so that I can report issues accurately.
345. As a player, I want JOVRA to contain no third-party analytics or advertising SDKs, so that nothing tracks me.
346. As a player, I want all permission prompts to be Apple's own dialogs preceded by an in-app explanation, so that the app never imitates system UI.

### Consent, competition and junior/parent mode

347. As a player, I want a Competition mode that turns off live feedback prompts and shows a rules reminder, so that I can record within event rules.
348. As a parent, I want child profiles stored only on my phone and private by default, so that my junior's footage is not shared accidentally.
349. As a parent, I want to record which written consents I hold for a junior match and attach the form, so that I can show consent was obtained.
350. As a parent, I want recording to stop and the recording to be deletable in one tap if consent is withdrawn, so that I can comply immediately.
351. As a parent, I want match exports for juniors to default to no audio and no public posting reminders, so that I respect junior recording rules.
352. As a parent, I want to give the opponent's family a full copy of the recording, so that the opponent-copy requirement in junior rules can be met.
353. As an opponent, I want to know I am being recorded before the match (through the player's consent step), so that I can agree or decline.

### Accessibility

354. As a VoiceOver user, I want a rotor of points that reads "Point 42, 4–3, 30–15, Alex serving, 8 shots, Jon won, needs review", so that I can navigate a match by points.
355. As a VoiceOver user, I want the timeline to be an adjustable control that steps one frame or one point per swipe, so that I can scrub without precise gestures.
356. As a VoiceOver user, I want every icon button labelled with its action, so that controls are understandable.
357. As a VoiceOver user, I want stat values read with their fraction and provenance ("67 percent, 40 of 60, manual"), so that numbers are complete when spoken.
358. As a player using large text, I want every screen to work at accessibility text sizes without truncated controls, so that I can read everything.
359. As a player with motor impairments, I want all targets at least 44 × 44 points, so that I can hit them reliably.
360. As a player, I want Reduce Motion to replace animated transitions and chart animations with simple fades, so that motion never makes me uncomfortable.
361. As a player who uses Increase Contrast, I want stronger colour roles that keep 4.5:1 text contrast, so that everything stays legible.
362. As a colour-blind player, I want status, chart series and shot markers to use shape, text or pattern as well as colour, so that meaning never depends on colour.
363. As a VoiceOver user, I want live recording status announced politely when it changes (saved, warming, interrupted), so that I know the recording state without looking.
364. As a VoiceOver user, I want the court diagrams to describe placements in words (for example "Deep cross-court, in"), so that shot maps are accessible.
365. As a VoiceOver user, I want the review deck's progress and the current point's state announced after each decision, so that I keep my place.
366. As a player, I want JOVRA's App Store accessibility declarations to claim only what the automated audits and manual checks verify, so that the declarations are honest.

### Honesty and provenance

367. As a player, I want every displayed number to carry a provenance badge (Manual, Estimated, Reviewed or Validated), so that I know how it was produced.
368. As a player, I want a stat that includes unreviewed estimated points to show "Estimated · includes 8 unreviewed points", so that one estimated input is never hidden inside a "manual" stat.
369. As a player, I want a capability page for each analysis feature that states its status, method version, what it was tested on and its results, so that I can judge it myself.
370. As a player, I want features that have not passed their checks to be hidden or clearly marked rather than shown as working, so that nothing pretends to work.
371. As a player, I want no spin RPM, 3D biomechanics, injury or medical claims, or line calls anywhere, so that the app never claims what one camera cannot measure.
372. As a player, I want manufacturer names to appear only as text I entered, with no third-party logos or implied sponsorship, so that the app stays independent.
373. As a player, I want every illustrative image and sample number labelled, so that nothing in the app is passed off as a real measurement.

### Platform integrations

374. As a player, I want to press a volume button, the Action button, Camera Control or an AirPods stem to "Mark point", never to stop recording, so that I can bookmark from the baseline.
375. As a player, I want a confirmation tone or haptic when a hands-free mark registers, so that I know it worked from across the court.
376. As a player, I want recording status (REC time and "saved 4 s ago") on the Lock Screen and, where iOS shows it, in the Apple Watch Smart Stack, so that I can check the recorder from my wrist without a Watch app — if the platform spike shows it works while recording.
377. As a player, I want a Siri / Shortcuts action "Start singles recording" that opens framing in the foreground, so that I can start hands-free without background camera tricks.
378. As a player, I want a "Show last match" shortcut, so that I can open my latest session quickly.
379. As a player, I want to opt in to saving tennis workouts to Apple Health with only start, end and session identifier (no invented calories or heart rate), so that my tennis time appears in Health honestly.
380. As a player, I want Health permission never to block recording, so that declining Health has no cost.
381. As an iPad player, I want split-view layouts for review, replay and compare with keyboard shortcuts (arrow keys for frame steps, space to play), so that big-screen review is efficient.
382. As a Spanish-speaking player, I want the app localised, so that I can use JOVRA in my language (English ships first; Spanish ships after native review).
383. As a player, I want dates, times, numbers and units formatted for my locale, so that values read naturally.

### Cross-cutting failure and recovery

384. As a player, I want every long-running task (import, analysis, export, upload, restore) to survive the app being closed and resume or fail with a reason, so that nothing is silently stuck.
385. As a player, I want each failure message to say what happened, what is safe and what I can do, so that errors are actionable.
386. As a player, I want a session document that fails to load to be quarantined and reported without crashing the app or hiding other sessions, so that one bad file does not break my library.
387. As a player offline, I want everything except Drive backup and restore to work, so that the court's poor signal does not matter.
388. As a player upgrading the app, I want older session documents migrated forward automatically, so that updates never strand my data.
389. As a player, I want the app to keep working when the iPhone is low on storage by pausing non-essential work first, so that recording keeps priority.

## Implementation Decisions

### Architecture and seams

- **Three seams.** (1) The **JovraCore** public API: Foundation-only domain modules (event model, scoring, stats, units,
  calibration maths, capability registry, stores, archive state machine, planners). Builds and tests on Linux CI.
  (2) The **JovraMedia** public API: AVFoundation/Vision/Accelerate modules (capture, fixture camera, import, playback,
  export, audio analysis, Vision analysis), tested with `swift test` on macOS against fixture media. (3) **The app**,
  tested end to end with XCUITest on the iOS simulator. The app target holds SwiftUI features, routing and thin
  platform adapters (Keychain, `ASWebAuthenticationSession`, PhotosPicker, background tasks, HealthKit, ActivityKit,
  App Intents) only. Business rules never live in views.
- Two further test boundaries exist at the edges of those seams, not as extra seams: the **fake Google Drive** (a
  `URLProtocol` stub at the HTTP boundary) and the **synthetic-video benchmark harness** (fixture media in, metrics out).
- **Packages.** ADR-0005's "JovraKit with two libraries" is implemented as two sibling packages, `JovraCore` and
  `JovraMedia`, so Linux CI never resolves an Apple-framework package (already recorded in the developer guide).
- **Deployment target iOS 18.0 (D1).** This supersedes ADR-0005's iOS 17 line; a new ADR records it. iOS 26-only APIs
  (`BGContinuedProcessingTask`, AirPods capture events, lens-smudge detection, iPhone `HKWorkoutSession`) sit behind
  `#available` checks with an iOS 18 fallback path. iOS 18 runtime behaviour is **UNVERIFIED** locally because the build
  Mac only has the iOS 26.5 simulator; the hardware phase needs an iOS 18 device in the matrix or the gap is reported.
- **No server, no JOVRA account, no StoreKit, no ads (D2).** Every feature is free and local. No third-party analytics
  SDK; the privacy manifest declares the required-reason APIs used (free-space query, file timestamps, UserDefaults).

### Domain modules (JovraCore)

**EventLog + ScoringEngine** — the heart of the product.
- A match is an append-only, ordered log of `PointEvent`s; scores are never stored (ADR-0003). Event kinds:
  `MatchSetup`, `DoublesOrder`, `ServeAttempt`, `PointOutcome` (winner, end type, start/end media time, stroke count,
  rally length, error direction), `RallyLet`, `ServerOverride`, `ReceiverOverride`, `DecidingPointSide`, `Penalty`,
  `Retirement`, `Default`, `Suspension`, `Checkpoint` (as-called game score at a changeover), `Bookmark` (with note),
  `PointCandidate` (an automatic suggestion), `Void(eventId)` and `Supersede(eventId, newFacts)`.
- Every event carries an id, a monotonically increasing sequence number, `provenance`
  (`manual | estimated | reviewed | validated`), `source` (`user` or `model:<capability>@<methodVersion>`) and a
  creation time. Points have a stable `pointId` from the event that created them; split and merge create new ids that
  record their parents.
- **Correction semantics.** A user edit never mutates an event: it appends `Supersede(target, newFacts)` with
  provenance `reviewed` (or `manual` for user-originated points). Confirming a suggestion unchanged is a `Supersede`
  with the same facts and provenance `reviewed`. Undo is `Void(lastUserEvent)` followed by a refold, so undoing a
  supersede restores the previous effective value. Automatic suggestions are never deleted; they stay in the log for
  benchmarking and for "what the app suggested" display. Re-running analysis appends new `PointCandidate` events under
  a new method version and may only supersede **unreviewed** earlier candidates; a reviewed point is never overwritten.
- **Effective view and fold.** `ScoringEngine.fold(setup, events, mode) -> MatchTimeline` is a pure function: resolve
  voids and supersede chains into the effective event list, then replay it from point 1 through the rules (§1–3 of
  `docs/research/tennis-rules-and-stats.md`: ad/no-ad, set and match tie-breaks, all v1 format presets, doubles rotation
  and receivers, lets, faults, penalties, terminations). Always refold from the start; no incremental folding.
- `MatchTimeline` holds, per point: pre-point score, server, receiver, side, ends, changeover flag,
  game/break/set/match-point flags (by hypothetical folding), `isProvisional`, conflicts; per set and match: summaries,
  result (`win | retirement | default | walkover | incomplete | noWinner`).
- **Provisional scores.** A point with outcome `unknown` makes every later state `isProvisional`; the timeline records
  `provisionalFrom`. Nothing guesses a winner.
- **As-called vs derived.** `Checkpoint` events record the as-called game score. The timeline exposes both the
  rules-derived score and, where checkpoints exist, the as-called score, and reports divergence.
- **Resolution modes.** `mode = rules` (default) recomputes strictly; `mode = asPlayed` keeps recorded server overrides
  and re-anchors later games to the observed server (Rule 27c).
- **Conflicts** reported by the fold: `serverMismatch`, `tiebreakAppeared`, `tiebreakVanished`, `pointsAfterMatchEnd`
  (flagged, never deleted), `matchIncomplete`, `checkpointConflict` (scoped to the stretch between two checkpoints),
  `doublesOrderConflict` (a stored doubles order names the team that is no longer due after a correction; spec/README.md
  decision 8), `sideMismatch`.
- **Recalculation.** Because the fold is synchronous, the "Recalculated" indicator is a diff:
  `ScoringEngine.diff(before, after) -> [ChangedValue]` lists later points, set scores and stats that changed after an
  edit. Exports record the event-log version they were rendered from; a later edit marks them "Exported before a
  correction".
- **CheckpointSolver.** `solve(timeline segment between checkpoints, candidate point boundaries) -> assignments | ambiguity`
  is a bounded enumeration over legal game lengths (never 7-point ad games). Unique assignments are appended as
  `PointOutcome` with provenance `estimated`; ambiguous stretches become review cards.
- Format and session type are part of `MatchSetup`; editing them after the match is a `Supersede` of the setup and
  triggers a refold plus a "results changed" warning when the final result differs.

**StatsEngine**
- `compute(timeline, perspective) -> MatchStats` produces every stat in research §6 as `Fraction {numerator,
  denominator, provenance, contributingPointIds}`; display goes through one function `pct(n, d) = (200·n + d) div (2·d)`
  (half-up integer), `d = 0` displays "—", never a platform percent formatter.
- Definitions fixed for v1 (D4 and research §9): **"Shots" = `strokeCount`** (racket contacts in live play; DF 0, ace 1,
  missed return 2); rally length (serve counts, final error does not) drives buckets 0–4 / 5–8 / 9+; second-serve
  points include double faults; penalty points count in total points only; tie-break games are excluded from service
  games; winners exclude aces; automatic error labels read "Error (unclassified)".
- **Provenance of a derived stat is the weakest of its inputs**: any `estimated` contributing point makes the stat
  `estimated` and the UI reports how many contributing points are unreviewed.
- Deltas are in percentage points computed from the two displayed integers.
- Composition rows (Deep / Short / Out) are rounded independently and the UI says when they do not sum to 100.

**Units**
- `Measurement`-based conversions for speed (mph, km/h), tension (lb, kg), length (m, ft) and string diameter (mm).
  Stored values keep their entered unit ("52 lb" is never round-tripped); conversion happens at display. Conformance
  fixtures fix the conversion factors and display rounding.

**CourtCalibration**
- Court model in metres from ITF dimensions (origin at the near-left doubles corner). `fit(imageCorners, extraPoints?)
  -> Homography` by normalized DLT (exact 4-point solve, least squares with more points), `project`/`unproject`
  between video pixels and court metres (ground plane only), `reprojectionRMSE(detectedLinePixels) -> Double` as the
  check that can fail (accept ≤ 3 px at 1080p), and validity bound to lens, format and zoom. Taps are converted to video
  pixels before fitting, never view points.
- `ServeSpeedEstimator.estimate(contactTime, bounceTime, contactGroundPoint, bounceGroundPoint, calibration, fps)
  -> SpeedEstimate {value, range, method: "average speed, contact→bounce"}` with the range from the error budget
  (pixel footprint at the bounce, ±½ frame timing at each end, contact-position uncertainty). Times are media
  timestamps, not frame indices. The contact ground point defaults to the server's baseline position derived from the
  serving side and can be refined by tapping the server's feet; the default widens the range. Implausible values are
  flagged as outliers. Missing, invalid or stale calibration returns `unavailable(reason)`.

**RallySegmenter**
- `segment(hits, bookmarks, params) -> [PointCandidate]`: rallies are hits with gaps below a threshold (about 3 s); a
  gap above about 5 s starts a new point; pre/post-roll defaults about 1.5 s / 2.5 s, adjustable per session and clip;
  bookmarks become candidates on their own when no audio exists. Excluded-side masks drop hits attributed to a
  neighbouring court. Pure and conformance-tested so Android reproduces it.
- `RallyOnlyPlan.build(points, rolls) -> [TimeRange] + [Gap]` drives rally-only playback and condensed export; gaps keep
  their durations for "+0:42" chips.

**CapabilityRegistry + Provenance**
- Each capability has `id`, `status` (`manual | estimated | validated | unsupported | disabled`, ADR-0004),
  `methodVersion`, `configurationBand` (what it was tested on), `benchmarkRecord` (latest recorded run, if any) and a
  user-facing explanation. Value provenance (`manual | estimated | reviewed | validated`) is separate from capability
  status; **Sample** is a third, independent flag on sessions and values.
- **Promotion rule.** Status changes only through a recorded benchmark run checked into the repository. Synthetic
  benchmarks can hold a capability at `estimated` for the "synthetic sample video" band and act as a regression floor;
  **`validated` requires the real-footage gate from `docs/research/technical-feasibility.md`** and is never reached in
  v1 without hardware-phase evidence.
- v1 registry (D10): manual scoring, bookmarks, rally-only from bookmarks, 4-tap calibration, manual placement, manual
  stroke tags, manual compare sync, drawing → `manual`; audio hit detection and automatic rally segmentation →
  `estimated` (synthetic band; every output is a `PointCandidate` that needs review); checkpoint auto-fill →
  `estimated`; camera-moved detection → `estimated` (synthetic band); line-snap suggestion → `estimated` if its
  synthetic benchmark passes, else `disabled` (manual taps always work); on-demand 2D pose → `estimated`, "not
  benchmarked" stated on its page; manual-assisted serve speed → `estimated` with range; export face blur → `estimated`;
  ball tracking, automatic bounce map, automatic stroke classification, automatic serve detection and speed, AI point
  winners, line calls, spin, 3D pose, string pitch check → `unsupported`.
- The registry is a versioned document in the shared contracts and is the single source of the badges and capability
  pages; views never hard-code provenance.

**SessionStore** (document store, ADR-0002)
- A session is a folder holding media and one versioned `session.json` (setup, players, event log, calibration,
  annotations, comparisons it owns, provenance, facet states, sample flag). Writes are atomic (temp then rename),
  encoded as canonical JSON (sorted keys, stable formatting) so conformance comparisons are byte-for-byte.
- Interface shape: `create(setup) -> SessionID`, `load(id) -> Session`, `append(events, to:)`, `updateFacet(_, for:)`,
  `list(query) -> [SessionSummary]` (search players, courts and notes; filter by type, state and sample),
  `trash`, `restoreFromTrash`, `purge(confirmation)`, `rebuildIndex()`, `migrate(document) -> current version`,
  `quarantine(id, reason)`.
- **Session state facets** are independent fields, never one status:
  - original: `recording | recovering | saved | savedWithGaps | partial | importing | archiveOnly | missing | trashed`
  - analysis: `notStarted | queued | running(progress) | paused(reason) | done(capabilities) | failed(reason) |
    unavailable(reason)`
  - review: `unscored | inProgress(reviewed, total) | needsReview(count) | complete`
  - archive: `localOnly | awaitingSetup | queued | waitingForWiFi | uploading(progress) | verifying |
    backedUp(verifiedAt) | failed(reason) | needsReconnect | quotaBlocked`
- Head-to-head and opponent history are queries over session summaries (sample sessions excluded).
- The library index is a cache rebuilt from folders whenever it is missing or inconsistent; folders are the truth.

**EquipmentStore**
- One versioned equipment document: `Racket` (user-entered name, notes, photos, active flag), `StringProduct`
  (user-entered), `StringInventoryItem`, `StringJob` (mains/crosses segments with product, gauge label, diameter mm,
  tension value + unit as entered, date, optional machine, method, pre-stretch, notes, photos, feel ratings,
  `brokeAt` media reference), `CourtKitItem`, `Reminder` (hours and/or days), and the `EquipmentUse` link from sessions.
- `loggedCourtTime(stringJob) -> Duration` sums match/session durations of linked real sessions (never sample).
  `cloneLastJob(racket)`. No catalog (D6), no tension measurement, no string-life prediction.

**PracticePlanner**
- A versioned, deterministic rule table: each rule names a stat, a threshold, a minimum denominator and session-type
  scope, and maps to drill templates from a bundled, user-editable drill library. `plan(stats, goals, history) ->
  [Suggestion]`; each `Suggestion` carries its evidence (stat id, fraction, sessions, contributing point ids for "Watch
  evidence") and is labelled "Suggested practice". Rules never fire on sample data mixed with real data.

**ProgressAggregator**
- `trend(stat, range: 4W | 3M | Year, sessionType, filters) -> Series` pools numerators and denominators per bucket,
  hides buckets and comparisons below minimum samples, reports percentage-point deltas from displayed integers,
  excludes sample sessions, and computes milestones (session count, court time) and goal completion.
- `association(stat, bySetup) -> [SetupComparison]` for equipment setups, same session type only, minimum 3 sessions and
  100 points per setup, with wording "Association in your sessions — not proof the strings caused it".

**ArchiveService (provider-independent) + GoogleDriveProvider**
- `ArchiveService` owns the per-item state machine `queued → hashing → sessionCreated(sessionURI, remoteFileId) →
  uploading(confirmedOffset) → verifying → backedUp | failed(reason, retryAt) | needsReconnect | quotaBlocked |
  waitingForNetwork | cancelled`, persisted as an atomic JSON journal next to the session **before** any network I/O
  (ADR-0002 wins over the research's SQLite suggestion). It also owns the account state `awaitingSetup | notConnected |
  connecting | connected(email) | needsReconnect`, the archive manifest (provider-independent: files with role, size,
  MD5, SHA-256, remote id), restore and disconnect.
- `ArchiveProvider` protocol: `ensureArchiveRoot`, `generateIds`, `createResumableSession`, `uploadChunk(offset)`,
  `queryStatus`, `fileMetadata(size, md5, sha256)`, `listArchive`, `download(range)`, `quota`, `revoke`.
- `GoogleDriveProvider` (D3): plain OAuth 2.0 authorization code + PKCE through `ASWebAuthenticationSession`, **no Google
  SDK**, scope `drive.file` only, client ID read from an xcconfig (absent → `awaitingSetup`), redirect on the reversed
  client ID scheme, tokens in Keychain, refresh on expiry, `invalid_grant` → `needsReconnect`. Resumable uploads to the
  Drive v3 upload endpoint with pre-generated file ids (retries return 409, never duplicates), chunk sizes a multiple of
  256 KiB, status query on resume (`308` + `Range` → resume at N+1; `404` → check `files.get` then new session),
  exponential backoff on 5xx/429/rate-403, terminal `quotaBlocked` on `storageQuotaExceeded`, quota preflight with
  `about.get`. Uploads run from chunk files so background URLSession transfers survive app exit; Wi-Fi only maps to
  `allowsExpensiveNetworkAccess = false` and `allowsConstrainedNetworkAccess = false`. "Backed up" only when remote size
  and MD5 (and SHA-256 when present) equal the locally computed values. Archive root found by `appProperties`
  (`jovraRole = archiveRoot`); layout `JOVRA/<year>/<date> <title>/` with the original(s) and `session.jovra.json`.
  Disconnect calls Google's revoke endpoint, deletes Keychain items and leaves remote files.
- Uploads never run while capture is active. Drive-derived data is never sent anywhere else (Google Limited Use).
- **Real-Drive behaviour is UNVERIFIED** until Jon creates the Google Cloud OAuth client and the project is "In
  production"; everything else is proven against the fake Drive. The Share Pack's expiring Drive link depends on an API
  spike (can `drive.file` create permissions on app-created folders?) and stays hidden until that spike passes.

**DataExporter**
- Produces the session JSON (same schema as the sidecar), points CSV and stats CSV, the full "Export my data" bundle, and
  the data part of a Share Pack (`match.json`, `points.csv`, a static `index.html` viewer). Column sets and JSON schemas
  live in the shared contracts.

**SampleContent**
- The coherent Jon vs Alex fixture (the verified 124-point Case A construction, Jon serving first, Point 42's state per
  C15, 116 reviewed + 8 flagged; Point 42's event starts at 18:23.7, and the 12:46 shown on screens 6 and 10 is the
  sample video's illustrative clock per D4/D8, never computed from the event), sample serve-practice and forehand sessions, illustrative sample-only values (the
  "104 mph" serve tile) and the synthetic sample video (D8). Install, reset and remove are explicit operations; every
  installed object carries `isSample`. The same fixture is a conformance fixture, so demo screens and tests share one
  oracle.

### Media modules (JovraMedia)

**CaptureEngine**
- Composed of a `CaptureSource` (`CameraSource` on device: physical ultra-wide when needed, locked frame rate,
  stabilization off, focus/exposure/white balance locked after framing, rotation locked at record start;
  `FixtureCamera` on the simulator) feeding one **segment pipeline**: an `AVAssetWriter` writing fragmented MP4
  segments (about 2 s fragments, segment rollover on interruption, pause or format change) behind a **write-ahead
  journal** (session id, segments, gaps with reasons, last confirmed media time, thermal and frame-rate changes).
- **Deviation from the research recommendation, stated explicitly:** the research proposed `AVCaptureMovieFileOutput`
  for P0 with the asset-writer path as a fallback. D9 requires the simulator fixture camera to run through the same
  recording/segment pipeline, which is only possible if the writer consumes sample buffers, so v1 uses the asset-writer
  path for both sources. The movie-file-output engine remains the fallback if the device soak test shows dropped
  frames or A/V sync problems; the journal, segment and recovery contracts are unchanged either way.
- Interface shape: `prepare(preset) -> PreflightReport` (supported presets, storage estimate range from bitrate ×
  planned length × 1.2 then the measured slope after 30 s, battery, Low Power Mode, thermal state), `start(session)`,
  `pause`, `resume`, `stop`, `markPoint(note?)` returning the media time from the timing map, and an async stream of
  `CaptureStatus` (recording time, saved-through time, thermal rung, warnings, interruptions).
- **Thermal ladder:** `fair` → helpers off, dim preview; `serious` → court mode (preview off) + "Phone warming";
  `critical` → 30 fps; `shutdown` → clean segment close. Each rung is journalled.
- **Recovery:** `RecoveryScanner.scan() -> [RecoveredSession]` runs at launch from the journal and segment files (never
  waiting for delegate callbacks), validates by decoding to the end, truncates torn segments, and records gaps.
- Hands-free Mark point uses `AVCaptureEventInteraction` mapped to Mark point only, never Stop.
- Screen stays awake only while recording. Microphone is optional (D5); audio absent → analysis capabilities that need
  it report `unavailable`.

**FixtureCamera** (D9)
- A `CaptureSource` that streams a bundled fixture video (with audio) in real time as sample buffers into the same
  segment pipeline. It is labelled "Simulator fixture camera" in the UI and offered only where no camera exists (or in
  a debug setting). Test hooks inject interruptions, thermal rungs, low storage and crashes, so capture, recovery and
  the recording UI are testable on the simulator. It proves pipeline logic only; real capture is validated in the
  hardware phase.

**MediaLibrary**
- Custody of media files in session folders: originals and segments, proxies (short-GOP analysis proxy when backward
  stepping is slow), thumbnails, pose caches. `probe(url) -> MediaInfo` (duration, fps, codec, dimensions, transform, HDR),
  `contentHash`, per-session `sizes`, `clearDerivedCaches`, `setIncludedInDeviceBackup(_)` (D7: originals excluded by
  default via `isExcludedFromBackup`), `saveOriginalToPhotos` (add-only, move without copy) / `saveToFiles`, and
  `removeLocalOriginal` that refuses unless the archive facet is `backedUp` and the caller passes an explicit
  confirmation token.

**ImportPipeline**
- `import(items) -> ImportReport` copies each picked file inside the picker handler into a new session folder, probes
  and validates it (supported codecs/frame rates/orientations; HDR kept), detects duplicates by content hash, reports
  per-file results (success, duplicate, unsupported(reason), failed(reason), cancelled), cleans up partial copies, and
  enqueues processing. Imports never auto-crop; manual 90° rotation is stored as metadata.

**ProcessingQueue**
- A persistent per-session queue of independent stages — `prepareReplay`, `analyze`, `backup` — whose state machine is
  pure (JovraCore) and whose scheduler is an app adapter. Stages run after capture only, at thermal state ≤ `fair`,
  preferring external power; on iOS 26 a user-initiated `BGContinuedProcessingTask` continues work with system progress,
  on iOS 18 work runs in the foreground with resumable checkpoints plus an overnight `BGProcessingTask` on power, and
  screen 7 says "Analysis pauses if you leave JOVRA" on that path. A failed stage never changes the original facet.

**PlaybackController**
- Wraps `AVPlayer` for screens 10, 12, 13, 14: chase-time seeking (one seek in flight), coarse tolerance while dragging
  and exact on release, `step(byCount:)` frame steps, rates 0.25×–2×, A–B loop, 10 s skip, readout (frame / time / fps),
  rally-only compositions from `RallyOnlyPlan`, gap chips, and an accessibility-adjustable timeline. The jog strip is
  ≥ 44 pt tall, ≥ 16 pt from the event timeline, above the transport row, and defers system edge gestures.
- **CompareSync** (pure, JovraCore): each clip stores `syncEventTime` and `captureFPS`; the shared playhead is time
  relative to the sync event; states `aligning → locked("Synced at Contact") → nudged(±frames)`. `DualPlayback`
  (JovraMedia) drives two players from it.

**ClipExporter / Composer**
- `exportClip(range, options)` (passthrough when audio is kept and the file stays in the app; re-encode for external
  shares), `exportCondensedMatch`, `exportHighlightReel(points, overlay: derived score, crop, captions)` using the Core
  Animation tool with `#available` branching for the iOS 26 composition API, `exportContactStrip`, `buildSharePack`,
  optional face blur (Vision face detection, `estimated`). Shared exports default to **no audio** with an "Include
  audio" toggle (D5). Every export records the event-log version it used. Start/end within ±1 frame of the source
  timecodes.

**HitDetector**
- `detect(audioTrack, calibration?, excludedSide?) -> [HitCandidate {time, confidence, kind: hit | bounce | other}]`:
  decode to mono 48 kHz, spectral flux onsets (vDSP), adaptive threshold, 150 ms refractory, refinement, heuristic
  classification, sound-travel correction from calibration when present. Output feeds `RallySegmenter`; nothing it
  produces is shown as a fact (D10).

**CameraMovedDetector**
- `check(video, calibrationReference, every: interval) -> [CalibrationValidity]` using Vision homographic image
  registration against the calibration frame on stable regions; drift beyond threshold marks the calibration "stale
  from mm:ss", which disables calibration-dependent features from that time. Also used live on the framing screen.

**PoseEstimator**
- On demand only (D10): `estimate(clip, range, roi?) -> PoseTrack` with Vision 2D body pose; joints below the confidence
  threshold are omitted, never interpolated; temporal left/right consistency with a user "swap sides" override; cached
  as a derived cache. Labelled "2D pose estimate"; no 3D, no angle decimals, no norms.

**LineSnapper**
- Suggests a snapped corner from contour/line detection around a tap at full resolution; the user accepts or ignores;
  manual taps remain the source of truth.

### App layer

**AppRouter**
- Five tabs (Home · Sessions · Record · Insights · Profile) plus full-screen routes that hide the tab bar (framing,
  capture, replay, review deck, compare, Stroke Lab focus), sheets for editors, deep links for App Intents and Share
  Pack opens, demo entry, and state restoration. Launch arguments select appearance, demo state, fixture camera and
  injected permission/archive states for UI tests.

**PermissionsCenter**
- One adapter for camera, microphone, Photos add-only, notifications and HealthKit: `status(of:)`, `request(_)` at the
  moment of need with the explanation shown first, consequence text per state, and "Open iOS Settings". It never draws
  imitation system dialogs. A fake implementation is injected by launch argument in UI tests.

**Platform adapters**
- `AppleSignIn` (optional; stores the Apple user identifier and name locally; credential-state check on launch; no
  server, so "Delete account and data" deletes local data and tells the player how to stop using Apple ID with JOVRA in
  iOS Settings), `KeychainTokenStore`, `DriveAuthSession` (`ASWebAuthenticationSession`), `HealthWorkoutRecorder`
  (opt-in, start/end/session id only), `RecordingLiveActivity` (spike-gated, P1-13), App Intents ("Start singles
  recording" opens framing in the foreground; "Show last match"), `DiagnosticsBundle` (OSLog export, session manifest,
  thermal log; built and shared only when the player taps it).

### Design system and copy

- Palette, type, spacing, card radius and brand mark from the foundation ticket; light utility screens and forest
  capture/replay screens belong to one system; landscape variants for framing, capture, replay and compare.
- Copy comes from `design-reference/brief/screens.json`, with these deliberate honesty corrections: Photos row "Not
  needed for import" / "Add-only" instead of "Selected photos"; shot-map provenance row states the real provenance
  instead of "Estimated from calibrated video"; Serve Lab real speeds read "Estimated average speed, contact→bounce"
  (the "104 mph · Fastest serve · Estimated" tile exists only on sample data); scoring row "Best of 3 · Ad · Tie-break at
  6–6" instead of "Best of 3 · Advantage"; trend deltas say "percentage points"; the provider pill reads "Awaiting Google
  Drive setup" / "Connected" / "Needs reconnect" for real state and "Demo" only on sample state; "Training data sharing"
  is a statement, not a toggle; the settings footer shows the app version instead of "Reference concept"; the storage
  estimate is computed, never the sample "3.2 GB".
- All strings live in String Catalogs from day one; English ships, Spanish is the first translation (shipped after
  native review).

### Shared contracts (`spec/`) and how Swift consumes them

- The shared contracts hold JSON Schemas for every persisted or exported document (session, equipment, archive
  manifest and sidecar, capability registry, benchmark record, Share Pack `match.json`, CSV column sets) and golden
  **conformance fixtures**: scoring sequences → expected timelines, stats and conflicts; `pct` vectors; unit
  conversions; checkpoint-solver cases; rally segmentation cases; homography and serve-speed cases (with tolerances);
  archive state-machine transcripts; the Jon vs Alex fixture.
- **Expected values are produced by the Python reference engine in the shared contracts, never by the Swift code under
  test** (no tautological oracles). A rule change lands as a fixture change first (ADR-0001).
- Swift conformance tests in JovraCore locate the shared contracts relative to the repository root, run every fixture
  listed in the fixture manifest, and compare canonical JSON byte-for-byte (integer outputs; floats only where a
  fixture states a tolerance). A manifest test fails if any fixture is not consumed. Swift-encoded documents are
  validated against the schemas by the reference tooling in CI. Android will consume the same fixtures.
- Media times are stored as rational values (value/timescale) so frame accuracy survives serialization.

## Testing Decisions

- **What a good test is here.** It exercises behaviour through one of the three seams (JovraCore public API, JovraMedia
  public API, the app through XCUITest) and would fail if the behaviour broke, regardless of internal structure.
  Expected values come from an independent source: the Python reference engine, the rules document's worked examples,
  synthetic-video ground truth, or a hand-checked literal. No test mocks internal collaborators; fakes exist only at
  real boundaries (the Drive HTTP API via `URLProtocol`, the camera via `FixtureCamera`, system permissions via the
  injected `PermissionsCenter`, the clock).
- **Golden conformance (JovraCore, Linux CI required check).** ScoringEngine (all format presets, deuce/no-ad,
  tie-breaks and match tie-breaks, doubles rotation and receivers, lets, faults, penalties, terminations, provisional
  scores, every conflict type, Rules vs As-played, supersede/void/undo chains, re-analysis never overwriting reviewed
  points), StatsEngine (the full Jon vs Alex fixture: 58%, 67%, 70%, 386 shots, BP invariants, `pct` vectors including
  1/8 → 13 and 0/0 → "—"), Units, CheckpointSolver, RallySegmenter, CourtCalibration and ServeSpeedEstimator (with
  tolerances), CompareSync, CapabilityRegistry (promotion only by benchmark record; derived-stat provenance is the
  weakest input), PracticePlanner (rules fire only above minimum samples, evidence ids correct, no sample mixing),
  ProgressAggregator (pooling, minimum samples, percentage-point deltas), EquipmentStore (logged court time, tension
  stored as entered), SessionStore (atomic write survives a simulated crash mid-write, index rebuild, migration,
  quarantine, trash/purge rules), DataExporter (schema-valid output).
- **ArchiveService against the fake Drive (macOS `swift test`, Linux where FoundationNetworking allows).** The fake
  implements generateIds, resumable sessions, `308` + `Range`, status queries, `404` session expiry, 5xx/429 backoff,
  `storageQuotaExceeded`, token refresh, `invalid_grant`, revoke, `appProperties` queries, size/MD5 metadata and ranged
  downloads. Tests mirror the research's archive acceptance checks that can run without Google: kill and resume at
  10/50/99% with no duplicate, expired session, quota block without a retry storm, revoked token → needs reconnect,
  reinstall finds the archive root, Wi-Fi-only policy, checksum mismatch never reaches `backedUp`, restore verifies, and
  "Awaiting setup" with no client ID. Real-Drive checks are listed as UNVERIFIED until the OAuth client exists.
- **JovraMedia on macOS with fixture media.** CaptureEngine through the fixture source (segments, journal, pause,
  interruption gaps, forced termination mid-segment then `RecoveryScanner` with decode-to-end validation, low-storage
  stop); ImportPipeline over a fixture suite (HEVC/H.264, 24–240 fps, portrait/landscape, HDR, an unsupported file, a
  duplicate); ClipExporter (start/end within ±1 frame of source timecodes, overlay score equals the fold at sampled
  frames, a correction changes the re-rendered overlay, audio stripped by default); PlaybackController (frame step and
  seek land on the exact frame of a frame-counter fixture at 60 and 240 fps); MediaLibrary (backup exclusion flag,
  refusal to remove an unverified original).
- **Synthetic-video benchmark (D8).** A repository script renders deterministic sample videos (perspective court,
  simple player figures, ball on physically plausible trajectories, hit clicks in the audio, injected camera nudges)
  with exact ground truth (hit times, bounces, rally boundaries, corners, camera moves, serve contact/bounce and true
  speed). The harness runs HitDetector, RallySegmenter, CameraMovedDetector, LineSnapper, CourtCalibration and
  ServeSpeedEstimator (with ground-truth marked frames), and writes a benchmark record (precision, recall, timing MAE,
  boundary F1 at ±1 s, kept-hit share, false alarms per hour, snap error, speed error) with method versions. Floors from
  the research gates apply to the synthetic band; a run below its floor fails CI and keeps or returns the capability to
  `disabled`. PoseEstimator is not benchmarked on synthetic figures and says so. Synthetic results never promote
  anything to `validated`.
- **XCUITest flows (simulator, run on the build Mac; evidence attached to the PR per ADR-0006).** One flow per screen
  and per auxiliary state family: onboarding (including cancelled Apple sign-in), demo entry and removal, setup →
  framing → fixture-camera recording → interruption → resume → stop → processing → library, live scoring with undo and
  checkpoints, replay correction propagating to the overview, Fast Point Review including VoiceOver custom actions,
  rally-only gaps, export, shot placement, Serve Lab speed estimate (and its unavailable state), Stroke Lab pose on
  demand, compare align/lock/nudge/draw/voice note, practice plan evidence, progress minimum-sample state, Racket Vault
  and restring, storage and archive states driven by the fake Drive (awaiting setup, connected, uploading, needs
  reconnect, quota blocked, verified), settings and permission states. Every screen runs `performAccessibilityAudit`
  (the foundation's documented tab-bar contrast exception only), checks 44 pt targets and runs at an accessibility
  text size and in dark mode. Named screenshots are attached and exported.
- **Screenshot comparison.** The 20 references are AI-generated rasters, so pixel diffs against them are meaningless.
  Instead: (1) copy assertions from `screens.json` (with the documented honesty corrections), (2) a side-by-side
  evidence page pairing each reference with the simulator screenshot for human review, and (3) once a screen is
  approved, perceptual-diff regression against our own approved screenshot.
- **Hardware phase (reported separately, not claimed by simulator runs).** Capture soak (≤ 3 s lost per crash, 0
  unrecoverable sessions, journal within one frame), interruptions of each kind, heat, low storage, rotation, network
  loss during upload, hands-free buttons and AirPods range, the Live Activity spike, iOS 18 device behaviour, real
  Google Drive, and real-court benchmarks for hit detection and segmentation.
- **Prior art in the repo.** The foundation ticket's `JovraSmokeUITests` (tab visits, 44 pt checks, accessibility audits,
  screenshot attachments), `ColorRoleContrastTests`, `AppRouterTests` and the JovraCore unit tests for provenance,
  frame rates and duration labels.

## Out of Scope

- **Analysis excluded by D10:** ball tracking and ball trails, automatic bounce/placement maps and depth bins, automatic
  stroke classification, automatic serve detection and automatic serve speed, AI point winners and auto-scoring, line
  calls or challenge verdicts, spin RPM, 3D pose and numeric biomechanics, injury, medical or arm-health claims, string
  tension measurement, string-life prediction and the acoustic pitch check, automatic compare contact-sync, on-device
  recap text.
- **Excluded by D11:** Google Picker import (P1-08), pricing and any paywall (P1-25; D2: no StoreKit, no ads in v1),
  Apple Watch app, Android (its own spec after the iOS gates), pickleball, padel, Mac app.
- **Backlog P2 (not in v1):** voice-over walkthrough export and transcription, practice instant-replay/delay loop,
  remote viewfinder from a second phone, "review the clip together" second-device viewer, UTR result copy, practice
  counters from audio hits, Lock Screen quick record (`LockedCameraCapture`).
- **Backlog Later:** two-phone multi-angle merge, automatic doubles player attribution and positioning, serve-target
  games with bounce localisation, ITF PAT approval, optional server analysis, rating integrations.
- **Never:** officiating claims, ads or cross-app tracking, default training-data sharing, locking or capping a user's
  own video, pro-player libraries or likenesses, dark-pattern pricing, live streaming, requiring upload before review,
  shipping Match Charting Project data or unlicensed competitor databases.
- **Other:** a JOVRA account or backend of any kind; equipment catalogs (D6); JOVRA Studio (references 21–40, separate
  prompt); App Store submission, signing and store listing (handled after the hardware gates).
- **Live Activity (P1-13) is in scope only as a spike-gated ticket**: if the spike shows the activity does not update
  while the app is foreground-recording, it is dropped from v1 and noted, not faked.

## Further Notes

### Lead decisions applied

| ID | Decision | Where it lands |
|---|---|---|
| D1 | iOS 18.0 target; iOS 26-only APIs behind availability; iOS 18 runtime UNVERIFIED locally | Architecture; new ADR superseding ADR-0005's target |
| D2 | No paywall, StoreKit or ads; all features free and local | Solution, Out of Scope |
| D3 | Drive via plain OAuth + PKCE, `drive.file`, xcconfig client ID, "Awaiting setup", fake-Drive tested | ArchiveService; departs from the research's GoogleSignIn/GTMSessionUploadFetcher suggestion by decision |
| D4 | "Shots" = racket contacts; Jon serves first; Point 42 at 12:46 is illustrative | StatsEngine, SampleContent |
| D5 | Mic optional, asked at first capture, never blocks; audio feeds detection; exports default to no audio | CaptureEngine, ClipExporter, stories 52, 90–91, 203 |
| D6 | Equipment user-entered only | EquipmentStore |
| D7 | Originals excluded from iCloud device backup by default; "Only on this iPhone" until archived | MediaLibrary, stories 15, 124, 324 |
| D8 | Synthetic sample video, labelled, doubles as benchmark fixture; coherent 124-point fixture | SampleContent, Testing |
| D9 | "Simulator fixture camera" through the same pipeline | FixtureCamera; drives the asset-writer decision in CaptureEngine |
| D10 | v1 analysis scope | CapabilityRegistry, HitDetector, CameraMovedDetector, PoseEstimator, ServeSpeedEstimator |
| D11 | All P0 and P1 except P1-08, P1-25; P1-13 spike-gated | User stories, Out of Scope |
| D12 | One PR per ticket, merged after required CI is green; simulator evidence on the PR | Testing |

### Interpretations the lead should confirm

1. **Hit detection and rally segmentation status.** D10 calls them "estimated, benchmark-gated". This spec ships them as
   `estimated` for the synthetic band with a CI regression floor, every output a reviewable suggestion, and the
   capability page stating that real-court accuracy is not yet measured. The research's real-footage gate (≥ 10
   sessions, ≥ 3 venues) remains the bar for any stronger claim.
2. **Line-snap assist** (part of P1-17) is not named in D10. It is included as an accept-or-ignore suggestion gated by
   its synthetic benchmark; if that fails it stays `disabled` and manual corner taps are unaffected.
3. **2D pose** ships as an on-demand `estimated` overlay without a benchmark (the research listed it as `disabled`
   until gated). D10 decides this; the capability page says "not benchmarked".
4. **Capture writer.** The asset-writer segment pipeline replaces the research's movie-file-output P0 choice so that D9
   holds; the fallback is kept for the device soak test.
5. **Sample video length.** The synthetic sample match video should cover the full 54:00 timeline at a low resolution
   and bitrate so every fixture point has video; if the bundled asset would exceed a size budget agreed in its ticket,
   ship an excerpt around Point 42 and show "Not in the sample video" for other points.

### Domain language (input for `GLOSSARY.md`)

Session (a recording or import plus its document) · Segment (one continuous media file) · Gap (a recorded absence
between segments, with a reason) · Journal (the write-ahead record of a recording) · Original (the captured or imported
media) · Derived cache (thumbnails, proxies, pose caches; always deletable) · Point event · Bookmark ("Mark point") ·
Checkpoint (as-called game score at a changeover) · Point candidate (an automatic suggestion) · Supersede / Void ·
Effective view · Match timeline · Provisional (later than an unknown outcome) · As-called vs rules-derived score ·
Rules mode / As-played mode · Conflict · Provenance (manual, estimated, reviewed, validated) · Capability and its status
(manual, estimated, validated, unsupported, disabled) · Sample · Facets (original, analysis, review, archive) · Archive,
Sidecar, Archive manifest · Space Saver · Share Pack · Rally-only playback · Fast Point Review · Practice suggestion and
evidence · Setup (racket + string job) · String job · Logged court time.

### Open spikes and external dependencies

- Google Cloud project, OAuth client (iOS), "In production" status, homepage and privacy policy on an
  `islanddevcrew.com` path, support address `hello@islanddevcrew.com` shown as text only — needed before real Drive use.
- `drive.file` permission creation for expiring Share Pack links (API spike).
- Live Activity visibility while foreground-recording (P1-13 spike).
- Background URLSession handling of Drive `308` responses (device check).
- AirPods stem-click range from the far baseline; volume/Action/Camera Control mapping on device.
- iOS 18 device behaviour for every `#available` fallback.
