import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/financial_tips_home_sync_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/admin_financial_tip_utils.dart';
import '../../utils/insights_engine.dart';

/// Nomes curtos dos dias (DateTime.weekday: 1=seg … 7=dom).
const List<({int weekday, String short, String label})> kFinancialTipWeekdays = [
  (weekday: 1, short: 'Seg', label: 'Segunda-feira'),
  (weekday: 2, short: 'Ter', label: 'Terça-feira'),
  (weekday: 3, short: 'Qua', label: 'Quarta-feira'),
  (weekday: 4, short: 'Qui', label: 'Quinta-feira'),
  (weekday: 5, short: 'Sex', label: 'Sexta-feira'),
  (weekday: 6, short: 'Sáb', label: 'Sábado'),
  (weekday: 7, short: 'Dom', label: 'Domingo'),
];

/// Programação do Início: ordem da rotação + dica fixa por dia da semana.
class AdminFinancialTipsScheduleSheet extends StatefulWidget {
  const AdminFinancialTipsScheduleSheet({
    super.key,
    required this.docs,
    this.initialConfig,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final FinancialTipsHomeConfig? initialConfig;

  static Future<bool?> show(
    BuildContext context, {
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    FinancialTipsHomeConfig? initialConfig,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AdminFinancialTipsScheduleSheet(
        docs: docs,
        initialConfig: initialConfig,
      ),
    );
  }

  @override
  State<AdminFinancialTipsScheduleSheet> createState() =>
      _AdminFinancialTipsScheduleSheetState();
}

class _AdminFinancialTipsScheduleSheetState
    extends State<AdminFinancialTipsScheduleSheet> {
  late List<String> _rotationIds;
  late Map<int, String> _weekdayIds;
  bool _saving = false;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _activeDocs =>
      widget.docs.where((d) => d.data()['ativo'] != false).toList();

  Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> get _docById =>
      {for (final d in _activeDocs) d.id: d};

  @override
  void initState() {
    super.initState();
    final cfg = widget.initialConfig;
    final homeMarked = widget.docs
        .where((d) => d.data()['exibirNoInicio'] == true)
        .map((d) => d.id)
        .toList();
    _rotationIds = List<String>.from(
      cfg?.rotationOrder.isNotEmpty == true ? cfg!.rotationOrder : homeMarked,
    );
    _rotationIds = [
      for (final id in _rotationIds)
        if (_docById.containsKey(id)) id,
    ];
    if (_rotationIds.isEmpty) {
      final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(_activeDocs);
      sorted.sort((a, b) {
        final oa = (a.data()['ordem'] as num?)?.toInt() ?? 999;
        final ob = (b.data()['ordem'] as num?)?.toInt() ?? 999;
        return oa.compareTo(ob);
      });
      _rotationIds = sorted.take(12).map((d) => d.id).toList();
    }
    _weekdayIds = Map<int, String>.from(cfg?.weekdayTipIds ?? {});
  }

  String _tipTitle(String? id) {
    if (id == null || id.isEmpty) return 'Automático (rotação)';
    final doc = _docById[id];
    if (doc == null) return id;
    return (doc.data()['titulo'] ?? doc.id).toString();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final homeIds = widget.docs
          .where((d) => d.data()['exibirNoInicio'] == true)
          .map((d) => d.id)
          .toList();
      final favIds = widget.docs
          .where((d) => d.data()['favorita'] == true)
          .map((d) => d.id)
          .toList();
      final email = FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
      await FinancialTipsHomeSyncService().publish(
        homeTipIds: homeIds.isNotEmpty ? homeIds : _rotationIds,
        favoriteTipIds: favIds,
        rotationOrder: _rotationIds,
        weekdayTipIds: _weekdayIds,
        syncedByEmail: email,
      );
      InsightsEngine.clearTipsCache();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao publicar: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTipForDay(int weekday) async {
    final picked = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TipPickerList(
        docs: _activeDocs,
        selectedId: _weekdayIds[weekday],
        allowAutomatic: true,
      ),
    );
    if (!mounted) return;
    if (picked == null) return;
    setState(() {
      if (picked.isEmpty) {
        _weekdayIds.remove(weekday);
      } else {
        _weekdayIds[weekday] = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF4F7FB),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                    const Expanded(
                      child: Text(
                        'Programar dicas no Início',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Publicar', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
                  children: [
                    _InfoBanner(
                      icon: Icons.today_rounded,
                      title: 'Uma dica por dia no Início',
                      body:
                          'Os usuários veem só a dica de hoje. No módulo Dicas, apenas os últimos 3 dias. '
                          'A rotação segue a ordem abaixo; você pode fixar uma dica em cada dia da semana.',
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Ordem da rotação diária',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Arraste para definir a sequência. Cada dia civil avança para a próxima dica.',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13, height: 1.35),
                    ),
                    const SizedBox(height: 10),
                    if (_rotationIds.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: const Text(
                          'Marque «Início» em pelo menos uma dica ou adicione itens à rotação.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      )
                    else
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _rotationIds.length,
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) newIndex -= 1;
                            final id = _rotationIds.removeAt(oldIndex);
                            _rotationIds.insert(newIndex, id);
                          });
                          HapticFeedback.lightImpact();
                        },
                        itemBuilder: (context, index) {
                          final id = _rotationIds[index];
                          final doc = _docById[id];
                          final title = doc != null
                              ? (doc.data()['titulo'] ?? id).toString()
                              : id;
                          return Material(
                            key: ValueKey('rot-$id'),
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: ListTile(
                                leading: ReorderableDragStartListener(
                                  index: index,
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                ),
                                title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                                subtitle: doc != null &&
                                        AdminFinancialTipUtils.isBiblical(doc.data())
                                    ? Text(
                                        (doc.data()['referenciaBiblica'] ?? '').toString(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : null,
                                trailing: IconButton(
                                  icon: const Icon(Icons.remove_circle_outline_rounded,
                                      color: AppColors.error),
                                  onPressed: () =>
                                      setState(() => _rotationIds.removeAt(index)),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () async {
                          final add = await showModalBottomSheet<String>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => _TipPickerList(
                              docs: _activeDocs
                                  .where((d) => !_rotationIds.contains(d.id))
                                  .toList(),
                              allowAutomatic: false,
                            ),
                          );
                          if (add != null && add.isNotEmpty && mounted) {
                            setState(() => _rotationIds.add(add));
                          }
                        },
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Adicionar à rotação'),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Dica por dia da semana',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Opcional: escolha qual dica aparece em cada dia. '
                      'Se não marcar, usa a rotação automática.',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13, height: 1.35),
                    ),
                    const SizedBox(height: 12),
                    ...kFinancialTipWeekdays.map((day) {
                      final selected = _weekdayIds[day.weekday];
                      final hasFix = selected != null && selected.isNotEmpty;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _pickTipForDay(day.weekday),
                            child: Ink(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: hasFix
                                      ? AppColors.primary.withValues(alpha: 0.45)
                                      : Colors.grey.shade200,
                                  width: hasFix ? 2 : 1,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: hasFix
                                              ? [AppColors.primary, AppColors.accent]
                                              : [Colors.grey.shade300, Colors.grey.shade400],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        day.short,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            day.label,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _tipTitle(selected),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: hasFix
                                                  ? AppColors.primary
                                                  : Colors.grey.shade600,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      color: Colors.grey.shade500,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.12),
            AppColors.accent.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 4),
                Text(body, style: TextStyle(color: Colors.grey.shade800, height: 1.4, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TipPickerList extends StatelessWidget {
  const _TipPickerList({
    required this.docs,
    this.selectedId,
    this.allowAutomatic = false,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String? selectedId;
  final bool allowAutomatic;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.72;
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Escolher dica',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                if (allowAutomatic)
                  ListTile(
                    leading: const Icon(Icons.autorenew_rounded),
                    title: const Text('Automático (rotação)'),
                    trailing: selectedId == null || selectedId!.isEmpty
                        ? const Icon(Icons.check_circle_rounded, color: AppColors.success)
                        : null,
                    onTap: () => Navigator.pop(context, ''),
                  ),
                ...docs.map((doc) {
                  final d = doc.data();
                  final title = (d['titulo'] ?? doc.id).toString();
                  final ref = (d['referenciaBiblica'] ?? '').toString();
                  return ListTile(
                    title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: ref.isNotEmpty ? Text(ref, maxLines: 1) : null,
                    trailing: selectedId == doc.id
                        ? const Icon(Icons.check_circle_rounded, color: AppColors.success)
                        : null,
                    onTap: () => Navigator.pop(context, doc.id),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
