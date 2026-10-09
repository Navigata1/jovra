import SwiftUI
import Testing
@testable import Jovra

@MainActor
@Suite("Service registration seam")
struct ServiceRegistrationTests {
    @Test("the demo flag selects the fake; no flag selects the live service")
    func demoFlagSelectsTheFake() {
        let demo = LaunchConfiguration(arguments: ["Jovra", "-demo", "sample"])
        let player = LaunchConfiguration(arguments: ["Jovra", "-demo", "off"])
        #expect(DemoGreetingServiceKey.resolve(demo).isFake)
        #expect(DemoGreetingServiceKey.resolve(demo).greeting == "from the fake service")
        #expect(!DemoGreetingServiceKey.resolve(player).isFake)
        #expect(!DemoGreetingServiceKey.resolve(LaunchConfiguration()).isFake)
    }

    @Test("a view reads the service from the environment with no registration anywhere else")
    func environmentDefault() {
        // The test host launched without `-demo`, so the key's default is the live service.
        #expect(!EnvironmentValues().demoGreetingService.isFake)
        var values = EnvironmentValues()
        values.demoGreetingService = FakeDemoGreetingService()
        #expect(values.demoGreetingService.isFake, "a preview or test can still override it")
    }

    @Test("the app's own services use the same seam")
    func appServices() async {
        #expect(EnvironmentValues().permissionsCenter is LivePermissionsCenter)
        #expect(EnvironmentValues().dataEraserRegistry === DataEraserRegistry.shared)
        #expect(await EnvironmentValues().sessionLookup.summaries().isEmpty, "no session store yet (T20 replaces the lookup)")
    }
}
