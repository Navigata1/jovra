# Auxiliary flows and implementation states

The twenty images establish the visual spine. Implement these sheets/routes using the same design system; they are not additional generated reference images.

| Parent | Required supplementary behavior |
|---|---|
| Welcome/onboarding | Returning sign-in, cancelled/failed Apple sign-in, guest/demo exit, editable profile and goals. |
| Setup | Player editor, match format/rules, doubles positions, racket selector, supported camera presets. |
| Calibration | Camera denied, open iOS Settings, no camera/simulator fixture, unclear corners, unsuitable angle, low light, low disk space. |
| Recording | Stop confirmation, interruption, segment saved/recovery, thermal reduced capability, low battery/storage, manual score undo, bookmark note. |
| Import/queue | Selected Photos/Files picker, unsupported codec/resolution, partial import, duplicate handling, cancelled task, failed analysis, retry, offline. |
| Library | Empty library, search no results, restored archive, archived-only download, delete-to-trash with undo and explicit original retention. |
| Match/replay | Point/shot editor, full-video timeline, unknown events, recalculation indicator, annotation drawing mode, clip range and export share sheet. |
| Shot/serve/stroke labs | No detected data, manual evidence, unknown confidence, outliers, calibration missing/invalid, visible estimated vs reviewed status. |
| Comparison | Select second personal video, missing file, align timecodes, saved draw/voice-note state, landscape adaptation. |
| Drills/progress | Edit plan, evidence unavailable, too few comparable sessions, filter by session type, units, goal completion. |
| Racket/strings | Add/edit frame, restring form, string inventory, gauge and units, mains/crosses, date, optional machine/method, note/photos, session association. |
| Archive | OAuth cancelled/expired/revoked, no quota, interrupted upload, resume/retry, checksum/integrity validation, export originals + JSON, storage retention editor, disconnect. |
| Settings | Camera/mic/Photos status, system Settings redirect, units/appearance, notification opt-in only when needed, accessibility, diagnostics consent, data export, deletion confirmation, recording help. |
| Optional future plan | Pricing remains a product decision. If subscriptions are added, use StoreKit: transparent paywall, exact billing/trial terms, restore purchases, entitlement states, management link and offline behavior. |
| Optional future Watch | Pairing/permission/camera-preview reliability and watch score/bookmark screens need separate wearable references and physical Watch QA. Not required for phone recording. |

Camera and Photos dialogs are system-owned. Permission screens explain the action; they do not replace Apple's UI. Recording requires foreground camera access; background archive work is separate.

Accessibility and production target:
- Dynamic Type without truncated controls; VoiceOver reading order and descriptive icon labels.
- Minimum 44-point touch targets; 4.5:1 normal-text contrast target, with large-text exceptions applied correctly.
- Chart legends, shapes and text supplement color; units explicit; trends show denominators.
- Reduce Motion and system appearance work; video playback supports captions where there is speech.
- Delete/export and original-retention controls describe exactly which data/location they affect.

Raster-reference limitations:
- Exact copy comes from screens.json and the build prompt.
- Court geometry is drawn from real court dimensions/rules, not generated photo markings.
- The Home concept's chart is a composition reference; reconstruct from actual data. Use “percentage points” for rate changes.
- A sample 3.2 GB storage estimate cannot be hardcoded into the product.
- The comparison uses two own-recording examples, not licensed professional footage.

