buildscript {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://chaquo.com/maven") }
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.11.1")
        // NOTE: the Chaquopy Gradle plugin is declared in settings.gradle.kts
        // (plugins DSL, com.chaquo.python 17.0.0). Do NOT add a legacy
        // buildscript classpath for it here - a stale classpath version wins
        // resolution and silently downgrades the plugin (that is exactly how a
        // 15.0.1-built libchaquopy_java.so with 4 KB ELF alignment ended up in
        // the APK and crashed on 16 KB page-size devices: "program alignment
        // (4096) cannot be smaller than system page size (16384)").
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://chaquo.com/maven") }
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