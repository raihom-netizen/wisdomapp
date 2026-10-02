import 'package:flutter/material.dart';

import '../constants/currency_formats.dart';
import '../constants/date_time_formats.dart';
import '../theme/app_colors.dart';
import '../theme/theme_context.dart';
import 'fast_text_field.dart';

/// Decoração padrão de sheets financeiros premium (fundo suave + cantos).
BoxDecoration financePremiumSheetDecoration({
  Color? surfaceTint,
  BuildContext? context,
}) {
  final tint = surfaceTint ?? AppColors.primary;
  final dark = context != null && Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      // O topo era `tint` com 6% (claro) / 14% (escuro) de opacidade: os
      // primeiros 12% da folha ficavam quase transparentes e o painel de trás
      // aparecia através dela. A mistura sobre a superfície dá a mesma cor,
      // só que opaca.
      colors: dark
          ? [
              Color.alphaBlend(tint.withValues(alpha: 0.14), const Color(0xFF1E1E1E)),
              const Color(0xFF1E1E1E),
              const Color(0xFF121212),
            ]
          : [
              Color.alphaBlend(tint.withValues(alpha: 0.06), Colors.white),
              const Color(0xFFF8FAFC),
              Colors.white,
            ],
      stops: const [0.0, 0.12, 0.35],
    ),
    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
    boxShadow: [
      BoxShadow(
        color: AppColors.deepBlueDark.withValues(alpha: 0.18),
        blurRadius: 28,
        offset: const Offset(0, -4),
      ),
    ],
  );
}

/// AppBar gradiente para telas de lançamento.
PreferredSizeWidget financePremiumGradientAppBar({
  required String title,
  required VoidCallback onBack,
  List<Widget>? actions,
  List<Color>? gradientColors,
  /// Telas abertas como aba do shell não têm para onde voltar: sem seta.
  bool showBack = true,
}) {
  return AppBar(
    toolbarHeight: 56,
    elevation: 0,
    scrolledUnderElevation: 0,
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    automaticallyImplyLeading: false,
    leading: showBack
        ? IconButton(
            tooltip: 'Voltar',
            onPressed: onBack,
            icon: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
          )
        : null,
    flexibleSpace: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors ??
              const [
                AppColors.deepBlueDark,
                AppColors.deepBlue,
                AppColors.primary,
                AppColors.accent,
              ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBlueDark.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
    ),
    title: Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.2,
      ),
    ),
    centerTitle: true,
    actions: actions,
    iconTheme: const IconThemeData(color: Colors.white),
    foregroundColor: Colors.white,
  );
}

/// Handle + cabeçalho colorido para bottom sheets.
class FinancePremiumSheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Color> iconGradient;
  final VoidCallback? onBack;
  final Color? titleColor;

  const FinancePremiumSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.iconGradient = const [AppColors.primary, AppColors.accent],
    this.onBack,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 44,
            height: 5,
            margin: const EdgeInsets.only(top: 10, bottom: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: iconGradient),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (onBack != null) ...[
                Material(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: onBack,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(Icons.arrow_back_rounded,
                          color: AppColors.primary, size: 22),
                    ),
                  ),
                ),
                SizedBox(width: 10),
              ],
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: iconGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: iconGradient.first.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: titleColor ??
                            (context.isDarkMode
                                ? context.appTextPrimary
                                : const Color(0xFF0F172A)),
                        height: 1.15,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: context.appTextSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Campo tocável (data, conta, etc.) com visual premium.
class FinancePremiumFieldTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
  final Widget? trailing;

  const FinancePremiumFieldTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: isDark ? 0.22 : 0.10),
                isDark ? context.appSurfaceHigh : Colors.white,
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            border: Border.all(
                color: accent.withValues(alpha: isDark ? 0.55 : 0.28),
                width: isDark ? 1.4 : 1.2),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: isDark ? 0.18 : 0.08),
                blurRadius: isDark ? 14 : 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accent,
                        Color.lerp(accent, AppColors.secondary, 0.35)!
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: accent.withValues(alpha: 0.85),
                          letterSpacing: 0.2,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: context.appTextPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                trailing ??
                    Icon(Icons.chevron_right_rounded,
                        color: accent.withValues(alpha: 0.7)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Decoração de dropdown premium.
InputDecoration financePremiumDropdownDecoration(
  BuildContext context, {
  required String label,
  IconData? prefixIcon,
  Color accent = AppColors.primary,
}) {
  return InputDecoration(
    filled: true,
    fillColor: context.appSurface,
    labelText: label,
    labelStyle: TextStyle(
        fontWeight: FontWeight.w700, color: context.appTextSecondary, fontSize: 13),
    prefixIcon: prefixIcon != null
        ? Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(prefixIcon, color: accent, size: 22),
          )
        : null,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: accent.withValues(alpha: 0.22)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: accent.withValues(alpha: 0.18)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: accent, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );
}

/// Botões confirmar / cancelar para sheets.
class FinancePremiumSheetActions extends StatelessWidget {
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;
  final String confirmLabel;
  final String cancelLabel;
  final Color confirmColor;
  final IconData confirmIcon;
  final bool confirmEnabled;

  const FinancePremiumSheetActions({
    super.key,
    required this.onConfirm,
    this.onCancel,
    this.confirmLabel = 'Confirmar',
    this.cancelLabel = 'Cancelar',
    this.confirmColor = AppColors.success,
    this.confirmIcon = Icons.check_rounded,
    this.confirmEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: confirmEnabled
                  ? [
                      confirmColor,
                      Color.lerp(confirmColor, AppColors.accent, 0.25)!
                    ]
                  : [Colors.grey.shade400, Colors.grey.shade500],
            ),
            boxShadow: confirmEnabled
                ? [
                    BoxShadow(
                      color: confirmColor.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: FilledButton.icon(
            onPressed: confirmEnabled ? onConfirm : null,
            icon: Icon(confirmIcon, size: 22),
            label: Text(confirmLabel,
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
            ),
          ),
        ),
        if (onCancel != null) ...[
          SizedBox(height: 8),
          TextButton(
            onPressed: onCancel,
            child: Text(cancelLabel,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ],
    );
  }
}

/// Toggle Receita / Despesa premium.
class FinancePremiumTypeToggle extends StatelessWidget {
  final bool isIncome;
  final ValueChanged<bool> onChanged;

  const FinancePremiumTypeToggle({
    super.key,
    required this.isIncome,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.deepBlue.withValues(alpha: 0.08),
            AppColors.accent.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          _chip(
            label: 'Receita',
            selected: isIncome,
            icon: Icons.arrow_downward_rounded,
            colors: const [Color(0xFF15803D), Color(0xFF22C55E)],
            onTap: () => onChanged(true),
            dark: context.isDarkMode,
          ),
          _chip(
            label: 'Despesa',
            selected: !isIncome,
            icon: Icons.arrow_upward_rounded,
            colors: const [Color(0xFFB91C1C), Color(0xFFEF4444)],
            onTap: () => onChanged(false),
            dark: context.isDarkMode,
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required IconData icon,
    required List<Color> colors,
    required VoidCallback onTap,
    bool dark = false,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight)
                : null,
            borderRadius: BorderRadius.circular(14),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: colors.first.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18,
                  color: selected
                      ? Colors.white
                      : (dark ? Colors.grey.shade400 : Colors.grey.shade600)),
              SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : (dark ? Colors.grey.shade300 : Colors.grey.shade700),
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Diálogo de edição premium (substitui AlertDialog plano).
Future<T?> showFinancePremiumEditDialog<T>({
  required BuildContext context,
  required String title,
  required Widget content,
  required VoidCallback onSave,
  VoidCallback? onCancel,
  Color accent = AppColors.primary,
  String saveLabel = 'Salvar',
}) {
  return showDialog<T>(
    context: context,
    barrierColor: AppColors.deepBlueDark.withValues(alpha: 0.55),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.88),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: ctx.isDarkMode
                  ? [ctx.appSurfaceHigh, ctx.appSurface]
                  : const [Color(0xFFF8FAFC), Colors.white],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.deepBlueDark.withValues(alpha: 0.22),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accent,
                      Color.lerp(accent, AppColors.accent, 0.45)!
                    ],
                  ),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.edit_rounded,
                          color: Colors.white, size: 22),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        onCancel?.call();
                        Navigator.pop(ctx);
                      },
                      icon:
                          Icon(Icons.close_rounded, color: Colors.white),
                      style:
                          IconButton.styleFrom(minimumSize: const Size(44, 44)),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                  child: content,
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                    18, 8, 18, 16 + MediaQuery.paddingOf(ctx).bottom),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          onCancel?.call();
                          Navigator.pop(ctx);
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side:
                              BorderSide(color: accent.withValues(alpha: 0.4)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text('Cancelar',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, color: accent)),
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(colors: [
                            accent,
                            Color.lerp(accent, AppColors.secondary, 0.3)!
                          ]),
                          boxShadow: [
                            BoxShadow(
                                color: accent.withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4)),
                          ],
                        ),
                        child: FilledButton(
                          onPressed: onSave,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(saveLabel,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900)),
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
    ),
  );
}

/// Rodapé duplo premium (Cancelar + Confirmar) para formulários financeiros.
class FinancePremiumFormFooterActions extends StatelessWidget {
  const FinancePremiumFormFooterActions({
    super.key,
    required this.onCancel,
    required this.onSave,
    required this.saveLabel,
    this.isBusy = false,
    this.busyLabel = 'Salvando…',
    this.saveIcon = Icons.check_rounded,
    this.accent = AppColors.deepBlue,
  });

  final VoidCallback onCancel;
  final VoidCallback onSave;
  final String saveLabel;
  final bool isBusy;
  final String busyLabel;
  final IconData saveIcon;
  final Color accent;

  static const double _kMinHeight = 52;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 400;

        final cancel = OutlinedButton(
          onPressed: isBusy ? null : onCancel,
          style: OutlinedButton.styleFrom(
            foregroundColor: accent,
            side: BorderSide(color: accent.withValues(alpha: 0.38), width: 1.2),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
            minimumSize: const Size(0, _kMinHeight),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.close_rounded, size: 20),
              SizedBox(width: 8),
              Text('Cancelar',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ],
          ),
        );

        final save = DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: isBusy
                  ? [Colors.grey.shade400, Colors.grey.shade500]
                  : [accent, Color.lerp(accent, AppColors.accent, 0.35)!],
            ),
            boxShadow: isBusy
                ? null
                : [
                    BoxShadow(
                        color: accent.withValues(alpha: 0.32),
                        blurRadius: 12,
                        offset: const Offset(0, 4)),
                  ],
          ),
          child: FilledButton(
            onPressed: isBusy ? null : onSave,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
              minimumSize: const Size(0, _kMinHeight),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isBusy) ...[
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: Colors.white),
                  ),
                  SizedBox(width: 10),
                  Text(busyLabel,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 15)),
                ] else ...[
                  Icon(saveIcon, size: 21),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      saveLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 15),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [cancel, SizedBox(height: 10), save],
          );
        }
        return Row(
          children: [
            Expanded(child: cancel),
            SizedBox(width: 12),
            Expanded(flex: 2, child: save),
          ],
        );
      },
    );
  }
}

/// Card de conta bancária premium (painel / saldo por contas).
class FinancePremiumAccountCard extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final String balanceText;
  final Color balanceColor;
  final List<Color> gradient;
  final VoidCallback? onTap;
  final Widget? trailing;

  const FinancePremiumAccountCard({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.balanceText,
    required this.balanceColor,
    required this.gradient,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [
                gradient.first.withValues(alpha: isDark ? 0.22 : 0.14),
                gradient.last.withValues(alpha: isDark ? 0.12 : 0.06),
                isDark ? context.appSurfaceHigh : Colors.white,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
                color: gradient.first.withValues(alpha: isDark ? 0.45 : 0.22)),
            boxShadow: [
              BoxShadow(
                color: gradient.first.withValues(alpha: isDark ? 0.16 : 0.12),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                leading,
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: context.appTextPrimary),
                      ),
                      SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.appTextSecondary),
                      ),
                      SizedBox(height: 6),
                      Text(
                        balanceText,
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            color: balanceColor),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Totalizador receitas + despesas + saldo no preview do período (inclui saldo de abertura).
class FinanceInsightPeriodTotalizer extends StatelessWidget {
  final double income;
  final double expense;

  /// Saldo antes do período — quando informado, exibe abertura e saldo acumulado.
  final double? openingBalance;

  const FinanceInsightPeriodTotalizer({
    super.key,
    required this.income,
    required this.expense,
    this.openingBalance,
  });

  @override
  Widget build(BuildContext context) {
    final showOpening = openingBalance != null;
    final opening = openingBalance ?? 0.0;
    final saldoPeriodo = income - expense;
    final saldoAcumulado = showOpening ? opening + saldoPeriodo : saldoPeriodo;
    final saldoAcumColor =
        saldoAcumulado >= 0 ? AppColors.saldoPositive : AppColors.saldoNegative;
    final openingColor =
        opening >= 0 ? AppColors.saldoPositive : AppColors.saldoNegative;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: context.appPanelDecoration(
        radius: 18,
        borderColor: context.appChipIdleBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Resumo do período',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: context.appTextSecondary),
          ),
          SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 340;
              final halfW = narrow ? c.maxWidth : (c.maxWidth - 8) / 2;
              final tiles = <Widget>[
                if (showOpening)
                  _totalTile(
                    'Saldo de abertura',
                    CurrencyFormats.formatBRLTight(opening),
                    openingColor,
                    Icons.account_balance_rounded,
                  ),
                _totalTile(
                  'Receitas',
                  CurrencyFormats.formatBRLTight(income),
                  AppColors.financeReceita,
                  Icons.trending_up_rounded,
                ),
                _totalTile(
                  'Despesas',
                  CurrencyFormats.formatBRLTight(expense),
                  AppColors.financeDespesa,
                  Icons.trending_down_rounded,
                ),
                _totalTile(
                  showOpening ? 'Saldo (acum.)' : 'Saldo',
                  CurrencyFormats.formatBRLTight(saldoAcumulado),
                  saldoAcumColor,
                  Icons.account_balance_wallet_rounded,
                ),
              ];
              if (narrow) {
                return Column(
                  children: [
                    for (var i = 0; i < tiles.length; i++) ...[
                      if (i > 0) SizedBox(height: 8),
                      tiles[i],
                    ],
                  ],
                );
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in tiles) SizedBox(width: halfW, child: t),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _totalTile(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.14),
            color.withValues(alpha: 0.05)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color.withValues(alpha: 0.9)),
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1.1),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cartão de lançamento no preview financeiro (edição/exclusão).
class FinanceInsightTransactionCard extends StatelessWidget {
  final String category;
  final String description;
  final double amount;
  final DateTime? date;
  final bool isIncome;
  final double percent;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// Linha do cliente/fornecedor (opcional) — quem monta é quem tem o
  /// lançamento em mãos.
  final Widget? parceiro;

  const FinanceInsightTransactionCard({
    super.key,
    required this.category,
    required this.description,
    required this.amount,
    required this.date,
    required this.isIncome,
    required this.percent,
    required this.onEdit,
    required this.onDelete,
    this.parceiro,
  });

  @override
  Widget build(BuildContext context) {
    final accent =
        isIncome ? AppColors.financeReceita : AppColors.financeDespesa;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border(left: BorderSide(color: accent, width: 4)),
        boxShadow: [
          BoxShadow(
              color: accent.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 5)),
          BoxShadow(
              color: Colors.black.withValues(alpha: context.isDarkMode ? 0.35 : 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: context.appTextPrimary),
                      ),
                      if (description.isNotEmpty) ...[
                        SizedBox(height: 3),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: context.appTextSecondary),
                        ),
                      ],
                      if (parceiro != null) ...[
                        SizedBox(height: 3),
                        parceiro!,
                      ],
                    ],
                  ),
                ),
                SizedBox(width: 8),
                _actionBtn(Icons.edit_rounded, AppColors.primary, onEdit),
                SizedBox(width: 6),
                _actionBtn(
                    Icons.delete_outline_rounded, AppColors.error, onDelete),
              ],
            ),
            SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  CurrencyFormats.formatBRLTight(amount),
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900, color: accent),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${percent.toStringAsFixed(1)}%',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: accent),
                  ),
                ),
                if (date != null)
                  Text(
                    DateTimeFormats.formatDateTimeMinute(date!),
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: context.appTextMuted),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}

/// Campo de pesquisa compacto para painéis de filtro financeiro.
class FinanceFilterSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;
  final bool showClear;

  const FinanceFilterSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.onClear,
    this.showClear = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: context.appPanelDecoration(
        radius: 18,
        borderAccent: AppColors.primary,
        borderAlpha: 0.12,
      ),
      child: FastTextField(
        controller: controller,
        kind: FastTextFieldKind.search,
        textInputAction: TextInputAction.search,
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
              color: context.appTextMuted.withValues(alpha: 0.9), fontSize: 14),
          prefixIcon: Icon(Icons.search_rounded,
              color: AppColors.primary.withValues(alpha: 0.85)),
          suffixIcon: showClear
              ? IconButton(
                  tooltip: 'Limpar busca',
                  onPressed: onClear,
                  icon: Icon(Icons.close_rounded,
                      size: 20,
                      color: context.appTextMuted.withValues(alpha: 0.9)),
                )
              : null,
          filled: true,
          fillColor: Colors.transparent,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

/// Tile para escolher categoria no painel de filtros (abre picker igual ao lançamento).
class FinanceCategoryFilterTile extends StatelessWidget {
  final String? selectedCategory;
  final bool loading;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  const FinanceCategoryFilterTile({
    super.key,
    required this.selectedCategory,
    this.loading = false,
    this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FinancePremiumFieldTile(
          label: 'Filtrar por categoria',
          value: loading
              ? 'A carregar categorias…'
              : (selectedCategory ?? 'Todas as categorias'),
          icon: Icons.category_rounded,
          accent: AppColors.accent,
          onTap: loading ? null : onTap,
          trailing: loading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: AppColors.primary.withValues(alpha: 0.85),
                  ),
                )
              : Icon(Icons.arrow_drop_down_circle_outlined,
                  color: AppColors.accent.withValues(alpha: 0.75)),
        ),
        if (!loading && selectedCategory != null && onClear != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onClear,
              icon: Icon(Icons.clear_rounded, size: 18),
              label: Text('Limpar categoria'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: context.appTextMuted,
              ),
            ),
          ),
      ],
    );
  }
}
