configure<com.dynatrace.tools.android.dsl.DynatraceExtension> {
    configurations {
        create("sampleConfig") {
            debug {
                certificateValidation(false)
            }
        }
    }
}
