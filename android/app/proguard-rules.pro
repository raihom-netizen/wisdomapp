# ---------------------------------------------------------------------------
# R8 enxuto (01/10/2026). Antes havia -keep amplos ({ *; }) de
# com.google.firebase.**, com.google.android.gms.**, com.google.gson.** e
# com.mercadopago.** — isso impedia o R8 de encolher/otimizar quase todo o
# SDK (Play Console acusou R8 baixo). Firebase, Play Services e Gson 2.10+
# já trazem as próprias regras (consumer rules / META-INF/proguard) dentro
# dos AARs/JARs; aqui ficam só regras ESTREITAS, cada uma com o motivo.
# Teste obrigatório no aparelho: ver checklist na memória do projeto.
# ---------------------------------------------------------------------------

# Reflexão/genéricos (Gson, Firestore, Pigeon) precisam destes atributos.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Firestore (plugin FlutterFire): só a ponte do plugin — o codec Pigeon
# mapeia tipos por classe; pacote pequeno, sem tocar no SDK do Firestore.
-keep class io.flutter.plugins.firebase.firestore.** { *; }

# Notificações locais agendadas: o plugin grava os modelos com Gson
# (reagendar após reiniciar o aparelho) — nomes de campos precisam ficar.
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }

# Mercado Pago: não há SDK Android no app (pagamento é via web/Functions);
# só silencia avisos caso alguma lib transitiva referencie.
-dontwarn com.mercadopago.**

# App Widget (provider Escalas)
-keep class com.wisdomapp.app.ControleTotalWidgetProvider { *; }

# Gson usa sun.misc.Unsafe para instanciar modelos sem construtor.
-dontwarn sun.misc.Unsafe

# ML Kit Text Recognition — scripts opcionais (chinês, devanágari, etc.) referenciados pelo plugin; R8 remove sem estas regras.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
