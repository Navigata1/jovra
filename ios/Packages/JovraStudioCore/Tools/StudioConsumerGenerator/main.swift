import Foundation
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

// Writes `generatedStudioConsumers`, one instance per `<Name>Consumer.swift` test file, each of which must declare
// `struct <Name>Consumer: StudioFixtureConsumer`. Duplicate names or a file without its struct fail the build.
struct DiscoveryError: Error, CustomStringConvertible {
    let description: String
}

func generate() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let output = arguments.first else { throw DiscoveryError(description: "output path required") }
    var names: [String] = []
    for path in arguments.dropFirst().sorted() where path.hasSuffix("Consumer.swift") {
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let source = try String(contentsOfFile: path, encoding: .utf8)
        guard source.contains("struct \(name): StudioFixtureConsumer") else {
            throw DiscoveryError(description: "\(path) must declare struct \(name): StudioFixtureConsumer")
        }
        guard !names.contains(name) else { throw DiscoveryError(description: "two consumer files named \(name)") }
        names.append(name)
    }
    let body = names.map { "    \($0)()," }.joined(separator: "\n")
    let generated = "// Generated from the *Consumer.swift files of this test target; do not edit.\n"
        + "let generatedStudioConsumers: [any StudioFixtureConsumer] = [\n\(body)\n]\n"
    try generated.write(toFile: output, atomically: true, encoding: .utf8)
}

do { try generate() } catch {
    FileHandle.standardError.write(Data("Studio consumer discovery failed: \(error)\n".utf8))
    exit(1)
}
