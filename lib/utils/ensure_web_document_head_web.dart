// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Garante [document.head] antes do `firebase_core_web` injetar scripts via
/// `document.head!.appendChild` — em alguns cenários WebKit/Safari iOS o head
/// pode não estar disponível no primeiro instante, gerando null check crash.
void ensureWebDocumentReadyForFirebase() {
  try {
    if (html.document.head != null) return;
    final head = html.document.createElement('head');
    final root = html.document.documentElement;
    if (root == null) return;
    final first = root.firstChild;
    if (first != null) {
      root.insertBefore(head, first);
    } else {
      root.append(head);
    }
  } catch (_) {}
}
