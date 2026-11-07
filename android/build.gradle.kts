// All plugins default to different JVM targets (1.8 vs 17 vs 25)
// which recent AGP refuses to build. The Gradle-recommended fix for
// AGP 8+/KGP involves a JVM toolchain so BOTH the Java and Kotlin
// sides follow the same toolchain release (17) on every subproject.
allprojects {
    if (plugins.hasPlugin("java")) {
        extensions.configure<JavaPluginExtension> {
            toolchain {
                languageVersion.set(JavaLanguageVersion.of(17))
            }
        }
    }
    plugins.withId("org.jetbrains.kotlin.android") {
        extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension> {
            jvmToolchain(17)
        }
    }
    plugins.withId("org.jetbrains.kotlin.jvm") {
        extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinJvmProjectExtension> {
            jvmToolchain(17)
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
