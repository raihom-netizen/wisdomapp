import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../utils/anexo_viewer_helper.dart';
import '../utils/url_launcher_helper.dart';
import '../screens/reminder_detail_screen.dart';

/// Mesmo visual da lista de compromissos/audiências da tela Início (sheet e cards).
class AgendaReminderListTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool isAudiencia;
  final UserProfile profile;
  final VoidCallback onEdit;

  const AgendaReminderListTile({
    super.key,
    required this.doc,
    required this.isAudiencia,
    required this.profile,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final title = (data['title'] ?? '').toString();
    final date = (data['date'] as Timestamp?)?.toDate();
    final timeStr = (data['time'] ?? '').toString();
    final oficioUrl = (data['oficioUrl'] ?? '').toString().trim();
    final linkSalaAudiencia =
        (data['linkSalaAudiencia'] ?? '').toString().trim();
    final hasOficio = isAudiencia && oficioUrl.isNotEmpty;
    final hasLinkSala = isAudiencia && linkSalaAudiencia.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: 0,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: ListTile(
            leading: Icon(
              isAudiencia ? Icons.gavel_rounded : Icons.schedule_rounded,
              size: 24,
              color: isAudiencia ? const Color(0xFF1A237E) : AppColors.primary,
            ),
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
            subtitle: (date != null || timeStr.isNotEmpty)
                ? Text(
                    [
                      if (date != null)
                        DateFormat('dd/MM/yyyy', 'pt_BR').format(date),
                      if (timeStr.isNotEmpty) timeStr,
                    ].join(' · '),
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : null,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            isThreeLine: false,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasLinkSala)
                  IconButton(
                    icon: const Icon(Icons.video_call_rounded, size: 22),
                    onPressed: () async {
                      try {
                        await openUrlPreferChrome(linkSalaAudiencia);
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Não foi possível abrir o link da sala.')),
                          );
                        }
                      }
                    },
                    tooltip: 'Abrir link da sala',
                  ),
                IconButton(
                  icon: const Icon(Icons.visibility_rounded, size: 22),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ReminderDetailScreen(
                          doc: doc,
                          isAudiencia: isAudiencia,
                          profile: profile,
                        ),
                      ),
                    );
                  },
                  tooltip: 'Ver detalhes',
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 22),
                  onPressed: onEdit,
                  tooltip: 'Editar',
                ),
                if (hasOficio)
                  IconButton(
                    icon: const Icon(Icons.attach_file_rounded, size: 22),
                    onPressed: () {
                      mostrarAnexoNaMesmaTela(
                        context,
                        url: oficioUrl,
                        fileName: (data['oficioFileName'] ?? '')
                                .toString()
                                .trim()
                                .isEmpty
                            ? 'Ofício'
                            : (data['oficioFileName'] ?? 'Ofício').toString(),
                      );
                    },
                    tooltip: 'Ver anexo',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
