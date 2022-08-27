configure<com.dynatrace.tools.android.dsl.DynatraceExtension> {
    configurations {
        create("sampleConfig") {
            webRequests {
                sensors {
                    // fine-tune the sensors if necessary
                }
            }
        }
    }
}
