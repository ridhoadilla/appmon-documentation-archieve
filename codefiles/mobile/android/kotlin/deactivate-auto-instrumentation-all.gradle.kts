configure<com.dynatrace.tools.android.dsl.DynatraceExtension> {
    pluginEnabled(false)
    configurations {
        create("dev") {
            // variant-specific properties
        }
        create("prod") {
            // variant-specific properties
        }
    }
}
