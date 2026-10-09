import SwiftUI

/// The service-registration seam. There is no central list of services and no edit to the app entry
/// point when one is added: each service declares its own key, in its own file, whose live default
/// reads the launch configuration to choose the fake or the live implementation.
///
/// ```swift
/// // Features/Sessions/Library/SessionLookupKey.swift
/// struct SessionLookupKey: ServiceKey {
///     static let defaultValue: any SessionLookup = resolve(.current)
///     static func live() -> any SessionLookup { StoreSessionLookup() }
///     static func fake(for configuration: LaunchConfiguration) -> any SessionLookup { SampleSessionLookup() }
/// }
/// extension EnvironmentValues {
///     var sessionLookup: any SessionLookup {
///         get { self[SessionLookupKey.self] }
///         set { self[SessionLookupKey.self] = newValue }
///     }
/// }
/// ```
///
/// Views read `@Environment(\.sessionLookup)`; a preview or test overrides it with `.environment`.
/// By default the demo flag (`-demo sample`) selects the fake; a service with its own injection
/// argument (permissions, archive state) overrides `usesFake(_:)`.
protocol ServiceKey: EnvironmentKey where Value: Sendable {
    static func live() -> Value
    static func fake(for configuration: LaunchConfiguration) -> Value
    static func usesFake(_ configuration: LaunchConfiguration) -> Bool
}

extension ServiceKey {
    static func usesFake(_ configuration: LaunchConfiguration) -> Bool {
        configuration.demo != .off
    }

    /// The implementation `configuration` asks for. Keys call it with `.current` for their default.
    static func resolve(_ configuration: LaunchConfiguration) -> Value {
        usesFake(configuration) ? fake(for: configuration) : live()
    }
}
