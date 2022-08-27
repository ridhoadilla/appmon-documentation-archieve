configure<com.dynatrace.tools.android.dsl.DynatraceExtension> {
    strictMode(false)
    configurations {
        create("prod") {
           variantFilter("Release")
           // other variant-specific properties
        }
    }
}
