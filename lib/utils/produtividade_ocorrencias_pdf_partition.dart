import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/date_time_formats.dart';

/// Partição de ocorrências para o PDF de produtividade (mesma lógica que [Relatórios]).
abstract final class ProdutividadeOcorrenciasPdfPartition {
  static DateTime dateFrom(dynamic v) {
    if (v == null) return DateTime(2000, 1, 1);
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime(2000, 1, 1);
  }

  static bool temFolgaMarcada(Map<String, dynamic> e) {
    final f = e['folgaDate'];
    if (f == null) return false;
    return f is Timestamp || f is DateTime;
  }

  static ({List<Map<String, dynamic>> semFolga, List<Map<String, dynamic>> usadasFolga}) partition(
    List<Map<String, dynamic>> todas,
  ) {
    final sem = todas.where((e) => !temFolgaMarcada(e)).toList();
    final com = todas.where((e) => temFolgaMarcada(e)).toList();
    final byFolga = <String, List<Map<String, dynamic>>>{};
    const diasSemana = ['Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado', 'Domingo'];
    for (final e in com) {
      final fd = e['folgaDate'];
      DateTime folgaDt;
      if (fd is Timestamp) {
        folgaDt = fd.toDate();
      } else if (fd is DateTime) {
        folgaDt = fd;
      } else {
        continue;
      }
      final day = DateTime(folgaDt.year, folgaDt.month, folgaDt.day);
      final key = DateTimeFormats.dateBR.format(day);
      byFolga.putIfAbsent(key, () => []).add(e);
    }
    final usadasFolga = byFolga.entries.map((ent) {
      final folgaDt = ent.value.isNotEmpty ? dateFrom(ent.value.first['folgaDate']) : DateTime.now();
      return {
        'folgaDate': ent.key,
        'diaSemana': diasSemana[folgaDt.weekday - 1],
        'ocorrencias': ent.value,
      };
    }).toList();
    usadasFolga.sort((a, b) {
      final la = (a['ocorrencias'] as List<Map<String, dynamic>>?) ?? [];
      final lb = (b['ocorrencias'] as List<Map<String, dynamic>>?) ?? [];
      final da = la.isNotEmpty ? dateFrom(la.first['folgaDate']) : DateTime(2000);
      final db = lb.isNotEmpty ? dateFrom(lb.first['folgaDate']) : DateTime(2000);
      return da.compareTo(db);
    });
    for (final g in usadasFolga) {
      final list = (g['ocorrencias'] as List<Map<String, dynamic>>?) ?? [];
      list.sort((a, b) => dateFrom(a['date']).compareTo(dateFrom(b['date'])));
    }
    sem.sort((a, b) => dateFrom(a['date']).compareTo(dateFrom(b['date'])));
    return (semFolga: sem, usadasFolga: usadasFolga);
  }
}
