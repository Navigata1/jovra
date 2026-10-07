# Research and product decisions
Observed: October 7, 2026. Scope: three selected US App Store listings, visible screenshot previews, selected reviews, release notes and primary storage/capture documentation. This is a focused comparison, not an exhaustive census of every tennis application or a hands-on test of competitors.

## Competitor comparison

| Application | Observed US rating | What to learn | Friction to design around |
|---|---|---|---|
| SwingVision | 4.7/5, about 4.9K ratings | Match/shot navigation, placement views and automatically shortened replay. | Selected 2024 reviews describe scoring correction difficulty. Recent release notes describe recording, heat and sync fixes. |
| SevenSix | 4.2/5, 68 ratings | A focused technique workflow, visual swing review and player progress. | A 2025 review reports camera retry trouble; older reviews report stalled analysis and lost capture. |
| Onform | 4.8/5, about 8.7K ratings in live browser | Two-video comparison, frame tools, voice-over and organization. | A 2022 review describes confusing capture navigation and scrubber/drawing conflicts. It is a multi-sport tool, not an equivalent automatic tennis match tracker. |

**SwingVision:** its listing advertises single-camera match stats, highlights, scoring and line calling. Preserve fast access to points and shots; add visible manual correction and uninterrupted full-video scrubbing. Ratings and selected complaints are user reports, not measured failure rates. A developer response documents an Edit Point correction path, so the conclusion is discoverability/reliability risk rather than proof that correction does not exist. [US App Store listing, reviews and release notes](https://apps.apple.com/us/app/swingvision-tennis-pickleball/id989461317).

**SevenSix:** its listing presents recorded-stroke analysis, visual feedback and progress. Preserve the focused technique journey; make repeat capture and analysis recovery visible. The indexed listing still mentioned an AI assistant, while version 4.0.1 notes said it was removed. The live browser showed version 4.0.2 and technique-focused copy. Do not assume a currently available chat coach from stale indexed marketing. [US App Store listing](https://apps.apple.com/us/app/sevensix-tennis-ai-coach/id1505604446).

**Onform:** its listing includes slow motion, markup, comparison, voice-over and shared feedback. Positive reviews value comparison and coaching organization. An older negative review identifies frame-scrubbing friction. Make Record globally reachable, give frame steps stable controls and keep Draw a deliberate mode. These are design lessons, not a claim that historical complaints remain unresolved. [US App Store listing](https://apps.apple.com/us/app/onform-video-analysis-app/id1490334045).

## Screenshot observations

The App Store screenshot previews were visually inspected in the browser. SwingVision uses vivid green promotional panels and video/placement demonstrations. SevenSix uses orange technique and capture messaging. Onform uses yellow multi-sport comparison/analysis framing. JOVRA uses original forest/ivory screens and court photography, with no copied page layouts, logos or promotional screenshots. The comparison is about useful workflows.

## Storage decision

| User value | Local originals | Google Drive archive | Private object storage + worker |
|---|---|---|---|
| Immediate court capture without internet | Best foundation | Network-dependent archive | Network-dependent analysis path |
| User ownership/export | Original file directly available | Familiar user-owned files | Requires clear export and deletion implementation |
| Simple personal setup | No cloud connection needed | Optional existing Google account | Provisioning, billing and operational responsibility |
| Analysis computation | On-device validated capabilities | Drive is file storage, not a tennis engine | Suitable for a separately built async inference service |
| Recommendation | Foundation | Optional archive connector | Later, only if analysis feasibility requires it |

Google documents resumable uploads for larger files and interrupted mobile networks. JOVRA should maintain a durable archive queue and verify provider completion before reporting Backed up. [Google upload documentation](https://developers.google.com/workspace/drive/api/guides/manage-uploads).

Prefer the narrow drive.file scope for files created or explicitly selected through the app rather than blanket full-Drive access. Arbitrary library access is not implied by this scope. Validate the chosen picker/native OAuth implementation. [Google Drive scope guidance](https://developers.google.com/workspace/drive/api/guides/api-specific-auth).

For optional server analysis, use a separate private storage and asynchronous worker. Expiring upload access is one available pattern; provider integration remains unimplemented. [Amazon S3 presigned uploads](https://docs.aws.amazon.com/AmazonS3/latest/userguide/PresignedUrlUploadObject.html).

## iOS architecture recommendation

Proposed: SwiftUI, AVFoundation capture, AVPlayer review, structured local persistence, and Vision/Core ML only for capabilities established by a real benchmark. Native capture preserves control over video configuration and interruptions. This is a design recommendation, not a tested implementation. [Apple AVCam sample](https://developer.apple.com/documentation/avfoundation/avcam-building-a-camera-app), [Apple body-pose detection](https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-images).

A pose API alone does not establish ball tracking, precise 3D form, spin measurement, reliable speed or tournament line calls. Give each proposed analysis feature its own labeled-footage feasibility gate.

## Findings and contrary checks

- Confirmed source observation: selected reviewers report recording/replay friction. Contrary check: dates are historical and current release notes show fixes. Result: use them to motivate resilience tests, not to claim current competitors are broken.
- Confirmed source disagreement: SevenSix indexed assistant marketing disagrees with removal notes and the live technique listing. Result: avoid claiming a current assistant.
- Unverified: any objective accuracy superiority of JOVRA, any trained model, on-court capture quality, brand availability or operating cost. No such claim drives this brief.
- Preserved strengths: point-based video review; focused stroke feedback; comparison/annotation; organized libraries.

## Baseline to build gate

| Dimension | Current observed baseline | Required future evidence |
|---|---|---|
| Product | Workspace had no application source at inspection | Runnable app with all reference routes and real persistence |
| Recording | Reference concept only | Physical iPhone sustained capture, interruption and low-storage recovery |
| Analysis | No model or labeled benchmark | Held-out footage with capability-specific accuracy, failure rates and confidence |
| Archive | No connected integration | Interrupted/restarted upload and verified playable restore |
| UI | 20 generated reference images | Native screenshots plus accessibility, small-device and landscape checks |
| Android | No Android implementation | Android build/emulator checks, then Pixel capture/recovery tests |

## Sequencing

P0: local capture, import and replay; manual scoring and recovery.
P1: correction, export, equipment and strings; optional Drive archive.
P2: validate individual automatic-analysis capabilities and link drills to evidence.
P3: device/accessibility/performance gates; then Android.

The screen pack is complete when its files and handoff are verified. Application readiness belongs to the later build and device-validation work.

