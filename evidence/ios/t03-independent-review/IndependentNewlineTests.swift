import Foundation
import Testing
@testable import JovraCore
@Test func independentStoredDecimalRejectsTrailingLineEndings() throws {
    for input in ["52\n", "52\r\n", "52\r"] {
        #expect(throws: (any Error).self) { try Units.display(input, unit: "lb", preferredUnit: "lb") }
        #expect(throws: (any Error).self) { try Units.convert(input, from: "lb", to: "kg", places: 1) }
    }
}
