import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/user_profile.dart';
import '../services/yearly_commitment_repeat_service.dart';
import '../theme/agenda_modern_ui.dart';
import '../theme/app_colors.dart';
import '../utils/anexo_viewer_helper.dart';
import '../utils/url_launcher_helper.dart';
import '../screens/reminder_detail_screen.dart';

/// Cartão premium para lista «em aberto» (Início / Agenda): edição, exclusão, link e anexo (audiência).
class AgendaOpenItemCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool isAudiencia;
  final UserProfile profile;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool>? onSelectionChanged;

  const AgendaOpenItemCard({
    super.key,
    required this.doc,
    required this.isAudiencia,
    required this.profile,
    required this.onEdit,
    required this.onDelete,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final title = (data['title'] ?? '').toString().trim();
    final displayTitle = title.isEmpty
        ? (isAudiencia ? 'Audiência' : 'Compromisso')
        : title;
    final date = (data['date'] as Timestamp?)?.toDate();
    final timeStr = (data['time'] ?? '').toString();
    final oficioUrl = (data['oficioUrl'] ?? '').toString().trim();
    final linkSalaAudiencia =
        (data['linkSalaAudiencia'] ?? '').toString().trim();
    final hasOficio = isAudiencia && oficioUrl.isNotEmpty;
    final hasLinkSala = isAudiencia && linkSalaAudiencia.isNotEmpty;

    final dateLine = [
      if (date != null) DateFormat('dd/MM/yyyy', 'pt_BR').format(date),
      if (timeStr.isNotEmpty) timeStr,
    ].join(' · ');

    DateTime? eventAt;
    if (date != null) {
      final parts = timeStr.split(':');
      if (parts.length >= 2) {
        eventAt = DateTime(
          date.year,
          date.month,
          date.day,
          int.tryParse(parts[0]) ?? 0,
          int.tryParse(parts[1]) ?? 0,
        );
      } else {
        eventAt = DateTime(date.year, date.month, date.day);
      }
    }
    final done = (data['done'] ?? false) == true;
    final urgency = AgendaModernUI.urgencyFromEventAt(eventAt, done: done);
    final audienciaStatus = isAudiencia
        ? AgendaModernUI.audienciaStatus(data)
        : null;

    final sei = (data['numeroSei'] ?? '').toString().trim();
    final oco = (data['numeroOcorrencia'] ?? '').toString().trim();
    final local = (data['localAudiencia'] ?? '').toString().trim();
    final notes = (data['notes'] ?? '').toString().trim();

    final isYearly =
        !isAudiencia && YearlyCommitmentRepeatService.isYearlyRepeatEntry(data);
    final instanceYear =
        YearlyCommitmentRepeatService.instanceYearFromData(data, docId: doc.id);

    final accentStart = isYearly
        ? const Color(0xFF1B5E20)
        : (isAudiencia ? const Color(0xFF1A237E) : AppColors.primary);
    final accentEnd = isYearly
        ? const Color(0xFF43A047)
        : (isAudiencia ? const Color(0xFF0E7490) : const Color(0xFF2563EB));

    final cardDecoration = isYearly
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFE8F5E9),
                Color(0xFFFFFDE7),
                Colors.white,
              ],
            ),
            border: Border.all(color: const Color(0xFF2E7D32), width: 2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.18),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          )
        : AgendaModernUI.modernCardDecoration(
            accent: accentStart,
            urgency: urgency,
          ).copyWith(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                accentStart.withValues(alpha: 0.06),
              ],
            ),
          );

    return RepaintBoundary(
      child: Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: selectionMode
              ? () => onSelectionChanged?.call(!selected)
              : onEdit,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: cardDecoration,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (selectionMode) ...[
                        Checkbox(
                          value: selected,
                          onChanged: (v) =>
                              onSelectionChanged?.call(v ?? false),
                          activeColor: accentStart,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                            colors: [
                              accentStart.withValues(alpha: 0.92),
                              accentEnd.withValues(alpha: 0.88),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accentStart.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(
                          isAudiencia
                              ? Icons.gavel_rounded
                              : Icons.event_available_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayTitle,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15.5,
                                letterSpacing: -0.2,
                                height: 1.2,
                                color: Color(0xFF0F172A),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (dateLine.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                dateLine,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (isYearly)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF2E7D32),
                                          Color(0xFF66BB6A),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.event_repeat_rounded,
                                            size: 14, color: Colors.white),
                                        const SizedBox(width: 4),
                                        Text(
                                          instanceYear != null
                                              ? 'Anual · $instanceYear'
                                              : 'Repete todo ano',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                AgendaUrgencyBadge(tier: urgency, compact: true),
                                if (audienciaStatus != null)
                                  AgendaAudienciaStatusBadge(
                                    status: audienciaStatus,
                                  ),
                              ],
                            ),
                            if (isYearly && notes.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFF2E7D32)
                                        .withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Observações',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF2E7D32),
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      notes,
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.35,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (isAudiencia &&
                                (sei.isNotEmpty ||
                                    oco.isNotEmpty ||
                                    local.isNotEmpty)) ...[
                              const SizedBox(height: 6),
                              if (sei.isNotEmpty)
                                _quickRow(Icons.folder_rounded, 'Processo (SEI): $sei'),
                              if (oco.isNotEmpty)
                                _quickRow(Icons.tag_rounded, 'Nº Ocorrência: $oco'),
                              if (local.isNotEmpty)
                                _quickRow(Icons.location_on_outlined, local),
                            ],
                          ],
                        ),
                      ),
                      if (!selectionMode)
                      IconButton(
                        tooltip: 'Excluir',
                        icon: Icon(Icons.delete_outline_rounded,
                            color: Colors.red.shade700),
                        constraints: const BoxConstraints(
                            minWidth: 48, minHeight: 48),
                        padding: EdgeInsets.zero,
                        onPressed: onDelete,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_rounded, size: 16),
                        label: const Text('Editar',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 12)),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          minimumSize: const Size(0, 40),
                          backgroundColor: isYearly
                              ? const Color(0xFF2E7D32).withValues(alpha: 0.12)
                              : null,
                          foregroundColor:
                              isYearly ? const Color(0xFF1B5E20) : null,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => ReminderDetailScreen(
                                doc: doc,
                                isAudiencia: isAudiencia,
                                profile: profile,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.visibility_rounded, size: 16),
                        label: const Text('Detalhes',
                            style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          foregroundColor: isYearly
                              ? const Color(0xFF1B5E20)
                              : null,
                          side: BorderSide(
                            color: isYearly
                                ? const Color(0xFF2E7D32)
                                : AppColors.primary,
                          ),
                        ),
                      ),
                      if (hasLinkSala)
                        FilledButton.icon(
                          onPressed: () async {
                            try {
                              await openUrlPreferChrome(linkSalaAudiencia);
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Não foi possível abrir o link da sala.'),
                                  ),
                                );
                              }
                            }
                          },
                          icon:
                              const Icon(Icons.video_call_rounded, size: 18),
                          label: const Text('Link da sala'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0D9488),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 48),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                        ),
                      if (hasOficio)
                        FilledButton.icon(
                          onPressed: () {
                            mostrarAnexoNaMesmaTela(
                              context,
                              url: oficioUrl,
                              fileName: (data['oficioFileName'] ?? '')
                                      .toString()
                                      .trim()
                                      .isEmpty
                                  ? 'Ofício'
                                  : (data['oficioFileName'] ?? 'Ofício')
                                      .toString(),
                            );
                          },
                          icon:
                              const Icon(Icons.attach_file_rounded, size: 18),
                          label: const Text('Anexo'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1A237E),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 48),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _quickRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
