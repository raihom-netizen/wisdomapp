import 'package:flutter/material.dart';

import '../../theme/theme_context.dart';

/// Um item da prévia da limpeza rápida (compromisso ou financeiro no calendário).
class AgendaBulkClearPreviewItem {
  const AgendaBulkClearPreviewItem({
    required this.date,
    required this.title,
    required this.origem,
  });

  final DateTime? date;
  final String title;

  /// 'app' | 'google' | 'apple' | 'anual' | 'financeiro'
  final String origem;
}

typedef _Origem = ({String key, String label, IconData icon, Color cor});

const List<_Origem> _kOrigens = [
  (key: 'app', label: 'Do app', icon: Icons.event_note_rounded, cor: Color(0xFF6366F1)),
  (key: 'google', label: 'Google', icon: Icons.cloud_rounded, cor: Color(0xFF0EA5E9)),
  (key: 'apple', label: 'Apple', icon: Icons.phone_iphone_rounded, cor: Color(0xFF64748B)),
  (key: 'anual', label: 'Anuais', icon: Icons.cake_rounded, cor: Color(0xFFEC4899)),
  (key: 'financeiro', label: 'Financeiro', icon: Icons.account_balance_wallet_rounded, cor: Color(0xFF10B981)),
];

_Origem _origemDe(String key) =>
    _kOrigens.firstWhere((o) => o.key == key, orElse: () => _kOrigens.first);

/// Prévia moderna e colorida da limpeza rápida (padrão Controle Total):
/// total, cards por origem, lista agrupada por dia, «Voltar» / «Confirmar limpeza».
/// Autorizada pelo dono em 02/10/2026 (apaga também no Google/Apple — só as
/// ocorrências do período; financeiro só sai do calendário).
Future<bool> showAgendaBulkClearPreview(
  BuildContext context, {
  required String title,
  required String periodLabel,
  required Color accent,
  required Color accent2,
  required List<AgendaBulkClearPreviewItem> itens,
  IconData icon = Icons.delete_sweep_rounded,
}) async {
  if (itens.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nada para limpar neste período.')),
    );
    return false;
  }
  int conta(String o) => itens.where((i) => i.origem == o).length;
  final ordenados = [...itens]
    ..sort((a, b) =>
        (a.date ?? DateTime(2100)).compareTo(b.date ?? DateTime(2100)));
  final porDia = <String, List<AgendaBulkClearPreviewItem>>{};
  for (final i in ordenados) {
    final d = i.date;
    final k = d == null
        ? 'Sem data'
        : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    (porDia[k] ??= []).add(i);
  }
  final financeiros = conta('financeiro');
  final externos = conta('google') + conta('apple');

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final escuro = ctx.isDarkMode;
      final textoSec = escuro ? ctx.appTextSecondary : Colors.grey.shade700;
      final textoPri = escuro ? ctx.appTextPrimary : Colors.grey.shade900;
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(6, 12, 16, 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accent, accent2],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Voltar',
                        onPressed: () => Navigator.pop(ctx, false),
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                      ),
                      Icon(icon, color: Colors.white, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16)),
                            Text(periodLabel,
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('${itens.length}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 20)),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final o in _kOrigens)
                        if (conta(o.key) > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: o.cor.withValues(alpha: escuro ? 0.22 : 0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: o.cor.withValues(alpha: 0.35)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(o.icon, size: 18, color: o.cor),
                                const SizedBox(width: 6),
                                Text('${conta(o.key)} ${o.label}',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: escuro ? textoPri : o.cor)),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
                if (financeiros > 0 || externos > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                    child: Text(
                      [
                        if (financeiros > 0)
                          'Financeiro: só sai do calendário — o lançamento continua no Financeiro.',
                        if (externos > 0)
                          'Google/Apple: apaga só as ocorrências deste período (nunca a série inteira).',
                      ].join('\n'),
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: textoSec),
                    ),
                  ),
                const Divider(height: 16),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    children: [
                      for (final e in porDia.entries) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 4),
                          child: Text(e.key,
                              style: TextStyle(
                                  fontWeight: FontWeight.w900, color: accent2)),
                        ),
                        for (final i in e.value)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Icon(_origemDe(i.origem).icon,
                                    size: 16, color: _origemDe(i.origem).cor),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    i.title.isEmpty ? '(sem título)' : i.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: textoPri),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(ctx, false),
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: const Text('Voltar',
                              style: TextStyle(fontWeight: FontWeight.w800)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(ctx, true),
                          icon: const Icon(Icons.delete_sweep_rounded),
                          label: const Text('Confirmar limpeza',
                              style: TextStyle(fontWeight: FontWeight.w900)),
                          style: FilledButton.styleFrom(
                            backgroundColor: accent2,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return ok == true;
}
