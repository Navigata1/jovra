import SwiftUI
@testable import Jovra

// A demo service registered the way every feature registers one: its own key, in its own file,
// outside the app target, with no edit to JovraApp.swift or any central list.

protocol DemoGreetingService: Sendable {
    var greeting: String { get }
    var isFake: Bool { get }
}

struct LiveDemoGreetingService: DemoGreetingService {
    let greeting = "from the live service"
    let isFake = false
}

struct FakeDemoGreetingService: DemoGreetingService {
    let greeting = "from the fake service"
    let isFake = true
}

struct DemoGreetingServiceKey: ServiceKey {
    static let defaultValue: any DemoGreetingService = resolve(.current)

    static func live() -> any DemoGreetingService { LiveDemoGreetingService() }

    static func fake(for configuration: LaunchConfiguration) -> any DemoGreetingService { FakeDemoGreetingService() }
}

extension EnvironmentValues {
    var demoGreetingService: any DemoGreetingService {
        get { self[DemoGreetingServiceKey.self] }
        set { self[DemoGreetingServiceKey.self] = newValue }
    }
}
