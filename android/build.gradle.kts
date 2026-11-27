plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.ksp) apply false
}

// Robolectric fetches its android-all jars into a local Maven repo (default ~/.m2); keep it under the Gradle user home so
// tests also run with a read-only home directory.
subprojects {
    tasks.withType<Test>().configureEach {
        systemProperty("maven.repo.local", gradle.gradleUserHomeDir.resolve("robolectric-m2").absolutePath)
    }
}
