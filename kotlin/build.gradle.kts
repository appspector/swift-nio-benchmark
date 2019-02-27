import org.gradle.jvm.tasks.Jar
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    kotlin("jvm") version "1.3.21"
    application
}

application {
    applicationName = "MornignPagesAPI"
    group = "mormingpages"
    mainClassName = "com.appspector.websocket.MainKt"
}

group = "com.appspector"
version = "1.0-SNAPSHOT"

repositories {
    mavenCentral()
}

dependencies {
    compile(kotlin("stdlib-jdk8"))
    compile(group = "io.netty", name = "netty-all", version = "4.1.33.Final")
}

tasks.withType<KotlinCompile> {
    kotlinOptions.jvmTarget = "1.8"
}

tasks {
    withType<Jar> {
        manifest {
            attributes(mapOf("Main-Class" to application.mainClassName))
        }

        from(configurations.compile.get().map { if (it.isDirectory) it else zipTree(it) })
    }
}