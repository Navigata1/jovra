import SwiftUI
import Synchronization

/// One store's part of "Delete all JOVRA data": erases everything that store keeps on this iPhone.
struct DataEraser: Sendable {
    /// Stable and unique, e.g. `preferences`, `sessions`, `equipment`.
    var id: String
    var erase: @Sendable () async throws -> Void
}

/// What happened to one store.
struct DataErasureResult: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case erased
        /// The store's own description of what failed; its data may still be on the iPhone.
        case failed(String)
    }

    var id: String
    var outcome: Outcome
}

/// The registry behind "Delete all JOVRA data" (T57): each store registers its own eraser, in its own
/// file, when its live instance is created (normally in its `ServiceKey.live()`), so the delete flow
/// never lists stores itself. `eraseAll()` runs every eraser, even after one fails, and reports each.
///
/// The delete flow must read each store's environment value before erasing, so every live store has
/// been created and registered; `registeredIDs` is what it shows as the deletion's scope.
final class DataEraserRegistry: Sendable {
    static let shared = DataEraserRegistry()

    private let erasers = Mutex<[DataEraser]>([])

    init() {}

    /// Adds `eraser`, replacing one already registered with the same id (a store created twice).
    func register(_ eraser: DataEraser) {
        erasers.withLock { erasers in
            if let index = erasers.firstIndex(where: { $0.id == eraser.id }) {
                erasers[index] = eraser
            } else {
                erasers.append(eraser)
            }
        }
    }

    /// Registered ids, in registration order.
    var registeredIDs: [String] {
        erasers.withLock { $0.map(\.id) }
    }

    /// Runs every registered eraser in registration order and reports each result.
    func eraseAll() async -> [DataErasureResult] {
        var results: [DataErasureResult] = []
        for eraser in erasers.withLock({ $0 }) {
            do {
                try await eraser.erase()
                results.append(DataErasureResult(id: eraser.id, outcome: .erased))
            } catch {
                results.append(DataErasureResult(id: eraser.id, outcome: .failed(String(describing: error))))
            }
        }
        return results
    }
}

/// Registers the eraser registry (the ServiceKey seam). There is one registry in every launch.
struct DataEraserRegistryKey: ServiceKey {
    static let defaultValue: DataEraserRegistry = resolve(.current)

    static func live() -> DataEraserRegistry { .shared }

    static func fake(for configuration: LaunchConfiguration) -> DataEraserRegistry { .shared }
}

extension EnvironmentValues {
    var dataEraserRegistry: DataEraserRegistry {
        get { self[DataEraserRegistryKey.self] }
        set { self[DataEraserRegistryKey.self] = newValue }
    }
}
