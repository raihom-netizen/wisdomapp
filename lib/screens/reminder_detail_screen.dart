import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../utils/anexo_viewer_helper.dart';
import '../utils/url_launcher_helper.dart';
import '../utils/premium_upgrade.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../theme/theme_context.dart';

/// True se o anexo for imagem (PNG/JPEG) para exibir preview.
bool _isImageOficio(String url, String fileName) {
  if (url.isEmpty) return false;
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return true;
  final urlLower = url.split('?').first.toLowerCase();
  return urlLower.endsWith('.png') || urlLower.endsWith('.jpg') || urlLower.endsWith('.jpeg');
}

/// Tela full com detalhes do compromisso ou audiência (Dashboard ou Agenda).
///
/// Stateful para que ao remover o anexo (botão dentro da seção "Ofício de
/// comparecimento") a UI atualize sem precisar voltar ao card e abrir de novo.
class ReminderDetailScreen extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool isAudiencia;
  final UserProfile profile;

  const ReminderDetailScreen({
    super.key,
    required this.doc,
    required this.isAudiencia,
    required this.profile,
  });

  @override
  State<ReminderDetailScreen> createState() => _ReminderDetailScreenState();
}

class _ReminderDetailScreenState extends State<ReminderDetailScreen> {
  // Cópia mutável do snapshot — atualizamos localmente após remover o anexo
  // para refletir a UI sem precisar refazer fetch.
  late Map<String, dynamic> _data;
  bool _removingAnexo = false;

  @override
  void initState() {
    super.initState();
    _data = Map<String, dynamic>.from(widget.doc.data());
  }

  Future<void> _removerAnexoOficio() async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover anexo?'),
        content: const Text(
          'O ofício de comparecimento será desvinculado deste compromisso. O compromisso continua no sistema.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover anexo'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _removingAnexo = true);
    try {
      await widget.doc.reference.update({
        'oficioUrl': '',
        'oficioFileName': '',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() {
        _data['oficioUrl'] = '';
        _data['oficioFileName'] = '';
        _removingAnexo = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Anexo removido.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _removingAnexo = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao remover anexo: ${e.toString().split('\n').first}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final isAudiencia = widget.isAudiencia;
    final title = (data['title'] ?? '').toString();
    final notes = (data['notes'] ?? '').toString();
    final date = (data['date'] as Timestamp?)?.toDate();
    final timeStr = (data['time'] ?? '').toString();
    final numeroSei = (data['numeroSei'] ?? '').toString();
    final numeroOcorrencia = (data['numeroOcorrencia'] ?? '').toString();
    final resumoRelato = (data['resumoRelato'] ?? '').toString();
    final localAudiencia = (data['localAudiencia'] ?? '').toString();
    final linkSalaAudiencia = (data['linkSalaAudiencia'] ?? '').toString().trim();
    final oficioUrl = (data['oficioUrl'] ?? '').toString().trim();
    final oficioFileName = (data['oficioFileName'] ?? '').toString().trim();
    final isDark = context.isDarkMode;
    final labelStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: isDark ? context.appTextMuted : const Color(0xFF64748B),
    );
    final bodyStyle = TextStyle(
      fontSize: 15,
      color: isDark ? context.appTextSecondary : Colors.grey.shade800,
    );

    return Scaffold(
      backgroundColor: isDark ? context.appScaffold : const Color(0xFFF4F7FA),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Voltar',
        ),
        title: const Text(
          'Detalhes do compromisso',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        backgroundColor: AppColors.deepBlueDark,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? context.appSurface : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.06), blurRadius: 12, offset: const Offset(0, 4))],
                border: Border.all(
                    color: isDark ? context.appChipIdleBorder : Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 28,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          (title.isEmpty || title == 'Audiência')
                              ? 'Compromisso'
                              : title,
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: context.appDeepTitle),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (!isAudiencia && title.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Título', style: labelStyle),
                    const SizedBox(height: 4),
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                  if (date != null || timeStr.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Data e horário', style: labelStyle),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (date != null) DateFormat('dd/MM/yyyy', 'pt_BR').format(date),
                        if (timeStr.isNotEmpty) timeStr,
                      ].join(' · '),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (!isAudiencia && notes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Observações', style: labelStyle),
                    const SizedBox(height: 4),
                    Text(notes, style: bodyStyle),
                  ],
                  if (isAudiencia) ...[
                    if (numeroSei.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('Número SEI', style: labelStyle),
                      const SizedBox(height: 4),
                      Text(numeroSei, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                    if (numeroOcorrencia.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('Nº Ocorrência', style: labelStyle),
                      const SizedBox(height: 4),
                      Text(numeroOcorrencia, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                    if (resumoRelato.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('Resumo relato', style: labelStyle),
                      const SizedBox(height: 4),
                      Text(resumoRelato, style: bodyStyle),
                    ],
                    if (localAudiencia.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('Local', style: labelStyle),
                      const SizedBox(height: 4),
                      Text(localAudiencia, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                    if (isAudiencia && linkSalaAudiencia.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('Link da sala', style: labelStyle),
                      const SizedBox(height: 6),
                      FilledButton.icon(
                        onPressed: () async {
                          try {
                            await openUrlPreferChrome(linkSalaAudiencia);
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Não foi possível abrir o link da sala.')),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.video_call_rounded, size: 20),
                        label: const Text('Acessar sala virtual'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          try {
                            await openUrlPreferChrome(linkSalaAudiencia);
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Não foi possível abrir o link da sala.')),
                              );
                            }
                          }
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            linkSalaAudiencia,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? const Color(0xFF64B5F6)
                                  : const Color(0xFF1565C0),
                              decoration: TextDecoration.underline,
                              decorationColor: isDark
                                  ? const Color(0xFF64B5F6)
                                  : const Color(0xFF1565C0),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    if (isAudiencia && oficioUrl.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('Ofício de comparecimento', style: labelStyle),
                      const SizedBox(height: 6),
                      _buildOficioPreview(context, oficioUrl, oficioFileName),
                      const SizedBox(height: 10),
                      // Wrap garante quebra de linha em iOS / celular estreito
                      // sem cortar nem desalinhar os botões.
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              mostrarAnexoNaMesmaTela(
                                context,
                                url: oficioUrl,
                                fileName: oficioFileName.isEmpty ? 'Ofício' : oficioFileName,
                              );
                            },
                            icon: const Icon(Icons.visibility_rounded, size: 18),
                            label: Text(oficioFileName.isEmpty ? 'Ver anexo' : 'Ver anexo · $oficioFileName'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _removingAnexo ? null : _removerAnexoOficio,
                            icon: _removingAnexo
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.link_off_rounded, size: 18),
                            label: Text(_removingAnexo ? 'Removendo…' : 'Remover anexo'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.orange.shade800,
                              side: BorderSide(color: Colors.orange.shade700),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  /// Exibe a foto do ofício quando for imagem; senão só o botão já cobre.
  static Widget _buildOficioPreview(BuildContext context, String oficioUrl, String oficioFileName) {
    if (oficioUrl.isEmpty || !_isImageOficio(oficioUrl, oficioFileName)) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => mostrarAnexoNaMesmaTela(
        context,
        url: oficioUrl,
        fileName: oficioFileName.isEmpty ? 'Ofício' : oficioFileName,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          oficioUrl,
          width: double.infinity,
          height: 200,
          fit: BoxFit.contain,
          // Limita a altura de decodificação (preview ~200px) para reduzir uso de memória.
          cacheHeight: 600,
          errorBuilder: (_, __, ___) => Container(
            height: 120,
            alignment: Alignment.center,
            color: context.isDarkMode ? context.appSurfaceHigh : Colors.grey.shade200,
            child: Icon(Icons.image_not_supported_rounded, size: 48, color: Colors.grey.shade600),
          ),
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return Container(
              height: 120,
              color: context.isDarkMode ? context.appSurfaceHigh : Colors.grey.shade100,
              alignment: Alignment.center,
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                      : null,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
