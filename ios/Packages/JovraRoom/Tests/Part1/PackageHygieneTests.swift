import Foundation
import JovraRoom
import XCTest

/// The package stays Foundation-only (it builds and tests on Linux) and its production clock keeps counting in
/// sleep. These read the package's own sources from #filePath.
final class PackageHygieneTests: XCTestCase {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func swiftSources(under folder: String) throws -> [(String, String)] {
        let root = Self.packageRoot.appendingPathComponent(folder)
        let paths = FileManager.default.enumerator(atPath: root.path)?.compactMap { $0 as? String } ?? []
        return try paths.filter { $0.hasSuffix(".swift") }.sorted().map {
            ($0, try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8))
        }
    }

    func test_noUIOrWatchTransportFrameworkImports() throws {
        let sources = try swiftSources(under: "Sources") + swiftSources(under: "Tests")
        XCTAssertFalse(sources.isEmpty)
        // Spelled in pieces so this file itself stays clean under the CI grep.
        let frameworks = ["UI" + "Kit", "Swift" + "UI", "Watch" + "Connectivity"].joined(separator: "|")
        let forbidden = try NSRegularExpression(pattern: #"import\s+("# + frameworks + #")\b"#)
        for (path, text) in sources {
            let range = NSRange(text.startIndex..., in: text)
            XCTAssertNil(forbidden.firstMatch(in: text, range: range), "\(path) imports a UI or watch framework")
        }
    }

    /// Freshness is measured only on the continuous clock: never `mach_absolute_time` or `SuspendingClock` (which
    /// pause in sleep), and never a wall clock.
    func test_freshnessUsesOnlyTheContinuousClock() throws {
        let sources = try swiftSources(under: "Sources/JovraRoom/Freshness")
        let clock = try XCTUnwrap(sources.first { $0.0 == "MonotonicClock.swift" }?.1)
        XCTAssertTrue(clock.contains("ContinuousClock.now"))
        for (path, source) in sources {
            // Code only: the doc comments name the clocks that are banned and why.
            let text = source.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            for banned in ["mach_absolute_time", "SuspendingClock", "Date()", "DispatchTime", "ProcessInfo.processInfo.systemUptime"] {
                XCTAssertFalse(text.contains(banned), "\(path) uses \(banned)")
            }
        }
    }

    func test_continuousClockIsMonotonicAndAdvances() {
        let clock = ContinuousMonotonicClock()
        let start = clock.nowMs()
        Thread.sleep(forTimeInterval: 0.05)
        let end = clock.nowMs()
        XCTAssertGreaterThanOrEqual(end - start, 40)
        XCTAssertLessThan(end - start, 5000)
    }

    func test_processBaselineIsAValidRoomIdAndStableWithinTheProcess() {
        let id = ProcessBaseline.current
        XCTAssertEqual(id, ProcessBaseline.current)
        XCTAssertNotNil(id.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$"#, options: .regularExpression))
        let live = FreshnessClock.live
        XCTAssertEqual(live.baselineId, id)
        let observation = live.accept(transitMs: nil)
        XCTAssertEqual(try live.read(senderAgeMs: 0, observation).freshness, .unknown, "a queued delivery is Unknown")
    }
}
