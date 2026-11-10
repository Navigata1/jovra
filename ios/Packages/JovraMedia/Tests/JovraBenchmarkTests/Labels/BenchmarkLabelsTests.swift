import Foundation
import JovraBenchmark
import Testing

@Suite("Benchmark label documents")
struct BenchmarkLabelsTests {
    static let recordingHash = LabelSplitTests.recording

    static func ms(_ value: Int64) -> RationalTime { RationalTime(value: value, timescale: 1000) }

    static func recording(seconds: Int64 = 120) -> BenchmarkLabels.Recording {
        .init(sha256: recordingHash, byteSize: 1_048_576, duration: RationalTime(value: seconds, timescale: 1), width: 1280, height: 720,
              frameRate: .init(num: 30, den: 1), variableFrameRate: false)
    }

    static func labels(method: BenchmarkLabels.LabelledBy.Method = .human) throws -> BenchmarkLabels {
        try BenchmarkLabels(recording: recording(), labelledBy: .init(method: method, tool: "jovra-label@1.0.0")).replacing(
            hits: [.init(time: ms(5000), player: .near, stroke: .forehand), .init(time: ms(6500), player: .far)],
            bounces: [.init(time: ms(5500), imagePoint: ImagePoint(x: 0.5, y: 0.4))],
            rallies: [.init(start: ms(4000), end: ms(9000))],
            cameraPositions: [.init(from: ms(0), corners: .init(points: [ImagePoint(x: 0.3, y: 0.2), nil, ImagePoint(x: 0.95, y: 0.9), ImagePoint(x: 0.05, y: 0.9)]))],
            hitCandidates: .some(.init(method: "jovra.audioOnsets.v1", items: [.init(time: ms(5030), decision: .confirmed), .init(time: ms(5600), decision: .rejected)])))
    }

    @Test("a new document carries the recording's hash-fixed split and no labels")
    func empty() throws {
        let labels = try BenchmarkLabels(recording: Self.recording(), labelledBy: .init(method: .human, tool: "jovra-label@1.0.0"))
        #expect(labels.split.heldOutWindows == [1])
        #expect(labels.counts == .init(hits: 0, strokes: 0, bounces: 0, rallies: 0, cameraPositions: 0))
        #expect(labels.problems().isEmpty)
        #expect(labels.fileName == "rec-d9db095691ae.labels.json")
    }

    @Test("encoding is stable, round-trips, and writes an unlabelled stroke and a hidden corner as null")
    func roundTrip() throws {
        let labels = try Self.labels()
        let data = try labels.encoded()
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.hasSuffix("}\n"))
        #expect(text.contains("\"stroke\" : null"))
        #expect(text.contains("null,"))
        let decoded = try JSONDecoder().decode(BenchmarkLabels.self, from: data)
        #expect(decoded == labels)
        #expect(try decoded.encoded() == data)
        #expect(labels.counts == .init(hits: 2, strokes: 1, bounces: 1, rallies: 1, cameraPositions: 1))
    }

    @Test("a label file holds no name, no path and no imagery: only the keys of the schema")
    func nothingPrivate() throws {
        let object = try #require(JSONSerialization.jsonObject(with: try Self.labels().encoded()) as? [String: Any])
        #expect(Set(object.keys) == ["schemaVersion", "kind", "recording", "labelledBy", "split", "hits", "bounces", "rallies", "cameraPositions", "hitCandidates"])
        let recording = try #require(object["recording"] as? [String: Any])
        #expect(Set(recording.keys) == ["sha256", "byteSize", "duration", "width", "height", "frameRate", "variableFrameRate"])
        let labelledBy = try #require(object["labelledBy"] as? [String: Any])
        #expect(Set(labelledBy.keys) == ["method", "tool"])
    }

    @Test("the Swift document validates against the shared schema's shape: the Python validator accepts it")
    func acceptedByTheValidator() throws {
        let root = MediaFixtureCatalog.repository().root
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("jovra-labels-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var synthetic = try Self.labels(method: .synthetic)
        synthetic = synthetic.replacing(hitCandidates: .some(nil))
        try synthetic.encoded().write(to: file)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", root.appendingPathComponent("scripts/spec/validate.py").path, "--document", file.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "\(output)")
        #expect(output.contains("external documents"))
    }

    @Test("order, duplicates, open rallies, late times and a hand-picked split are reported")
    func problems() throws {
        let base = try Self.labels()
        #expect(base.problems().isEmpty)
        #expect(base.replacing(hits: base.hits.reversed()).problems() == ["hits are not in time order"])
        #expect(base.replacing(hits: [base.hits[0], base.hits[0]]).problems() == ["two hits by the near player at 5 s"])
        #expect(base.replacing(rallies: [.init(start: Self.ms(1000), end: nil), .init(start: Self.ms(4000), end: Self.ms(9000))]).problems()
                == ["rally 1 is open but is not the last rally"])
        #expect(base.replacing(rallies: [.init(start: Self.ms(4000), end: Self.ms(9000)), .init(start: Self.ms(8000), end: Self.ms(9500))]).problems()
                == ["rally 2 starts before the previous rally ends"])
        #expect(base.replacing(bounces: [.init(time: Self.ms(121_000), imagePoint: ImagePoint(x: 0.5, y: 0.5))]).problems()
                == ["bounces hold a time after the recording ends"])
        #expect(base.replacing(bounces: [.init(time: Self.ms(1000), imagePoint: ImagePoint(x: 1.5, y: 0.5))]).problems()
                == ["an image point lies outside the picture"])
        let picked = try LabelSplit(recordingSha256: LabelSplitTests.hash("someone else's recording 3"), duration: base.recording.duration)
        let tampered = BenchmarkLabels(recording: base.recording, labelledBy: base.labelledBy, split: picked, hits: base.hits)
        #expect(picked.heldOutWindows != base.split.heldOutWindows)
        #expect(tampered.problems() == ["split is not the hash-fixed split of this recording"])
    }

    @Test("image points are clamped to the picture and rounded to six places")
    func normalizedPoints() {
        #expect(ImagePoint(x: 0.12345678, y: 1.2).normalized == ImagePoint(x: 0.123457, y: 1))
        #expect(ImagePoint(x: -0.1, y: 0.5).normalized == ImagePoint(x: 0, y: 0.5))
    }
}
