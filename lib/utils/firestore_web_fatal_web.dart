import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Chama `window.waFirestoreFatal` (web/index.html): aviso visível e recarga
/// única da página depois do assert ca9/b815 do SDK JS do Firestore.
void reportFirestoreWebFatal(String message) {
  try {
    final fn = globalContext['waFirestoreFatal'];
    if (fn == null) return;
    globalContext.callMethod('waFirestoreFatal'.toJS, message.toJS);
  } catch (_) {}
}
