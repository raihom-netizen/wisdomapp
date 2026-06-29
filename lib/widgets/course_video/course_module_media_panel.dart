import 'package:flutter/material.dart';

import '../../utils/course_media_url_resolver.dart';
import '../../utils/course_thumb_resolver.dart';
import '../../utils/youtube_url_helper.dart';
import '../course_media_preview.dart';
import 'course_video_player_shell.dart';

/// Conteúdo de curso/dica **dentro do módulo** — vídeo inline, fotos, detalhes modernos.
class CourseModuleMediaPanel extends StatefulWidget {
  const CourseModuleMediaPanel({
    super.key,
    required this.data,
    required this.accent,
    required this.accent2,
    required this.badge,
    this.onSelectRelated,
    this.related = const [],
  });

  final Map<String, dynamic> data;
  final Color accent;
  final Color accent2;
  final String badge;
  final void Function(Map<String, dynamic> item)? onSelectRelated;
  final List<Map<String, dynamic>> related;

  static String? youtubeIdFrom(Map<String, dynamic> data) {
    final stored = (data['youtubeVideoId'] ?? '').toString().trim();
    if (stored.isNotEmpty) return stored;
    final link = (data['linkUrl'] ??
            data['externalUrl'] ??
            data['youtubeUrl'] ??
            data['videoUrl'] ??
            '')
        .toString();
    return YoutubeUrlHelper.extractVideoId(link);
  }

  static String? mp4From(Map<String, dynamic> data) {
    final u = (data['mp4Url'] ?? '').toString().trim();
    return u.isEmpty ? null : u;
  }

  static bool hasInlineVideo(Map<String, dynamic> data) {
    if (!CourseThumbResolver.isVideoContent(data)) return false;
    return mp4From(data) != null ||
        youtubeIdFrom(data) != null ||
        CourseMediaUrlResolver.collectVideoEntries(data).isNotEmpty;
  }

  static bool hasInlineDicaContent(Map<String, dynamic> data) {
    final type = (data['type'] ?? 'curso').toString().trim().toLowerCase();
    if (type != 'dica') return false;
    final body = (data['bodyText'] ?? data['description'] ?? '').toString().trim();
    return CourseMediaUrlResolver.hasResolvableImage(data) || body.isNotEmpty;
  }

  @override
  State<CourseModuleMediaPanel> createState() => _CourseModuleMediaPanelState();
}

class _CourseModuleMediaPanelState extends State<CourseModuleMediaPanel>
    with AutomaticKeepAliveClientMixin {
  String? _resolvedMp4;
  var _mp4Loading = false;
  var _descExpanded = false;
  String? _panelDocId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _panelDocId = widget.data['id']?.toString();
    _loadMp4();
  }

  @override
  void didUpdateWidget(covariant CourseModuleMediaPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newId = widget.data['id']?.toString();
    if (newId != _panelDocId) {
      _panelDocId = newId;
      _descExpanded = false;
      _resolvedMp4 = CourseModuleMediaPanel.mp4From(widget.data);
      _loadMp4();
    }
  }

  Future<void> _loadMp4() async {
    final direct = CourseModuleMediaPanel.mp4From(widget.data);
    if (direct != null) {
      if (_resolvedMp4 != direct) {
        setState(() => _resolvedMp4 = direct);
      }
      return;
    }
    if (CourseMediaUrlResolver.collectVideoEntries(widget.data).isEmpty) return;
    if (!_mp4Loading) setState(() => _mp4Loading = true);
    try {
      final entries = await CourseMediaUrlResolver.resolveVideoEntries(widget.data);
      if (!mounted) return;
      setState(() {
        _resolvedMp4 = entries.isNotEmpty ? entries.first.url : null;
        _mp4Loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _mp4Loading = false);
    }
  }

  String get _title => (widget.data['title'] ?? 'Conteúdo').toString();

  String get _description {
    final body = (widget.data['bodyText'] ?? '').toString().trim();
    if (body.isNotEmpty) return body;
    return (widget.data['description'] ?? '').toString().trim();
  }

  String? get _youtubeId => CourseModuleMediaPanel.youtubeIdFrom(widget.data);

  bool get _isDica => (widget.data['type'] ?? 'curso').toString().trim().toLowerCase() == 'dica';

  bool get _showVideo =>
      CourseModuleMediaPanel.hasInlineVideo(widget.data) &&
      (_youtubeId != null || _resolvedMp4 != null || _mp4Loading);

  bool get _showGallery =>
      CourseMediaUrlResolver.hasResolvableImage(widget.data);

  void _openFullscreen() {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: CourseVideoPlayerShell(
                  embedKey: ValueKey('fs-${_youtubeId ?? ''}|${_resolvedMp4 ?? ''}'),
                  posterData: widget.data,
                  youtubeVideoId: _youtubeId,
                  mp4Url: _resolvedMp4,
                  autoplay: true,
                  accent: widget.accent,
                  accent2: widget.accent2,
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(ctx).top + 8,
              right: 12,
              child: IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: Colors.white24),
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final screenW = MediaQuery.sizeOf(context).width;
    final maxW = screenW > 960 ? 720.0 : screenW;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [
                widget.accent.withValues(alpha: 0.08),
                widget.accent2.withValues(alpha: 0.04),
                Colors.white,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: widget.accent.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: widget.accent.withValues(alpha: 0.14),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ModernHeader(
                  title: _title,
                  badge: widget.badge,
                  accent: widget.accent,
                  accent2: widget.accent2,
                  isDica: _isDica,
                ),
                if (_showVideo) ...[
                  Stack(
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: ColoredBox(
                          color: const Color(0xFF0F0F0F),
                          child: _mp4Loading
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white54,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : RepaintBoundary(
                                  child: CourseVideoPlayerShell(
                                    embedKey: ValueKey(
                                      'mod-${widget.data['id']}|${_youtubeId ?? ''}|${_resolvedMp4 ?? ''}',
                                    ),
                                    posterData: widget.data,
                                    youtubeVideoId: _youtubeId,
                                    mp4Url: _resolvedMp4,
                                    autoplay: false,
                                    accent: widget.accent,
                                    accent2: widget.accent2,
                                  ),
                                ),
                        ),
                      ),
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Material(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(999),
                          child: InkWell(
                            onTap: _openFullscreen,
                            borderRadius: BorderRadius.circular(999),
                            child: const Padding(
                              padding: EdgeInsets.all(9),
                              child: Icon(
                                Icons.open_in_full_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else if (_showGallery) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: CoursePhotoGallery(
                        data: widget.data,
                        height: 260,
                        fit: BoxFit.contain,
                        title: _title,
                        accent: widget.accent,
                      ),
                    ),
                  ),
                ],
                if (_description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    child: _DescriptionCard(
                      text: _description,
                      expanded: _descExpanded,
                      accent: widget.accent,
                      onToggle: () => setState(() => _descExpanded = !_descExpanded),
                    ),
                  ),
                if (_showVideo)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: Row(
                      children: [
                        Icon(Icons.play_circle_outline_rounded,
                            size: 18, color: widget.accent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _youtubeId != null
                                ? 'Toque ▶ no player · qualidade até 4K'
                                : 'Toque ▶ no player para assistir',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _openFullscreen,
                          icon: Icon(Icons.fullscreen_rounded,
                              size: 18, color: widget.accent),
                          label: Text(
                            'Ampliar',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: widget.accent,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (widget.related.isNotEmpty && widget.onSelectRelated != null)
                  _RelatedStrip(
                    related: widget.related,
                    currentId: widget.data['id']?.toString(),
                    accent: widget.accent,
                    onSelect: widget.onSelectRelated!,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModernHeader extends StatelessWidget {
  const _ModernHeader({
    required this.title,
    required this.badge,
    required this.accent,
    required this.accent2,
    required this.isDica,
  });

  final String title;
  final String badge;
  final Color accent;
  final Color accent2;
  final bool isDica;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent, accent2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white38),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const Spacer(),
              Icon(
                isDica ? Icons.lightbulb_rounded : Icons.school_rounded,
                color: Colors.amber.shade200,
                size: 22,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
              height: 1.22,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _DescriptionCard extends StatelessWidget {
  const _DescriptionCard({
    required this.text,
    required this.expanded,
    required this.accent,
    required this.onToggle,
  });

  final String text;
  final bool expanded;
  final Color accent;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, size: 16, color: accent),
                const SizedBox(width: 6),
                Text(
                  'Sobre este conteúdo',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              text,
              maxLines: expanded ? null : 4,
              overflow: expanded ? null : TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              expanded ? 'Ver menos' : 'Ver mais',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RelatedStrip extends StatelessWidget {
  const _RelatedStrip({
    required this.related,
    required this.currentId,
    required this.accent,
    required this.onSelect,
  });

  final List<Map<String, dynamic>> related;
  final String? currentId;
  final Color accent;
  final void Function(Map<String, dynamic> item) onSelect;

  @override
  Widget build(BuildContext context) {
    final items = related
        .where((r) => r['id']?.toString() != currentId)
        .take(8)
        .toList();
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mais conteúdos',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
              color: accent,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final item = items[i];
                final title = (item['title'] ?? 'Vídeo').toString();
                return Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onSelect(item),
                    child: SizedBox(
                      width: 140,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 56,
                            height: 56,
                            child: CourseMediaThumbnail.fromData(
                              item,
                              fit: BoxFit.cover,
                              showPlayButton: CourseThumbResolver.isVideoContent(item),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Text(
                                title,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Painel inline para curso (vídeo) ou dica (fotos/texto).
bool courseShowModulePanel(Map<String, dynamic> data) =>
    CourseModuleMediaPanel.hasInlineVideo(data) ||
    CourseModuleMediaPanel.hasInlineDicaContent(data);
