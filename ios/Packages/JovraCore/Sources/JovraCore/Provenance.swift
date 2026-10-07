/// Where a displayed value came from (ADR-0004). Persisted as its lowercase raw value.
///
/// Sample/demo data is a separate concern: a value can be `estimated` *and* sample.
public enum Provenance: String, Codable, CaseIterable, Sendable {
    /// Entered by the player (manual scoring, manual tag).
    case manual
    /// Produced automatically by an analysis capability that has not been validated.
    case estimated
    /// An automatic result the player has checked or corrected.
    case reviewed
    /// Produced by a capability promoted to validated by a recorded benchmark run.
    case validated
}
