// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// No web: dispara a impressão da janela (igual a Ctrl+P).
Future<void> printCurrentScreen() async {
  html.window.print();
}
