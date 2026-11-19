import Foundation
import Testing
@testable import JovraCore

/// T21: the storage need is always a range computed from the preset's bitrate and the planned length,
/// judged against free space (screens.md S04 and N8).
struct StorageEstimatorTests {
    /// 1080p · 60 fps in the documented table: 90 MB per minute, 12 Mbit/s.
    static let bitRate = 12_000_000

    @Test func oneHourAtTwelveMegabitsIsTheStatedRange() {
        let range = StorageEstimator.range(bitRate: Self.bitRate, plannedSeconds: 3_600)
        // Nominal 5.4 GB; low = 0.85 ×, high = 1.2 ×: the "4.6–6.5 GB for 1 h" of the screen spec.
        #expect(range == 4_590_000_000...6_480_000_000)
    }

    @Test func theRangeScalesWithLengthAndBitrateWithoutFloatingPoint() {
        #expect(StorageEstimator.range(bitRate: 8_000_000, plannedSeconds: 1_800) == 1_530_000_000...2_160_000_000)
        #expect(StorageEstimator.range(bitRate: 4_000_000, plannedSeconds: 60) == 25_500_000...36_000_000)
        #expect(StorageEstimator.range(bitRate: 0, plannedSeconds: 3_600) == 0...0)
        #expect(StorageEstimator.range(bitRate: Self.bitRate, plannedSeconds: -5) == 0...0)
    }

    @Test func amplFreeSpaceIsReady() {
        let estimate = StorageEstimator.estimate(bitRate: Self.bitRate, plannedSeconds: 3_600, freeBytes: 231_000_000_000)
        #expect(estimate.bytes == 4_590_000_000...6_480_000_000)
        #expect(estimate.freeBytes == 231_000_000_000)
        #expect(estimate.verdict == .ready)
        // 231 GB ÷ (1.5 MB/s × 1.2) = 128,333 s: about 35 h 38 min.
        #expect(estimate.fitsSeconds == 128_333)
    }

    @Test func lessThanThePlannedLengthIsAWarningThatSaysHowMuchFits() {
        // Exactly 38 minutes at the high end of the range.
        let free: Int64 = 38 * 60 * 1_500_000 * 12 / 10
        let estimate = StorageEstimator.estimate(bitRate: Self.bitRate, plannedSeconds: 3_600, freeBytes: free)
        #expect(estimate.fitsSeconds == 38 * 60)
        #expect(estimate.verdict == .lessThanPlanned)
    }

    @Test func exactlyThePlannedLengthIsReadyAndOneSecondLessIsNot() {
        let needed = StorageEstimator.range(bitRate: Self.bitRate, plannedSeconds: 3_600).upperBound
        #expect(StorageEstimator.estimate(bitRate: Self.bitRate, plannedSeconds: 3_600, freeBytes: needed).verdict == .ready)
        #expect(StorageEstimator.estimate(bitRate: Self.bitRate, plannedSeconds: 3_600, freeBytes: needed - 1_800_000).verdict == .lessThanPlanned)
    }

    @Test func underFiveMinutesIsAlmostFull() {
        let free: Int64 = 4 * 60 * 1_800_000
        let estimate = StorageEstimator.estimate(bitRate: Self.bitRate, plannedSeconds: 3_600, freeBytes: free)
        #expect(estimate.fitsSeconds == 240)
        #expect(estimate.verdict == .almostFull)
        #expect(StorageEstimator.estimate(bitRate: Self.bitRate, plannedSeconds: 3_600, freeBytes: 0).verdict == .almostFull)
        #expect(StorageEstimator.estimate(bitRate: Self.bitRate, plannedSeconds: 3_600, freeBytes: -1).fitsSeconds == 0)
    }

    @Test func aShortPlanIsNeverCalledAlmostFullWhenItFits() {
        // Three minutes planned and four minutes of room: it fits, so it is ready.
        let estimate = StorageEstimator.estimate(bitRate: Self.bitRate, plannedSeconds: 180, freeBytes: 4 * 60 * 1_800_000)
        #expect(estimate.verdict == .ready)
    }
}
