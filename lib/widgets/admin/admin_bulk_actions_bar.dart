import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';



typedef AdminBulkAction = void Function(String actionId);



/// Barra flutuante de ações em lote na lista de utilizadores.

class AdminBulkActionsBar extends StatelessWidget {

  final int selectedCount;

  final bool enabled;

  final bool canRemove;

  final bool canDeletePermanent;

  final VoidCallback onClear;

  final AdminBulkAction onAction;



  const AdminBulkActionsBar({

    super.key,

    required this.selectedCount,

    required this.enabled,

    this.canRemove = false,

    this.canDeletePermanent = false,

    required this.onClear,

    required this.onAction,

  });



  @override

  Widget build(BuildContext context) {

    if (selectedCount <= 0) return const SizedBox.shrink();



    return Material(

      elevation: 8,

      borderRadius: BorderRadius.circular(16),

      color: Colors.white,

      child: Padding(

        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),

        child: Wrap(

          spacing: 8,

          runSpacing: 8,

          crossAxisAlignment: WrapCrossAlignment.center,

          children: [

            Text(

              '$selectedCount selecionado(s)',

              style: const TextStyle(fontWeight: FontWeight.w800),

            ),

            if (enabled)

              OutlinedButton.icon(

                onPressed: () => onAction('prorrogar_30'),

                icon: const Icon(Icons.schedule_rounded, size: 18),

                label: const Text('+30 dias'),

              ),

            if (enabled)

              OutlinedButton.icon(

                onPressed: () => onAction('export_csv'),

                icon: const Icon(Icons.download_rounded, size: 18),

                label: const Text('Exportar'),

              ),

            if (enabled)

              OutlinedButton.icon(

                onPressed: () => onAction('push'),

                icon: const Icon(Icons.notifications_rounded, size: 18),

                label: const Text('Push'),

              ),

            if (canRemove)

              OutlinedButton.icon(

                onPressed: () => onAction('remover'),

                icon: const Icon(Icons.person_remove_rounded, size: 18),

                label: const Text('Remover'),

                style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),

              ),

            if (canDeletePermanent)

              FilledButton.icon(

                onPressed: () => onAction('excluir_total'),

                icon: const Icon(Icons.delete_forever_rounded, size: 18),

                label: const Text('Excluir total'),

                style: FilledButton.styleFrom(backgroundColor: AppColors.error),

              ),

            if (selectedCount == 2)

              OutlinedButton.icon(

                onPressed: () => onAction('compare'),

                icon: const Icon(Icons.compare_arrows_rounded, size: 18),

                label: const Text('Comparar'),

              ),

            TextButton(

              onPressed: onClear,

              child: const Text('Limpar'),

            ),

          ],

        ),

      ),

    );

  }

}



/// Checkbox de seleção em lote no card.

class AdminBulkSelectCheckbox extends StatelessWidget {

  final bool selected;

  final bool enabled;

  final ValueChanged<bool> onChanged;



  const AdminBulkSelectCheckbox({

    super.key,

    required this.selected,

    required this.enabled,

    required this.onChanged,

  });



  @override

  Widget build(BuildContext context) {

    if (!enabled) return const SizedBox.shrink();

    return SizedBox(

      width: 48,

      height: 48,

      child: Checkbox(

        value: selected,

        onChanged: (v) => onChanged(v == true),

        activeColor: AppColors.primary,

      ),

    );

  }

}


