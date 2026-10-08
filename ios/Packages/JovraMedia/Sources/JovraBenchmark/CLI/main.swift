// jovra-benchmark: run a registered estimator through the benchmark harness and write its record.
//
//   swift run --package-path ios/Packages/JovraMedia jovra-benchmark run \
//     --estimator oracle.eventTimes --clip harness/events-s23 --mode gate --floor harnessSelfTest \
//     --out spec/fixtures/media/benchmark/oracle.gate.json
//
// Options: --tolerance VALUE/TIMESCALE (event tasks, default 50/1000), --capability ID (candidate estimators
// only; the floor defaults to, and must equal, that capability's registry gate), --run-id ID, --repo PATH
// (default: the repository containing the current directory). Each --clip counts once.
// `jovra-benchmark list` prints the registered estimators and floors.
// Exit status: 0 record written (tuning run, or gate passed); 3 record written and the gate FAILED;
// 2 refused or invalid (no record written).

import Foundation
import JovraBenchmark

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data("jovra-benchmark: \(message)\n".utf8))
    exit(code)
}

func parse(_ args: ArraySlice<String>) -> [String: [String]] {
    var options: [String: [String]] = [:]
    var iterator = args.makeIterator()
    while let flag = iterator.next() {
        guard flag.hasPrefix("--"), let value = iterator.next() else { fail("expected --flag value pairs, got \(flag)") }
        options[String(flag.dropFirst(2)), default: []].append(value)
    }
    return options
}

func tolerance(_ text: String) -> RationalTime {
    let parts = text.split(separator: "/").compactMap { Int64($0) }
    guard parts.count == 2, parts[0] >= 0, parts[1] > 0 else { fail("--tolerance must be VALUE/TIMESCALE, e.g. 50/1000") }
    return RationalTime(value: parts[0], timescale: parts[1])
}

let arguments = CommandLine.arguments.dropFirst()
switch arguments.first {
case "list":
    print("estimators: " + EstimatorRegistry.all.keys.sorted().joined(separator: ", "))
    print("floors: " + Floor.builtIn.keys.sorted().joined(separator: ", "))
case "run":
    let options = parse(arguments.dropFirst())
    func one(_ key: String) -> String? { options[key]?.last }
    guard let estimatorID = one("estimator"), let runner = EstimatorRegistry.all[estimatorID] else {
        fail("--estimator must be one of: " + EstimatorRegistry.all.keys.sorted().joined(separator: ", "))
    }
    guard let clips = options["clip"], !clips.isEmpty else { fail("give at least one --clip set/id") }
    guard let mode = one("mode").flatMap(RunMode.init(rawValue:)) else { fail("--mode gate|tuning") }
    guard let out = one("out") else { fail("--out PATH") }
    let catalog: MediaFixtureCatalog
    do {
        catalog = try MediaFixtureCatalog.locate(from: URL(fileURLWithPath: one("repo") ?? FileManager.default.currentDirectoryPath))
    } catch {
        fail("\(error)")
    }
    var floor: Floor?
    if let name = one("floor") {
        guard let found = Floor.builtIn[name] else { fail("unknown floor \(name); known: \(Floor.builtIn.keys.sorted())") }
        floor = found
    } else if let capability = one("capability"), mode == .gate {
        do { floor = try Floor.capabilityGate(capability, catalog: catalog) } catch { fail("\(error)") }
    }
    let now = Date()
    let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "")
    let request = RunRequest(clipIDs: clips, mode: mode, floor: floor, capabilityId: one("capability"),
                             tolerance: one("tolerance").map(tolerance) ?? RunRequest.defaultTolerance,
                             runId: one("run-id") ?? "\(estimatorID)-\(mode.rawValue)-\(stamp)", at: now)
    do {
        let record = try await runner(BenchmarkHarness(catalog: catalog), request)
        let url = URL(fileURLWithPath: out, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try record.encoded().write(to: url, options: .atomic)
        let summary = record.metrics.map { "\($0.name) \($0.value ?? "undefined")\($0.unit.map { " \($0)" } ?? "")" }.joined(separator: ", ")
        print("wrote \(out): \(record.estimator.id) \(record.estimator.methodVersion), \(record.mode.rawValue) on \(clips.joined(separator: ", "))")
        print("metrics: \(summary)")
        if let verdict = record.verdict {
            for check in verdict.checks {
                print("  \(check.passed ? "PASS" : "FAIL") \(check.name) \(check.value ?? "undefined") \(check.comparator.rawValue) \(check.threshold)")
            }
            print("verdict: \(verdict.passed ? "PASSED" : "FAILED") the floor (\(record.floor?.source ?? ""))")
            if !verdict.passed { exit(3) }
        } else {
            print("verdict: none (tuning run; gates nothing)")
        }
    } catch {
        fail("\(error)")
    }
default:
    fail("usage: jovra-benchmark run --estimator ID --clip SET/ID [--clip ...] --mode gate|tuning [--floor NAME] --out PATH | list")
}
