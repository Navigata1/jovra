import Foundation
import JovraBenchmark
import JovraCore
import JovraMedia
import Testing

/// T21 (story 49): the camera preset row lists only formats this camera can record.
struct CaptureFormatCatalogTests {
    @Test func onlyFormatsTheCameraSupportsAreListedAndTheUltraWideLensWins() {
        let capabilities: [CameraFormatCapability] = [
            .init(lens: .ultraWide, width: 1920, height: 1080, maxFramesPerSecond: 60),
            .init(lens: .wide, width: 1920, height: 1080, maxFramesPerSecond: 60),
            .init(lens: .wide, width: 3840, height: 2160, maxFramesPerSecond: 60),
        ]
        let options = CaptureFormatCatalog.supported(by: capabilities)
        #expect(options.map(\.id) == ["1080p60.ultraWide", "1080p30.ultraWide"],
                "4K exists only on the wide lens, so it is not offered beside the ultra-wide")
        #expect(options.allSatisfy { $0.lens == .ultraWide })
    }

    @Test func withoutAnUltraWideLensTheWideLensFormatsAreListed() {
        let options = CaptureFormatCatalog.supported(by: [
            .init(lens: .wide, width: 1920, height: 1080, maxFramesPerSecond: 30),
            .init(lens: .wide, width: 3840, height: 2160, maxFramesPerSecond: 30),
        ])
        #expect(options.map(\.id) == ["1080p30.wide", "4k30.wide"], "60 fps is never offered at a 30 fps maximum")
    }

    @Test func aCameraWithNoKnownFormatOffersNothingRatherThanAGuess() {
        #expect(CaptureFormatCatalog.supported(by: []).isEmpty)
        #expect(CaptureFormatCatalog.supported(by: [.init(lens: .wide, width: 640, height: 480, maxFramesPerSecond: 30)]).isEmpty)
    }

    @Test func bitratesComeFromTheDocumentedPerMinuteTable() throws {
        // technical-feasibility §1: 1080p30 60 MB/min, 1080p60 90 MB/min, 4K30 170 MB/min, 4K60 400 MB/min.
        let byID = Dictionary(uniqueKeysWithValues: CaptureFormatCatalog.table.map { ($0.slug, $0) })
        #expect(try #require(byID["1080p60"]).bitRate == 12_000_000)
        #expect(try #require(byID["1080p30"]).bitRate == 8_000_000)
        #expect(try #require(byID["4k30"]).megabytesPerMinute == 170)
        #expect(try #require(byID["4k60"]).megabytesPerMinute == 400)
    }

    @Test func anOptionIsTheCapturePresetTheEngineRecords() throws {
        let option = try #require(CaptureFormatCatalog.supported(by: [
            .init(lens: .ultraWide, width: 1920, height: 1080, maxFramesPerSecond: 60),
        ]).first)
        #expect(option.preset == CapturePreset(width: 1920, height: 1080, frameRate: .init(num: 60, den: 1),
                                               bitRate: 12_000_000, useUltraWide: true))
    }

    @Test func theSimulatorOffersOnlyTheFixtureClipsOwnFormat() async throws {
        let clip = MediaFixtureCatalog.repository().root.appendingPathComponent("ios/Jovra/Resources/Fixtures/fixture-camera-720p30.mp4")
        let options = try await CaptureFormatCatalog.fixture(clip)
        #expect(options.map(\.id) == ["720p30.fixture"])
        let option = try #require(options.first)
        #expect(option.lens == .fixture)
        #expect(option.preset.width == 1280 && option.preset.height == 720)
        #expect(option.preset.frameRate == RecordedFrameRate(num: 30, den: 1))
        // The fixture camera accepts exactly the formats the catalog offers for it.
        let camera = FixtureCamera(url: clip, clock: VirtualCaptureClock())
        let format = try await camera.prepare(preset: option.preset, microphone: .notRequested)
        #expect(format.width == 1280)
    }

    @Test func optionsAreFoundByIDAndAnUnknownIDFallsBackToTheFirst() {
        let options = CaptureFormatCatalog.supported(by: [.init(lens: .wide, width: 1920, height: 1080, maxFramesPerSecond: 60)])
        #expect(CaptureFormatCatalog.option(id: "1080p30.wide", in: options)?.id == "1080p30.wide")
        #expect(CaptureFormatCatalog.option(id: "4k60.ultraWide", in: options)?.id == "1080p60.wide")
        #expect(CaptureFormatCatalog.option(id: nil, in: options)?.id == "1080p60.wide")
        #expect(CaptureFormatCatalog.option(id: nil, in: []) == nil)
    }
}
