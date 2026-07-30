import 'url_launcher_helper.dart';

/// Helper para WhatsApp e link de localização em Compromisso Particular.
abstract final class CompromissoContactLinks {
  CompromissoContactLinks._();

  /// Digits only; BR sem DDI → prefixa 55.
  static String normalizeWhatsAppDigits(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return '';
    // wa.me / url com country code já no path
    if (d.length >= 12 && d.startsWith('55')) return d;
    if (d.length >= 10 && d.length <= 11) return '55$d';
    return d;
  }

  /// Aceita número, `wa.me/...` ou URL completa.
  /// Números com 8+ dígitos (ex.: local sem DDD) também abrem o WhatsApp.
  static String? whatsappLaunchUrl(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final lower = t.toLowerCase();
    if (lower.contains('wa.me') || lower.contains('api.whatsapp.com')) {
      if (lower.startsWith('http')) return t;
      return 'https://${t.replaceFirst(RegExp(r'^/+'), '')}';
    }
    final digits = normalizeWhatsAppDigits(t);
    if (digits.length < 8) return null;
    return 'https://wa.me/$digits';
  }

  static String whatsappDisplayLabel(String raw) {
    final digits = normalizeWhatsAppDigits(raw);
    if (digits.length >= 12 && digits.startsWith('55')) {
      final rest = digits.substring(2);
      if (rest.length == 11) {
        return '(${rest.substring(0, 2)}) ${rest.substring(2, 7)}-${rest.substring(7)}';
      }
      if (rest.length == 10) {
        return '(${rest.substring(0, 2)}) ${rest.substring(2, 6)}-${rest.substring(6)}';
      }
    }
    final t = raw.trim();
    if (t.length > 28) return '${t.substring(0, 26)}…';
    return t.isEmpty ? 'WhatsApp' : t;
  }

  static Future<void> openWhatsApp(String raw) async {
    final url = whatsappLaunchUrl(raw);
    if (url == null) return;
    await openUrlPreferChrome(url);
  }

  /// URL, maps.app.goo.gl ou endereço texto → abre no Maps/navegador.
  static String? locationLaunchUrl(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final lower = t.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) return t;
    if (lower.startsWith('maps.app.goo.gl') ||
        lower.startsWith('goo.gl/maps') ||
        lower.contains('maps.google.') ||
        lower.contains('google.com/maps')) {
      return 'https://${t.replaceFirst(RegExp(r'^/+'), '')}';
    }
    // Endereço / texto livre → busca no Google Maps.
    return 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(t)}';
  }

  static String locationDisplayLabel(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'Localização';
    final lower = t.toLowerCase();
    if (lower.contains('maps.app.goo.gl') ||
        lower.contains('goo.gl/maps') ||
        lower.contains('maps.google') ||
        lower.contains('google.com/maps') ||
        lower.startsWith('http')) {
      return 'Abrir mapa';
    }
    if (t.length > 28) return '${t.substring(0, 26)}…';
    return t;
  }

  static Future<void> openLocation(String raw) async {
    final url = locationLaunchUrl(raw);
    if (url == null) return;
    await openUrlPreferChrome(url);
  }
}
