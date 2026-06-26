# Firebase - preservar classes para Auth, Firestore e funções
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Firestore - evitar ofuscação que quebra serialização
-keep class io.flutter.plugins.firebase.firestore.** { *; }

# Mercado Pago SDK
-keep class com.mercadopago.** { *; }
-dontwarn com.mercadopago.**

# App Widget (provider Escalas)
-keep class com.wisdomapp.app.ControleTotalWidgetProvider { *; }

-keepattributes Signature
-keepattributes *Annotation*
-keep class sun.misc.Unsafe { *; }
-keep class com.google.gson.** { *; }

# ML Kit Text Recognition — scripts opcionais (chinês, devanágari, etc.) referenciados pelo plugin; R8 remove sem estas regras.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
