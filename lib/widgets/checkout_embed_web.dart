/// Exporta o embed de checkout: iframe na web, stub no mobile (mobile usa WebView na tela).
library;

export 'checkout_embed_web_stub.dart' if (dart.library.html) 'checkout_embed_web_impl.dart';
