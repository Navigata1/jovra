@preconcurrency import AVFoundation
import Foundation
import JovraCore

/// Which camera records: the physical ultra-wide is preferred because it fits the whole court from the
/// fence (technical-feasibility §1); the simulator records the labelled fixture clip (ADR-0012).
public enum CaptureLens: String, Codable, CaseIterable, Hashable, Sendable {
    case ultraWide, wide, fixture
}

/// One size and top frame rate a camera reports, independent of AVFoundation so the catalog is testable.
public struct CameraFormatCapability: Hashable, Sendable {
    public var lens: CaptureLens
    public var width: Int
    public var height: Int
    public var maxFramesPerSecond: Double

    public init(lens: CaptureLens, width: Int, height: Int, maxFramesPerSecond: Double) {
        self.lens = lens; self.width = width; self.height = height; self.maxFramesPerSecond = maxFramesPerSecond
    }
}

/// A camera preset the player can pick (story 49): size, frame rate, lens and the planning bitrate the
/// storage estimate uses. Only options built from the camera's own capabilities ever exist.
public struct CaptureFormatOption: Hashable, Sendable, Identifiable {
    /// Stable across launches, so the remembered setup can name it: "1080p60.ultraWide".
    public var id: String
    public var width: Int
    public var height: Int
    public var framesPerSecond: Int
    public var bitRate: Int
    public var lens: CaptureLens

    public init(id: String, width: Int, height: Int, framesPerSecond: Int, bitRate: Int, lens: CaptureLens) {
        self.id = id; self.width = width; self.height = height
        self.framesPerSecond = framesPerSecond; self.bitRate = bitRate; self.lens = lens
    }

    /// The preset the capture engine records with.
    public var preset: CapturePreset {
        CapturePreset(width: width, height: height, frameRate: .init(num: framesPerSecond, den: 1),
                      bitRate: bitRate, useUltraWide: lens == .ultraWide)
    }

    /// Whole megabytes per minute at the planning bitrate (the camera sheet's "MB per minute").
    public var megabytesPerMinute: Int { bitRate * 60 / 8_000_000 }
}

/// The formats JOVRA records, with planning bitrates, and the filter that keeps only what a camera supports.
public enum CaptureFormatCatalog {
    public struct Entry: Hashable, Sendable {
        /// "1080p60", "4k30".
        public var slug: String
        public var width: Int
        public var height: Int
        public var framesPerSecond: Int
        /// HEVC planning size per minute (technical-feasibility §1, iOS Settings figures; verify on device).
        public var megabytesPerMinute: Int

        public var bitRate: Int { megabytesPerMinute * 8_000_000 / 60 }
    }

    /// In the order the camera sheet lists them: the recommended match format first.
    public static let table: [Entry] = [
        .init(slug: "1080p60", width: 1920, height: 1080, framesPerSecond: 60, megabytesPerMinute: 90),
        .init(slug: "1080p30", width: 1920, height: 1080, framesPerSecond: 30, megabytesPerMinute: 60),
        .init(slug: "4k30", width: 3840, height: 2160, framesPerSecond: 30, megabytesPerMinute: 170),
        .init(slug: "4k60", width: 3840, height: 2160, framesPerSecond: 60, megabytesPerMinute: 400),
    ]

    /// The fixture writer's bitrate (the capture route records the fixture at 4 Mb/s).
    public static let fixtureBitRate = 4_000_000

    /// Table entries the camera can record, on the ultra-wide lens when it has one (else the wide lens).
    /// A camera that reports nothing JOVRA knows offers nothing: never a guessed format.
    public static func supported(by capabilities: [CameraFormatCapability]) -> [CaptureFormatOption] {
        let lens: CaptureLens = capabilities.contains { $0.lens == .ultraWide } ? .ultraWide : .wide
        let usable = capabilities.filter { $0.lens == lens }
        return table.compactMap { entry in
            let fits = usable.contains {
                $0.width == entry.width && $0.height == entry.height && $0.maxFramesPerSecond + 0.01 >= Double(entry.framesPerSecond)
            }
            guard fits else { return nil }
            return CaptureFormatOption(id: "\(entry.slug).\(lens.rawValue)", width: entry.width, height: entry.height,
                                       framesPerSecond: entry.framesPerSecond, bitRate: entry.bitRate, lens: lens)
        }
    }

    /// The simulator's only format: the fixture clip's own size and frame rate, read from the clip.
    public static func fixture(_ clip: URL) async throws -> [CaptureFormatOption] {
        let info = try await MediaProbe.probe(clip)
        guard let video = info.video, let rate = video.frameRate, rate.perSeconds > 0,
              rate.frames % rate.perSeconds == 0 else { return [] }
        let fps = rate.frames / rate.perSeconds
        let slug = video.codedHeight >= 2160 ? "4k\(fps)" : "\(video.codedHeight)p\(fps)"
        return [CaptureFormatOption(id: "\(slug).\(CaptureLens.fixture.rawValue)", width: video.codedWidth,
                                    height: video.codedHeight, framesPerSecond: fps, bitRate: fixtureBitRate, lens: .fixture)]
    }

    /// The option `id` names, else the first supported one; nil when the camera offers nothing.
    public static func option(id: String?, in options: [CaptureFormatOption]) -> CaptureFormatOption? {
        options.first { $0.id == id } ?? options.first
    }

    #if os(iOS)
    /// What the back ultra-wide and wide cameras report. Device-only: the simulator has no camera.
    public static func liveCapabilities() -> [CameraFormatCapability] {
        let lenses: [(AVCaptureDevice.DeviceType, CaptureLens)] = [(.builtInUltraWideCamera, .ultraWide), (.builtInWideAngleCamera, .wide)]
        return lenses.flatMap { type, lens -> [CameraFormatCapability] in
            guard let device = AVCaptureDevice.default(type, for: .video, position: .back) else { return [] }
            return device.formats.map { format in
                let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let top = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
                return CameraFormatCapability(lens: lens, width: Int(size.width), height: Int(size.height), maxFramesPerSecond: top)
            }
        }
    }
    #endif
}
