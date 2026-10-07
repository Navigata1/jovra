# Local-first document store; Google Drive is an optional archive

Every session is a folder in the app's protected storage holding the original media plus a versioned JSON
`session.json` document (players, format, points, shots, calibration, annotations, provenance) and small derived
caches. Writes are atomic (write-temp-then-rename). A lightweight library index is rebuilt from the folders if it is
ever missing, so the folder is the source of truth. The same JSON (schema in `spec/schemas/`) is the Drive sidecar and
the export format, which keeps archive, export and the Android port on one shape.

## Considered Options

- SwiftData / Core Data: fast queries, but a binary store that the Android app and the Drive archive cannot share,
  and harder to recover by hand. Session counts are in the hundreds, so an in-memory index over JSON is ample.
- SQLite (GRDB/Room): reasonable; rejected for v1 to avoid two schemas (SQL + JSON) for the same records.
- A JOVRA cloud account/backend: out of scope for v1. No server, no JOVRA account, no analytics upload by default.
