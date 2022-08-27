configure<com.dynatrace.tools.android.dsl.DynatraceExtension> {
    configurations {
        create("sampleConfig") {
            lifecycle {
                sensors {
                    // fine-tune the sensors if necessary
                }
            }
        }
    }
}
