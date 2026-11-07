// All plugins default to different JVM targets (1.8 vs 17 vs 25)
// which recent AGP refuses to build. Force 17 everywhere.
// The android extension's compileOptions are what AGP reads when it
// configures JavaCompile tasks, so set them via reflection here — the
// Kotlin DSL does not expose them on the generic extension type.
gradle.projectsEvaluated {
    allprojects {
        afterEvaluate {
            try {
                val android = extensions.findByName("android")
                val compileOptions = android?.javaClass
                    ?.getMethod("getCompileOptions")
                    ?.invoke(android)
                compileOptions?.javaClass
                    ?.getMethod("setSourceCompatibility", String::class.java)
                    ?.invoke(compileOptions, "17")
                compileOptions?.javaClass
                    ?.getMethod("setTargetCompatibility", String::class.java)
                    ?.invoke(compileOptions, "17")
            } catch (_: Exception) {
                // Not an Android module — nothing to do.
            }
            tasks.withType<JavaCompile>().configureEach {
                sourceCompatibility = JavaVersion.VERSION_17.toString()
                targetCompatibility = JavaVersion.VERSION_17.toString()
            }
            tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
                compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
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

// Align every Kotlin task project-wide to JVM 17. receive_sharing_intent
// ships with Kotlin defaults that target JVM 25, which the AGP Java
// compatibility check rejects (sourceCompatibility 17 vs target 25).
subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
