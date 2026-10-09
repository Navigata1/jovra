@preconcurrency import AVFoundation
import Foundation

public struct DecodedCapture: Sendable {
    public let videoFrames: Int
    public let duration: CMTime
}
/// Read every video frame, not the asset's declared duration, before claiming a segment is playable.
public func decodeCaptureToEnd(_ url: URL) async throws -> DecodedCapture {
    let asset = AVURLAsset(url: url)
    guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw CaptureError.noVideo }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
    reader.add(output)
    guard reader.startReading() else { throw CaptureError.decodeFailed(reader.error?.localizedDescription ?? "startReading") }
    var count = 0, end = CMTime.zero, previous: CMTime?, lastStep = CMTime.invalid
    while let sample = output.copyNextSampleBuffer() {
        guard CMSampleBufferGetImageBuffer(sample) != nil else { throw CaptureError.decodeFailed("missing decoded image") }
        count += 1
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        let duration = CMSampleBufferGetDuration(sample)
        if duration.isNumeric, CMTimeCompare(duration, .zero) > 0 { lastStep = duration }
        else if let previous { lastStep = CMTimeSubtract(pts, previous) }
        end = pts; previous = pts
    }
    guard count > 0, reader.status == .completed else { throw CaptureError.decodeFailed(reader.error?.localizedDescription ?? "incomplete segment") }
    guard lastStep.isNumeric, CMTimeCompare(lastStep, .zero) > 0 else { throw CaptureError.decodeFailed("missing frame duration") }
    return DecodedCapture(videoFrames: count, duration: CMTimeAdd(end, lastStep))
}
