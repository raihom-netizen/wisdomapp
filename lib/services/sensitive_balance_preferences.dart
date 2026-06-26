import 'package:shared_preferences/shared_preferences.dart';

import '../constants/currency_formats.dart';

/// Preferência global (dispositivo): ocultar valores monetários sensíveis no painel Início.
class SensitiveBalancePreferences {
  SensitiveBalancePreferences._();

  static const String _key = 'dashboard_hide_sensitive_amounts_v1';

  static Future<bool> load() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_key) ?? false;
  }

  static Future<void> set(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, value);
  }

  static String formatBrl(double value, {required bool hidden}) {
    if (!hidden) return CurrencyFormats.formatBRL(value);
    return 'R\$ ••••';
  }
}
