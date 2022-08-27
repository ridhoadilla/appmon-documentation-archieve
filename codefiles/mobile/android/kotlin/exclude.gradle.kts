configure<com.dynatrace.tools.android.dsl.DynatraceExtension> {
    configurations {
        create("sampleConfig") {
            exclude {
                packages("com.mypackage", "com.another.example")
                classes("com.example.MyClass")
                methods("com.example.ExampleClass.exampleMethod", "com.example.ExampleClass\$InnerClass.anotherMethod")
            }
       }
    }
}
