import Foundation
import JovraBenchmark
@testable import JovraLabelKit
import Testing

@Suite("Hit candidates from audio onsets")
struct OnsetCandidateFinderTests {
    @Test("on the synthetic sample video every hit click has a candidate within 10 ms, and the clip's sound is not flooded")
    func syntheticSample() async throws {
        let truth = try SampleVideo.truth()
        guard case .found(let candidates) = try await OnsetCandidateFinder.find(in: try SampleVideo.url()) else {
            Issue.record("the sample video has an audio track")
            return
        }
        let hits = (truth.events ?? []).map(\.time)
        #expect(hits.count == 7)
        for hit in hits {
            let nearest = candidates.map { abs($0.seconds - hit.seconds) }.min() ?? .infinity
            #expect(nearest <= 0.010, "hit at \(hit.seconds) s: nearest candidate \(nearest * 1000) ms away")
        }
        #expect(candidates == candidates.sorted())
        #expect(candidates.count <= hits.count * 3, "\(candidates.count) candidates for \(hits.count) hits")
        // Synthetic clicks only: this says the pre-fill works, not how well it does on a real court.
    }

    @Test("silence and steady noise produce no candidates; a click in noise produces one at its onset")
    func envelope() {
        let sampleRate = 48_000.0
        func onsets(_ samples: [Float]) -> [Int] {
            var envelope = OnsetCandidateFinder.Envelope(sampleRate: sampleRate, highPassHz: 2000)
            samples.withUnsafeBufferPointer { envelope.append($0) }
            return OnsetCandidateFinder.onsets(in: envelope, parameters: .init())
        }
        var generator = SystemRandomNumberGenerator()
        let noise = (0..<96_000).map { _ in Float.random(in: -0.01...0.01, using: &generator) }
        #expect(onsets([Float](repeating: 0, count: 96_000)).isEmpty)
        #expect(onsets(noise).isEmpty)
        var clicked = noise
        for i in 0..<240 { clicked[48_000 + i] += (i % 2 == 0 ? 0.6 : -0.6) * Float(240 - i) / 240 }   // 5 ms burst at 1.000 s
        let found = onsets(clicked)
        #expect(found.count == 1)
        #expect(abs(Double(found.first ?? 0) / sampleRate - 1.0) <= 0.004)
        // A click in the very last 10 ms of the sound is still found (the neighbourhood ends with the audio).
        var late = noise
        for i in 0..<240 { late[96_000 - 240 + i] += (i % 2 == 0 ? 0.6 : -0.6) }
        #expect(onsets(late).count == 1)
    }

    @Test("a file without sound reports that, instead of zero candidates")
    func noAudio() async throws {
        // The frame-counter fixtures are video only.
        let truth = try SampleVideo.catalog.truth(id: "frameCounter/fc-030")
        #expect(truth.audio == nil)
        #expect(try await OnsetCandidateFinder.find(in: try SampleVideo.catalog.mediaURL(for: truth)) == .noAudio)
    }

    /// The founder's excerpts are private (docs/fixtures/real-footage.md): this reads their sound only, on
    /// this Mac, and reports a count. It is skipped wherever the files are absent, which includes CI.
    @Test("real excerpt, sound only: the finder runs and offers a workable number of candidates",
          .enabled(if: FileManager.default.fileExists(atPath: OnsetCandidateFinderTests.realExcerpt.path),
                   "real footage absent: set JOVRA_EXCERPTS_DIR (docs/fixtures/real-footage.md)"))
    func realExcerpt() async throws {
        guard case .found(let candidates) = try await OnsetCandidateFinder.find(in: Self.realExcerpt) else {
            Issue.record("the excerpt has an audio track")
            return
        }
        let perMinute = Double(candidates.count) / 2
        print("real excerpt (2 min, sound only): \(candidates.count) candidates, \(perMinute) per minute")
        #expect((10...240).contains(candidates.count))
    }

    static var realExcerpt: URL {
        let folder = ProcessInfo.processInfo.environment["JOVRA_EXCERPTS_DIR"] ?? "/Users/IDC2.5/JOVRA-media/excerpts"
        return URL(fileURLWithPath: folder).appendingPathComponent("match-feb2024-14m00s-2min-720p30.mp4")
    }
}
