import Foundation
import JovraBenchmark
import Testing

/// The label set (spec/benchmarks/labels/manifest.json) records each sealed label file with its hash and split.
@Suite("Benchmark label set")
struct BenchmarkLabelSetTests {
    /// A scratch repository holding a label set whose match recording is the fixture hash and needs `target` hits.
    struct Scratch {
        let root: URL

        init(target: Int) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("jovra-label-set-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root.appendingPathComponent(BenchmarkLabelSet.folder), withIntermediateDirectories: true)
            let manifest = """
            {"schemaVersion": "1.0.0", "kind": "jovra.benchmarkLabelSet", "description": "test", "status": "founderPending",
             "recordings": [{"role": "match", "sha256": "\(LabelSplitTests.recording)", "description": "synthetic", "targets": {"hits": \(target)}}],
             "labelFiles": []}
            """
            try Data(manifest.utf8).write(to: root.appendingPathComponent(BenchmarkLabelSet.path))
        }

        func write(_ labels: BenchmarkLabels, name: String? = nil) throws -> URL {
            let url = root.appendingPathComponent(BenchmarkLabelSet.folder).appendingPathComponent(name ?? labels.fileName)
            try labels.encoded().write(to: url)
            return url
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    @Test("the committed set lists the three recordings with the ticket's targets")
    func committed() throws {
        let root = MediaFixtureCatalog.repository().root
        let set = try BenchmarkLabelSet.load(repository: root)
        #expect(set.recordings.map(\.role) == ["match", "cornerAngle", "sideView"])
        #expect(set.recordings[0].targets == ["hits": 300, "bounces": 150])
        #expect(set.recordings[2].targets == ["strokes": 100])
        #expect(try JSONDecoder().decode(BenchmarkLabelSet.self, from: set.encoded()) == set)
        if set.labelFiles.isEmpty {
            #expect(set.status == .founderPending)
            #expect(set.progress.allSatisfy { $0.labelled == 0 && !$0.met })
        }
    }

    @Test("sealing records the file's hash, its split and its counts, and completes the set when the targets are met")
    func seal() throws {
        let scratch = try Scratch(target: 2)
        defer { scratch.remove() }
        let labels = try BenchmarkLabelsTests.labels()
        let url = try scratch.write(labels)
        let sealed = try BenchmarkLabelSet.load(repository: scratch.root).sealing(labelFile: url, repository: scratch.root)
        let entry = try #require(sealed.labelFiles.first)
        #expect(sealed.labelFiles.count == 1)
        #expect(entry.path == "spec/benchmarks/labels/rec-d9db095691ae.labels.json")
        #expect(entry.labelsSha256 == BenchmarkLabels.sha256(of: try Data(contentsOf: url)))
        #expect(entry.split == labels.split)
        #expect(entry.split.heldOutWindows == [1])
        #expect(entry.counts == labels.counts)
        #expect(sealed.status == .complete)
        #expect(sealed.progress == [.init(role: "match", target: "hits", wanted: 2, labelled: 2)])
        // Sealing again replaces the entry instead of counting the file twice.
        #expect(try sealed.sealing(labelFile: url, repository: scratch.root) == sealed)
    }

    @Test("below the target the set stays founder-pending")
    func pending() throws {
        let scratch = try Scratch(target: 300)
        defer { scratch.remove() }
        let url = try scratch.write(try BenchmarkLabelsTests.labels())
        let sealed = try BenchmarkLabelSet.load(repository: scratch.root).sealing(labelFile: url, repository: scratch.root)
        #expect(sealed.status == .founderPending)
        #expect(sealed.progress == [.init(role: "match", target: "hits", wanted: 300, labelled: 2)])
    }

    @Test("a sealed set passes the Python validator, and editing the label file afterwards fails it")
    func validatorAgrees() throws {
        let repository = MediaFixtureCatalog.repository().root
        let scratch = try Scratch(target: 2)
        defer { scratch.remove() }
        let labels = try BenchmarkLabelsTests.labels()
        let url = try scratch.write(labels)
        let sealed = try BenchmarkLabelSet.load(repository: scratch.root).sealing(labelFile: url, repository: scratch.root)
        try sealed.encoded().write(to: scratch.root.appendingPathComponent(BenchmarkLabelSet.path))
        func problems() throws -> String {
            let script = """
            import json, sys
            sys.path[:0] = [sys.argv[1] + '/scripts/spec', sys.argv[1] + '/spec/reference']
            from pathlib import Path
            from jsonschema_subset import SchemaSet
            from cases import label_scoring_cases as cases
            root = Path(sys.argv[2])
            doc = json.loads((root / 'spec/benchmarks/labels/manifest.json').read_text())
            schemas = SchemaSet(Path(sys.argv[1]) / 'spec/schemas')
            found = schemas.validate(doc, 'benchmark-label-set.schema.json') + cases.label_set_problems(doc, root)
            for entry in doc['labelFiles']:
                labels = json.loads((root / entry['path']).read_text())
                found += schemas.validate(labels, 'benchmark-labels.schema.json') + cases.check_labels(root / entry['path'], labels, {})
            print(json.dumps(found))
            """
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", "-c", script, repository.path, scratch.root.path]
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #expect(try problems() == "[]")
        try labels.replacing(hits: [labels.hits[0]]).encoded().write(to: url)
        #expect(try problems().contains("changed after it was sealed"))
    }

    @Test("a wrong name, a file outside the labels folder, synthetic labels and an open rally are refused")
    func refusals() throws {
        let scratch = try Scratch(target: 2)
        defer { scratch.remove() }
        let set = try BenchmarkLabelSet.load(repository: scratch.root)
        let labels = try BenchmarkLabelsTests.labels()
        let misnamed = try scratch.write(labels, name: "match.labels.json")
        #expect(throws: LabelSetError.wrongFileName(expected: "rec-d9db095691ae.labels.json", actual: "match.labels.json")) {
            try set.sealing(labelFile: misnamed, repository: scratch.root)
        }
        let outside = scratch.root.appendingPathComponent(labels.fileName)
        try labels.encoded().write(to: outside)
        #expect(throws: LabelSetError.notInLabelsFolder(outside.path)) { try set.sealing(labelFile: outside, repository: scratch.root) }
        let synthetic = try scratch.write(try BenchmarkLabelsTests.labels(method: .synthetic))
        #expect(throws: LabelSetError.notHumanLabels) { try set.sealing(labelFile: synthetic, repository: scratch.root) }
        let open = try scratch.write(labels.replacing(rallies: [.init(start: BenchmarkLabelsTests.ms(4000), end: nil)]))
        #expect(throws: LabelSetError.openRally) { try set.sealing(labelFile: open, repository: scratch.root) }
    }
}
