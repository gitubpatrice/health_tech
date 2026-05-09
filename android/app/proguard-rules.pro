# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.editing.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# SQLCipher
-keep class net.zetetic.** { *; }
-keep class net.sqlcipher.** { *; }

# Pointycastle
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# Local auth biometrics
-keep class androidx.biometric.** { *; }

# Stripped reflection-using libs
-keepattributes Signature, *Annotation*, EnclosingMethod, InnerClasses
