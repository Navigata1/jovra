import Foundation
import JovraCore

/// The record rules of a stored `jovra.usage-reservation/1` beyond its schema (`ledger.check_reservation_record`).
///
/// Totals equal the entries; entry keys are unique and tied to this record (finding 5): reserve keys are the record's
/// own `reserve:<projectId>:<planRevision>:<outputSpecSha256>` (one initial entry, first) or that key plus
/// `:topup:<quoteId>`, where a top-up quote is neither `initialQuoteId` nor one an earlier top-up used; consume keys are
/// `consume:<jobId>:<charged stage>:<attempt>` with the record's job and a stage spelled exactly as the job contract
/// does, charged once whatever the attempt; release keys are `release:<jobId>:<outcome>` matching the status; every
/// key's prefix is its entry kind. The cap holds, closed reservations account for every credit, the demo holds zero,
/// demo and test are Sample, and live is refused.
public enum ReservationRecordRules {
    private static let releaseOutcome: [UsageReservationStatus: String] = [.settled: "ready", .released: "failed", .canceled: "canceled"]

    public static func check(_ record: UsageReservation, chargedStages: Set<String>) throws(LedgerRejection) {
        typealias R = LedgerRejection
        try R.require(record.reservedCredits <= record.capCredits, .overCap, "reserved credits exceed the cap")
        var totals: [UsageReservationEntryKind: Int] = [.reserve: 0, .consume: 0, .release: 0]
        var seen: Set<String> = []
        var charged: Set<[String]> = []
        var topups: [String] = []
        for (index, entry) in record.entries.enumerated() {
            try R.require(!seen.contains(entry.key), .idempotencyConflict, "duplicate entry key \(entry.key)")
            seen.insert(entry.key)
            totals[entry.kind, default: 0] += entry.credits
            if let jobStage = try checkEntryKey(record, entry, chargedStages: chargedStages, topups: &topups, index: index) {
                try R.require(!charged.contains(jobStage), .idempotencyConflict,
                              "stage \(jobStage[1]) of \(jobStage[0]) is charged once, whatever the attempt")
                charged.insert(jobStage)
            }
        }
        try R.require(record.entries.first?.kind == .reserve, .badEntryKey, "a reservation starts with its reserve entry")
        try R.require(record.entries.filter { $0.kind == .release }.count <= 1, .badEntryKey, "one release per reservation")
        if let last = topups.last {
            try R.require(record.quoteId == last, .badEntryKey, "after a top-up, quoteId names the newest quote")
        } else {
            try R.require(record.quoteId == record.initialQuoteId, .badEntryKey,
                          "without a top-up, quoteId is the quote that funded the initial hold")
        }
        try R.require(totals[.reserve] == record.reservedCredits && totals[.consume] == record.consumedCredits
                      && totals[.release] == record.releasedCredits, .ledgerMismatch, "entry totals differ from the record")
        try R.require(record.consumedCredits + record.releasedCredits <= record.reservedCredits, .budgetExceeded,
                      "consumed plus released exceeds the reservation")
        if record.status == .held {
            try R.require(record.releasedCredits == 0, .ledgerMismatch, "a held reservation has released nothing")
        } else {
            try R.require(record.consumedCredits + record.releasedCredits == record.reservedCredits, .ledgerMismatch,
                          "a closed reservation accounts for every reserved credit")
        }
        if record.environment == .demo {
            try R.require(record.reservedCredits == 0, .demoNeverReserves, "demo reservations hold zero credits")
        }
        if record.environment != .live {
            try R.require(record.sample, .sampleRequired, "demo and test reservations are Sample")
        }
        try R.require(record.environment != .live, .liveChargingNotActivated, "no live reservation before its ADR")
    }

    /// Ties one entry's key to its record; returns `[jobId, stage]` for a consume entry.
    private static func checkEntryKey(_ record: UsageReservation, _ entry: UsageReservationEntry, chargedStages: Set<String>,
                                      topups: inout [String], index: Int) throws(LedgerRejection) -> [String]? {
        typealias R = LedgerRejection
        let parts = entry.key.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        try R.require(parts[0] == entry.kind.rawValue, .badEntryKey, "\(entry.key): a \(entry.kind.rawValue) entry is keyed \(entry.kind.rawValue):...")
        switch entry.kind {
        case .reserve:
            let k = record.idempotencyKey
            let own = ["reserve", k.projectId, String(k.planRevision), k.outputSpecSha256]
            try R.require(k.projectId == record.projectId, .badEntryKey, "the idempotency key names another project")
            try R.require(Array(parts.prefix(4)) == own && (parts.count == 4 || (parts.count == 6 && parts[4] == "topup")),
                          .badEntryKey, "\(entry.key): reserve keys are the record's own key \(own.joined(separator: ":")), or that key plus :topup:<quoteId>")
            if parts.count == 4 {
                try R.require(index == 0, .badEntryKey, "the one initial reserve entry is the first entry; a retried reserve "
                              + "replays, it never writes a second hold under another key")
            } else {
                try R.require(index > 0 && !topups.contains(parts[5]) && parts[5] != record.initialQuoteId, .badEntryKey,
                              "\(entry.key): one top-up per accepted quote, never the quote that funded the initial hold (\(record.initialQuoteId))")
                topups.append(parts[5])
            }
            return nil
        case .consume, .release:
            let job = record.jobId.value
            try R.require(job != nil && parts.count >= 3 && parts[1] == job, .badEntryKey,
                          "\(entry.key): \(entry.kind.rawValue) entries name this reservation's job \(job ?? "null")")
            if entry.kind == .consume {
                try R.require(parts.count == 4 && chargedStages.contains(parts[2]) && isAttempt(parts[3]), .badEntryKey,
                              "\(entry.key): consume keys are consume:<jobId>:<charged stage>:<attempt>")
                return [parts[1], parts[2]]
            }
            try R.require(parts.count == 3 && parts[2] == releaseOutcome[record.status], .badEntryKey,
                          "\(entry.key): release keys are release:<jobId>:<outcome> and match the status \(record.status.rawValue)")
            return nil
        }
    }

    /// `[1-9][0-9]{0,3}`.
    private static func isAttempt(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        guard let first = bytes.first, (49...57).contains(first), bytes.count <= 4 else { return false }
        return bytes.allSatisfy { (48...57).contains($0) }
    }
}
