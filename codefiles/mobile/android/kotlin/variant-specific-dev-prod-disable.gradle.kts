configure<com.dynatrace.tools.android.dsl.DynatraceExtension> {
    configurations {
        create("debug") {
            variantFilter("[dD]ebug")
            enabled(false)
        }
        create("prod") {
            variantFilter("[rR]elease")
            autoStart {
                applicationId("<ProductionApplicationID>")
                agentPath("<ProductionAgentPathUrl>")
            }
        }
    }
}
