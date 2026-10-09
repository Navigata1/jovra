# Native receipt custody

Readable logs, counts, screenshots, and SHA-bound review are committed here. Raw xcresult archives are retained locally in this same isolated review worktree and intentionally excluded from Git to avoid adding a 1 GB diagnostic archive.

- `xcresults.tar.gz`: 19 baseline/diagnostic/interrupted receipts; SHA-256 `b92b2502b58405898272665ce4b3e06e248925d4045eaa38c2db7ef184ef0ebd`.
- `xcresults-final.tar.gz`: two final Passed receipts, seven tests; SHA-256 `ee7abbbfcaea2852fbc0f11c5c9302d3708844bcd9da332b4d15e38c43151342`.

Both archives were read fully with Python tarfile and their members verified before deleting only owned derived data. Their JSON manifests are committed. Dedicated simulator 4265ADFD-39A3-4E71-8482-1945DDB5F899 is retained shut down; other projects’ simulators/caches were untouched.
