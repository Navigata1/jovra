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

    @Test("-library fresh opens a new, empty library on each launch; no flag uses the device library")
    func freshLibrary() async throws {
        let fresh = LaunchConfiguration(arguments: ["Jovra", "-library", "fresh"])
        #expect(LocalCaptureLibraryKey.usesFake(fresh))
        #expect(!LocalCaptureLibraryKey.usesFake(LaunchConfiguration()))
        #expect(!LocalCaptureLibraryKey.usesFake(LaunchConfiguration(arguments: ["Jovra", "-demo", "sample"])),
                "demo choices never switch the store")
        guard case .ready(let first) = LocalCaptureLibraryKey.resolve(fresh),
              case .ready(let second) = LocalCaptureLibraryKey.resolve(fresh) else {
            Issue.record("a fresh library opens")
            return
        }
        #expect(try await first.sessions().isEmpty)
        #expect(try await second.sessions().isEmpty)
    }

    @Test("the app's own services use the same seam")
    func appServices() async {
        #expect(EnvironmentValues().permissionsCenter is LivePermissionsCenter)
        #expect(EnvironmentValues().dataEraserRegistry === DataEraserRegistry.shared)
        #expect(await EnvironmentValues().sessionLookup.summaries().isEmpty, "no session store yet (T20 replaces the lookup)")
    }
}
