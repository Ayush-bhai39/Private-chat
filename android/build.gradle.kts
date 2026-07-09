allprojects {
    repositories {
        google()
        mavenCentral()
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

subprojects {
    val configureSdk = {
        val android = project.extensions.findByName("android")
        if (android != null) {
            try {
                val base = android as com.android.build.gradle.BaseExtension
                base.compileSdkVersion(36)
            } catch (e: Exception) {
                // Ignore non-android subprojects
            }
        }
    }
    if (project.state.executed) {
        configureSdk()
    } else {
        project.afterEvaluate {
            configureSdk()
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
