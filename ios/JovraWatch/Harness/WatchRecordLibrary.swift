import Foundation
import JovraRoom

/// spec/room records bundled in place (the `records` folder reference in ios/project.yml), decoded with JovraRoom's
/// strict decoder. The harness and the tests read the same bytes the contract validator reads.
struct WatchRecordLibrary: Sendable {
    enum LoadError: Error, Equatable, CustomStringConvertible {
        case missing(String)
        case notAWatchBridgeSnapshot(String)
        case invalid(record: String, reason: String)

        var description: String {
            switch self {
            case .missing(let name): "record \(name).json is not in the bundle's records folder"
            case .notAWatchBridgeSnapshot(let name): "record \(name).json is not a jovra.room.watch-bridge/1 snapshot"
            case .invalid(let name, let reason): "record \(name).json does not decode: \(reason)"
            }
        }
    }

    let directory: URL

    init(directory: URL) { self.directory = directory }

    /// The `records` folder inside `bundle`, or nil when the bundle does not carry it.
    init?(bundle: Bundle) {
        guard let url = bundle.url(forResource: "records", withExtension: nil) else { return nil }
        self.init(directory: url)
    }

    func watchBridgeSnapshot(_ name: String) throws(LoadError) -> WatchBridgeSnapshot {
        let url = directory.appendingPathComponent("\(name).json")
        guard let data = try? Data(contentsOf: url) else { throw .missing(name) }
        let record: RoomRecord
        do { record = try RoomRecord.decode(data) } catch {
            throw .invalid(record: name, reason: String(describing: error))
        }
        guard case .watchBridge(let snapshot) = record else { throw .notAWatchBridgeSnapshot(name) }
        return snapshot
    }
}
