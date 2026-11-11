package com.islanddevcrew.jovra.buildlogic.boundaries

import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.api.artifacts.ExternalModuleDependency
import org.gradle.api.artifacts.ProjectDependency
import org.gradle.api.file.ConfigurableFileCollection
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.provider.ListProperty
import org.gradle.api.tasks.CacheableTask
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.InputFiles
import org.gradle.api.tasks.OutputFile
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.TaskAction
import java.io.File
import java.io.Serializable

/**
 * Applied to the root project only. Registers `checkModuleBoundaries` (also run by the root `check`), which gathers
 * every module's kind, declared dependencies and Kotlin/Java sources and fails the build on any [Violation].
 * Needs no Android SDK: it reads the Gradle model and source text only.
 */
class ModuleBoundariesPlugin : Plugin<Project> {
    override fun apply(target: Project) {
        require(target == target.rootProject) { "jovra.module-boundaries is applied to the root project only" }
        target.pluginManager.apply("base")
        val check = target.tasks.register("checkModuleBoundaries", ModuleBoundaryCheckTask::class.java) {
            group = "verification"
            description = "Fails when a module crosses an ADR-0024 module boundary."
            val projects = target.subprojects.filter { it.buildFile.exists() }
            modules.set(target.provider { projects.map { describe(it) } })
            projects.forEach { module ->
                sources.from(module.fileTree("src") { include("**/*.kt", "**/*.java") })
            }
            report.set(target.layout.buildDirectory.file("reports/module-boundaries/report.txt"))
        }
        target.tasks.named("check").configure { dependsOn(check) }
    }

    private fun describe(project: Project): ModuleDescriptor {
        val dependencies = project.configurations.flatMap { it.dependencies }
        return ModuleDescriptor(
            path = project.path,
            kind = if (project.extensions.findByName("android") != null) ModuleKind.ANDROID else ModuleKind.JVM,
            projectDependencies = dependencies.filterIsInstance<ProjectDependency>().map { it.path }.toSortedSet(),
            externalDependencies = dependencies.filterIsInstance<ExternalModuleDependency>()
                .map { "${it.group}:${it.name}" }.toSortedSet(),
            moduleDir = project.projectDir.absolutePath,
        )
    }
}

/** The configuration-time facts about one module; source text is read when the task runs. */
data class ModuleDescriptor(
    val path: String,
    val kind: ModuleKind,
    val projectDependencies: Set<String>,
    val externalDependencies: Set<String>,
    val moduleDir: String,
) : Serializable

@CacheableTask
abstract class ModuleBoundaryCheckTask : DefaultTask() {
    @get:Input
    abstract val modules: ListProperty<ModuleDescriptor>

    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val sources: ConfigurableFileCollection

    @get:OutputFile
    abstract val report: RegularFileProperty

    @TaskAction
    fun checkBoundaries() {
        val facts = modules.get().map { module ->
            val dir = File(module.moduleDir)
            val files = File(dir, "src").walkTopDown()
                .filter { it.isFile && (it.extension == "kt" || it.extension == "java") }
                .map { SourceText(it.relativeTo(dir).invariantSeparatorsPath, it.readText()) }
                .toList()
            ModuleFacts(module.path, module.kind, module.projectDependencies, module.externalDependencies, files)
        }
        val violations = ModuleBoundaries.check(facts)
        val lines = listOf("Checked ${facts.size} modules: ${violations.size} violation(s).") + violations.map { "  $it" }
        report.get().asFile.apply { parentFile.mkdirs() }.writeText(lines.joinToString("\n", postfix = "\n"))
        if (violations.isNotEmpty()) {
            throw GradleException("Module boundary violations:\n" + violations.joinToString("\n") { "  $it" })
        }
        logger.lifecycle(lines.first())
    }
}
