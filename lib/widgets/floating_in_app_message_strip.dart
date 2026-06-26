import 'package:flutter/material.dart';

import '../services/in_app_floating_message_service.dart';
import '../theme/app_colors.dart';
import '../utils/url_launcher_helper.dart';

/// Cartão flutuante “premium” com OK (e link opcional) — usado pelo [FloatingShellBanners].
class InAppFloatingBannerCard extends StatelessWidget {
  final InAppFloatingPayload payload;

  const InAppFloatingBannerCard({super.key, required this.payload});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset > 0 ? 2 : 0),
      child: Material(
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                const Color(0xFF0F766E),
                const Color(0xFF0D9488),
                AppColors.accent.withValues(alpha: 0.92),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  payload.kind == InAppFloatingKind.weeklySummary
                      ? Icons.summarize_rounded
                      : Icons.campaign_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        payload.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        payload.body,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => InAppFloatingMessageService.dismissCurrent(),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        payload.bannerActionLabel,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                      ),
                    ),
                    if ((payload.openUrl ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      FilledButton.tonal(
                        onPressed: () {
                          final u = payload.openUrl!.trim();
                          if (u.isEmpty) return;
                          openPromoMaintenanceLink(u);
                        },
                        style: FilledButton.styleFrom(
                          foregroundColor: const Color(0xFF0F766E),
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Abrir', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
