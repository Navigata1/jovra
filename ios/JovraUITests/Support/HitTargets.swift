import XCTest

/// The 44 × 44 pt minimum for every control (CLAUDE.md rule 8).
enum HitTarget {
    static let minimum: CGFloat = 44

    struct Control: Equatable {
        var description: String
        var frame: CGRect
    }

    /// Controls smaller than `minimum` in either dimension. A pure function, so it is tested
    /// without the app.
    static func undersized(_ controls: [Control], minimum: CGFloat = minimum) -> [Control] {
        controls.filter { $0.frame.width < minimum - 0.5 || $0.frame.height < minimum - 0.5 }
    }
}

extension XCTestCase {
    /// Asserts that every hittable button, link, switch, slider, text field and segmented control
    /// on screen is at least 44 × 44 pt. `exempt` lists accessibility identifiers allowed to be
    /// smaller, each with the reason in the caller.
    @MainActor
    func assertHitTargets(in app: XCUIApplication, exempt: Set<String> = [], file: StaticString = #filePath, line: UInt = #line) {
        let queries = [app.buttons, app.links, app.switches, app.sliders, app.textFields, app.segmentedControls]
        var controls: [HitTarget.Control] = []
        for query in queries {
            for element in query.allElementsBoundByIndex where element.exists && element.isHittable && !exempt.contains(element.identifier) {
                let name = element.identifier.isEmpty ? element.label : element.identifier
                controls.append(.init(description: "\(element.elementType.rawValue) “\(name)”", frame: element.frame))
            }
        }
        XCTAssertFalse(controls.isEmpty, "no controls found on screen", file: file, line: line)
        for control in HitTarget.undersized(controls) {
            XCTFail("\(control.description) is \(control.frame.width) × \(control.frame.height) pt, under 44 × 44", file: file, line: line)
        }
    }
}
