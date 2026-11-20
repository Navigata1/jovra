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
        guard case .ready(let first) = LocalCaptureLibraryKey.resolve(fresh),
              case .ready(let second) = LocalCaptureLibraryKey.resolve(fresh) else {
            Issue.record("a fresh library opens")
            return
        }
        #expect(try await first.sessions().isEmpty)
        #expect(try await second.sessions().isEmpty)
    }

    @Test("-demo sample opens a temporary library with the shipped Sample sessions, never the device library")
    func demoLibrary() async throws {
        let demo = LaunchConfiguration(arguments: ["Jovra", "-demo", "sample"])
        #expect(LocalCaptureLibraryKey.usesFake(demo), "a harness demo never writes sample sessions into the device library")
        guard case .ready(let library) = LocalCaptureLibraryKey.resolve(demo) else {
            Issue.record("the demo library opens")
            return
        }
        let titles = try await library.libraryEntries().entries.map(\.title)
        #expect(titles.count == 8, "the eight sessions of spec/fixtures/sample/library")
        #expect(titles.contains("Jon vs Alex") && titles.contains("Serve practice") && titles.contains("Forehand session"))
        #expect(try await library.libraryEntries().entries.allSatisfy(\.isSample))
    }

    @Test("the app's own services use the same seam")
    func appServices() async {
        #expect(EnvironmentValues().permissionsCenter is LivePermissionsCenter)
        #expect(EnvironmentValues().dataEraserRegistry === DataEraserRegistry.shared)
        #expect(EnvironmentValues().sessionLookup is LibrarySessionLookup, "deep links resolve against the stored library (T20)")
    }
}
