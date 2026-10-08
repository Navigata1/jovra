import XCTest

enum Screenshots {
    /// Lower-case words (letters and digits) joined by single hyphens, e.g. `s04-dark-setup`.
    static func isValidName(_ name: String) -> Bool {
        name.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression) != nil
    }
}

extension XCTestCase {
    /// Attaches a named screenshot that `scripts/ios/ui-test.sh` exports to `evidence/ios/<ticket>/`.
    /// Names are lower-case words joined by hyphens. Name a screenshot that pairs with a reference
    /// image `sNN-<appearance>-<what>` (NN = the reference screen number) so `side_by_side.py` pairs it.
    /// A bad name is a recorded failure and no screenshot, never a crash of the test runner.
    @MainActor
    func attachScreenshot(_ app: XCUIApplication, name: String, file: StaticString = #filePath, line: UInt = #line) {
        guard Screenshots.isValidName(name) else {
            XCTFail("screenshot names are lower-case words joined by hyphens: '\(name)'", file: file, line: line)
            return
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
