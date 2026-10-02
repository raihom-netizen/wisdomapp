import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../constants/commitment_symbols.dart';
import '../services/yearly_commitment_repeat_service.dart';

/// Compartilhar compromisso (WhatsApp, e-mail, etc.): título, data/hora, local
/// e link do mapa. Usado no card do «Resumo do dia» e no detalhe (edição).

/// Link do mapa: o próprio link (http) ou busca no Google Maps pelo texto.
String? compromissoMapLink(String? local) {
  final s = (local ?? '').trim();
  if (s.isEmpty) return null;
  if (s.startsWith('http://') || s.startsWith('https://')) return s;
  return 'https://www.google.com/maps/search/?api=1&query='
      '${Uri.encodeQueryComponent(s)}';
}

/// Texto pronto para compartilhar. [data] no formato do doc `reminders`.
String compromissoShareText(Map<String, dynamic> data) {
  final title = (data['title'] ?? '').toString().trim();
  final symbol = CommitmentSymbol.fromData(data);
  final emoji = symbol?.emoji ?? suggestCommitmentEmoji(title) ?? '📌';
  final linhas = <String>[
    '$emoji ${title.isEmpty ? 'Compromisso' : title}',
  ];

  final rawDate = data['date'];
  final date = rawDate is Timestamp
      ? rawDate.toDate()
      : (rawDate is DateTime ? rawDate : null);
  if (date != null) {
    final dia = DateFormat("EEEE, dd/MM/yyyy", 'pt_BR').format(date);
    linhas.add('📅 ${dia[0].toUpperCase()}${dia.substring(1)}');
  }

  final ini = (data['time'] ?? '').toString().trim();
  final fim = (data['endTime'] ?? '').toString().trim();
  if (ini.isNotEmpty) {
    linhas.add('🕘 ${fim.isNotEmpty && fim != ini ? '$ini às $fim' : ini}');
  }

  final local = (data['linkLocalizacao'] ?? data['localAudiencia'] ?? '')
      .toString()
      .trim();
  final mapa = compromissoMapLink(local);
  if (local.isNotEmpty && !local.startsWith('http')) {
    linhas.add('📍 $local');
  }
  if (mapa != null) linhas.add('🗺️ Mapa: $mapa');

  final notas = YearlyCommitmentRepeatService.stripYearlyRepeatLines(
    (data['notes'] ?? '').toString(),
  ).trim();
  if (notas.isNotEmpty) linhas.add('📝 $notas');

  return linhas.join('\n');
}

/// Abre a folha de compartilhar do sistema.
Future<void> shareCompromisso(
  BuildContext context,
  Map<String, dynamic> data,
) async {
  final text = compromissoShareText(data);
  final title = (data['title'] ?? 'Compromisso').toString();
  Rect? origem;
  // iPad exige a origem do popover.
  final box = context.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    origem = box.localToGlobal(Offset.zero) & box.size;
  }
  try {
    await Share.share(text, subject: title, sharePositionOrigin: origem);
  } catch (_) {}
}
