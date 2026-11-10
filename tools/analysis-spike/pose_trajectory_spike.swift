// Local-only feasibility spike: runs Apple Vision over a clip and prints aggregate numbers.
// No frame, crop or thumbnail is written or printed.
import AVFoundation
import Foundation
import Vision

let args = CommandLine.arguments
guard args.count >= 2 else { fatalError("usage: vision_spike <video> [startSeconds] [durationSeconds]") }
let url = URL(fileURLWithPath: args[1])
let start = args.count > 2 ? Double(args[2])! : 0
let duration = args.count > 3 ? Double(args[3])! : 120

let roi: CGRect? = ProcessInfo.processInfo.environment["ROI_Y0"].flatMap(Double.init).map { CGRect(x: 0.2, y: $0, width: 0.6, height: 1 - $0) }
let asset = AVURLAsset(url: url)
let sem = DispatchSemaphore(value: 0)
var trackBox: AVAssetTrack?
Task {
    trackBox = try? await asset.loadTracks(withMediaType: .video).first
    sem.signal()
}
sem.wait()
guard let track = trackBox else { fatalError("no video track") }

let reader = try AVAssetReader(asset: asset)
reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                               duration: CMTime(seconds: duration, preferredTimescale: 600))
let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
])
output.alwaysCopiesSampleData = false
reader.add(output)
reader.startReading()

struct TrajectoryStat { var first: Double; var last: Double; var confidence: Float; var points: Int; var dx: Double; var dy: Double }
var trajectories: [UUID: TrajectoryStat] = [:]
let trajectoryRequest = VNDetectTrajectoriesRequest(frameAnalysisSpacing: .zero, trajectoryLength: 5) { request, _ in
    for case let t as VNTrajectoryObservation in request.results ?? [] {
        let pts = t.detectedPoints
        guard let a = pts.first, let b = pts.last else { continue }
        let now = t.timeRange.end.seconds
        var s = trajectories[t.uuid] ?? TrajectoryStat(first: t.timeRange.start.seconds, last: now, confidence: 0, points: 0, dx: 0, dy: 0)
        s.last = now
        s.confidence = max(s.confidence, t.confidence)
        s.points = max(s.points, pts.count)
        s.dx = Double(b.x - a.x); s.dy = Double(b.y - a.y)
        trajectories[t.uuid] = s
    }
}
trajectoryRequest.objectMinimumNormalizedRadius = 0.0015
trajectoryRequest.objectMaximumNormalizedRadius = 0.02

var frames = 0
var framesWithBody = 0
var framesNearWrists = 0
var framesTwoBodies = 0
var nearHeights: [Double] = []
var farHeights: [Double] = []
var width = 0, height = 0
let clock = Date()

func bodyHeight(_ o: VNHumanBodyPoseObservation) -> (Double, Bool) {
    guard let pts = try? o.recognizedPoints(.all) else { return (0, false) }
    let good = pts.values.filter { $0.confidence > 0.2 }
    guard let lo = good.map(\.location.y).min(), let hi = good.map(\.location.y).max() else { return (0, false) }
    let wrists = (pts[.leftWrist]?.confidence ?? 0) > 0.3 && (pts[.rightWrist]?.confidence ?? 0) > 0.3
    return (Double(hi - lo), wrists)
}

while let sample = output.copyNextSampleBuffer() {
    guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
    if frames == 0 { width = CVPixelBufferGetWidth(pixels); height = CVPixelBufferGetHeight(pixels) }
    frames += 1
    let pose = VNDetectHumanBodyPoseRequest()
    if let roi { pose.regionOfInterest = roi }
    let handler = VNImageRequestHandler(cmSampleBuffer: sample, orientation: .up, options: [:])
    try? handler.perform(roi == nil ? [pose, trajectoryRequest] : [pose])
    let bodies = (pose.results ?? []).map(bodyHeight).sorted { $0.0 > $1.0 }
    if let near = bodies.first, near.0 > 0 {
        framesWithBody += 1
        nearHeights.append(near.0)
        if near.1 { framesNearWrists += 1 }
        if bodies.count > 1, bodies[1].0 > 0 { framesTwoBodies += 1; farHeights.append(bodies[1].0) }
    }
}

func median(_ v: [Double]) -> Double { v.isEmpty ? 0 : v.sorted()[v.count / 2] }
let elapsed = Date().timeIntervalSince(clock)
let confident = trajectories.values.filter { $0.confidence >= 0.9 }
let lasting = confident.filter { $0.last - $0.first >= 0.15 }
let result: [String: Any] = [
    "frames": frames, "width": width, "height": height,
    "seconds_processed": duration, "wall_seconds": (elapsed * 10).rounded() / 10,
    "fps_processing": (Double(frames) / elapsed * 10).rounded() / 10,
    "pose_frames_with_body_pct": (Double(framesWithBody) / Double(max(frames, 1)) * 1000).rounded() / 10,
    "pose_near_both_wrists_pct": (Double(framesNearWrists) / Double(max(frames, 1)) * 1000).rounded() / 10,
    "pose_two_bodies_pct": (Double(framesTwoBodies) / Double(max(frames, 1)) * 1000).rounded() / 10,
    "near_body_height_median_frac": (median(nearHeights) * 1000).rounded() / 1000,
    "second_body_height_median_frac": (median(farHeights) * 1000).rounded() / 1000,
    "trajectories_total": trajectories.count,
    "trajectories_conf_ge_0_9": confident.count,
    "trajectories_conf_ge_0_9_lasting_150ms": lasting.count,
    "trajectories_mostly_vertical_pct": lasting.isEmpty ? 0 : (Double(lasting.filter { abs($0.dy) > abs($0.dx) }.count) / Double(lasting.count) * 1000).rounded() / 10,
]
let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
print(String(data: data, encoding: .utf8)!)
