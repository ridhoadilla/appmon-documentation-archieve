configure<com.dynatrace.tools.android.dsl.DynatraceExtension> {
    configurations {
        create("developer") {
            variantFilter("[dD]ebug")
            autoStart {
                applicationId("<ProductionApplicationID>")
                agentPath("<DebugAgentPathUrl>")
            }
        }
        create("ciTesting") {
            // deactivate instrumentation for CI tests
            variantFilter("CI")
            enabled(false)
        }
        create("prod") {
            variantFilter("[rR]elease")
            autoStart {
                applicationId("<DebugApplicationID>")
                agentPath("<ProductionAgentPathUrl>")
            }
        }
    }
}
