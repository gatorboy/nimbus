import org.gradle.api.Project
import org.gradle.api.artifacts.Dependency
import org.gradle.api.artifacts.dsl.DependencyHandler

fun DependencyHandler.nimbusModule(nimbusModule: String): Dependency {
    return project(mapOf("path" to ":modules:$nimbusModule"))
}

fun Project.isAndroidModule(): Boolean {
    return (project.plugins.hasPlugin("com.android.application") ||
        project.plugins.hasPlugin("com.android.library"))
}
