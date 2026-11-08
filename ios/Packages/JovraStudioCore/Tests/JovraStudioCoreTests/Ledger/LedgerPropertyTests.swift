import Foundation
import Testing
import JovraStudioCore

/// STU-04 acceptance 3: 1,000 seeded random sequences of reserves, top-ups, stage attempts, retries and redeliveries
/// never make a reservation exceed its cap and never charge a stage twice. The invariants are checked against the
/// test's own bookkeeping of what each call answered, not against the ledger's internals.
@Suite("Ledger: random retry and redelivery sequences")
struct LedgerPropertyTests {
    /// SplitMix64: a small, fully specified generator, so a seed reproduces a sequence on every platform.
    struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static let baseSeed: UInt64 = 0x0512_2026_1108
    static let sequences = 1_000
    static let hash = String(repeating: "b", count: 64)
    static let stages = ["normalizing", "syncing", "analyzing", "planning", "preview_rendering", "final_rendering", "verifying"]

    struct Summary {
        var operations = 0, replays = 0, topups = 0, charges = 0, releases = 0
        var rejections: [String: Int] = [:]
    }

    /// One accepted quote per cap; a story-2-3 quote whose cap is `cap` (>= 4) costs (cap - 1) * 800 000 + 1 µUSD.
    static func quote(_ id: String, cap: Int) -> Ledger.QuoteTerms {
        .init(quoteId: id, projectId: "p", planRevision: 1, outputSpecSha256: hash, filmClassId: "story-2-3",
              estimatedMaxCostMicroUsd: (cap - 1) * 800_000 + 1, estimateMinCredits: 1, estimateMaxCredits: 4, capCredits: cap,
              expiresAt: "2026-10-07T23:15:00Z")
    }

    @Test("1,000 seeded sequences: reserved never exceeds the cap, no stage is charged twice, credits are conserved")
    func randomSequencesKeepTheInvariants() throws {
        var summary = Summary()
        for index in 0..<Self.sequences {
            let seed = Self.baseSeed &+ UInt64(index)
            try Self.run(seed: seed, summary: &summary)
        }
        print("Ledger property test: base seed 0x\(String(Self.baseSeed, radix: 16)), \(Self.sequences) sequences, "
              + "\(summary.operations) operations, \(summary.replays) replays, \(summary.charges) stage charges, "
              + "\(summary.topups) top-ups, \(summary.releases) releases; rejections \(summary.rejections.sorted { $0.key < $1.key })")
        #expect(summary.replays > 0 && summary.topups > 0 && summary.charges > 0 && summary.rejections["budgetExceeded", default: 0] > 0)
    }

    static func run(seed: UInt64, summary: inout Summary) throws {
        var rng = SplitMix64(state: seed)
        let start = Int.random(in: 4...40, using: &rng)
        var ledger = try Ledger(environment: .test, balance: start, classes: LedgerVectors.classes, jobContract: LedgerVectors.transitions)
        let caps = [4, 6, 9, 12]
        for (i, cap) in caps.enumerated() {
            try ledger.addQuote(quote("q-\(i)", cap: cap))
            try ledger.accept(quoteId: "q-\(i)", at: "2026-10-07T22:50:00Z", consent: true)
        }
        var applied: [(quoteId: String, credits: Int)] = []   // reserve and top-up requests the ledger applied
        var charged: [String: Int] = [:]                     // stage -> credits of its one charge
        var rid: String?
        for _ in 0..<Int.random(in: 4...30, using: &rng) {
            summary.operations += 1
            do {
                switch Int.random(in: 0..<10, using: &rng) {
                case 0...1:   // reserve: a fresh request, or a redelivery of one already applied
                    let (q, credits) = applied.isEmpty || Bool.random(using: &rng)
                        ? ("q-\(Int.random(in: 0..<caps.count, using: &rng))", Int.random(in: 0...13, using: &rng))
                        : applied.randomElement(using: &rng)!
                    let r = try ledger.reserve(quoteId: q, projectId: "p", planRevision: 1, outputSpecSha256: hash, credits: credits,
                                               at: "2026-10-07T22:51:00Z", jobId: "job")
                    if r.replayed { summary.replays += 1 } else { applied.append((q, credits)); rid = r.reservationId }
                case 2...3:   // top-up: a fresh request, or a redelivery
                    guard let id = rid else { continue }
                    let (q, credits) = applied.count < 2 || Bool.random(using: &rng)
                        ? ("q-\(Int.random(in: 0..<caps.count, using: &rng))", Int.random(in: 0...13, using: &rng))
                        : applied.randomElement(using: &rng)!
                    let r = try ledger.topup(reservationId: id, quoteId: q, credits: credits, at: "2026-10-07T22:58:00Z")
                    if r.replayed { summary.replays += 1 } else { applied.append((q, credits)); summary.topups += 1 }
                case 4...8:   // a stage attempt succeeded (first time, retry, or a redelivered message)
                    guard let id = rid else { continue }
                    let stage = stages.randomElement(using: &rng)!
                    let credits = charged[stage] ?? Int.random(in: 0...3, using: &rng)
                    let r = try ledger.consume(reservationId: id, jobId: "job", stage: stage,
                                               attempt: Int.random(in: 1...3, using: &rng), credits: credits)
                    if r.replayed {
                        summary.replays += 1
                        #expect(charged[stage] == credits, "seed \(seed): \(stage) replayed without an earlier charge")
                    } else {
                        #expect(charged[stage] == nil, "seed \(seed): \(stage) charged twice")
                        charged[stage] = credits
                        summary.charges += 1
                    }
                default:      // the job ends
                    guard let id = rid, Int.random(in: 0..<4, using: &rng) == 0 else { continue }
                    _ = try ledger.release(reservationId: id, outcome: Ledger.Outcome.allCases.randomElement(using: &rng)!)
                    summary.releases += 1
                }
            } catch let rejection as LedgerRejection {
                summary.rejections[rejection.code.rawValue, default: 0] += 1
            }
            try check(ledger, seed: seed, start: start, charged: charged)
        }
    }

    static func check(_ ledger: Ledger, seed: UInt64, start: Int, charged: [String: Int]) throws {
        #expect(ledger.reservations.count <= 1, "seed \(seed): one key, one reservation")
        var held = 0
        for r in ledger.reservations.values {
            #expect(r.reservedCredits <= r.capCredits, "seed \(seed): reserved \(r.reservedCredits) > cap \(r.capCredits)")
            #expect(r.reservedCredits <= 12, "seed \(seed): reserved above the largest accepted cap")
            #expect(r.consumedCredits <= r.reservedCredits, "seed \(seed): consumed above the reservation")
            #expect(r.consumedCredits == charged.values.reduce(0, +), "seed \(seed): consumed differs from the stage charges answered")
            held += r.reservedCredits - r.releasedCredits
        }
        #expect(ledger.balance >= 0 && ledger.balance + held == start, "seed \(seed): credits not conserved")
    }
}
