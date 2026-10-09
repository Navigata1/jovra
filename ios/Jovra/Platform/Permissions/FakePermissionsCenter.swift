import Synchronization

/// A permissions center whose states are set by a test or a launch argument. `request(_:)` records
/// the request and answers with `answer` (Apple's prompt is never shown).
final class FakePermissionsCenter: PermissionsCenter {
    private struct Storage {
        var states: [Permission: PermissionState]
        var requests: [Permission] = []
    }

    private let storage: Mutex<Storage>
    /// What the "system prompt" answers for a `notDetermined` permission.
    let answer: PermissionState

    init(states: [Permission: PermissionState] = [:], answer: PermissionState = .authorized) {
        storage = Mutex(Storage(states: states))
        self.answer = answer
    }

    /// Requests made so far, in order.
    var requests: [Permission] { storage.withLock { $0.requests } }

    func set(_ state: PermissionState, for permission: Permission) {
        storage.withLock { $0.states[permission] = state }
    }

    func status(of permission: Permission) async -> PermissionState {
        storage.withLock { $0.states[permission] ?? .notDetermined }
    }

    func request(_ permission: Permission) async -> PermissionState {
        let answer = self.answer
        return storage.withLock { storage in
            storage.requests.append(permission)
            let current = storage.states[permission] ?? .notDetermined
            guard current == .notDetermined else { return current }
            storage.states[permission] = answer
            return answer
        }
    }
}

/// The launch harness's center: the injected states (`-permissions camera=denied,...`) for the
/// permissions listed, the live system state for the rest (docs/DEVELOPING.md, launch configuration).
struct InjectedPermissionsCenter: PermissionsCenter {
    let injected: FakePermissionsCenter
    let listed: Set<Permission>
    let live: any PermissionsCenter

    init(states: [Permission: PermissionState], live: any PermissionsCenter = LivePermissionsCenter()) {
        injected = FakePermissionsCenter(states: states, answer: .authorized)
        listed = Set(states.keys)
        self.live = live
    }

    func status(of permission: Permission) async -> PermissionState {
        listed.contains(permission) ? await injected.status(of: permission) : await live.status(of: permission)
    }

    func request(_ permission: Permission) async -> PermissionState {
        listed.contains(permission) ? await injected.request(permission) : await live.request(permission)
    }
}
