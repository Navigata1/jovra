@preconcurrency import AVFoundation
import Foundation
import JovraCore

public struct CapturePreset: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var frameRate: RecordedFrameRate
    public var bitRate: Int
    public var useUltraWide: Bool
    public init(width: Int = 1920, height: Int = 1080, frameRate: RecordedFrameRate = RecordedFrameRate(num: 30, den: 1),
                bitRate: Int = 8_000_000, useUltraWide: Bool = false) {
        self.width = width; self.height = height; self.frameRate = frameRate; self.bitRate = bitRate; self.useUltraWide = useUltraWide
    }
}
public struct CaptureSourceFormat: Sendable {
    public var width: Int
    public var height: Int
    public var frameRate: RecordedFrameRate
    public var hasAudio: Bool
    public var sampleRate: Int
    public var channels: Int
    public init(width: Int, height: Int, frameRate: RecordedFrameRate, hasAudio: Bool, sampleRate: Int = 48_000, channels: Int = 1) {
        self.width = width; self.height = height; self.frameRate = frameRate; self.hasAudio = hasAudio
        self.sampleRate = sampleRate; self.channels = channels
    }
}
/// Sample buffers are retained and consumed serially by the segment pipeline before the source reuses them.
public struct CaptureSample: @unchecked Sendable {
    public let buffer: CMSampleBuffer
    public let mediaType: AVMediaType
    public init(buffer: CMSampleBuffer, mediaType: AVMediaType) { self.buffer = buffer; self.mediaType = mediaType }
}
public protocol CaptureSource: Sendable {
    var mode: SessionRecordingMode { get }
    var label: String { get }
    func prepare(preset: CapturePreset, microphone: SessionRecordingMicrophone) async throws -> CaptureSourceFormat
    func start(at sessionTime: CMTime, onSample: @escaping @Sendable (CaptureSample) throws -> Void,
               onFailure: @escaping @Sendable (any Error) -> Void) async throws
    func stop() async
}
public protocol RecordingSink: Sendable {
    func saveRecording(sessionID: String, recording: SessionRecording, marks: [SessionMark]) async throws
}
public enum CaptureError: Error, Equatable, Sendable {
    case invalidState, unsupportedPreset, noVideo, sourceFailed(String), writerFailed(String), backPressureTimeout
    case decodeFailed(String), storageUnavailable
}
public protocol CaptureClock: Sendable {
    func now() -> CMTime
    func wait(until time: CMTime) async throws
}
public final class RealtimeCaptureClock: CaptureClock, @unchecked Sendable {
    private let origin = CMClockGetTime(CMClockGetHostTimeClock())
    public init() {}
    public func now() -> CMTime { CMTimeSubtract(CMClockGetTime(CMClockGetHostTimeClock()), origin) }
    public func wait(until time: CMTime) async throws {
        let delay = CMTimeSubtract(time, now()).convertScale(1_000_000_000, method: .roundTowardZero).value
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay)) }
    }
}
/// Advances an injected media clock without wall-time waits. Only fixture capture uses this clock.
public final class VirtualCaptureClock: CaptureClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current = CMTime.zero
    public init() {}
    public func now() -> CMTime { lock.withLock { current } }
    public func advance(by time: CMTime) { lock.withLock { current = CMTimeAdd(current, time) } }
    public func wait(until time: CMTime) async throws {
        try Task.checkCancellation()
        lock.withLock { if CMTimeCompare(time, current) > 0 { current = time } }
    }
}
public final class CaptureActivity: @unchecked Sendable {
    private let lock = NSLock()
    private var active = false
    private var observers: [UUID: @Sendable (Bool) -> Void] = [:]
    public init() {}
    public var isActive: Bool { lock.withLock { active } }
    @discardableResult public func observe(_ observer: @escaping @Sendable (Bool) -> Void) -> UUID {
        let id = UUID(); let initial = lock.withLock { observers[id] = observer; return active }
        observer(initial); return id
    }
    public func removeObserver(_ id: UUID) { _ = lock.withLock { observers.removeValue(forKey: id) } }
    func setActive(_ value: Bool) {
        let callbacks = lock.withLock { () -> [@Sendable (Bool) -> Void] in
            guard active != value else { return [] }; active = value; return Array(observers.values)
        }
        for callback in callbacks { callback(value) }
    }
}
