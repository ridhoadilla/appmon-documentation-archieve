configure<com.dynatrace.tools.android.dsl.DynatraceExtension> {
    configurations {
        create("sampleConfig") {
            exclude {
                // exclude all inner classes
                filter {
                    className("\$")
                }

                // exclude all methods that fulfill this requirements
                filter {
                    // the class is part of the "com.example" package
                    className("^com\\.example\\.")
                    // the method name contain the phrase "webrequest" (uppercase notation is ignored for two letters)
                    methodName("[wW]eb[rR]equest")
                    // where the last parameter is a String and where the return value is void
                    methodDescription("Ljava/lang/String;\\)V")
                }
            }
        }
    }
}
