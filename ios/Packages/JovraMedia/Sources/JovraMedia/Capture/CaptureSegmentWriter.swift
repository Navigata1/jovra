@preconcurrency import AVFoundation
import Foundation
import UniformTypeIdentifiers
import JovraCore
import Darwin

/// Owns the real encoder. Its delegate receives completed fMP4 container fragments; confirmed time only
/// advances after writing and synchronizing those bytes, never merely after append(sampleBuffer) succeeds.
final class CaptureSegmentWriter: NSObject, AVAssetWriterDelegate, @unchecked Sendable {
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let audio: AVAssetWriterInput?
    private let handle: FileHandle
    private let mediaURL: URL
    private let journal: CaptureJournal
    private let segment: SessionSegment
    private let sessionStart: CMTime
    private let frameRate: RecordedFrameRate
    private let lock = NSLock()
    private var failure: (any Error)?
    private var durableDuration = CMTime.zero
    private var reportOrigin: CMTime?
    private var lastVideoEnd = CMTime.zero
    private var bytes = 0

    init(url: URL, segment: SessionSegment, preset: CapturePreset, format: CaptureSourceFormat,
         sessionStart: CMTime, journal: CaptureJournal) throws {
        self.mediaURL = url
        self.segment = segment; self.journal = journal; self.sessionStart = sessionStart; self.frameRate = format.frameRate
        guard !FileManager.default.fileExists(atPath: url.path) else { throw CaptureError.storageUnavailable }
        let directory = url.deletingLastPathComponent()
        let createdDirectory = !FileManager.default.fileExists(atPath: directory.path)
        try DurableDirectory.create(at: directory)
        if createdDirectory {
            var directory = directory
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
        }
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CaptureError.storageUnavailable }
        handle = try FileHandle(forWritingTo: url)
        writer = AVAssetWriter(contentType: .mpeg4Movie)
        writer.outputFileTypeProfile = .mpeg4AppleHLS
        writer.preferredOutputSegmentInterval = CMTime(value: 2, timescale: 1)
        writer.initialSegmentStartTime = .zero
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: format.width, AVVideoHeightKey: format.height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: preset.bitRate,
                AVVideoMaxKeyFrameIntervalDurationKey: 2, AVVideoAllowFrameReorderingKey: false]
        ])
        video.expectsMediaDataInRealTime = true
        if format.hasAudio {
            audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: format.channels, AVEncoderBitRateKey: 96_000])
            audio?.expectsMediaDataInRealTime = true
        } else { audio = nil }
        super.init()
        writer.delegate = self
        guard writer.canAdd(video) else { throw CaptureError.unsupportedPreset }
        writer.add(video)
        if let audio { guard writer.canAdd(audio) else { throw CaptureError.unsupportedPreset }; writer.add(audio) }
        guard writer.startWriting() else { throw CaptureError.writerFailed(String(describing: writer.error)) }
        writer.startSession(atSourceTime: .zero)
    }
    func append(_ sample: CaptureSample) throws {
        if let failure = lock.withLock({ failure }) { throw failure }
        let input = sample.mediaType == .video ? video : audio
        guard let input else { return }
        let deadline = Date().addingTimeInterval(5)
        while !input.isReadyForMoreMediaData {
            if writer.status != .writing { throw CaptureError.writerFailed(writer.error?.localizedDescription ?? "writer stopped") }
            guard Date() < deadline else { throw CaptureError.backPressureTimeout }
            Thread.sleep(forTimeInterval: 0.001)
        }
        let local = try retimeCaptureSample(sample.buffer, offset: CMTimeMultiplyByFloat64(sessionStart, multiplier: -1))
        guard input.append(local) else { throw CaptureError.writerFailed(writer.error?.localizedDescription ?? "append") }
        if sample.mediaType == .video {
            lastVideoEnd = captureVideoEnd(local, frameRate: frameRate)
        }
    }
    func finish() async throws {
        if lastVideoEnd.isNumeric, CMTimeCompare(lastVideoEnd, .zero) > 0 { writer.endSession(atSourceTime: lastVideoEnd) }
        video.markAsFinished(); audio?.markAsFinished()
        await withCheckedContinuation { continuation in writer.finishWriting { continuation.resume() } }
        try lock.withLock {
            if let failure { throw failure }
            guard writer.status == .completed else { throw CaptureError.writerFailed(writer.error?.localizedDescription ?? "finishWriting") }
            try synchronizeMediaLocation(); try handle.close()
        }
    }
    /// An orphaned descriptor is not durable media at the path promised by the journal.
    private func synchronizeMediaLocation() throws {
        try handle.synchronize()
        var declared = stat(), opened = stat()
        guard lstat(mediaURL.path, &declared) == 0, fstat(handle.fileDescriptor, &opened) == 0 else {
            throw CaptureError.storageUnavailable
        }
        guard declared.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              declared.st_dev == opened.st_dev, declared.st_ino == opened.st_ino else {
            throw CaptureError.storageUnavailable
        }
        try DurableDirectory.synchronize(mediaURL.deletingLastPathComponent())
    }
    func assetWriter(_ writer: AVAssetWriter, didOutputSegmentData segmentData: Data,
                     segmentType: AVAssetSegmentType, segmentReport: AVAssetSegmentReport?) {
        lock.withLock {
            guard failure == nil else { return }
            do {
                try handle.write(contentsOf: segmentData)
                try synchronizeMediaLocation()
                bytes += segmentData.count
                if let report = segmentReport?.trackReports.first(where: { $0.mediaType == .video }),
                   report.earliestPresentationTimeStamp.isNumeric, report.duration.isNumeric {
                    if reportOrigin == nil { reportOrigin = report.earliestPresentationTimeStamp }
                    let end = CMTimeSubtract(CMTimeAdd(report.earliestPresentationTimeStamp, report.duration), reportOrigin!)
                    if CMTimeCompare(end, durableDuration) > 0 { durableDuration = end }
                }
                if CMTimeCompare(durableDuration, .zero) > 0 {
                    let confirmed = CMTimeAdd(sessionStart, durableDuration)
                    try journal.confirmDurableMedia(segmentID: segment.id,
                        segmentDurationMs: Int(durableDuration.convertScale(1000, method: .roundHalfAwayFromZero).value),
                        sessionTime: MediaTime(value: confirmed.value, timescale: confirmed.timescale), bytes: bytes)
                }
            } catch { failure = error }
        }
    }
}

func retimeCaptureSample(_ sample: CMSampleBuffer, offset: CMTime) throws -> CMSampleBuffer {
    var count = 0
    guard CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count) == noErr else {
        throw CaptureError.sourceFailed("sample timing")
    }
    var times = Array(repeating: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid), count: count)
    guard CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: count, arrayToFill: &times, entriesNeededOut: &count) == noErr else {
        throw CaptureError.sourceFailed("sample timing")
    }
    for index in times.indices {
        times[index].presentationTimeStamp = CMTimeAdd(times[index].presentationTimeStamp, offset)
        if times[index].decodeTimeStamp.isNumeric { times[index].decodeTimeStamp = CMTimeAdd(times[index].decodeTimeStamp, offset) }
    }
    var result: CMSampleBuffer?
    guard CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sample,
        sampleTimingEntryCount: count, sampleTimingArray: &times, sampleBufferOut: &result) == noErr, let result else {
        throw CaptureError.sourceFailed("retime sample")
    }
    return result
}

func captureVideoEnd(_ sample: CMSampleBuffer, frameRate: RecordedFrameRate) -> CMTime {
    let stated = CMSampleBufferGetDuration(sample)
    let duration = stated.isNumeric && CMTimeCompare(stated, .zero) > 0
        ? stated : CMTime(value: Int64(frameRate.den), timescale: Int32(frameRate.num))
    return CMTimeAdd(CMSampleBufferGetPresentationTimeStamp(sample), duration)
}
