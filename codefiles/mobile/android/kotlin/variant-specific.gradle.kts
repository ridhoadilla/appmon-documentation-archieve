configure<com.dynatrace.tools.android.dsl.DynatraceExtension> {
    configurations {
        create("dev") {
            // build type name is upper case because a product flavor is used
            variantFilter("Debug")
            // other variant-specific properties
        }
        create("demo") {
            // the first product flavor name is always lower case
            variantFilter("demo")
            // other variant-specific properties
        }
        create("prod") {
            // build type name is upper case because a product flavor is used
            variantFilter("Release")
            // other variant-specific properties
        }
    }
}
