import AVFoundation
import Foundation
import JovraBenchmark
import JovraMedia

/// Finds sharp sounds in a recording's audio and offers them as hit candidates (`jovra.audioOnsets.v1`), so
/// the labeller confirms or rejects instead of searching.
///
/// This is a labelling aid, not the audio hit detection capability (T34): it favours recall, it has no
/// benchmark, and its output is never ground truth. Bounces, footsteps and neighbouring courts appear among
/// the candidates and are rejected by the labeller.
///
/// Method: a 2 kHz high-pass, the RMS envelope in 2 ms steps, and a 10 ms envelope for detection. A candidate
/// is a 10 ms step that is the loudest within 120 ms either side and at least `ratio` times the median of the
/// second around it. Its time is the first 2 ms step, up to 30 ms earlier, that reaches half the peak.
public enum OnsetCandidateFinder {
    public static let method = "jovra.audioOnsets.v1"

    public struct Parameters: Sendable, Equatable {
        public var highPassHz: Double = 2000
        /// How many times the local median a peak must reach.
        public var ratio: Float = 6
        /// Peaks quieter than this (full scale = 1) are ignored whatever the background.
        public var floor: Float = 0.002
        public var neighbourhoodMs: Int = 120

        public init() {}
    }

    public enum Outcome: Sendable, Equatable {
        case noAudio
        case found([RationalTime])
    }

    /// Reads the first audio track and returns its onsets, or `.noAudio` when the file has none.
    public static func find(in url: URL, parameters: Parameters = Parameters()) async throws -> Outcome {
        let asset = AVURLAsset(url: url)
        guard let track = try await AssetLoading.tracks(of: asset, mediaType: .audio).first,
              let audio = try await MediaProbe.probe(url).audio, audio.sampleRate > 0 else { return .noAudio }
        let sampleRate = Double(audio.sampleRate)
        return try await Task.detached(priority: .utility) {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false, AVNumberOfChannelsKey: 1,
            ])
            reader.add(output)
            guard reader.startReading() else { throw reader.error ?? RecordingError.unreadable("the audio could not be read") }
            var envelope = Envelope(sampleRate: sampleRate, highPassHz: parameters.highPassHz)
            var firstTime: CMTime?
            var samples: [Float] = []
            while let buffer = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                if firstTime == nil { firstTime = CMSampleBufferGetPresentationTimeStamp(buffer) }
                guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
                // Copy the bytes out: a block buffer need not be one contiguous run of memory, so a pointer
                // into it is only good for part of its length.
                let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
                guard count > 0 else { continue }
                if samples.count < count { samples = [Float](repeating: 0, count: count) }
                let status = samples.withUnsafeMutableBytes { bytes in
                    CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size, destination: bytes.baseAddress!)
                }
                guard status == kCMBlockBufferNoErr else { continue }
                samples.withUnsafeBufferPointer { envelope.append(UnsafeBufferPointer(rebasing: $0[0..<count])) }
            }
            if reader.status == .failed { throw reader.error ?? RecordingError.unreadable("the audio could not be read") }
            let start = firstTime.flatMap { $0.isNumeric ? $0.seconds : nil } ?? 0
            let offset = Int64((max(start, 0) * sampleRate).rounded())
            let timescale = Int64(sampleRate.rounded())
            return .found(onsets(in: envelope, parameters: parameters).map { RationalTime(value: Int64($0) + offset, timescale: timescale) })
        }.value
    }

    /// The high-passed RMS envelope in 2 ms steps, built as the audio streams past.
    struct Envelope {
        let fineHop: Int
        private(set) var fine: [Float] = []
        private var sum: Float = 0
        private var filled = 0
        // Direct-form-I biquad high-pass (RBJ cookbook, Q = 0.7071).
        private let b0: Float, b1: Float, b2: Float, a1: Float, a2: Float
        private var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

        init(sampleRate: Double, highPassHz: Double) {
            fineHop = max(Int((sampleRate * 0.002).rounded()), 1)
            let w = 2 * Double.pi * min(highPassHz, sampleRate * 0.45) / sampleRate
            let alpha = sin(w) / (2 * 0.7071), cosw = cos(w), a0 = 1 + alpha
            b0 = Float((1 + cosw) / 2 / a0)
            b1 = Float(-(1 + cosw) / a0)
            b2 = Float((1 + cosw) / 2 / a0)
            a1 = Float(-2 * cosw / a0)
            a2 = Float((1 - alpha) / a0)
        }

        mutating func append(_ samples: UnsafeBufferPointer<Float>) {
            for x in samples {
                let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                x2 = x1; x1 = x; y2 = y1; y1 = y
                sum += y * y
                filled += 1
                if filled == fineHop {
                    fine.append((sum / Float(fineHop)).squareRoot())
                    sum = 0
                    filled = 0
                }
            }
        }
    }

    /// Onsets as sample indexes from the start of the audio.
    static func onsets(in envelope: Envelope, parameters: Parameters) -> [Int] {
        let fine = envelope.fine, group = 5                       // 5 x 2 ms = 10 ms
        let coarseCount = fine.count / group
        guard coarseCount > 0 else { return [] }
        var coarse = [Float](repeating: 0, count: coarseCount)
        for k in 0..<coarseCount {
            var total: Float = 0
            for i in 0..<group { total += fine[k * group + i] * fine[k * group + i] }
            coarse[k] = (total / Float(group)).squareRoot()
        }
        // Background: the median of the second around every tenth step.
        let stride = 10, half = 50
        var background = [Float](repeating: 0, count: (coarseCount + stride - 1) / stride)
        for index in background.indices {
            let centre = index * stride
            let window = coarse[max(centre - half, 0)..<min(centre + half + 1, coarseCount)].sorted()
            background[index] = window[window.count / 2]
        }
        let reach = max(parameters.neighbourhoodMs / 10, 1)
        var found: [Int] = []
        for k in 0..<coarseCount {
            let level = coarse[k]
            guard level >= parameters.floor, level >= parameters.ratio * background[k / stride] else { continue }
            let low = max(k - reach, 0), high = min(k + reach, coarseCount - 1)
            // The loudest step of its neighbourhood; of two equal steps the earlier one wins.
            guard !coarse[low..<k].contains(where: { $0 >= level }), !coarse[(k + 1)..<(high + 1)].contains(where: { $0 > level }) else { continue }
            let last = k * group + group - 1, first = max(k * group - 15, 0)
            let peak = fine[first...last].max() ?? level
            let onset = (first...last).first { fine[$0] >= peak / 2 } ?? k * group
            found.append(onset * envelope.fineHop)
        }
        return found
    }
}
