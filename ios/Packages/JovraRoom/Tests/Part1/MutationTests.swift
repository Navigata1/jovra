import Foundation
import JovraRoom
import XCTest

/// The mutations the issue names must fail. Each test hands the fixture runners a deliberately broken rule and
/// requires the fixtures to catch it with the named cases. (Source-level mutations of the package itself are run by
/// scripts/ios/room-mutations.sh; their transcripts are the PR evidence.)
final class MutationTests: XCTestCase {
    /// Fresh threshold moved from 5 s to 6 s.
    func test_freshThresholdOf6SecondsIsCaught() throws {
        let mutated = FreshnessPolicy(freshMaxMs: 6000, delayedMaxMs: 15000)
        let (_, failures) = try VectorRunners.freshness { VectorRunners.classify($0, policy: mutated) }
        XCTAssertTrue(failures.contains { $0.contains("#delayed-just-over") }, "\(failures)")
        XCTAssertTrue(failures.contains { $0.contains("#delayed-by-watch-time") }, "\(failures)")
    }

    /// An unbounded (queued) transit treated as if it had been bounded by zero.
    func test_unboundedTransitTreatedAsBoundedIsCaught() throws {
        let (_, freshnessFailures) = try VectorRunners.freshness { input in
            let forced = VectorRunners.FreshnessInput(senderAgeMs: input.senderAgeMs, sinceAcceptMs: input.sinceAcceptMs,
                                                      transitBounded: true, baselineValid: input.baselineValid,
                                                      transitMs: input.transitMs ?? 0)
            return VectorRunners.classify(forced, policy: .proposal)
        }
        XCTAssertTrue(freshnessFailures.contains { $0.contains("#queued-arrives-now") }, "\(freshnessFailures)")
        let (_, phoneFailures) = try VectorRunners.phoneStatus { observation in
            var forced = observation
            forced.transitBounded = true
            forced.transitMs = observation.transitMs ?? 0
            return forced
        }
        XCTAssertTrue(phoneFailures.contains { $0.contains("#phone-queued") }, "\(phoneFailures)")
    }

    /// A clock that stops while the device sleeps under-states age: a camera last heard 1 s before a 20 s sleep reads
    /// Fresh instead of Unknown. The continuous clock gets it right; the sleeping fake is caught by the same check.
    func test_aClockThatStopsDuringSleepIsCaught() throws {
        XCTAssertEqual(try ageAfterSleep(clock: FakeDeviceClock(countsDuringSleep: true)), .unknown)
        XCTAssertNotEqual(try ageAfterSleep(clock: FakeDeviceClock(countsDuringSleep: false)), .unknown,
                          "the fake must actually under-state age, or this test proves nothing")
    }

    /// Accept a report that is 1 s old over a 40 ms bounded transit, sleep 20 s, read it back.
    private func ageAfterSleep(clock: FakeDeviceClock) throws -> Freshness {
        let receiver = FreshnessClock(clock: clock, baselineId: "pb-sleep-test")
        let observation = receiver.accept(transitMs: 40)
        clock.sleep(milliseconds: 20_000)
        return try receiver.read(senderAgeMs: 1000, observation).freshness
    }
}

/// A device clock for tests: time advances only when told to, and optionally pauses while the device sleeps (the
/// behaviour of `mach_absolute_time` / `SuspendingClock`).
final class FakeDeviceClock: MonotonicClock, @unchecked Sendable {
    private let lock = NSLock()
    private var now = 0
    let countsDuringSleep: Bool

    init(countsDuringSleep: Bool) { self.countsDuringSleep = countsDuringSleep }

    func nowMs() -> Int {
        lock.lock(); defer { lock.unlock() }
        return now
    }

    func advance(milliseconds: Int) {
        lock.lock(); defer { lock.unlock() }
        now += milliseconds
    }

    func sleep(milliseconds: Int) { if countsDuringSleep { advance(milliseconds: milliseconds) } }
}
