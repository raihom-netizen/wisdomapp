import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<Uint8List> gerarPdfFinanceiro(List<Map<String, dynamic>> transacoes) async {
  final pdf = pw.Document();

  double totalReceitas = 0;
  double totalDespesas = 0;

  for (final t in transacoes) {
    final tipo = (t['tipo'] ?? '').toString().toLowerCase();
    final valorRaw = t['valor'];
    final valor = valorRaw is num ? valorRaw.toDouble() : double.tryParse(valorRaw.toString()) ?? 0.0;
    if (tipo == 'receita') {
      totalReceitas += valor;
    } else {
      totalDespesas += valor;
    }
  }

  final saldo = totalReceitas - totalDespesas;

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        pw.Text(
          'RELATORIO FINANCEIRO',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        pw.Text('Total Receitas: R\$ ${totalReceitas.toStringAsFixed(2)}'),
        pw.Text('Total Despesas: R\$ ${totalDespesas.toStringAsFixed(2)}'),
        pw.Text('Saldo: R\$ ${saldo.toStringAsFixed(2)}'),
        pw.SizedBox(height: 20),
        pw.Text(
          'Transacoes:',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        pw.Table.fromTextArray(
          headers: const ['Data', 'Descricao', 'Tipo', 'Valor'],
          data: transacoes.map((t) {
            final valorRaw = t['valor'];
            final valor = valorRaw is num ? valorRaw.toDouble() : double.tryParse(valorRaw.toString()) ?? 0.0;
            return [
              (t['data'] ?? '').toString(),
              (t['descricao'] ?? '').toString(),
              (t['tipo'] ?? '').toString(),
              'R\$ ${valor.toStringAsFixed(2)}',
            ];
          }).toList(),
        ),
      ],
    ),
  );

  return pdf.save();
}

