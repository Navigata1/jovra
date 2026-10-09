# ClipExporter preliminary independent Standards axis

Read-only working snapshot in implementation/clip-export at HEAD35117e198de141da1c723ed20d7c5c8c06945ad5 plus new exporter/tests, before pending runtime acceptance. Source/test hashes below bind the inspected contents; an evolving source requires rebind.

Zero documented-standard violations or actionable Fowler findings. Local composition, exact CMTime ranges, default audio exclusion, transform preservation, empty metadata, no-overwrite staging, decode-to-end before publication and post-publication directory flush are coherent boundaries. ClipExportJob's small unchecked-Sendable wrapper documents AVFoundation cross-thread cancellation and shares no further mutable configuration. Public tests use actual decoded counter/audio fixtures and preservation controls. No first-PTS, cancellation, frame-selection or runtime acceptance is implied by this Standards-only source review. SPEC belongs to domain_core.

ios/Packages/JovraMedia/Sources/JovraMedia/Export/ClipExporter.swift: SHA256 dacdae23b6121661312868e5667a0a3d24f268d0010686e9a0f2202682879f0c
ios/Packages/JovraMedia/Tests/JovraMediaTests/Export/ClipExporterTests.swift: SHA256 5e8ad6ffaa55e9901b37e9b05739eeafa0d93e4c1c7d896ee7283cafa2d9d2a0

## Final committed rebind

Standards ACCEPT exact `c41d7b876f418fcc6e3b82012f713f9162a9c491` vs merged directory base `3ae5caa2bb2cff78e9d9b76b9a28a092faf54cf6`. Production exporter remains SHA256 `dacdae23b6121661312868e5667a0a3d24f268d0010686e9a0f2202682879f0c`, byte-identical to the initial independent source review. Read the committed 104-line public test suite, including the actual FixtureCamera→writer→export range proof. The corrected test compares 30 decoded frames and one-second output duration instead of relying on an AVFoundation track-start assumption; retained red evidence makes that correction inspectable. Zero documented-standard violations and zero actionable Fowler findings in the final source/test diff. No local build or runtime acceptance performed by this reviewer; final directory-composed Media runtime is pending its owner gate. Full T36 remains outside this bounded local single-range exporter slice.
