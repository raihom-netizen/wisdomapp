// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_util' as js_util;

import 'package:flutter/foundation.dart';

/// Implementação web: usa window.pwaInstall do script em index.html.
class PwaInstall {
  static dynamic get _pwa {
    try {
      return (html.window as dynamic).pwaInstall;
    } catch (_) {
      return null;
    }
  }

  static bool get supported => kIsWeb;

  static bool get isIos {
    if (!supported) return false;
    try {
      return _pwa?.isIos() == true;
    } catch (_) {
      return false;
    }
  }

  static bool get isInstalled {
    if (!supported) return false;
    try {
      return _pwa?.isInStandaloneMode() == true;
    } catch (_) {
      return false;
    }
  }

  static bool get canPrompt {
    if (!supported) return false;
    try {
      return _pwa?.canPromptInstall() == true;
    } catch (_) {
      return false;
    }
  }

  static Future<String> promptInstall() async {
    if (!supported) return 'unavailable';
    try {
      final p = _pwa?.promptInstall();
      if (p == null) return 'unavailable';
      final result = await js_util.promiseToFuture<dynamic>(p);
      final outcome = js_util.getProperty(result, 'outcome');
      return (outcome ?? 'unknown').toString();
    } catch (_) {
      return 'unknown';
    }
  }
}
