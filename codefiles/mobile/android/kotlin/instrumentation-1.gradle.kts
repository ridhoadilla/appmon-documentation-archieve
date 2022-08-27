buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // build script classpath of the Android Gradle plugin
        classpath("com.android.tools.build:gradle:<version>")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
