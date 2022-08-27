configure<com.dynatrace.tools.android.dsl.DynatraceExtension> {
    configurations {
        create("dev") {
            enabled(false)
            variantFilter("Debug")
        }
        create("prod") {
            // variant-specific properties
        }
    }
}
