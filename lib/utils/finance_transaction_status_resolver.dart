import 'package:cloud_firestore/cloud_firestore.dart';

/// Resolve o status de um lançamento com base na sua data/hora.
///
/// Regra de negócio: um lançamento só faz sentido como "pendente" quando a
/// data/hora é hoje ou futura. Lançamentos passados devem entrar como "pagos".
abstract final class FinanceTransactionStatusResolver {
  FinanceTransactionStatusResolver._();

  static DateTime _startOfTodayLocal() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Compara apenas o dia (ignora horário). Usado para geração de despesas/receitas fixas,
  /// onde a data é sempre meia-noite do dia de vencimento.
  static String resolveByDate(DateTime date, {String? preferredStatus}) {
    final startOfToday = _startOfTodayLocal();
    final d = DateTime(date.year, date.month, date.day);
    if (d.isBefore(startOfToday)) return 'paid';
    return preferredStatus ?? 'pending';
  }

  /// Compara data e horário completos. Usado para lançamentos manuais, onde o usuário
  /// pode escolher uma hora específica no dia.
  static String resolveByDateTime(DateTime date, {String? preferredStatus}) {
    final now = DateTime.now();
    if (date.isBefore(now)) return 'paid';
    return preferredStatus ?? 'pending';
  }

  /// Timestamp apropriado para gravar [paidAt] quando o sistema auto-paga um lançamento
  /// a partir da data original (evita contabilizar o pagamento no momento atual).
  static Timestamp paidAtForAutoPaid(DateTime date) {
    return Timestamp.fromDate(
      DateTime(date.year, date.month, date.day, date.hour, date.minute),
    );
  }
}
