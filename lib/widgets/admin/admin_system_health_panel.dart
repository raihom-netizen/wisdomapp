import 'package:flutter/material.dart';
import '../../constants/app_version.dart';

/// Painel de saúde do sistema no Resumo admin.
class AdminSystemHealthPanel extends StatelessWidget {
  final int totalUsers;
  final String? txResumoAviso;
  final DateTime? latestTransactionAt;
  final DateTime? latestUserCreatedAt;
  final double usersEstimatedMb;
  final double txEstimatedMb;

  const AdminSystemHealthPanel({
    super.key,
    required this.totalUsers,
    this.txResumoAviso,
    this.latestTransactionAt,
    this.latestUserCreatedAt,
    this.usersEstimatedMb = 0,
    this.txEstimatedMb = 0,
  });

  @override
  Widget build(BuildContext context) {
    final hasTxWarning = (txResumoAviso ?? '').trim().isNotEmpty;
    final items = <_HealthRow>[
      _HealthRow(
        label: 'Versão publicada',
        value: 'v${AppVersion.current}',
        ok: true,
        icon: Icons.verified_rounded,
      ),
      _HealthRow(
        label: 'Utilizadores indexados',
        value: '$totalUsers',
        ok: totalUsers > 0,
        icon: Icons.people_rounded,
      ),
      _HealthRow(
        label: 'Último lançamento',
        value: _fmt(latestTransactionAt),
        ok: latestTransactionAt != null &&
            DateTime.now().difference(latestTransactionAt!).inDays < 14,
        icon: Icons.receipt_long_rounded,
      ),
      _HealthRow(
        label: 'Último cadastro',
        value: _fmt(latestUserCreatedAt),
        ok: latestUserCreatedAt != null,
        icon: Icons.person_add_rounded,
      ),
      _HealthRow(
        label: 'Estimativa Firestore',
        value:
            '${usersEstimatedMb.toStringAsFixed(1)} MB users · ${txEstimatedMb.toStringAsFixed(1)} MB tx',
        ok: !hasTxWarning,
        icon: Icons.storage_rounded,
      ),
      if (hasTxWarning)
        _HealthRow(
          label: 'Aviso resumo',
          value: txResumoAviso!,
          ok: false,
          icon: Icons.warning_amber_rounded,
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.health_and_safety_rounded,
                  color: Colors.teal.shade700, size: 22),
              const SizedBox(width: 8),
              const Text(
                'Saúde do sistema',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map((row) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      row.ok ? Icons.check_circle_rounded : Icons.error_rounded,
                      size: 18,
                      color: row.ok ? Colors.green.shade700 : Colors.orange.shade800,
                    ),
                    const SizedBox(width: 8),
                    Icon(row.icon, size: 18, color: Colors.grey.shade600),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          Text(
                            row.value,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  String _fmt(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}

class _HealthRow {
  final String label;
  final String value;
  final bool ok;
  final IconData icon;

  const _HealthRow({
    required this.label,
    required this.value,
    required this.ok,
    required this.icon,
  });
}
