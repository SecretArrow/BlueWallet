# ProGuard/R8 rules for the Flutter release build.
# The Flutter engine and plugin registrant reference plugin classes directly,
# so R8 keeps reachable code automatically; the rules below cover
# reflection/JNI entry points and platform-channel plugin packages.

# Flutter embedding
-keep class io.flutter.** { *; }
-keep class androidx.lifecycle.DefaultLifecycleObserver

# JNI / FFI entry points
-keepclasseswithmembernames class * {
    native <methods>;
}

# Platform plugins used by the app (referenced via GeneratedPluginRegistrant,
# kept explicitly so R8 full mode never strips their platform-channel handlers)
-keep class io.flutter.plugins.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keep class dev.fluttercommunity.plus.** { *; }
-keep class com.baseflow.** { *; }
-keep class io.github.ponnamkarthik.** { *; }
-keep class androidx.biometric.** { *; }
-keep class com.lvzhou.** { *; }

# Local auth / secure storage may look up platform classes by name
-dontwarn io.flutter.plugins.**
-dontwarn com.mr.flutter.plugin.**
-dontwarn dev.fluttercommunity.plus.**
