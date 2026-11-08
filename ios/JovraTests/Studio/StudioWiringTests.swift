import Foundation
import JovraCore
import JovraStudioCore
import JovraStudioMedia
import Testing

/// S04: the hosted test bundle links the Studio packages (no further project.yml edit is needed for Studio tests
/// under ios/JovraTests/Studio), and the app it runs in carries the Studio settings and Info.plist keys.
@Suite("Studio wiring")
struct StudioWiringTests {
    @Test("the hosted bundle imports JovraStudioCore and calls into it")
    func studioCoreLinksInHostedTests() throws {
        let header = try StudioRecordHeader(json: Data(#"{"schemaVersion": "jovra.project-lock/1", "sample": true}"#.utf8))
        #expect(header.schemaVersion == StudioSchemaVersion(kind: "project-lock", version: 1))
        #expect(header.isSample)
    }

    @Test("the hosted bundle imports JovraStudioMedia and calls into it")
    func studioMediaLinksInHostedTests() {
        let end = StudioSourceTiming.nominalEnd(frameCount: 120, at: .fps60)
        #expect(end.value == 120 && end.timescale == 60)
    }

    @Test("the app is built for the Studio demo environment from Config/Studio.xcconfig")
    func studioEnvironmentIsDemo() throws {
        let info = try #require(Bundle.main.infoDictionary)
        #expect(info["JovraStudioEnvironment"] as? String == "demo")
    }

    @Test("the app declares JOVRA Room's local network use and the Studio render task identifier")
    func studioInfoPlistKeys() throws {
        let info = try #require(Bundle.main.infoDictionary)
        let usage = try #require(info["NSLocalNetworkUsageDescription"] as? String)
        #expect(usage.contains("JOVRA Room"))
        #expect(info["NSBonjourServices"] as? [String] == ["_jovra-room._tcp"])
        let tasks = try #require(info["BGTaskSchedulerPermittedIdentifiers"] as? [String])
        #expect(tasks.contains("com.islanddevcrew.jovra.continued.studio-render"))
    }
}
