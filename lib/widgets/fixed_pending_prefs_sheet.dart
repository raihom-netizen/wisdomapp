import 'package:flutter/material.dart';

import '../constants/app_business_rules.dart';
import '../theme/app_colors.dart';

/// Resultado do sheet de preferências de pendentes (despesas/receitas fixas).
class FixedPendingPrefsResult {
  const FixedPendingPrefsResult({
    required this.showInPending,
    required this.pendingMonthsAhead,
  });

  final bool showInPending;
  final int pendingMonthsAhead;
}

/// Sheet moderno (Controle Total): chips coloridos para meses + Cancelar / Salvar.
Future<FixedPendingPrefsResult?> showFixedPendingPrefsSheet({
  required BuildContext context,
  required bool initialShowInPending,
  required int initialMonthsAhead,
  required bool isExpense,
}) {
  return showModalBottomSheet<FixedPendingPrefsResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _FixedPendingPrefsSheet(
      initialShowInPending: initialShowInPending,
      initialMonthsAhead: initialMonthsAhead.clamp(0, 12),
      isExpense: isExpense,
    ),
  );
}

class _FixedPendingPrefsSheet extends StatefulWidget {
  const _FixedPendingPrefsSheet({
    required this.initialShowInPending,
    required this.initialMonthsAhead,
    required this.isExpense,
  });

  final bool initialShowInPending;
  final int initialMonthsAhead;
  final bool isExpense;

  @override
  State<_FixedPendingPrefsSheet> createState() =>
      _FixedPendingPrefsSheetState();
}

class _FixedPendingPrefsSheetState extends State<_FixedPendingPrefsSheet> {
  late bool _showInPending;
  late int _monthsAhead;

  Color get _accent =>
      widget.isExpense ? const Color(0xFFEA580C) : const Color(0xFF16A34A);
  Color get _accentDeep =>
      widget.isExpense ? const Color(0xFFC2410C) : const Color(0xFF15803D);
  List<Color> get _gradient => widget.isExpense
      ? const [Color(0xFFEA580C), Color(0xFFF97316), Color(0xFFFBBF24)]
      : const [Color(0xFF15803D), Color(0xFF16A34A), Color(0xFF4ADE80)];

  String get _title => widget.isExpense
      ? 'Exibição nas contas pendentes'
      : 'Exibição nas receitas pendentes';

  String get _toggleLabel => widget.isExpense
      ? 'Mostrar despesas fixas nas contas pendentes'
      : 'Mostrar receitas fixas nas receitas pendentes';

  String get _monthsHint => widget.isExpense
      ? 'Quantos meses à frente entram nas despesas pendentes'
      : 'Quantos meses à frente entram nas receitas pendentes';

  @override
  void initState() {
    super.initState();
    _showInPending = widget.initialShowInPending;
    _monthsAhead = widget.initialMonthsAhead;
  }

  String _labelForMonths(int m) {
    if (m == 0) return 'Mês atual';
    if (m == 1) return '1 mês';
    return '$m meses';
  }

  void _cancel() => Navigator.of(context).pop();

  void _save() {
    Navigator.of(context).pop(
      FixedPendingPrefsResult(
        showInPending: _showInPending,
        pendingMonthsAhead: _monthsAhead,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF111827) : Colors.white;
    final textPrimary = isDark ? Colors.white : AppColors.textPrimary;
    final textSecondary = isDark ? Colors.white70 : AppColors.textSecondary;

    return Container(
      margin: const EdgeInsets.only(top: 24),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, 10, 18, 12 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: _gradient),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      widget.isExpense
                          ? Icons.payments_outlined
                          : Icons.trending_up_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.isExpense
                              ? 'Despesas fixas'
                              : 'Receitas fixas',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: _accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: isDark ? 0.16 : 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _accent.withValues(alpha: 0.22),
                  ),
                ),
                child: SwitchListTile(
                  value: _showInPending,
                  onChanged: (v) => setState(() => _showInPending = v),
                  contentPadding: EdgeInsets.zero,
                  activeTrackColor: _accent.withValues(alpha: 0.55),
                  activeThumbColor: Colors.white,
                  title: Text(
                    _toggleLabel,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Exibir período',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _monthsHint,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.34,
                ),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var m = 0; m <= 12; m++)
                        _MonthChip(
                          label: _labelForMonths(m),
                          selected: _monthsAhead == m,
                          accent: _accent,
                          accentDeep: _accentDeep,
                          enabled: _showInPending,
                          onTap: () => setState(() => _monthsAhead = m),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: _showInPending ? 1 : 0.45,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _accent.withValues(alpha: 0.14),
                        _accent.withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_month_rounded,
                          color: _accent, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _showInPending
                              ? 'Selecionado: ${_labelForMonths(_monthsAhead)}'
                              : 'Fixas ocultas nas pendentes',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _cancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textPrimary,
                        minimumSize: const Size(48, 52),
                        side: BorderSide(
                          color: Colors.grey.withValues(alpha: 0.4),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Cancelar',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: _gradient),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: _accent.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: FilledButton.icon(
                        onPressed: _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(48, 52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text(
                          'Salvar',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthChip extends StatelessWidget {
  const _MonthChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.accentDeep,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final Color accentDeep;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minWidth: 88, minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(colors: [accentDeep, accent])
                : null,
            color: selected
                ? null
                : accent.withValues(alpha: enabled ? 0.08 : 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : accent.withValues(alpha: enabled ? 0.28 : 0.12),
              width: 1.4,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 16),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: selected
                      ? Colors.white
                      : (enabled ? accentDeep : Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Helpers para abrir o sheet já com valores atuais dos services.
int fixedPendingMonthsAheadFromMap(Map<String, dynamic>? data) {
  final v = data?['pendingMonthsAhead'];
  if (v is num) return v.toInt().clamp(0, 12);
  return AppBusinessRules.pendingMonthsAheadDefault;
}

bool fixedPendingShowFromMap(Map<String, dynamic>? data) {
  return data?['showInPending'] as bool? ?? true;
}
