import Foundation
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

struct DiscoveryError: Error { let detail: String }
func generate() throws {

let arguments = Array(CommandLine.arguments.dropFirst())
guard let output = arguments.first else { throw DiscoveryError(detail: "Output path required") }
var owners: [String: String] = [:]
var runners: [String] = []
for path in arguments.dropFirst().sorted() where path.contains("/Conformance/Runners/") && path.hasSuffix("Runner.swift") {
    let source = try String(contentsOfFile: path, encoding: .utf8)
    let markers = source.components(separatedBy: .newlines).filter { $0.hasPrefix("// fixture-kind: ") }
    guard markers.count == 1 else { throw DiscoveryError(detail: "One fixture-kind marker required in \(path)") }
    let kind = String(markers[0].dropFirst("// fixture-kind: ".count))
    guard owners[kind] == nil else { throw DiscoveryError(detail: "Duplicate conformance ownership for \(kind): \(owners[kind]!) and \(path)") }
    let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    guard source.contains("struct \(name): FixtureRunner") else { throw DiscoveryError(detail: "Runner type must match filename \(name)") }
    owners[kind] = path
    runners.append(name + "()")
}
let generated = "// Generated from one runner file per kind; do not edit.\nlet generatedFixtureRunners: [any FixtureRunner] = [\n    " + runners.joined(separator: ",\n    ") + "\n]\n"
try generated.write(toFile: output, atomically: true, encoding: .utf8)

}
do { try generate() } catch {
    FileHandle.standardError.write(Data("Conformance runner discovery failed: \(error)\n".utf8))
    exit(1)
}
