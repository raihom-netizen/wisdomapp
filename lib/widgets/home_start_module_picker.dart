import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/home_start_module_cache.dart';
import '../theme/app_colors.dart';
import '../widgets/shell_keyboard_bottom_pad.dart';

/// Campo em `users/{uid}/settings/planning` — índice do módulo no [HomeShell].
const String kHomeDefaultStartModuleField = 'defaultStartModuleIndex';

/// Nome do módulo índice 3 (shell, gaveta, menu lateral, título do shell).
const String kAgendaModuleDisplayName = 'Agenda';

/// Rodapé muito estreito: mantém ícone no tamanho normal; só o texto abrevia.
const String kAgendaModuleFooterLabelNarrow = 'Agenda';

/// Rótulos e índices permitidos (deve coincidir com as abas do shell).
const Map<int, String> kHomeDefaultStartModuleLabels = {
  1: 'Financeiro',
  2: 'Objetivo Financeiro',
  3: 'Agenda',
  7: 'Cursos',
};

/// Índices legados (Início, Calculadora) passam a abrir em Financeiro.
int normalizeHomeStartModuleIndex(int idx) {
  if (kHomeDefaultStartModuleLabels.containsKey(idx)) return idx;
  if (idx == 0 || idx == 4) return 1;
  return 1;
}

/// Metadados visuais do seletor (ícone + subtítulo). Ordem = ordem na lista.
class _PickerEntry {
  final int index;
  final IconData icon;
  final List<Color> iconGradient;
  final String subtitle;

  const _PickerEntry({
    required this.index,
    required this.icon,
    required this.iconGradient,
    required this.subtitle,
  });
}

const List<_PickerEntry> _kPickerEntries = [
  _PickerEntry(
    index: 1,
    icon: Icons.account_balance_wallet_rounded,
    iconGradient: [AppColors.deepBlue, AppColors.primary],
    subtitle: 'Contas a pagar, receber e lançamentos',
  ),
  _PickerEntry(
    index: 2,
    icon: Icons.flag_rounded,
    iconGradient: [Color(0xFF6366F1), Color(0xFFEC4899)],
    subtitle: 'Metas com Projeto 52 semanas — viagem, carro, casa…',
  ),
  _PickerEntry(
    index: 3,
    icon: Icons.calendar_month_rounded,
    iconGradient: [Color(0xFF1E3A5F), Color(0xFF6366F1)],
    subtitle: 'Compromissos particulares no calendário',
  ),
  _PickerEntry(
    index: 7,
    icon: Icons.ondemand_video_rounded,
    iconGradient: [Color(0xFF0E7490), Color(0xFF06B6D4)],
    subtitle: 'Cursos financeiros com princípios bíblicos',
  ),
];

DocumentReference<Map<String, dynamic>> homePlanningRef(String uid) =>
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('planning');

/// Abre o mesmo bottom sheet usado em Configurações.
/// [onSaved] é chamado após gravar no Firestore (ex.: atualizar aba atual).
Future<void> showHomeStartModulePickerSheet(
  BuildContext context, {
  required String uid,
  int? initialSelected,
  void Function(int moduleIndex)? onSaved,
}) async {
  int current;
  if (initialSelected != null &&
      kHomeDefaultStartModuleLabels.containsKey(initialSelected)) {
    current = initialSelected;
  } else {
    try {
      final snap = await homePlanningRef(uid).get(
        const GetOptions(source: Source.serverAndCache),
      );
      final raw = snap.data()?[kHomeDefaultStartModuleField];
      current = raw is num ? normalizeHomeStartModuleIndex(raw.toInt()) : 1;
      if (!kHomeDefaultStartModuleLabels.containsKey(current)) {
        current = 1;
      }
    } catch (_) {
      current = 1;
    }
  }

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          final bottomInset = MediaQuery.paddingOf(ctx).bottom;
          final keyboard = MediaQuery.viewInsetsOf(ctx).bottom;
          return Padding(
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              bottom: 8 + bottomInset + keyboard,
            ),
            child: Material(
              color: AppColors.surface,
              elevation: 24,
              shadowColor: Colors.black.withValues(alpha: 0.2),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(
                        colors: AppColors.logoGradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.deepBlue.withValues(alpha: 0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.layers_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Text(
                                'Escolha a tela inicial do app',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  height: 1.15,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Essa preferência pode ser alterada a qualquer momento. O app abre direto no módulo escolhido.',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.92),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (final entry in _kPickerEntries) ...[
                    _HomeStartModuleTile(
                      entry: entry,
                      title: kHomeDefaultStartModuleLabels[entry.index]!,
                      selected: current == entry.index,
                      onTap: () => setModalState(() => current = entry.index),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 4),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        colors: AppColors.logoGradient,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          elevation: 0,
                          backgroundColor: AppColors.surface,
                          foregroundColor: AppColors.deepBlueDark,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.check_circle_rounded, size: 22),
                        label: const Text(
                          'Salvar preferência',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        onPressed: () async {
                          await homePlanningRef(uid).set({
                            kHomeDefaultStartModuleField: current,
                            'updatedAt': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));
                          await HomeStartModuleCache.save(uid, current);
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          onSaved?.call(current);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Tela inicial padrão atualizada.'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

class _HomeStartModuleTile extends StatelessWidget {
  final _PickerEntry entry;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _HomeStartModuleTile({
    required this.entry,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: selected
            ? AppColors.primary.withValues(alpha: 0.06)
            : const Color(0xFFF8FAFC),
        border: Border.all(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.55)
              : const Color(0xFFE2E8F0),
          width: selected ? 2 : 1,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: entry.iconGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: entry.iconGradient.last.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(entry.icon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: selected
                              ? AppColors.deepBlueDark
                              : AppColors.textPrimary,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        entry.subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textMuted,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: selected
                      ? Container(
                          key: const ValueKey('on'),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: AppColors.success,
                            size: 22,
                          ),
                        )
                      : Icon(
                          Icons.circle_outlined,
                          key: const ValueKey('off'),
                          color: Colors.grey.shade400,
                          size: 22,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
