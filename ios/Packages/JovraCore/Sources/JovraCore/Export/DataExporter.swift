import Foundation

public struct SessionDataExport: Sendable {
    public let sessionJSON: Data
    public let pointsCSV: Data
    public let statsCSV: Data
}
public enum DataExportError: Error, Equatable, Sendable { case missingContract, unsupportedContract(String) }

/// One fresh fold supplies all outputs. Exporting never mutates or stamps the source session.
public enum DataExporter {
    public static func exportSession(_ document: SessionDocument) throws -> SessionDataExport {
        let input = try ScoringInput(session: document)
        let timeline = try ScoringEngine.fold(input)
        let stats = try StatsEngine.compute(timeline)
        let names = Dictionary(uniqueKeysWithValues: input.players.map { ($0.id, $0.displayName) })
        let sideNames = [Side.a: input.sides.A.map { names[$0]! }.joined(separator: " / "),
                         Side.b: input.sides.B.map { names[$0]! }.joined(separator: " / ")]
        let pointsContract = try CSV.contract(.points), statsContract = try CSV.contract(.stats)
        let pointRows = try timeline.points.map { point in
            try pointsContract.columns.map { try PointCSV.cell($0.name, point: point, names: names, sideNames: sideNames, contract: pointsContract) }
        }
        guard let definitions = statsContract.rows, !definitions.isEmpty else { throw DataExportError.unsupportedContract("stats rows") }
        var statRows: [[String?]] = []
        for definition in definitions {
            let sides: [Side?] = definition.scope == .side ? [.a, .b] : [nil]
            for side in sides {
                let value = try ExportStats.value(definition.stat, side: side, stats: stats)
                statRows.append(try statsContract.columns.map { column in
                    switch column.name {
                    case "stat": return definition.stat
                    case "side": return side?.rawValue
                    case "players": return side.flatMap { sideNames[$0] }
                    case "numerator": switch value { case .count(let n): return String(n); case .ratio(let r): return String(r.n) }
                    case "denominator": if case .ratio(let r) = value { return String(r.d) }; return nil
                    case "pct": if case .ratio(let r) = value { return r.pct.value.map { String($0) } }; return nil
                    case "display": switch value { case .count(let n): return String(n); case .ratio(let r): return r.display }
                    default: throw DataExportError.unsupportedContract(column.name)
                    }
                })
            }
        }
        return .init(sessionJSON: try CanonicalJSON.encode(document),
                     pointsCSV: CSV.render(pointRows, contract: pointsContract), statsCSV: CSV.render(statRows, contract: statsContract))
    }
}

enum CSV {
    static func contract(_ name: CSVContractName) throws -> CSVContract {
        guard let url = Bundle.module.url(forResource: name.rawValue + ".v1", withExtension: "json") else { throw DataExportError.missingContract }
        let value = try ContractCodec.decode(CSVContract.self, from: Data(contentsOf: url))
        guard value.name == name, value.version == 1, value.header, !value.byteOrderMark, value.booleans.count == 2,
              !value.columns.isEmpty, Set(value.columns.map(\.name)).count == value.columns.count else {
            throw DataExportError.unsupportedContract(name.rawValue)
        }
        return value
    }
    static func render(_ rows: [[String?]], contract: CSVContract) -> Data {
        let delimiter = contract.delimiter.rawValue
        func cell(_ value: String?) -> String {
            guard let value else { return contract.null.rawValue }
            if value.contains(delimiter) || value.contains("\"") || value.contains("\r") || value.contains("\n") {
                return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return value
        }
        let header = contract.columns.map { $0.name }
        let lines = [header.map { cell($0) }.joined(separator: delimiter)] + rows.map { $0.map(cell).joined(separator: delimiter) }
        return Data((lines.joined(separator: contract.lineEnding.rawValue) + contract.lineEnding.rawValue).utf8)
    }
    static func boolean(_ value: Bool, contract: CSVContract) -> String { contract.booleans[value ? 0 : 1] }
}
