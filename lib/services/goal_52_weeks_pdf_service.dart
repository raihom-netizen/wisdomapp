import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../constants/currency_formats.dart';
import '../screens/report_preview_screen.dart';
import '../services/relatorio_service.dart';
import '../utils/fifty_two_weeks_plan.dart';

/// PDF moderno: Projeto 52 semanas (padrão extrato financeiro WISDOMAPP).
class Goal52WeeksPdfService {
  Goal52WeeksPdfService._();

  static Future<Uint8List> generateReportBytes({
    required String goalTitle,
    required double target,
    required List<FiftyTwoWeeksWeekEntry> schedule,
    required List<int> paidWeeks,
    required List<Map<String, dynamic>> contributions,
    required DateTime planStart,
    Uint8List? logoPngBytes,
  }) async {
    final paid = paidWeeks.toSet();
    var deposited = 0.0;
    for (final c in contributions) {
      deposited += ((c['amount'] ?? 0) as num).toDouble();
    }
    final remaining = (target - deposited).clamp(0.0, double.infinity);
    final percent = target > 0 ? ((deposited / target) * 100).clamp(0.0, 100.0) : 0.0;
    final remainingWeeks = (52 - paid.length).clamp(0, 52);
    final logo = logoPngBytes ?? await RelatorioService.loadPdfLogoBytesOnce();
    final now = DateTime.now();
    final emitido =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    final primary = PdfColor.fromInt(0xFF122B6B);
    final onPrimary = PdfColors.white;
    final muted = PdfColors.grey700;
    final green = PdfColor.fromInt(0xFF166534);
    final blue = PdfColor.fromInt(0xFF1D4ED8);
    final orange = PdfColor.fromInt(0xFFEA580C);

    pw.Widget footer(pw.Context ctx) {
      return pw.Container(
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text(
              'Gerado por WISDOMAPP',
              style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: muted),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Emitido em $emitido  |  Pag. ${ctx.pageNumber} de ${ctx.pagesCount}',
              style: pw.TextStyle(fontSize: 8, color: muted),
            ),
          ],
        ),
      );
    }

    pw.Widget headerBand() {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        decoration: pw.BoxDecoration(
          gradient: pw.LinearGradient(
            colors: [
              PdfColor.fromInt(0xFF0B1F4B),
              PdfColor.fromInt(0xFF6366F1),
              PdfColor.fromInt(0xFF0D9488),
            ],
          ),
          borderRadius: pw.BorderRadius.circular(14),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logo != null && logo.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(right: 12),
                child: pw.Image(pw.MemoryImage(logo), width: 44, height: 44, fit: pw.BoxFit.contain),
              ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'WISDOMAPP',
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: onPrimary),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Projeto 52 semanas',
                    style: pw.TextStyle(fontSize: 11, color: onPrimary),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    goalTitle,
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: onPrimary),
                  ),
                ],
              ),
            ),
            pw.Container(
              constraints: const pw.BoxConstraints(maxWidth: 160),
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: pw.BoxDecoration(
                color: const PdfColor(1, 1, 1, 0.2),
                borderRadius: pw.BorderRadius.circular(10),
              ),
              child: pw.Text(
                'Início: ${DateFormat('dd/MM/yyyy').format(planStart)}',
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: onPrimary),
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget resumoCards() {
      return pw.Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          pw.SizedBox(
            width: 120,
            child: _pdfCard(label: 'Meta total', value: CurrencyFormats.formatBRL(target), color: primary, bg: PdfColor.fromInt(0xFFEEF2FF)),
          ),
          pw.SizedBox(
            width: 120,
            child: _pdfCard(label: 'Depositado', value: CurrencyFormats.formatBRL(deposited), color: green, bg: PdfColor.fromInt(0xFFDCFCE7)),
          ),
          pw.SizedBox(
            width: 120,
            child: _pdfCard(label: 'Falta guardar', value: CurrencyFormats.formatBRL(remaining), color: orange, bg: PdfColor.fromInt(0xFFFFEDD5)),
          ),
          pw.SizedBox(
            width: 120,
            child: _pdfCard(label: 'Concluído', value: '${percent.toStringAsFixed(1)}%', color: blue, bg: PdfColor.fromInt(0xFFDBEAFE)),
          ),
          pw.SizedBox(
            width: 120,
            child: _pdfCard(label: 'Semanas ok', value: '${paid.length}/52', color: green, bg: PdfColor.fromInt(0xFFDCFCE7)),
          ),
          pw.SizedBox(
            width: 120,
            child: _pdfCard(label: 'Semanas restantes', value: '$remainingWeeks', color: orange, bg: PdfColor.fromInt(0xFFFFEDD5)),
          ),
        ],
      );
    }

    final depositBlocks = <pw.Widget>[];
    if (contributions.isEmpty) {
      depositBlocks.add(
        pw.Text('Nenhum depósito registrado ainda.', style: pw.TextStyle(fontSize: 10, color: muted)),
      );
    } else {
      for (final c in contributions) {
        final date = (c['date'] as Timestamp?)?.toDate();
        final amount = ((c['amount'] ?? 0) as num).toDouble();
        final w1 = c['weekNumber'] as int?;
        final wl = (c['weekNumbers'] as List?)?.whereType<int>().toList() ?? [];
        final weeksLabel = w1 != null ? 'Sem. $w1' : wl.isEmpty ? '—' : 'Sem. ${wl.join(', ')}';
        depositBlocks.add(
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 8),
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(12),
              border: pw.Border.all(color: PdfColor.fromInt(0xFFE2E8F0)),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        date != null ? DateFormat('dd/MM/yyyy').format(date) : '—',
                        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: primary),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(weeksLabel, style: pw.TextStyle(fontSize: 9, color: muted)),
                    ],
                  ),
                ),
                pw.Text(
                  CurrencyFormats.formatBRL(amount),
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: green),
                ),
              ],
            ),
          ),
        );
      }
    }

    final weekBlocks = <pw.Widget>[];
    for (final e in schedule) {
      final isPaid = paid.contains(e.week);
      weekBlocks.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 6),
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: pw.BoxDecoration(
            color: isPaid ? PdfColor.fromInt(0xFFDCFCE7) : PdfColors.white,
            borderRadius: pw.BorderRadius.circular(10),
            border: pw.Border.all(
              color: isPaid ? PdfColor.fromInt(0xFF86EFAC) : PdfColor.fromInt(0xFFE2E8F0),
            ),
          ),
          child: pw.Row(
            children: [
              pw.Container(
                width: 36,
                height: 36,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  color: isPaid ? green : PdfColor.fromInt(0xFFEEF2FF),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Text(
                  'S${e.week}',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: isPaid ? PdfColors.white : primary,
                  ),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      DateFormat('dd/MM/yyyy').format(e.dueDate),
                      style: pw.TextStyle(fontSize: 9.5, color: muted),
                    ),
                    pw.Text(
                      CurrencyFormats.formatBRL(e.amount),
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: primary),
                    ),
                  ],
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: pw.BoxDecoration(
                  color: isPaid ? PdfColor.fromInt(0xFFBBF7D0) : PdfColor.fromInt(0xFFF1F5F9),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Text(
                  isPaid ? 'Guardada' : 'Pendente',
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: isPaid ? green : muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        footer: footer,
        build: (ctx) => [
          headerBand(),
          pw.SizedBox(height: 14),
          resumoCards(),
          pw.SizedBox(height: 16),
          pw.Text(
            'Depósitos registrados',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: primary),
          ),
          pw.SizedBox(height: 8),
          ...depositBlocks,
          pw.SizedBox(height: 16),
          pw.Text(
            'Cronograma semanal (52 semanas)',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: primary),
          ),
          pw.SizedBox(height: 8),
          ...weekBlocks,
        ],
      ),
    );

    return Uint8List.fromList(await doc.save());
  }

  static pw.Widget _pdfCard({
    required String label,
    required String value,
    required PdfColor color,
    required PdfColor bg,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: PdfColor.fromInt(0xFFE2E8F0), width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  /// Pré-visualização antes de imprimir/compartilhar.
  static Future<void> previewFromGoalDoc({
    required BuildContext context,
    required DocumentReference<Map<String, dynamic>> goalRef,
    required Map<String, dynamic> goalData,
  }) async {
    final title = (goalData['title'] ?? 'Objetivo').toString();
    final target = (goalData['targetAmount'] as num?)?.toDouble() ?? 0;
    final planStart =
        FiftyTwoWeeksPlan.planStartFromData(goalData) ?? DateTime.now();
    final schedule = FiftyTwoWeeksPlan.buildSchedule(
      target: target,
      planStart: planStart,
    );
    final paid = FiftyTwoWeeksPlan.paidWeeksFromData(goalData);
    final snap = await goalRef.collection('contributions').orderBy('date').get();
    final contribs = snap.docs.map((d) => d.data()).toList();
    final logo = await RelatorioService.loadPdfLogoBytesOnce();
    final bytes = await generateReportBytes(
      goalTitle: title,
      target: target,
      schedule: schedule,
      paidWeeks: paid,
      contributions: contribs,
      planStart: planStart,
      logoPngBytes: logo,
    );
    if (!context.mounted) return;
    final safeName = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ReportPreviewScreen(
          bytes: bytes,
          filename: 'objetivo_52_semanas_$safeName',
        ),
      ),
    );
  }

  /// Legado: compartilhamento direto (preferir [previewFromGoalDoc]).
  static Future<void> shareReportFromGoalDoc({
    required DocumentReference<Map<String, dynamic>> goalRef,
    required Map<String, dynamic> goalData,
  }) async {
    final title = (goalData['title'] ?? 'Objetivo').toString();
    final target = (goalData['targetAmount'] as num?)?.toDouble() ?? 0;
    final planStart =
        FiftyTwoWeeksPlan.planStartFromData(goalData) ?? DateTime.now();
    final schedule = FiftyTwoWeeksPlan.buildSchedule(
      target: target,
      planStart: planStart,
    );
    final paid = FiftyTwoWeeksPlan.paidWeeksFromData(goalData);
    final snap = await goalRef.collection('contributions').orderBy('date').get();
    final contribs = snap.docs.map((d) => d.data()).toList();
    final bytes = await generateReportBytes(
      goalTitle: title,
      target: target,
      schedule: schedule,
      paidWeeks: paid,
      contributions: contribs,
      planStart: planStart,
    );
    await RelatorioService.sharePdfBytes(
      bytes,
      'objetivo_52_semanas_${title.replaceAll(' ', '_')}',
    );
  }
}
