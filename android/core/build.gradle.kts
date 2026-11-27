plugins {
    alias(libs.plugins.kotlin.jvm)
}

kotlin { jvmToolchain(21) }

dependencies {
    api(libs.kotlinx.serialization.json)

    testImplementation(platform(libs.junit5.bom))
    testImplementation(libs.junit5.jupiter)
    testImplementation(libs.junit5.params)
    testRuntimeOnly(libs.junit5.launcher)
}

tasks.test {
    useJUnitPlatform()
    // Shared parity fixtures are read in place (doc 38 §15.2): no copies.
    val fixtures = rootProject.layout.projectDirectory.dir("../fixtures")
    inputs.dir(fixtures).withPropertyName("fixtures").withPathSensitivity(PathSensitivity.RELATIVE)
    systemProperty("fixturesDir", fixtures.asFile.absolutePath)
}
