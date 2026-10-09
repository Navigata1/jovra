@preconcurrency import AVFoundation
import Foundation
import JovraCore

public enum CaptureSourceFailure: Error, Equatable, Sendable { case interrupted, mediaServicesReset }

/// Device adapter for the same sample-buffer writer as the fixture camera. Lens/locks and real-time
/// endurance remain UNVERIFIED until the physical-device gate; compilation alone is not capture evidence.
public final class CameraSource: NSObject, CaptureSource, AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    public let mode = SessionRecordingMode.camera
    public let label = "Camera"
    private let control = DispatchQueue(label: "com.islanddevcrew.jovra.camera.control")
    private let samples = DispatchQueue(label: "com.islanddevcrew.jovra.camera.samples")
    private let lock = NSLock()
    private var session = AVCaptureSession()
    private var cameraDevice: AVCaptureDevice?
    private var onSample: (@Sendable (CaptureSample) throws -> Void)?
    private var onFailure: (@Sendable (any Error) -> Void)?
    private var sampleOrigin: CMTime?
    private var sessionStart = CMTime.zero
    private var lastPreset: CapturePreset?
    private var lastMicrophone = SessionRecordingMicrophone.notRequested
    private var resetRequired = false
    private var observers: [NSObjectProtocol] = []

    public override init() { super.init() }
    public var previewSession: AVCaptureSession { control.sync { session } }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    public func prepare(preset: CapturePreset, microphone: SessionRecordingMicrophone) async throws -> CaptureSourceFormat {
        try control.sync {
            let format = try configure(preset: preset, microphone: microphone)
            session.startRunning() // Framing preview uses automatic focus/exposure until record start.
            return format
        }
    }
    private func configure(preset: CapturePreset, microphone: SessionRecordingMicrophone) throws -> CaptureSourceFormat {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { throw CaptureError.sourceFailed("Camera permission is required") }
        guard !session.isRunning else { throw CaptureError.invalidState }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }; observers.removeAll()
        session = AVCaptureSession()
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        #if os(iOS)
        let type: AVCaptureDevice.DeviceType = preset.useUltraWide ? .builtInUltraWideCamera : .builtInWideAngleCamera
        let selected = AVCaptureDevice.default(type, for: .video, position: .back)
        #else
        let selected = AVCaptureDevice.default(for: .video)
        #endif
        guard let camera = selected else { throw CaptureError.noVideo }
        let fps = Double(preset.frameRate.num) / Double(preset.frameRate.den)
        guard let format = camera.formats.first(where: {
            let size = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            return size.width == preset.width && size.height == preset.height && $0.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= fps && fps <= $0.maxFrameRate }
        }) else { throw CaptureError.unsupportedPreset }
        try camera.lockForConfiguration()
        defer { camera.unlockForConfiguration() }
        camera.activeFormat = format
        let interval = CMTime(value: Int64(preset.frameRate.den), timescale: Int32(preset.frameRate.num))
        camera.activeVideoMinFrameDuration = interval; camera.activeVideoMaxFrameDuration = interval
        if camera.isFocusModeSupported(.continuousAutoFocus) { camera.focusMode = .continuousAutoFocus }
        if camera.isExposureModeSupported(.continuousAutoExposure) { camera.exposureMode = .continuousAutoExposure }
        if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { camera.whiteBalanceMode = .continuousAutoWhiteBalance }
        cameraDevice = camera
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else { throw CaptureError.unsupportedPreset }; session.addInput(input)
        let video = AVCaptureVideoDataOutput()
        video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        video.alwaysDiscardsLateVideoFrames = false
        video.setSampleBufferDelegate(self, queue: samples)
        guard session.canAddOutput(video) else { throw CaptureError.unsupportedPreset }; session.addOutput(video)
        if let connection = video.connection(with: .video) {
            #if os(iOS)
            if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .off }
            #endif
            if connection.isVideoRotationAngleSupported(0) { connection.videoRotationAngle = 0 }
        }
        var audioPresent = false
        if microphone == .granted, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
           let microphoneDevice = AVCaptureDevice.default(for: .audio), let audioInput = try? AVCaptureDeviceInput(device: microphoneDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
            let audio = AVCaptureAudioDataOutput(); audio.setSampleBufferDelegate(self, queue: samples)
            if session.canAddOutput(audio) { session.addOutput(audio); audioPresent = true }
        }
        lastPreset = preset; lastMicrophone = microphone; resetRequired = false
        observers.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] _ in
            self?.lock.withLock { self?.onFailure }?(CaptureSourceFailure.interrupted)
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] notification in
            guard let self else { return }
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
            let didReset: Bool
            #if os(iOS)
            didReset = error?.code == .mediaServicesWereReset
            #else
            didReset = false
            #endif
            if didReset {
                self.control.async { self.resetRequired = true }
                self.lock.withLock { self.onFailure }?(CaptureSourceFailure.mediaServicesReset)
            } else { self.lock.withLock { self.onFailure }?(error ?? CaptureError.sourceFailed("Camera runtime failure")) }
        })
        return CaptureSourceFormat(width: preset.width, height: preset.height, frameRate: preset.frameRate, hasAudio: audioPresent)
    }
    public func start(at sessionTime: CMTime, onSample: @escaping @Sendable (CaptureSample) throws -> Void,
                      onFailure: @escaping @Sendable (any Error) -> Void) async throws {
        try control.sync {
            if resetRequired, let preset = lastPreset { _ = try configure(preset: preset, microphone: lastMicrophone) }
            if let camera = cameraDevice {
                try camera.lockForConfiguration()
                if camera.isFocusModeSupported(.locked) { camera.focusMode = .locked }
                if camera.isExposureModeSupported(.locked) { camera.exposureMode = .locked }
                if camera.isWhiteBalanceModeSupported(.locked) { camera.whiteBalanceMode = .locked }
                camera.unlockForConfiguration()
            }
            lock.withLock { self.onSample = onSample; self.onFailure = onFailure; sampleOrigin = nil; sessionStart = sessionTime }
            session.startRunning()
        }
    }
    public func stop() async {
        control.sync { session.stopRunning() }
        lock.withLock { onSample = nil; onFailure = nil }
    }
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let mediaType: AVMediaType = output is AVCaptureVideoDataOutput ? .video : .audio
        let mapping = lock.withLock { () -> (CMTime, (@Sendable (CaptureSample) throws -> Void))? in
            guard let onSample else { return nil }
            if sampleOrigin == nil, mediaType == .video { sampleOrigin = CMSampleBufferGetPresentationTimeStamp(sampleBuffer) }
            guard let sampleOrigin else { return nil }
            return (CMTimeSubtract(sessionStart, sampleOrigin), onSample)
        }
        guard let (offset, handler) = mapping else { return }
        do {
            let retimed = try retimeCaptureSample(sampleBuffer, offset: offset)
            guard CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(retimed), .zero) >= 0 else { return }
            try handler(CaptureSample(buffer: retimed, mediaType: mediaType))
        } catch { lock.withLock { onFailure }?(error) }
    }
}
