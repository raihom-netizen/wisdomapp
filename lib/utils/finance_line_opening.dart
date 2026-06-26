import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Suporte ao saldo de abertura do gráfico "Evolução do Saldo" (painel) com agregados
/// `users/{uid}/finance_month_buckets/{yyyy-MM}` — chave de mês em America/Sao_Paulo (igual Cloud Function).
abstract final class FinanceLineOpening {
  FinanceLineOpening._();

  static bool _tz = false;

  static void _ensureTz() {
    if (_tz) return;
    tz_data.initializeTimeZones();
    _tz = true;
  }

  /// Chave `yyyy-MM` em America/Sao_Paulo para alinhar com [financeMonthBuckets.js].
  static String monthKeySaoPaulo(DateTime limiteAnteriorLocal) {
    _ensureTz();
    final loc = tz.getLocation('America/Sao_Paulo');
    final t = tz.TZDateTime.from(limiteAnteriorLocal, loc);
    return '${t.year}-${t.month.toString().padLeft(2, '0')}';
  }

  /// Início do mês civil (meia-noite local do dispositivo) — alinhado ao restante do painel.
  static DateTime startOfMonthWallLocal(DateTime limiteAnterior) =>
      DateTime(limiteAnterior.year, limiteAnterior.month, 1);

  /// Campo gravado no Firestore: espelha `paidAt ?? date` (igual regra do gráfico).
  static Timestamp effectiveTimestampForWrite({
    required DateTime date,
    Timestamp? paidAt,
  }) =>
      paidAt ?? Timestamp.fromDate(date);

  static Timestamp? _effectiveFromMap(Map<String, dynamic> d) {
    final e = d['effectiveDate'];
    if (e is Timestamp) return e;
    final p = d['paidAt'];
    if (p is Timestamp) return p;
    final dt = d['date'];
    if (dt is Timestamp) return dt;
    return null;
  }

  /// Contribuição para o saldo de abertura (só movimentos pagos), igual ao painel.
  static double openingContribution(Map<String, dynamic> d) {
    final isPaid = (d['status'] ?? 'paid').toString() == 'paid';
    if (!isPaid) return 0;
    final type = (d['type'] ?? 'expense').toString();
    final raw = d['amount'];
    final amount = raw is num ? raw.toDouble() : (double.tryParse('$raw') ?? 0);
    if (type == 'income') return amount;
    return -amount.abs();
  }

  /// `true` se [effective] é estritamente anterior a [limiteAnterior] (início do dia do período).
  static bool isEffectiveBeforeLimite(
    DateTime effective,
    DateTime limiteAnterior,
  ) {
    return effective.isBefore(limiteAnterior);
  }

  /// Data efetiva como [DateTime] local (para fallback a partir dos docs do gráfico).
  static DateTime? effectiveDateTimeFromMap(Map<String, dynamic> d) {
    final ts = _effectiveFromMap(d);
    return ts?.toDate();
  }
}
