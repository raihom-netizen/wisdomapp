import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/date_time_formats.dart';
import '../theme/app_colors.dart';

/// Filtro da lista de ocorrências exibida pelo sheet do painel do módulo
/// Produtividade.
enum ProdutividadeAbertoFilter {
  emAberto, // sem folgaDate (ainda disponíveis para folga)
  folgasTiradas, // com folgaDate (folga já utilizada)
}

DateTime? _docDate(Map<String, dynamic> data) {
  final v = data['date'];
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  return null;
}

DateTime? _docFolgaDate(Map<String, dynamic> data) {
  final v = data['folgaDate'];
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  return null;
}

/// Sheet estilo Início (Audiências/Compromissos): cards premium clicáveis com
/// a lista de ocorrências (em aberto ou folgas tiradas) restritas ao período.
/// `buildTile` injeta a UI de cada item conforme a tela pai.
Future<void> showProdutividadeEmAbertoSheet(
  BuildContext context, {
  required String userFsId,
  required ProdutividadeAbertoFilter filter,
  required DateTime rangeStart,
  required DateTime rangeEnd,
  required String periodLabel,
  required Widget Function(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) buildTile,
  VoidCallback? onAbrirModuloCompleto,
}) async {
  final ref = FirebaseFirestore.instance
      .collection('users')
      .doc(userFsId)
      .collection('ocorrencias');

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.32,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Topo do preview: botão «Voltar» (esquerda) + atalho X (direita).
            // Igual ao sheet de Audiências/Compromissos — funciona em iPhone,
            // Android e Web (área de toque mínima 44).
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
              child: Row(
                children: [
                  Material(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(ctx).pop(),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: AppColors.primary,
                          size: 22,
                          semanticLabel: 'Voltar',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 8),
                      foregroundColor: AppColors.primary,
                    ),
                    child: const Text(
                      'Voltar',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Material(
                    color: Colors.grey.shade100,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(ctx).pop(),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.close_rounded,
                          size: 22,
                          color: Color(0xFF1A237E),
                          semanticLabel: 'Fechar',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
              child: Row(
                children: [
                  Icon(
                    filter == ProdutividadeAbertoFilter.emAberto
                        ? Icons.task_alt_rounded
                        : Icons.event_available_rounded,
                    color: AppColors.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          filter == ProdutividadeAbertoFilter.emAberto
                              ? 'Ocorrências em aberto'
                              : 'Folgas tiradas',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A237E),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          periodLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: ref.snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snap.data?.docs ?? const [];
                  final start = DateTime(
                      rangeStart.year, rangeStart.month, rangeStart.day);
                  final end = DateTime(rangeEnd.year, rangeEnd.month,
                      rangeEnd.day, 23, 59, 59, 999);
                  final filtered = docs.where((d) {
                    final data = d.data();
                    final hasFolga = data['folgaDate'] != null;
                    if (filter == ProdutividadeAbertoFilter.emAberto &&
                        hasFolga) {
                      return false;
                    }
                    if (filter == ProdutividadeAbertoFilter.folgasTiradas &&
                        !hasFolga) {
                      return false;
                    }
                    // Em "Folgas tiradas" filtra por folgaDate; em "em aberto"
                    // filtra por date (ocorrência).
                    final ref =
                        filter == ProdutividadeAbertoFilter.folgasTiradas
                            ? _docFolgaDate(data)
                            : _docDate(data);
                    if (ref == null) return false;
                    return !ref.isBefore(start) && !ref.isAfter(end);
                  }).toList()
                    ..sort((a, b) {
                      final da = filter ==
                              ProdutividadeAbertoFilter.folgasTiradas
                          ? _docFolgaDate(a.data())
                          : _docDate(a.data());
                      final db = filter ==
                              ProdutividadeAbertoFilter.folgasTiradas
                          ? _docFolgaDate(b.data())
                          : _docDate(b.data());
                      if (da == null && db == null) return 0;
                      if (da == null) return 1;
                      if (db == null) return -1;
                      return da.compareTo(db);
                    });
                  if (filtered.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              filter == ProdutividadeAbertoFilter.emAberto
                                  ? Icons.task_alt_rounded
                                  : Icons.beach_access_rounded,
                              size: 48,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              filter == ProdutividadeAbertoFilter.emAberto
                                  ? 'Nenhuma ocorrência em aberto neste período.'
                                  : 'Nenhuma folga tirada neste período.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Período: $periodLabel',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) =>
                        buildTile(context, filtered[i]),
                  );
                },
              ),
            ),
            if (onAbrirModuloCompleto != null)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 20),
                      label: const Text(
                        'Abrir módulo completo',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        onAbrirModuloCompleto();
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Helper para formatar a data BR ou "—".
String formatDateOrDash(DateTime? date) =>
    date == null ? '—' : DateTimeFormats.dateBR.format(date);

/// Helper para formatar a hora ou "—".
String formatTimeOrDash(DateTime? date) =>
    date == null ? '—' : DateFormat('HH:mm').format(date);
