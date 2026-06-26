import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/pluggy_sync_schedule.dart';
import '../theme/app_colors.dart';

/// Mostra janela fixa (12h/23h) + última sync gravada em `users/{uid}.openFinanceLastScheduledSyncAt`.
class PluggySyncScheduleBanner extends StatelessWidget {
  const PluggySyncScheduleBanner({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        final d = snap.data?.data() ?? {};
        final ts = d['openFinanceLastScheduledSyncAt'];
        DateTime? at;
        if (ts is Timestamp) at = ts.toDate();
        String last = '—';
        if (at != null) {
          last = DateFormat("dd/MM/yyyy 'às' HH:mm").format(at);
        }
        return Material(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.schedule_rounded, color: AppColors.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sincronização: ${PluggySyncSchedule.slotsLabelBr}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, height: 1.3),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        PluggySyncSchedule.shortUserMessage,
                        style: TextStyle(fontSize: 12, height: 1.35, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Última sincronização agendada no servidor: $last',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
