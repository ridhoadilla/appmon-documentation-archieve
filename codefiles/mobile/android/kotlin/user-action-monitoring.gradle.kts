configure<com.dynatrace.tools.android.dsl.DynatraceExtension> {
    configurations {
        create("sampleConfig") {
            userActions {
                // your user action monitoring configuration
            }
        }
    }
}
