import Foundation
import XCTest

/// Copy assertions from the brief (`design-reference/brief/screens.json`), with the spec's honesty
/// corrections applied (spec, "Design system and copy"; screen spec §0.2).
///
/// The brief quotes each screen's exact copy inside its layout description. `expected(screen:)`
/// returns those quoted strings, corrected. A ticket adds its screen's own deliberate differences
/// (screen spec, "Deliberate differences from the reference image") through `corrections`.
enum BriefCopy {
    enum Correction: Equatable {
        /// The brief's string is replaced by these strings.
        case replace(with: [String])
        /// The brief's string is not shown (the reason names the rule).
        case drop(reason: String)
    }

    /// The honesty corrections every screen inherits, keyed by the brief's exact string.
    static let honestyCorrections: [String: Correction] = [
        "Selected photos": .replace(with: ["Not needed for import", "Add-only"]),
        "Estimated from calibrated video": .drop(reason: "the shot-map provenance row states the real provenance"),
        "Fastest serve · Estimated": .replace(with: ["Fastest marked serve"]),
        "Best of 3 · Advantage": .replace(with: ["Best of 3 · Ad · Tie-break at 6–6"]),
        "+4 pts": .replace(with: ["+4 percentage points"]),
        "Connected · Demo": .replace(with: ["Demo"]),
        "JOVRA · Reference concept": .drop(reason: "the settings footer shows the app version"),
        "Estimated space: 3.2 GB": .drop(reason: "the storage estimate is computed, never the sample 3.2 GB"),
    ]

    struct Screen: Decodable {
        var n: Int
        var id: String
        var title: String
        var layout: String
    }

    /// The repository root, found from this source file (UI tests run on the Mac that built them).
    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Support
        .deletingLastPathComponent() // JovraUITests
        .deletingLastPathComponent() // ios
        .deletingLastPathComponent()

    static func screens() throws -> [Screen] {
        let url = repositoryRoot.appendingPathComponent("design-reference/brief/screens.json")
        return try JSONDecoder().decode([Screen].self, from: Data(contentsOf: url))
    }

    /// The brief's quoted strings for a screen, uncorrected, in order.
    static func briefStrings(screen number: Int) throws -> [String] {
        guard let screen = try screens().first(where: { $0.n == number }) else {
            throw NSError(domain: "BriefCopy", code: 1, userInfo: [NSLocalizedDescriptionKey: "no screen \(number) in screens.json"])
        }
        let quoted = try NSRegularExpression(pattern: "\"([^\"]+)\"")
        let layout = screen.layout as NSString
        return quoted.matches(in: screen.layout, range: NSRange(location: 0, length: layout.length))
            .map { layout.substring(with: $0.range(at: 1)) }
    }

    /// The copy a screen must show: the brief's strings with the honesty corrections and `corrections`
    /// applied (a screen's own corrections win), duplicates removed.
    static func expected(screen: Int, corrections: [String: Correction] = [:]) throws -> [String] {
        var result: [String] = []
        for string in try briefStrings(screen: screen) {
            switch corrections[string] ?? honestyCorrections[string] {
            case .replace(let replacements): result += replacements
            case .drop: continue
            case nil: result.append(string)
            }
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }
}

extension XCTestCase {
    /// Asserts that every expected string of a brief screen is on screen, as an element's label or
    /// value. Strings already asserted elsewhere, or not on this state of the screen, go in `excluding`.
    @MainActor
    func assertBriefCopy(
        screen: Int,
        in app: XCUIApplication,
        corrections: [String: BriefCopy.Correction] = [:],
        excluding: Set<String> = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for string in try BriefCopy.expected(screen: screen, corrections: corrections) where !excluding.contains(string) {
            let match = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@ OR value == %@", string, string)).firstMatch
            XCTAssertTrue(match.exists, "screen \(screen) shows “\(string)”", file: file, line: line)
        }
    }
}
