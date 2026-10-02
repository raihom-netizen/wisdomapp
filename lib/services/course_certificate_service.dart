import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../screens/report_preview_screen.dart';
import 'relatorio_service.dart';

/// Nome do aluno para certificado/comentários: perfil do app → conta → e-mail.
class CourseStudentName {
  CourseStudentName._();

  static final Map<String, String> _cache = {};

  static Future<String> resolve(String uid) async {
    final hit = _cache[uid];
    if (hit != null) return hit;
    String name = '';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 8));
      final d = snap.data() ?? const <String, dynamic>{};
      for (final k in const ['name', 'nome', 'displayName', 'fullName']) {
        final v = (d[k] ?? '').toString().trim();
        if (v.isNotEmpty) {
          name = v;
          break;
        }
      }
    } catch (_) {}
    final user = FirebaseAuth.instance.currentUser;
    if (name.isEmpty && user != null && user.uid == uid) {
      name = (user.displayName ?? '').trim();
      if (name.isEmpty) {
        final email = (user.email ?? '').trim();
        if (email.contains('@')) name = email.split('@').first;
      }
    }
    if (name.isEmpty) name = 'Aluno WisdomApp';
    _cache[uid] = name;
    return name;
  }
}

/// Certificado de conclusão do curso (PDF, marca WisdomApp).
class CourseCertificateService {
  CourseCertificateService._();

  static pw.ThemeData? _theme;

  /// Noto Sans (acentos do pt-BR); sem rede, cai na fonte padrão.
  static Future<pw.ThemeData> _loadTheme() async {
    final hit = _theme;
    if (hit != null) return hit;
    try {
      final base = await PdfGoogleFonts.notoSansRegular()
          .timeout(const Duration(seconds: 20));
      final bold = await PdfGoogleFonts.notoSansBold()
          .timeout(const Duration(seconds: 20));
      final italic = await PdfGoogleFonts.notoSansItalic()
          .timeout(const Duration(seconds: 20));
      final t = pw.ThemeData.withFont(base: base, bold: bold, italic: italic);
      _theme = t;
      return t;
    } catch (_) {
      return pw.ThemeData();
    }
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _date(DateTime d) =>
      '${_two(d.day)}/${_two(d.month)}/${d.year}';

  /// Carga horária legível («1 h 30 min», «45 min»).
  static String workloadLabel(int minutes) {
    if (minutes <= 0) return '';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m min';
    if (m == 0) return '$h h';
    return '$h h $m min';
  }

  /// Código curto para conferência (mesmo aluno + curso = mesmo código).
  static String verificationCode(String uid, String courseId) {
    var h = 0x811C9DC5;
    for (final c in '$uid|$courseId'.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    final s = h.toRadixString(36).toUpperCase().padLeft(7, '0');
    return 'WA-${s.substring(0, 4)}-${s.substring(4)}';
  }

  static Future<Uint8List> buildPdf({
    required String studentName,
    required String courseTitle,
    required int lessonCount,
    int workloadMinutes = 0,
    required DateTime issuedAt,
    required String code,
  }) async {
    final theme = await _loadTheme();
    final logo = await RelatorioService.loadPdfLogoBytesOnce();
    final primary = PdfColor.fromInt(0xFF122B6B);
    final red = PdfColor.fromInt(0xFFCC0000);
    final gold = PdfColor.fromInt(0xFFB8860B);
    final muted = PdfColor.fromInt(0xFF5B6475);

    final details = <String>[
      '$lessonCount ${lessonCount == 1 ? 'aula' : 'aulas'}',
      if (workloadMinutes > 0) 'carga horária de ${workloadLabel(workloadMinutes)}',
    ].join(' · ');

    final doc = pw.Document(theme: theme, title: 'Certificado · $courseTitle');
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(22),
        build: (ctx) => pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: primary, width: 3),
          ),
          padding: const pw.EdgeInsets.all(6),
          child: pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: gold, width: 1),
            ),
            padding: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 28),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    if (logo != null)
                      pw.Container(
                        width: 38,
                        height: 38,
                        margin: const pw.EdgeInsets.only(right: 10),
                        child: pw.Image(pw.MemoryImage(logo)),
                      ),
                    pw.Text(
                      'WisdomApp',
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                        color: primary,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 22),
                pw.Text(
                  'CERTIFICADO DE CONCLUSÃO',
                  style: pw.TextStyle(
                    fontSize: 28,
                    fontWeight: pw.FontWeight.bold,
                    color: primary,
                    letterSpacing: 2,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Container(width: 120, height: 3, color: red),
                pw.SizedBox(height: 26),
                pw.Text(
                  'Certificamos que',
                  style: pw.TextStyle(fontSize: 14, color: muted),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  studentName,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 30,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Text(
                  'concluiu com êxito o curso',
                  style: pw.TextStyle(fontSize: 14, color: muted),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  courseTitle,
                  textAlign: pw.TextAlign.center,
                  maxLines: 3,
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: primary,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  details,
                  style: pw.TextStyle(fontSize: 13, color: muted),
                ),
                pw.Spacer(),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Emitido em ${_date(issuedAt)}',
                            style: pw.TextStyle(fontSize: 11, color: muted),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Código: $code',
                            style: pw.TextStyle(fontSize: 10, color: muted),
                          ),
                        ],
                      ),
                    ),
                    pw.Column(
                      children: [
                        pw.Container(width: 190, height: 1, color: primary),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'WisdomApp Cursos',
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: primary,
                          ),
                        ),
                        pw.Text(
                          'wisdomapp.com.br',
                          style: pw.TextStyle(fontSize: 10, color: muted),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Uint8List.fromList(await doc.save());
  }

  /// Gera e abre a prévia (com Salvar / Compartilhar).
  static Future<void> openCertificate(
    BuildContext context, {
    required String uid,
    required String courseId,
    required String courseTitle,
    required int lessonCount,
    int workloadMinutes = 0,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final nav = Navigator.of(context);
    messenger?.showSnackBar(const SnackBar(
      content: Text('Gerando o certificado…'),
      duration: Duration(seconds: 2),
    ));
    try {
      final name = await CourseStudentName.resolve(uid);
      final bytes = await buildPdf(
        studentName: name,
        courseTitle: courseTitle,
        lessonCount: lessonCount,
        workloadMinutes: workloadMinutes,
        issuedAt: DateTime.now(),
        code: verificationCode(uid, courseId),
      );
      final safe = courseTitle
          .replaceAll(RegExp(r'[^A-Za-z0-9À-ÿ ]'), '')
          .trim()
          .replaceAll(RegExp(r'\s+'), '_');
      await nav.push(
        MaterialPageRoute<void>(
          builder: (_) => ReportPreviewScreen(
            bytes: bytes,
            filename: 'certificado_${safe.isEmpty ? 'curso' : safe}.pdf',
          ),
        ),
      );
    } catch (e) {
      messenger?.showSnackBar(SnackBar(
        content: Text('Não foi possível gerar o certificado: $e'),
      ));
    }
  }
}
