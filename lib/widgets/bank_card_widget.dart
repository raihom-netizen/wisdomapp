import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Cartão de conta conectada (Open Finance): nome, status, saldo (quando a API existir) e última sync.
class BankCardWidget extends StatelessWidget {
  final String bankName;
  final String statusLabel;
  final bool connected;
  final String? balanceLabel;
  final String lastSyncLabel;
  final VoidCallback? onTap;

  const BankCardWidget({
    super.key,
    required this.bankName,
    required this.statusLabel,
    required this.connected,
    this.balanceLabel,
    required this.lastSyncLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bal = balanceLabel?.trim() ?? '';
    final child = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(
            connected ? Icons.check_circle_rounded : Icons.hourglass_empty_rounded,
            color: connected ? AppColors.success : AppColors.amber,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bankName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: connected ? AppColors.success : AppColors.textMuted,
                  ),
                ),
                Text(
                  [
                    if (bal.isNotEmpty) bal,
                    'Última sincronização: $lastSyncLabel',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          if (onTap != null) Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
        ],
      ),
    );

    if (onTap == null) return child;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: child,
    );
  }
}
