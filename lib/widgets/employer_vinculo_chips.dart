import 'package:flutter/material.dart';

import '../models/shift_location.dart';
import '../theme/app_colors.dart';

/// Chips **Estado / Município / Particular** — mesmo padrão visual (lançamento expresso, pré-cadastro, incluir plantão).
class EmployerVinculoChips {
  EmployerVinculoChips._();

  static const Color _todosAccent = AppColors.deepBlue;

  static Widget _chip({
    required bool selected,
    required String label,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
    bool dense = false,
  }) {
    final dark = accent.computeLuminance() > 0.55;
    final fg = selected ? (dark ? const Color(0xFF37474F) : Colors.white) : accent;
    final bg = selected ? accent : accent.withValues(alpha: 0.12);
    final border = selected ? accent : accent.withValues(alpha: 0.4);
    final r = dense ? 12.0 : 14.0;
    final iconSz = dense ? 17.0 : 22.0;
    final fs = dense ? 10.5 : 12.0;
    final padV = dense ? 6.0 : 10.0;
    final padH = dense ? 2.0 : 4.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(r),
        child: Ink(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(r),
            border: Border.all(color: border, width: selected ? 2.0 : 1),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.32),
                      blurRadius: dense ? 6 : 10,
                      offset: Offset(0, dense ? 2 : 4),
                    ),
                  ]
                : null,
          ),
          padding: EdgeInsets.symmetric(vertical: padV, horizontal: padH),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: iconSz, color: fg),
              SizedBox(height: dense ? 3 : 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: fs, fontWeight: FontWeight.w800, color: fg, letterSpacing: 0.1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Seleção única dos três vínculos (ex.: lançamento expresso).
  static Widget selectionRow({
    required EmployerType selected,
    required ValueChanged<EmployerType> onChanged,
    /// Menor e mais denso (ex.: lançamento expresso full screen).
    bool dense = false,
  }) {
    final gap = dense ? 6.0 : 8.0;
    return Row(
      children: [
        Expanded(
          child: _chip(
            dense: dense,
            selected: selected == EmployerType.state,
            label: 'Estado',
            icon: Icons.account_balance_rounded,
            accent: AppColors.vinculoEstado,
            onTap: () => onChanged(EmployerType.state),
          ),
        ),
        SizedBox(width: gap),
        Expanded(
          child: _chip(
            dense: dense,
            selected: selected == EmployerType.municipality,
            label: 'Município',
            icon: Icons.location_city_rounded,
            accent: AppColors.vinculoMunicipio,
            onTap: () => onChanged(EmployerType.municipality),
          ),
        ),
        SizedBox(width: gap),
        Expanded(
          child: _chip(
            dense: dense,
            selected: selected == EmployerType.private,
            label: 'Particular',
            icon: Icons.person_rounded,
            accent: AppColors.vinculoParticular,
            onTap: () => onChanged(EmployerType.private),
          ),
        ),
      ],
    );
  }

  /// Filtro da lista de plantões: `null` = todos.
  static Widget filterRow({
    required EmployerType? filter,
    required ValueChanged<EmployerType?> onChanged,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 380;
        final todos = Expanded(
          child: _chip(
            selected: filter == null,
            label: 'Todos',
            icon: Icons.layers_rounded,
            accent: _todosAccent,
            onTap: () => onChanged(null),
          ),
        );
        final estado = Expanded(
          child: _chip(
            selected: filter == EmployerType.state,
            label: 'Estado',
            icon: Icons.account_balance_rounded,
            accent: AppColors.vinculoEstado,
            onTap: () => onChanged(EmployerType.state),
          ),
        );
        final municipio = Expanded(
          child: _chip(
            selected: filter == EmployerType.municipality,
            label: 'Município',
            icon: Icons.location_city_rounded,
            accent: AppColors.vinculoMunicipio,
            onTap: () => onChanged(EmployerType.municipality),
          ),
        );
        final particular = Expanded(
          child: _chip(
            selected: filter == EmployerType.private,
            label: 'Particular',
            icon: Icons.person_rounded,
            accent: AppColors.vinculoParticular,
            onTap: () => onChanged(EmployerType.private),
          ),
        );
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [todos, const SizedBox(width: 8), estado]),
              const SizedBox(height: 8),
              Row(children: [municipio, const SizedBox(width: 8), particular]),
            ],
          );
        }
        return Row(
          children: [
            todos,
            const SizedBox(width: 8),
            estado,
            const SizedBox(width: 8),
            municipio,
            const SizedBox(width: 8),
            particular,
          ],
        );
      },
    );
  }
}
