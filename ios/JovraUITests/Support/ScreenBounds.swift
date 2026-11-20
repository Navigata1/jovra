import XCTest

extension XCTestCase {
    /// Fails when any element matched by `identifierPrefixes` is laid out past the left or right edge of the app's
    /// window. A page wider than the screen still passes `isHittable` for its centred elements, so the audit alone
    /// only catches it by chance (clipped text, an off-screen control); this states it directly.
    @MainActor
    func assertFitsTheScreenWidth(_ app: XCUIApplication, identifierPrefixes: [String],
                                  file: StaticString = #filePath, line: UInt = #line) {
        let screen = app.windows.firstMatch.frame
        for prefix in identifierPrefixes {
            let elements = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).allElementsBoundByIndex
            for element in elements where element.exists && !element.frame.isEmpty {
                let frame = element.frame
                XCTAssertTrue(frame.minX >= screen.minX - 0.5 && frame.maxX <= screen.maxX + 0.5,
                              "'\(element.identifier)' at \(frame) is wider than the screen \(screen)",
                              file: file, line: line)
            }
        }
    }
}
