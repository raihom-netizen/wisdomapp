// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void setBrowserDocumentTitle(String title) {
  if (title.isEmpty) return;
  try {
    html.document.title = title;
  } catch (_) {}
}

void setBrowserMetaDescription(String? description) {
  if (description == null || description.isEmpty) return;
  try {
    final existing = html.document.querySelector('meta[name="description"]');
    if (existing is html.MetaElement) {
      existing.content = description;
      return;
    }
    final m = html.MetaElement()
      ..name = 'description'
      ..content = description;
    html.document.head?.append(m);
  } catch (_) {}
}
