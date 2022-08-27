configure<com.dynatrace.tools.android.dsl.DynatraceExtension> {
    configurations {
        create("sampleConfig") {
            webRequests {
                // your web request monitoring configuration
            }
        }
    }
}
