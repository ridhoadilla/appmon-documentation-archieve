configure<com.dynatrace.tools.android.dsl.DynatraceExtension> {
    configurations {
        create("sampleConfig") {
            lifecycle {
                // your lifecycle monitoring configuration
            }
        }
    }
}
