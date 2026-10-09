import Testing
@testable import JovraCore

@Test func unitsConvertOnceAndPreserveEnteredText() throws {
    #expect(try Units.convert("52", from: "lb", to: "kg", places: 8) == "23.58680324")
    #expect(try Units.convert("23", from: "kg", to: "lb", places: 6) == "50.706320")
    #expect(try Units.display("52.0", unit: "lb", preferredUnit: "lb").value == "52.0")
    #expect(try Units.display("1.25", unit: "m/s", preferredUnit: "km/h").value == "5")
    #expect(Units.gaugeHint("17").ranges.count == 2)
}

@Test func exactStoredDecimalAllowsLeadingZeroesWithoutRewriting() throws {
    #expect(try Units.display("00052.00", unit: "lb", preferredUnit: "lb").value == "00052.00")
    #expect(try Units.convert("00052.00", from: "lb", to: "kg", places: 8) == "23.58680324")
}
