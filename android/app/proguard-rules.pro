# MyGoatFarms — R8 / ProGuard rules for RELEASE builds.
#
# WHY THIS FILE EXISTS
# Release builds shrink and obfuscate the Android code with R8 (full mode
# by default on AGP 8+). flutter_local_notifications stores every
# SCHEDULED notification (the health digest) as JSON with Gson and reads
# it back when the alarm fires. Without the rules below R8 strips the
# generic type information Gson needs, so the alarm fires but the
# notification is silently dropped ("Missing type parameter"). Debug
# builds are not shrunk, which is why it works with `flutter run` but not
# in the release APK.

# --- flutter_local_notifications ---------------------------------------
-keep class com.dexterous.** { *; }

# --- Gson (used by flutter_local_notifications) --------------------------
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-dontwarn sun.misc.**

-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# --- WorkManager background refresh (workmanager plugin) ----------------
-keep class dev.fluttercommunity.workmanager.** { *; }