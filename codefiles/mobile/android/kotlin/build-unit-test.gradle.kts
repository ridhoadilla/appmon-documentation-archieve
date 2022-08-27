android {
    buildTypes {
        // build type used for unit tests in the CI
        create("CI") {
            initWith(getByName("debug"))
            applicationIdSuffix = ".debugTesting"
        }
    }
}
