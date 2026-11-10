// Local-only: counts person rectangles per frame. Prints aggregates, never imagery.
import AVFoundation
import Foundation
import Vision
let a = CommandLine.arguments
let asset = AVURLAsset(url: URL(fileURLWithPath: a[1]))
let sem = DispatchSemaphore(value: 0); var tr: AVAssetTrack?
Task { tr = try? await asset.loadTracks(withMediaType: .video).first; sem.signal() }; sem.wait()
let reader = try AVAssetReader(asset: asset)
reader.timeRange = CMTimeRange(start: CMTime(seconds: Double(a[2])!, preferredTimescale: 600), duration: CMTime(seconds: Double(a[3])!, preferredTimescale: 600))
let out = AVAssetReaderTrackOutput(track: tr!, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange])
reader.add(out); reader.startReading()
var frames = 0, ge1 = 0, ge2 = 0, upperHalf = 0
var counts: [Int] = []; var smallH: [Double] = []
let t0 = Date()
while let s = out.copyNextSampleBuffer() {
    frames += 1
    if frames % 3 != 0 { continue }   // sample every third frame
    let r = VNDetectHumanRectanglesRequest(); r.upperBodyOnly = false
    try? VNImageRequestHandler(cmSampleBuffer: s, orientation: .up, options: [:]).perform([r])
    let boxes = (r.results ?? []).filter { $0.confidence > 0.5 }.map(\.boundingBox)
    counts.append(boxes.count)
    if boxes.count >= 1 { ge1 += 1 }
    if boxes.count >= 2 { ge2 += 1 }
    // a small person whose box centre is in the upper 45% of the image: candidate far player
    let far = boxes.filter { $0.midY > 0.55 && $0.height < 0.15 }
    if !far.isEmpty { upperHalf += 1; smallH.append(Double(far.map(\.height).max()!)) }
}
let n = max(counts.count, 1)
func pct(_ x: Int) -> Double { (Double(x) / Double(n) * 1000).rounded() / 10 }
print("sampled_frames=\(n) any_person_pct=\(pct(ge1)) two_or_more_pct=\(pct(ge2)) small_person_upper_region_pct=\(pct(upperHalf)) median_small_height_frac=\((smallH.sorted()[safe: smallH.count/2] ?? 0)) max_people=\(counts.max() ?? 0) fps=\((Double(n)/Date().timeIntervalSince(t0)).rounded())")
extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }
