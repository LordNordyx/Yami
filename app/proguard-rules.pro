# SDL calls into Java via JNI by name.
-keep class org.libsdl.app.** { *; }
-keep class com.lordnordyx.yami.player.** { *; }
-keepclassmembers class * { native <methods>; }
-dontwarn org.libsdl.app.**
