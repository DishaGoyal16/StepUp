// :stepup_core (copied unchanged from the v2 prototype :core) = pure Kotlin/JVM (NO Android imports). Holds L3 classifier, L4 verifier, L5 ledgers,
// the counter ledger, replay harness and CSV writers, so everything is unit-testable on the JVM.
plugins {
    id("org.jetbrains.kotlin.jvm")
    application
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}

application {
    // Offline replay CLI:  gradlew :stepup_core:run --args="--dir <recording-dir>"
    mainClass.set("com.stepup.trust.replay.ReplayMainKt")
}

tasks.test {
    useJUnit()
    testLogging {
        events("passed", "failed", "skipped")
        showStandardStreams = false
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }
}
