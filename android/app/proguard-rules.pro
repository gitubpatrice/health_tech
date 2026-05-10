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

# androidx.biometric : BiometricPrompt utilise reflection sur des fragments,
# R8 peut renommer la classe -> ClassNotFoundException au prompt biometrique.
-keep class androidx.biometric.** { *; }

# flutter_local_notifications : receivers declares en manifest, R8 peut
# renommer les classes -> ClassNotFoundException au boot device.
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Notre bridge biometrique : appele par Flutter via methodChannel sur la
# classe nommee. Si R8 rename la classe, le channel ne resout plus.
-keep class com.filestech.health_tech.MainActivity { *; }
-keep class com.filestech.health_tech.BiometricBridge { *; }

# Stripped reflection-using libs
-keepattributes Signature, *Annotation*, EnclosingMethod, InnerClasses
