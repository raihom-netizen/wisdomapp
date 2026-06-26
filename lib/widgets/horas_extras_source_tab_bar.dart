import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Abas coloridas — Goiás / CLT / Personalizar (seletor visível da aba ativa).
class HorasExtrasSourceTabBar extends StatelessWidget {
  const HorasExtrasSourceTabBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _tabs = [
    (
      label: 'Goiás',
      icon: Icons.flag_rounded,
      colors: [Color(0xFF1E3A8A), Color(0xFF2563EB), Color(0xFF0EA5E9)],
    ),
    (
      label: 'CLT',
      icon: Icons.gavel_rounded,
      colors: [Color(0xFF047857), Color(0xFF059669), Color(0xFF34D399)],
    ),
    (
      label: 'Personalizar',
      icon: Icons.tune_rounded,
      colors: [Color(0xFF7C3AED), Color(0xFF8B5CF6), Color(0xFFF97316)],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: List.generate(_tabs.length, (i) {
          final t = _tabs[i];
          final selected = selectedIndex == i;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 4, right: i == 2 ? 0 : 4),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onSelected(i),
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: selected
                          ? LinearGradient(
                              colors: t.colors,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: selected ? null : Colors.white.withValues(alpha: 0.7),
                      border: Border.all(
                        color: selected
                            ? t.colors.first.withValues(alpha: 0.5)
                            : t.colors.first.withValues(alpha: 0.22),
                        width: selected ? 1.5 : 1,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: t.colors.first.withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          t.icon,
                          size: 22,
                          color: selected ? Colors.white : t.colors.first,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t.label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.1,
                            color: selected ? Colors.white : AppColors.textSecondary,
                          ),
                        ),
                        if (selected) ...[
                          const SizedBox(height: 6),
                          Container(
                            width: 28,
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
