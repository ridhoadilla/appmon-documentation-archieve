subprojects {
    pluginManager.withPlugin("com.android.library") {
        dependencies {
            "implementation"(com.dynatrace.tools.android.DynatracePlugin.agentDependency())
        }
    }
}
