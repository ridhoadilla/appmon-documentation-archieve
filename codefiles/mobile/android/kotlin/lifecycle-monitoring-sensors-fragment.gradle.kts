configure<com.dynatrace.tools.android.dsl.DynatraceExtension> {
    configurations {
        create("sampleConfig") {
            lifecycle {
                sensors {
                    fragment(false)
                }
            }
        }
    }
}
