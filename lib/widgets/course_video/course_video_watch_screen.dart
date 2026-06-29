import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../utils/course_media_url_resolver.dart';
import '../../utils/youtube_url_helper.dart';
import '../course_media_preview.dart';
import 'course_video_player_shell.dart';

/// Abre vídeo de curso com UI estilo YouTube (player + lista relacionada).
Future<void> openCourseVideoFromData(
  BuildContext context, {
  required Map<String, dynamic> data,
  List<Map<String, dynamic>> related = const [],
}) async {
  final videos = await CourseMediaUrlResolver.resolveVideoEntries(data);
  if (videos.length > 1) {
    if (!context.mounted) return;
    final title = (data['title'] ?? 'Vídeo').toString();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _VideoPickerSheet(
        title: title,
        videos: videos,
        onPick: (url, label) {
          Navigator.pop(ctx);
          if (!context.mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CourseVideoWatchScreen(
                data: data,
                mp4Url: url,
                mp4Label: label,
                related: related,
              ),
            ),
          );
        },
      ),
    );
    return;
  }

  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CourseVideoWatchScreen(
        data: data,
        mp4Url: videos.isNotEmpty ? videos.first.url : _mp4FromData(data),
        related: related,
      ),
    ),
  );
}

String? _mp4FromData(Map<String, dynamic> data) {
  final u = (data['mp4Url'] ?? '').toString().trim();
  return u.isEmpty ? null : u;
}

String? _youtubeIdFromData(Map<String, dynamic> data) {
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

/// Tela de reprodução estilo YouTube — player 16:9, metadados e vídeos relacionados.
class CourseVideoWatchScreen extends StatefulWidget {
  const CourseVideoWatchScreen({
    super.key,
    required this.data,
    this.mp4Url,
    this.mp4Label,
    this.related = const [],
  });

  final Map<String, dynamic> data;
  final String? mp4Url;
  final String? mp4Label;
  final List<Map<String, dynamic>> related;

  @override
  State<CourseVideoWatchScreen> createState() => _CourseVideoWatchScreenState();
}

class _CourseVideoWatchScreenState extends State<CourseVideoWatchScreen> {
  var _descExpanded = false;

  String get _title => (widget.data['title'] ?? 'Vídeo').toString();

  String get _description {
    final body = (widget.data['bodyText'] ?? '').toString().trim();
    if (body.isNotEmpty) return body;
    return (widget.data['description'] ?? '').toString().trim();
  }

  String? get _youtubeId => _youtubeIdFromData(widget.data);

  String? get _mp4Url {
    final direct = widget.mp4Url?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    return _mp4FromData(widget.data);
  }

  String get _typeLabel {
    final t = (widget.data['type'] ?? 'curso').toString();
    return t == 'dica' ? 'Dica Wisdom' : 'Wisdom Cursos';
  }

  Color get _accent {
    final t = (widget.data['type'] ?? 'curso').toString();
    return t == 'dica' ? const Color(0xFFF59E0B) : const Color(0xFF2563EB);
  }

  void _openRelated(Map<String, dynamic> item) {
    final filtered = widget.related
        .where((r) => r['id']?.toString() != item['id']?.toString())
        .toList();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => CourseVideoWatchScreen(
          data: item,
          related: [widget.data, ...filtered],
        ),
      ),
    );
  }

  Future<void> _openFullscreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _CourseVideoFullscreenPage(
          youtubeVideoId: _youtubeId,
          mp4Url: _mp4Url,
          title: _title,
          posterData: widget.data,
          accent: _accent,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final related = widget.related
        .where((r) => r['id']?.toString() != widget.data['id']?.toString())
        .take(12)
        .toList();

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            elevation: 0,
            backgroundColor: const Color(0xFF0F0F0F),
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              _title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            actions: [
              IconButton(
                tooltip: 'Tela cheia',
                icon: const Icon(Icons.fullscreen_rounded),
                onPressed: _openFullscreen,
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = MediaQuery.sizeOf(context).width;
                final maxW = kIsWeb ? (w > 960 ? 720.0 : w) : w;
                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxW),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CourseVideoPlayerShell(
                            embedKey: ValueKey('${_youtubeId ?? ''}|${_mp4Url ?? ''}'),
                            posterData: widget.data,
                            youtubeVideoId: _youtubeId,
                            mp4Url: _mp4Url,
                            autoplay: true,
                            accent: _accent,
                            accent2: _accent.withValues(alpha: 0.72),
                          ),
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: Material(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(999),
                              child: InkWell(
                                onTap: _openFullscreen,
                                borderRadius: BorderRadius.circular(999),
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.fullscreen_rounded, color: Colors.white, size: 22),
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
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      height: 1.25,
                      color: Color(0xFF0F0F0F),
                    ),
                  ),
                  if (widget.mp4Label != null && widget.mp4Label!.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.mp4Label!,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_accent, _accent.withValues(alpha: 0.75)],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.school_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _typeLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              _youtubeId != null ? 'YouTube · até 4K' : 'HD · MP4',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F0F0F),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Wisdom',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_youtubeId != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(Icons.hd_rounded, size: 18, color: _accent),
                          const SizedBox(width: 6),
                          Text(
                            'Qualidade até 4K no player',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_description.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: () => setState(() => _descExpanded = !_descExpanded),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F2F2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _description,
                              maxLines: _descExpanded ? null : 3,
                              overflow: _descExpanded ? null : TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey.shade800,
                                height: 1.45,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _descExpanded ? 'Mostrar menos' : 'Mostrar mais',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (related.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Text(
                  'Próximos vídeos',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: Colors.grey.shade900,
                  ),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final item = related[i];
                  return _RelatedVideoTile(
                    data: item,
                    onTap: () => _openRelated(item),
                  );
                },
                childCount: related.length,
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _CourseVideoFullscreenPage extends StatelessWidget {
  const _CourseVideoFullscreenPage({
    this.youtubeVideoId,
    this.mp4Url,
    required this.title,
    this.posterData,
    this.accent = const Color(0xFF2563EB),
  });

  final String? youtubeVideoId;
  final String? mp4Url;
  final String title;
  final Map<String, dynamic>? posterData;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: CourseVideoPlayerShell(
              embedKey: ValueKey('fs-${youtubeVideoId ?? ''}|${mp4Url ?? ''}'),
              posterData: posterData,
              youtubeVideoId: youtubeVideoId,
              mp4Url: mp4Url,
              autoplay: true,
              accent: accent,
              accent2: accent.withValues(alpha: 0.72),
            ),
          ),
        ),
      ),
    );
  }
}

class _RelatedVideoTile extends StatelessWidget {
  const _RelatedVideoTile({
    required this.data,
    required this.onTap,
  });

  final Map<String, dynamic> data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? 'Vídeo').toString();
    final type = (data['type'] ?? 'curso').toString();
    final accent = type == 'dica' ? const Color(0xFFF59E0B) : const Color(0xFF2563EB);

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 168,
                  height: 94,
                  child: CourseMediaThumbnail.fromData(
                    data,
                    fit: BoxFit.cover,
                    fallback: Container(
                      color: accent.withValues(alpha: 0.2),
                      child: Icon(Icons.play_circle_fill_rounded, color: accent, size: 40),
                    ),
                    showPlayButton: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      type == 'dica' ? 'Dica Wisdom' : 'Wisdom Cursos',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.more_vert_rounded, color: Colors.grey.shade500, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoPickerSheet extends StatelessWidget {
  const _VideoPickerSheet({
    required this.title,
    required this.videos,
    required this.onPick,
  });

  final String title;
  final List<CourseVideoEntry> videos;
  final void Function(String url, String label) onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Escolha o vídeo · $title',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < videos.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF2563EB).withValues(alpha: 0.12),
                  child: Icon(Icons.play_arrow_rounded, color: Colors.blue.shade700),
                ),
                title: Text(
                  videos[i].label ?? 'Vídeo ${i + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                onTap: () => onPick(
                  videos[i].url,
                  videos[i].label ?? 'Vídeo ${i + 1}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Atalho para YouTube por ID (admin / preview).
Future<void> openYoutubeWatchScreen(
  BuildContext context, {
  required String videoId,
  required String title,
  Map<String, dynamic>? extraData,
}) {
  final data = {
    'title': title,
    'youtubeVideoId': videoId,
    'type': 'curso',
    if (extraData != null) ...extraData,
  };
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CourseVideoWatchScreen(data: data),
    ),
  );
}

/// Atalho MP4 (admin / preview).
Future<void> openMp4WatchScreen(
  BuildContext context, {
  required String videoUrl,
  required String title,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CourseVideoWatchScreen(
        data: {'title': title, 'type': 'curso'},
        mp4Url: videoUrl,
      ),
    ),
  );
}
