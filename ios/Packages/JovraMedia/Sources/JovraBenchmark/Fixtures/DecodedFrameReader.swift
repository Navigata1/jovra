import AVFoundation
import CoreMedia
import Foundation

public enum DecodedFrameReaderError: Error, CustomStringConvertible {
    case noVideoTrack(URL)
    case readerFailed(URL, String)

    public var description: String {
        switch self {
        case .noVideoTrack(let url): "\(url.lastPathComponent) has no video track"
        case .readerFailed(let url, let reason): "AVAssetReader failed on \(url.lastPathComponent): \(reason)"
        }
    }
}

/// Decodes every frame of a fixture with AVFoundation, in coded orientation (no track transform), and
/// reports each frame's presentation time, burned-in frame code and signature levels.
public enum DecodedFrameReader {
    public struct Frame: Sendable {
        public let presentationTime: CMTime
        public let code: Int
        public let levels: [UInt8]
    }

    public static func frames(of url: URL, truth: GroundTruth) async throws -> [Frame] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw DecodedFrameReaderError.noVideoTrack(url)
        }
        let format = truth.video.bitDepth == 10
            ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: format])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        let job = ReadJob(reader: reader, output: output, url: url, columns: truth.signature.columns,
                          rows: truth.signature.rows, cells: truth.frameCode.cells)
        // copyNextSampleBuffer blocks; keep it off the cooperative pool, where parallel tests would starve it.
        return try await withCheckedThrowingContinuation { continuation in
            Thread.detachNewThread {
                continuation.resume(with: Result { try job.run() })
            }
        }
    }

    /// The clip's `jovra.cellLuma.v1` hash as decoded by AVFoundation, and the number of frames decoded.
    public static func signatureHash(of url: URL, truth: GroundTruth) async throws -> (sha256: String, frames: Int) {
        var hasher = ClipSignatureHasher()
        for frame in try await frames(of: url, truth: truth) {
            hasher.add(frame.levels)
        }
        return (hasher.hexDigest(), hasher.frames)
    }
}

/// One synchronous AVAssetReader pass, owned by a single thread for its whole life.
private final class ReadJob: @unchecked Sendable {
    let reader: AVAssetReader
    let output: AVAssetReaderTrackOutput
    let url: URL
    let columns: Int, rows: Int, cells: Int

    init(reader: AVAssetReader, output: AVAssetReaderTrackOutput, url: URL, columns: Int, rows: Int, cells: Int) {
        self.reader = reader
        self.output = output
        self.url = url
        self.columns = columns
        self.rows = rows
        self.cells = cells
    }

    func run() throws -> [DecodedFrameReader.Frame] {
        guard reader.startReading() else {
            throw DecodedFrameReaderError.readerFailed(url, reader.error?.localizedDescription ?? "could not start")
        }
        var frames: [DecodedFrameReader.Frame] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let image = CMSampleBufferGetImageBuffer(sample) else { continue }
            let plane = try LumaPlane(pixelBuffer: image)
            let means = FrameSignature.cellMeans(of: plane, columns: columns, rows: rows)
            frames.append(DecodedFrameReader.Frame(
                presentationTime: CMSampleBufferGetPresentationTimeStamp(sample),
                code: FrameCode.read(means: means, bitDepth: plane.bitDepth, cells: cells),
                levels: FrameSignature.levels(means: means, bitDepth: plane.bitDepth)
            ))
        }
        if reader.status == .failed {
            throw DecodedFrameReaderError.readerFailed(url, reader.error?.localizedDescription ?? "unknown")
        }
        return frames
    }
}
