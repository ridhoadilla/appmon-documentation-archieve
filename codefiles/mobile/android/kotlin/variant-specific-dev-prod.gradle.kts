configure<com.dynatrace.tools.android.dsl.DynatraceExtension> {
    configurations {
        create("debug") {
            variantFilter("[dD]ebug")
            autoStart {
                applicationId("<DebugApplicationID>")
                agentPath("<DebugAgentPathUrl>")
            }
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
