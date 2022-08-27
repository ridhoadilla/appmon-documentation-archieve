configure<com.dynatrace.tools.android.dsl.DynatraceExtension> {
    configurations {
        create("sampleConfig") {
            hybridWebView {
                enabled(true)
                domains("<domain1>", "<domain2>")
                domains("<anotherDomain>")
            }
        }
    }
}
