import Testing
import JovraCore

@Suite("Duration labels")
struct DurationLabelTests {
    @Test("under an hour shows whole minutes", arguments: [
        (0, "0 min"),
        (59, "0 min"),
        (60, "1 min"),
        (3270, "54 min"),
        (3599, "59 min"),
    ] as [(Double, String)])
    func minutes(_ seconds: Double, _ expected: String) {
        #expect(DurationLabel.compact(seconds: seconds) == expected)
    }

    @Test("an hour or more shows hours and minutes", arguments: [
        (3600, "1h 0m"),
        (24120, "6h 42m"),
        (90359, "25h 5m"),
    ] as [(Double, String)])
    func hours(_ seconds: Double, _ expected: String) {
        #expect(DurationLabel.compact(seconds: seconds) == expected)
    }

    @Test("negative and non-finite durations are treated as zero", arguments: [-5.0, .nan, .infinity])
    func invalid(_ seconds: Double) {
        #expect(DurationLabel.compact(seconds: seconds) == "0 min")
    }
}
