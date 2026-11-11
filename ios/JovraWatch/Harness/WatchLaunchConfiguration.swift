import Foundation

/// What a launch of the watch app asked for. This file is the launch-argument contract between JovraWatch and
/// JovraWatchUITests and is compiled into both (ios/project.yml), so tests build `arguments` from a value and the app
/// parses them back with `init(arguments:)`.
///
/// `-watchState <surface>.<state>` opens one registered surface state fed from spec/room records through the fake
/// bridge (`WatchStateRegistry`). A value that is not registered is never ignored: the app shows the error and the
/// list of registered values. With no `-watchState` the app runs live (no harness, no fixtures).
struct WatchLaunchConfiguration: Equatable, Sendable {
    enum Key {
        static let watchState = "-watchState"
        static let reduceMotion = "-reduceMotion"
    }

    enum Problem: Error, Equatable, Sendable, CustomStringConvertible {
        /// `-watchState` with no value after it.
        case missingValue(String)
        /// A value that is not `<surface>.<state>` for a registered surface and state.
        case unknownWatchState(String)
        case invalidBoolean(key: String, value: String)

        var description: String {
            switch self {
            case .missingValue(let key): "\(key) needs a value"
            case .unknownWatchState(let value): "unknown -watchState \(value)"
            case .invalidBoolean(let key, let value): "\(key) takes YES or NO, not \(value)"
            }
        }
    }

    /// The harness state to open, or nil for live behaviour.
    var watchState: WatchStateID?
    /// Forces Reduce Motion on (YES) or off (NO); nil follows the system setting.
    var reduceMotion: Bool?
    /// Everything the parser could not use. The app shows these instead of guessing.
    var problems: [Problem] = []

    init(watchState: WatchStateID? = nil, reduceMotion: Bool? = nil) {
        self.watchState = watchState
        self.reduceMotion = reduceMotion
    }

    init(arguments: [String], registry: WatchStateRegistry = .shared) {
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            index += 1
            guard argument == Key.watchState || argument == Key.reduceMotion else { continue }
            guard index < arguments.endIndex, !arguments[index].hasPrefix("-") else {
                problems.append(.missingValue(argument))
                continue
            }
            let value = arguments[index]
            index += 1
            if argument == Key.watchState {
                if let id = WatchStateID(value), registry.state(id) != nil {
                    watchState = id
                } else {
                    problems.append(.unknownWatchState(value))
                }
            } else {
                switch value.uppercased() {
                case "YES": reduceMotion = true
                case "NO": reduceMotion = false
                default: problems.append(.invalidBoolean(key: argument, value: value))
                }
            }
        }
    }

    /// The launch arguments for this configuration.
    var arguments: [String] {
        var result: [String] = []
        if let watchState { result += [Key.watchState, watchState.rawValue] }
        if let reduceMotion { result += [Key.reduceMotion, reduceMotion ? "YES" : "NO"] }
        return result
    }
}
