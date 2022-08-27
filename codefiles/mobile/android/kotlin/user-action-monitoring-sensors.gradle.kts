configure<com.dynatrace.tools.android.dsl.DynatraceExtension> {
    configurations {
        create("sampleConfig") {
            userActions {
                sensors {
                    // fine-tune the sensors if necessary
                }
            }
        }
    }
}
