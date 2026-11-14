# MainActivity exposes JNI methods by their Java/Kotlin names.
-keep class io.iemdriver.iem_driver.MainActivity { *; }

# Keep native method names and signatures used by JNI symbol lookup.
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}
