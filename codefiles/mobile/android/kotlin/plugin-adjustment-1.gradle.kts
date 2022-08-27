buildscript {
    repositories {
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:<version>")
        // add this line to your build.gradle.kts file
        classpath("com.dynatrace.tools.android:gradle-plugin:8.+")
    }
}
