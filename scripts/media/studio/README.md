# Studio media fixtures (S08)

Generated frame-truth media for JOVRA Studio's renderers and FilmVerifier: barcode and click sources at 24, 30 and
60 fps (plus a restarted two-segment capture and a no-audio file), the coherent synthetic match with barcode and click
tracks, short B-roll and six angle-labelled renders of the match sample for the ST27 demo. The design, the barcode
and click formats, the manifests and what is checked live on the module page:
[`spec/studio/modules/media-fixtures.md`](../../../spec/studio/modules/media-fixtures.md).

```sh
python3 scripts/media/studio/render_studio.py            # render into .cache/media/studio, write spec/studio/fixtures/media
python3 scripts/media/studio/render_studio.py --check    # verify every file; fail unless the committed manifests reproduce
python3 scripts/media/studio/reader.py FILE --manifest spec/studio/fixtures/media/barcodeSources/bc-030.json
python3 scripts/media/studio/install_demo.py             # bundled demo subset -> ios/Jovra/Resources/StudioSampleMedia
python3 scripts/media/studio/check_added_binaries.py     # no media committed outside the bundled subset
python3 -m unittest discover -s scripts/media/studio -p 'test_*.py' -v
```

Needs ffmpeg with libx264 (`brew install ffmpeg`, `apt-get install ffmpeg`) and Python 3.10+ standard library only.
It builds on the core renderer in `scripts/media/` (T10, T11) and never edits it: editing anything there, or in
`jovra_studio_media/`, changes the source hash and re-renders the affected sets. Media is never committed; this
folder is not a Python package, so the core `unittest discover -s scripts/media` run does not pick these tests up
(the Studio workflow's `studio-media` job runs them).

| File | Role |
|---|---|
| `render_studio.py` | the generator CLI: render, verify (full decode: barcodes, clicks, decoded signature), write manifests |
| `reader.py` | read frame ids from barcodes (also through a scaled or letterboxed picture) and check burned-in labels |
| `install_demo.py` | copy the bundled demo subset into the app's resources within its 25 MB budget |
| `check_added_binaries.py` | list the binary files a branch adds; fail on media outside the bundled subset |
| `jovra_studio_media/barcode.py`, `clicks.py`, `badge.py` | the barcode codec, the 1 kHz click codec, the angle-name banner |
| `jovra_studio_media/model.py`, `manifest.py`, `pipeline.py` | Studio clips over core clips, the manifest plan and hashes, render and verify |
| `jovra_studio_media/sets/` | `barcode_sources.py`, `match.py`, `broll.py`, `angles.py` (discovered by file name) |
