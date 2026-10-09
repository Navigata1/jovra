# Bounded DataExporter and sample conformance

Public seam: DataExporter.exportSession(SessionDocument) returns one coherent in-memory SessionDataExport with canonical sessionJSON, pointsCSV and statsCSV produced from one fresh fold. The first public test compares the sample CSV bytes with independent committed goldens and preserves the typed session document. No implementation precedes its actual missing-API red.

CSV contracts are typed, byte-identical SwiftPM resources. Runtime uses Bundle.module, not repository paths. Their column/row order, delimiter, null/boolean spelling and LF/minimal quoting govern the renderer. A convention-discovered SampleRunner compares complete fold/stats plus both CSV goldens and consumes the final pending kind. Emitted session JSON is schema/canonical-checked by the independent reference validator. Data bundles, Share Pack assembly, trends and richer stat diffs remain pending; no Studio/backend/native UI/device claim.
