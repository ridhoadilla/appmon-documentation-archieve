apply(plugin = "com.dynatrace.instrumentation")
configure<com.dynatrace.tools.android.dsl.DynatraceExtension> {
    configurations {
        create("sampleConfig") {
            autoStart {
                applicationId("<YourApplicationID>")
                agentPath("<YourAgentPathUrl>")
            }
        }
    }
}
