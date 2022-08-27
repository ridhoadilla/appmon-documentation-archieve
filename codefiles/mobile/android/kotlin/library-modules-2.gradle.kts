subprojects { project ->
    pluginManager.withPlugin("com.android.library") {
        if(project.name == "firstLibrary" || project.name == "secondLibrary") {
            dependencies {
                "implementation"(com.dynatrace.tools.android.DynatracePlugin.agentDependency())
            }
        }
    }
}
