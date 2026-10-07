# JOVRA Studio reference and Claude handoff

Open `index.html` for the combined 40-screen collection. It includes the original 20 JOVRA Tennis screens, 20 new Studio screens, a top-ten Studio filter, enlarged reference viewing, five film styles and links to the handoff.

Keep the extracted folder structure intact: the combined gallery loads its images from the adjoining `screens/` folders. `standalone-studio-20.html` embeds all 20 new Studio images and can be viewed on its own. Its document links still require the rest of the pack.

Give Claude `docs/handoff/CLAUDE-STUDIO-EXPANSION-PROMPT.md` from the root of this handoff, together with the screenshots and briefs. It expands the existing JOVRA foundation without overwriting the native app or its prior decisions. The original Claude prompt is also included under `docs/handoff/`.

The five stories are Coach’s Cut, Match Broadcast, Rally Pulse, Progress Story and Court Memories. References cover independent one-to-six-phone capture, import, synchronization, alternate-angle replay, lessons, progress, source-linked editing, optional cloud processing, costs, private delivery, YouTube preparation and storage/privacy settings.

Read `JOVRA-Studio-Research-v1-2026-10-07.html` for the evidence and proposed architecture. `brief/backend-media-design.md` covers Supabase identity/metadata, private R2 media, authorization, separate render workers, budget controls and integration stages. `brief/implementation-states.md` defines recovery and unavailable/demo behavior beyond the pictured states.

The attached video suite was inspected as source material. All 17 archive files and the landing HTML are retained unchanged under `sources/`, with hashes. Its instructions were not executed. The separate existing local editor was inspected read-only; that editor’s implementation and approved media are not copied into this archive.

These are generated visual targets. Pictured people, footage, metrics, jobs, quotes and connections are illustrative. No JOVRA backend, multi-camera engine, paid job, film export or YouTube upload was activated in this task. The actual old tennis match was not included in the attachments; it is still needed for end-to-end media testing. A single old match cannot validate six-camera synchronization.

Validation is recorded in `brief/verification.json`. Image hashes are in `asset-manifest.json`; prompts and edits are in `brief/image-prompts.json`. The optional standard-library builder is `docs/handoff/build-studio-reference-pack.py`; run it from the extracted handoff to regenerate the galleries and report.
