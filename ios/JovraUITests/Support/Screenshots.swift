import XCTest

extension XCTestCase {
    /// Attaches a named screenshot that `scripts/ios/ui-test.sh` exports to `evidence/ios/<ticket>/`.
    /// Names are lower-case words joined by hyphens. Name a screenshot that pairs with a reference
    /// image `sNN-<appearance>-<what>` (NN = the reference screen number) so `side_by_side.py` pairs it.
    @MainActor
    func attachScreenshot(_ app: XCUIApplication, name: String) {
        precondition(name.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression) != nil,
                     "screenshot names are lower-case words joined by hyphens: \(name)")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
