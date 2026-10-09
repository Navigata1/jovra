import Foundation
import Testing
import JovraCore

@Test func exportedSampleDataMatchesTheIndependentCSVContracts() throws {
    let root = try FixtureManifest.repository()
    let folder = root.appendingPathComponent("spec/fixtures/sample")
    let source = try Data(contentsOf: folder.appendingPathComponent("jon-vs-alex.session.json"))
    let document = try ContractCodec.decode(SessionDocument.self, from: source)
    let exported = try DataExporter.exportSession(document)
    #expect(exported.pointsCSV == (try Data(contentsOf: folder.appendingPathComponent("jon-vs-alex.points.csv"))))
    #expect(exported.statsCSV == (try Data(contentsOf: folder.appendingPathComponent("jon-vs-alex.stats.csv"))))
    #expect(try ContractCodec.decode(SessionDocument.self, from: exported.sessionJSON) == document)
}

@Test func CSVQuotesNamesAndPreservesSampleAndUnicode() throws {
    var document = try exportSample()
    document.players[0].displayName = "Jon, \"J\" 🎾\r\nIDC"
    let exported = try DataExporter.exportSession(document)
    let points = String(decoding: exported.pointsCSV, as: UTF8.self)
    let stats = String(decoding: exported.statsCSV, as: UTF8.self)
    let quoted = "\"Jon, \"\"J\"\" 🎾\r\nIDC\""
    #expect(points.contains("," + quoted + ",Alex,"))
    #expect(stats.contains("totalPointsWon,A," + quoted + ",72,124,58,58%\n"))
    #expect(!exported.pointsCSV.starts(with: [0xef, 0xbb, 0xbf]))
    #expect(exported.pointsCSV.last == 10)
    let restored = try ContractCodec.decode(SessionDocument.self, from: exported.sessionJSON)
    #expect(restored == document)
    #expect(restored.sample != nil)
}

@Test func correctionRecomputesCSVFromTheCurrentLog() throws {
    var document = try exportSample()
    let original = try DataExporter.exportSession(document)
    var match = try #require(document.match)
    let index = try #require(match.log.firstIndex { $0.seq == 42 })
    guard case .point(var point) = match.log[index] else { Issue.record("Sample seq42 must be a point"); return }
    var observation = try #require(point.reviewed ?? point.detected)
    observation.winner = .a
    point.reviewed = observation
    match.log[index] = .point(point)
    document.match = match
    let corrected = try DataExporter.exportSession(document)
    // Independently recomputed reference: changed game boundaries end this corrected match at116points.
    #expect(String(decoding: original.statsCSV, as: UTF8.self).contains("totalPointsWon,A,Jon,72,124,58,58%\n"))
    #expect(String(decoding: corrected.statsCSV, as: UTF8.self).contains("totalPointsWon,A,Jon,68,116,59,59%\n"))
    #expect(corrected.pointsCSV != original.pointsCSV)
    #expect(try ContractCodec.decode(SessionDocument.self, from: corrected.sessionJSON) == document)
}

@Test func unknownWinnerAndMissingTimesStayEmptyRatherThanInvented() throws {
    var document = try exportSample()
    var match = try #require(document.match)
    guard case .point(var point) = try #require(match.log.first) else { Issue.record("Expected first point"); return }
    var observation = try #require(point.reviewed)
    observation.winner = .unknown
    point.reviewed = observation
    point.tStartMs = nil; point.tEndMs = nil
    match.log = [.point(point)]
    document.match = match
    let exported = try DataExporter.exportSession(document)
    let row = "1,3a24700f-0a33-528d-8bf6-851e1b3e23b7,point,1,1,1,,Jon,Alex,A,deuce,0-0,0-0,0-0,,,unforcedError,1,2,1,false,,,reviewed,reviewed,true,false\n"
    #expect(String(decoding: exported.pointsCSV, as: UTF8.self).hasSuffix(row))
    #expect(String(decoding: exported.statsCSV, as: UTF8.self).contains("totalPointsWon,A,Jon,0,0,,—\n"))
    #expect(try ContractCodec.decode(SessionDocument.self, from: exported.sessionJSON) == document)
}

private func exportSample() throws -> SessionDocument {
    let path = try FixtureManifest.repository().appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")
    return try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: path))
}
