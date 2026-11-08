import Foundation
import PackagePlugin

/// Finds the test target's fixture consumers (S10): every `*Consumer.swift` file declares one `StudioFixtureConsumer`
/// named after the file. The generated list is the only registry, so a Studio ticket adds its consumer file in its own
/// folder and never edits a shared list.
@main struct StudioConsumerDiscoveryPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        let inputs = target.sourceFiles.map(\.url).filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
        let output = context.pluginWorkDirectoryURL.appendingPathComponent("GeneratedStudioConsumers.swift")
        return [.buildCommand(displayName: "Discover Studio fixture consumers",
            executable: try context.tool(named: "StudioConsumerGenerator").url,
            arguments: [output.path] + inputs.map(\.path),
            inputFiles: inputs, outputFiles: [output])]
    }
}
