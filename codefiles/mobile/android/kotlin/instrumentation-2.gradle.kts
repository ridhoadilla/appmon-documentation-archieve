buildscript {
    repositories {
    	google()
        mavenCentral() // hosts the Dynatrace Android Gradle plugin
    }
    dependencies {
        classpath("com.android.tools.build:gradle:<version>")
        // add this line to your build.gradle.kts file
        classpath("com.dynatrace.tools.android:gradle-plugin:8.+")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral() // hosts the OneAgent SDK for Android
    }
}
