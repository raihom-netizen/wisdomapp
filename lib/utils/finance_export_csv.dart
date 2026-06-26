import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/date_time_formats.dart';
import '../constants/currency_formats.dart';
import '../models/finance_account.dart';
import 'user_export_csv_save.dart';

/// CSV (UTF-8 com BOM no salvamento) para Excel — colunas alinhadas ao PDF exportado.
class FinanceExportCsv {
  FinanceExportCsv._();

  static String _contaLabel(Map<String, dynamic> d, List<FinanceAccount> accounts) {
    final aid = (d['financeAccountId'] ?? '').toString().trim();
    if (aid.isEmpty) return '—';
    for (final a in accounts) {
      if (a.id == aid) return a.displayName;
    }
    return 'Conta removida';
  }

  static String _data(dynamic ts) {
    if (ts == null) return '';
    if (ts is DateTime) return DateTimeFormats.dateBR.format(ts);
    if (ts is Timestamp) return DateTimeFormats.dateBR.format(ts.toDate());
    return '';
  }

  static String _escape(String s) {
    if (s.contains(';') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static Future<bool> saveOrShare(String filename, String csvBody) {
    return saveCsvContent(
      filename,
      csvBody,
      dialogTitle: 'Salvar relatório financeiro (CSV)',
      shareSubject: 'Relatório financeiro — CSV',
      shareText: 'Colunas alinhadas ao PDF exportado. Abra no Excel ou salve no dispositivo.',
    );
  }

  /// Gera CSV com separador `;` (padrão BR no Excel). O BOM é aplicado em [saveCsvContent].
  static String buildFromFirestoreDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required List<FinanceAccount> accounts,
  }) {
    final buf = StringBuffer();
    buf.writeln('Data;Conta;Tipo;Categoria;Descrição;Valor;Situação');
    for (final doc in docs) {
      final d = doc.data();
      final tipo = (d['type'] ?? 'expense').toString() == 'income' ? 'Receita' : 'Despesa';
      final cat = (d['category'] ?? '').toString().trim();
      final desc = (d['description'] ?? '').toString().trim();
      final status = (d['status'] ?? 'paid').toString() == 'paid' ? 'Pago' : 'Pendente';
      final amount = (d['amount'] ?? 0).toDouble();
      final valor = CurrencyFormats.formatBRL(amount.abs());
      buf.writeln([
        _escape(_data(d['date'])),
        _escape(_contaLabel(d, accounts)),
        _escape(tipo),
        _escape(cat.isEmpty ? '—' : cat),
        _escape(desc.isEmpty ? '—' : desc),
        _escape(valor),
        _escape(status),
      ].join(';'));
    }
    return buf.toString();
  }
}
