import kotlin.String
import org.gradle.plugin.use.PluginDependenciesSpec
import org.gradle.plugin.use.PluginDependencySpec

/**
 * Generated by https://github.com/jmfayard/buildSrcVersions
 *
 * Find which updates are available by running
 *     `$ ./gradlew buildSrcVersions`
 * This will only update the comments.
 *
 * YOU are responsible for updating manually the dependency version.
 */
object Versions {
    const val org_jetbrains_kotlinx_kotlinx_serialization: String = "0.20.0"

    const val org_jetbrains_kotlin_kotlin_serialization: String = "1.3.72"

    const val com_android_tools_build_gradle: String = "4.0.0"

    const val androidx_test_rules: String = "1.1.1" // available: "1.2.0"

    const val de_fayard_buildsrcversions_gradle_plugin: String = "0.7.0"

    const val kotlin_scripting_compiler_embeddable: String = "1.3.72"

    const val kotlin_android_extensions: String = "1.3.72"

    const val kotlintest_runner_junit4: String = "4.1.1"

    const val gradle_bintray_plugin: String = "1.8.5"

    const val kotlin_gradle_plugin: String = "1.3.72"

    const val kotlinx_metadata_jvm: String = "0.1.0"

    const val dokka_gradle_plugin: String = "0.10.1"

    const val jacoco_android: String = "0.2"

    const val jacoco: String = "0.8.4"

    const val espresso_core: String = "3.2.0"

    const val kotlin_stdlib: String = "1.3.72"

    const val lint_gradle: String = "26.6.3"

    const val kotlinpoet: String = "1.6.0"

    const val appcompat: String = "1.1.0"

    const val ktlint: String = "0.36.0"

    const val guava: String = "29.0-android"

    const val junit: String = "1.1.1"

    const val mockk: String = "1.10.0"

    const val truth: String = "1.0.1"

    const val j2v8: String = "6.1.0@aar"

    const val json: String = "20190722"

    const val k2v8: String = "0.0.1"

    /**
     * Current version: "6.4.1"
     * See issue 19: How to update Gradle itself?
     * https://github.com/jmfayard/buildSrcVersions/issues/19
     */
    const val gradleLatestVersion: String = "6.4.1"
}

/**
 * See issue #47: how to update buildSrcVersions itself
 * https://github.com/jmfayard/buildSrcVersions/issues/47
 */
val PluginDependenciesSpec.buildSrcVersions: PluginDependencySpec
    inline get() =
            id("de.fayard.buildSrcVersions").version(Versions.de_fayard_buildsrcversions_gradle_plugin)
