import Foundation
import PackagePlugin

@main struct FixtureDiscoveryPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        let inputs = target.sourceFiles.map(\.url).filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
        let output = context.pluginWorkDirectoryURL.appendingPathComponent("GeneratedFixtureRunners.swift")
        return [.buildCommand(displayName: "Discover conformance runners by kind",
            executable: try context.tool(named: "FixtureRunnerGenerator").url,
            arguments: [output.path] + inputs.map(\.path),
            inputFiles: inputs, outputFiles: [output])]
    }
}
