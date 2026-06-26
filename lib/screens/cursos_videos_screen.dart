import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/wisdom_courses_module_config.dart';
import '../theme/app_colors.dart';
import '../utils/course_content_link_helper.dart';
import '../utils/youtube_url_helper.dart';
import '../widgets/course_media_preview.dart';
import '../widgets/course_mp4_player_dialog.dart';
import '../widgets/youtube_video_player_dialog.dart';

BoxFit _courseThumbFit(Map<String, dynamic> data) {
  final type = (data['type'] ?? 'curso').toString();
  if (type == 'dica' && (data['imageUrl'] ?? '').toString().trim().isNotEmpty) {
    return BoxFit.contain;
  }
  return BoxFit.cover;
}

/// Módulo **Cursos** — vídeos YouTube publicados pelo admin (`course_videos`).
class CursosVideosScreen extends StatefulWidget {
  const CursosVideosScreen({
    super.key,
    required this.uid,
    this.shellScrollController,
  });

  final String uid;
  final ScrollController? shellScrollController;

  @override
  State<CursosVideosScreen> createState() => _CursosVideosScreenState();
}

class _CursosVideosScreenState extends State<CursosVideosScreen> {
  int _tabIndex = 0;
  int _retryGen = 0;

  bool _isPublished(Map<String, dynamic> data) {
    if (data['published'] == false) return false;
    final type = (data['type'] ?? 'curso').toString();
    if (type == 'curso') return _isPublishedCurso(data);
    return _isPublishedDica(data);
  }

  bool _isPublishedCurso(Map<String, dynamic> data) {
    if (_mp4Url(data) != null) return true;
    if (_videoId(data) != null) return true;
    final source = (data['source'] ?? '').toString().toLowerCase();
    if (source.isNotEmpty && source != 'youtube' && !source.contains('upload')) return false;
    return false;
  }

  String? _mp4Url(Map<String, dynamic> data) {
    final u = (data['mp4Url'] ?? '').toString().trim();
    return u.isEmpty ? null : u;
  }

  bool _isPublishedDica(Map<String, dynamic> data) {
    if (_videoId(data) != null) return true;
    final link = _externalLink(data);
    if (link != null && CourseContentLinkHelper.isValidHttpUrl(link)) return true;
    if ((data['bodyText'] ?? '').toString().trim().isNotEmpty) return true;
    if ((data['imageUrl'] ?? '').toString().trim().isNotEmpty) return true;
    return (data['description'] ?? '').toString().trim().isNotEmpty;
  }

  String? _videoId(Map<String, dynamic> data) {
    final stored = (data['youtubeVideoId'] ?? '').toString().trim();
    if (stored.isNotEmpty) return stored;
    final link = (data['linkUrl'] ?? data['externalUrl'] ?? data['youtubeUrl'] ?? data['videoUrl'] ?? '')
        .toString();
    return YoutubeUrlHelper.extractVideoId(link);
  }

  String? _externalLink(Map<String, dynamic> data) {
    final link = (data['linkUrl'] ?? data['externalUrl'] ?? '').toString().trim();
    return link.isEmpty ? null : link;
  }

  String? _thumbUrl(Map<String, dynamic> data) {
    final img = (data['imageUrl'] ?? '').toString().trim();
    if (img.isNotEmpty) return img;
    final thumb = (data['thumbnailUrl'] ?? '').toString().trim();
    if (thumb.isNotEmpty) return thumb;
    final id = _videoId(data);
    if (id != null) return YoutubeUrlHelper.thumbnailUrl(id);
    return null;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterAndSort(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String type,
  ) {
    final out = docs.where((d) {
      final data = d.data();
      if (!_isPublished(data)) return false;
      return (data['type'] ?? 'curso').toString() == type;
    }).toList();

    out.sort((a, b) {
      final ta = a.data()['createdAt'];
      final tb = b.data()['createdAt'];
      if (ta is Timestamp && tb is Timestamp) {
        return tb.compareTo(ta);
      }
      return 0;
    });
    return out;
  }

  void _retryLoad() => setState(() => _retryGen++);

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _ = _retryGen;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('app_config')
          .doc('wisdom_courses_module')
          .snapshots(),
      builder: (context, cfgSnap) {
        final cfg = cfgSnap.hasData
            ? WisdomCoursesModuleConfig.fromMap(cfgSnap.data?.data())
            : WisdomCoursesModuleConfig.defaults;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('course_videos').snapshots(),
          builder: (context, videosSnap) {
            if (videosSnap.hasError) {
              return _errorView(cfg, videosSnap.error);
            }

            final allDocs = videosSnap.data?.docs ?? const [];
            final published = allDocs.where((d) => _isPublished(d.data())).toList();
            final cursos = _filterAndSort(published, 'curso');
            final dicas = _filterAndSort(published, 'dica');
            final syncing = videosSnap.connectionState == ConnectionState.waiting &&
                !videosSnap.hasData;

            return Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFF0F4FF), Color(0xFFF8FAFC), Color(0xFFEFFDF9)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: ListView(
                controller: widget.shellScrollController,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                children: [
                  _buildHero(cfg, syncing),
                  if (cfg.showTipsSection) ...[
                    const SizedBox(height: 16),
                    _ModernTabSelector(
                      index: _tabIndex,
                      cursosCount: cursos.length,
                      dicasCount: dicas.length,
                      onChanged: (i) => setState(() => _tabIndex = i),
                    ),
                    const SizedBox(height: 14),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      child: _tabIndex == 0
                          ? _buildSection(
                              key: const ValueKey('cursos'),
                              cfg: cfg,
                              docs: cursos,
                              syncing: syncing,
                              accent: const Color(0xFF2563EB),
                              accent2: const Color(0xFF1D4ED8),
                              icon: Icons.school_rounded,
                              label: 'Cursos',
                            )
                          : _buildSection(
                              key: const ValueKey('dicas'),
                              cfg: cfg,
                              docs: dicas,
                              syncing: syncing,
                              accent: const Color(0xFFF59E0B),
                              accent2: const Color(0xFFD97706),
                              icon: Icons.lightbulb_rounded,
                              label: 'Dicas',
                            ),
                    ),
                  ] else ...[
                    const SizedBox(height: 16),
                    _sectionTitle(cfg.sectionTitle, AppColors.primary),
                    const SizedBox(height: 10),
                    _buildListBody(
                      cfg: cfg,
                      docs: cursos,
                      syncing: syncing,
                      accent: AppColors.primary,
                      accent2: AppColors.deepBlue,
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _errorView(WisdomCoursesModuleConfig cfg, Object? error) {
    return ListView(
      controller: widget.shellScrollController,
      padding: const EdgeInsets.all(20),
      children: [
        _buildHero(cfg, false),
        const SizedBox(height: 24),
        Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey.shade500),
        const SizedBox(height: 12),
        const Text(
          'Não foi possível carregar os vídeos.',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _retryLoad,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tentar novamente'),
        ),
      ],
    );
  }

  Widget _buildHero(WisdomCoursesModuleConfig cfg, bool syncing) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF0B1B4B), Color(0xFF134074), Color(0xFF0D9488)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B1B4B).withValues(alpha: 0.32),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.play_circle_fill_rounded,
                    color: Colors.amber.shade200, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  cfg.heroTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                    height: 1.25,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            cfg.heroMessage,
            style: TextStyle(
              color: Colors.amber.shade100,
              height: 1.35,
              fontWeight: FontWeight.w800,
              fontSize: 14,
              letterSpacing: 0.6,
            ),
          ),
          if (syncing) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              minHeight: 2,
              color: Colors.amber.shade200,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, Color color) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: color.withValues(alpha: 0.95),
          ),
        ),
      ],
    );
  }

  Widget _buildSection({
    required Key key,
    required WisdomCoursesModuleConfig cfg,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required bool syncing,
    required Color accent,
    required Color accent2,
    required IconData icon,
    required String label,
  }) {
    final isDicas = label == 'Dicas';
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (docs.isNotEmpty) ...[
          _FeaturedVideoHighlight(
            data: docs.first.data(),
            videoId: _videoId(docs.first.data()),
            thumbUrl: _thumbUrl(docs.first.data()),
            accent: accent,
            accent2: accent2,
            badge: 'DESTAQUE · $label',
            onTap: () => _openContent(context, docs.first.data()),
          ),
          if (docs.length > 1) ...[
            const SizedBox(height: 14),
            _sectionTitle('Mais $label', accent),
            const SizedBox(height: 10),
          ],
        ],
        if (isDicas)
          _buildDicasGrid(
            cfg: cfg,
            docs: docs.length > 1 ? docs.sublist(1) : (docs.isEmpty ? docs : []),
            syncing: syncing,
            accent: accent,
            accent2: accent2,
            showEmptyWhenNoFeatured: docs.isEmpty,
          )
        else
          _buildListBody(
            cfg: cfg,
            docs: docs.length > 1 ? docs.sublist(1) : (docs.isEmpty ? docs : []),
            syncing: syncing,
            accent: accent,
            accent2: accent2,
            showEmptyWhenNoFeatured: docs.isEmpty,
          ),
      ],
    );
  }

  Future<void> _openContent(BuildContext context, Map<String, dynamic> data) async {
    final type = (data['type'] ?? 'curso').toString();
    final mp4 = _mp4Url(data);
    if (mp4 != null) {
      showCourseMp4PlayerDialog(
        context,
        videoUrl: mp4,
        title: (data['title'] ?? 'Vídeo').toString(),
      );
      return;
    }
    final videoId = _videoId(data);
    if (videoId != null) {
      showYoutubeVideoPlayerDialog(
        context,
        videoId: videoId,
        title: (data['title'] ?? 'Vídeo').toString(),
      );
      return;
    }
    final link = _externalLink(data);
    if (link != null && CourseContentLinkHelper.isValidHttpUrl(link)) {
      final uri = Uri.parse(link.startsWith('http') ? link : 'https://$link');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }
    if (type == 'dica') {
      await _showDicaDetail(context, data);
    }
  }

  Future<void> _showDicaDetail(BuildContext context, Map<String, dynamic> data) async {
    final body = (data['bodyText'] ?? data['description'] ?? '').toString();
    final img = (data['imageUrl'] ?? '').toString().trim();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (_, scroll) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                (data['title'] ?? 'Dica').toString(),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, height: 1.25),
              ),
              if (img.isNotEmpty) ...[
                const SizedBox(height: 14),
                CourseImagePreview(networkUrl: img, maxHeight: 240),
              ],
              if (body.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  body,
                  style: TextStyle(fontSize: 15, height: 1.55, color: Colors.grey.shade800),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDicasGrid({
    required WisdomCoursesModuleConfig cfg,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required bool syncing,
    required Color accent,
    required Color accent2,
    bool showEmptyWhenNoFeatured = true,
  }) {
    if (docs.isEmpty && showEmptyWhenNoFeatured) {
      return _emptyState(cfg, syncing, accent);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 720 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.72,
          ),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data();
            return _DicaGridCard(
              data: data,
              videoId: _videoId(data),
              thumbUrl: _thumbUrl(data),
              accent: accent,
              accent2: accent2,
              onTap: () => _openContent(context, data),
            );
          },
        );
      },
    );
  }

  Widget _buildListBody({
    required WisdomCoursesModuleConfig cfg,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required bool syncing,
    required Color accent,
    required Color accent2,
    bool showEmptyWhenNoFeatured = true,
  }) {
    if (docs.isEmpty && showEmptyWhenNoFeatured) {
      return _emptyState(cfg, syncing, accent);
    }
    return Column(
      children: [
        for (final doc in docs)
          _ModernVideoCard(
            data: doc.data(),
            videoId: _videoId(doc.data()),
            thumbUrl: _thumbUrl(doc.data()),
            accent: accent,
            accent2: accent2,
            onTap: () => _openContent(context, doc.data()),
          ),
      ],
    );
  }

  Widget _emptyState(WisdomCoursesModuleConfig cfg, bool syncing, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.ondemand_video_rounded, size: 40, color: accent),
          ),
          const SizedBox(height: 16),
          Text(
            syncing ? 'A carregar conteúdo…' : cfg.emptyMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade800,
              height: 1.45,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModernTabSelector extends StatelessWidget {
  const _ModernTabSelector({
    required this.index,
    required this.cursosCount,
    required this.dicasCount,
    required this.onChanged,
  });

  final int index;
  final int cursosCount;
  final int dicasCount;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabPill(
              label: 'Cursos',
              icon: Icons.school_rounded,
              count: cursosCount,
              selected: index == 0,
              gradient: const [Color(0xFF2563EB), Color(0xFF1D4ED8)],
              onTap: () => onChanged(0),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _TabPill(
              label: 'Dicas',
              icon: Icons.lightbulb_rounded,
              count: dicasCount,
              selected: index == 1,
              gradient: const [Color(0xFFF59E0B), Color(0xFFD97706)],
              onTap: () => onChanged(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.gradient,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final int count;
  final bool selected;
  final List<Color> gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: selected
                ? LinearGradient(colors: gradient)
                : null,
            color: selected ? null : Colors.grey.shade50,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: gradient.first.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? Colors.white : gradient.first,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: selected ? Colors.white : const Color(0xFF334155),
                  ),
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.25)
                        : gradient.first.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: selected ? Colors.white : gradient.first,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturedVideoHighlight extends StatelessWidget {
  const _FeaturedVideoHighlight({
    required this.data,
    required this.videoId,
    required this.thumbUrl,
    required this.accent,
    required this.accent2,
    required this.badge,
    required this.onTap,
  });

  final Map<String, dynamic> data;
  final String? videoId;
  final String? thumbUrl;
  final Color accent;
  final Color accent2;
  final String badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? 'Vídeo').toString();
    final description = (data['description'] ?? '').toString();
    final body = (data['bodyText'] ?? '').toString();
    final preview = body.isNotEmpty ? body : description;
    final thumb = thumbUrl ?? '';
    final thumbFit = _courseThumbFit(data);
    final overlayIcon = videoId != null
        ? Icons.play_circle_fill_rounded
        : Icons.article_rounded;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              colors: [accent, accent2],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (thumb.isNotEmpty)
                        CourseCoverImage(
                          url: thumb,
                          fit: thumbFit,
                          fallback: _coverPlaceholder(accent),
                        )
                      else
                        _coverPlaceholder(accent),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.55),
                            ],
                          ),
                        ),
                      ),
                      Center(
                        child: Icon(
                          overlayIcon,
                          color: Colors.white.withValues(alpha: 0.95),
                          size: 64,
                        ),
                      ),
                      Positioned(
                        left: 12,
                        top: 12,
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.white30),
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
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        height: 1.25,
                      ),
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
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

  Widget _coverPlaceholder(Color c) {
    return Container(
      color: c.withValues(alpha: 0.5),
      child: const Center(
        child: Icon(Icons.ondemand_video_rounded, color: Colors.white70, size: 48),
      ),
    );
  }
}

class _ModernVideoCard extends StatelessWidget {
  const _ModernVideoCard({
    required this.data,
    required this.videoId,
    required this.thumbUrl,
    required this.accent,
    required this.accent2,
    required this.onTap,
  });

  final Map<String, dynamic> data;
  final String? videoId;
  final String? thumbUrl;
  final Color accent;
  final Color accent2;
  final VoidCallback onTap;

  String? _localMp4() {
    final u = (data['mp4Url'] ?? '').toString().trim();
    return u.isEmpty ? null : u;
  }

  String _sourceLabel() {
    if (_localMp4() != null) return 'MP4';
    if (videoId != null) return 'YOUTUBE';
    final link = (data['linkUrl'] ?? data['externalUrl'] ?? '').toString();
    if (link.isNotEmpty) return CourseContentLinkHelper.linkLabel(link).toUpperCase();
    return 'CONTEÚDO';
  }

  IconData _overlayIcon() {
    if (_localMp4() != null || videoId != null) {
      return Icons.play_circle_fill_rounded;
    }
    final link = (data['linkUrl'] ?? data['externalUrl'] ?? '').toString();
    if (link.isNotEmpty) return Icons.open_in_new_rounded;
    return Icons.article_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? 'Vídeo').toString();
    final description = (data['description'] ?? '').toString();
    final body = (data['bodyText'] ?? '').toString();
    final preview = body.isNotEmpty ? body : description;
    final type = (data['type'] ?? 'curso').toString();
    final thumb = thumbUrl ?? '';
    final thumbFit = _courseThumbFit(data);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.1),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(18)),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (thumb.isNotEmpty)
                        CourseCoverImage(
                          url: thumb,
                          fit: thumbFit,
                          fallback: _coverFallback(type, accent, accent2),
                        )
                      else
                        _coverFallback(type, accent, accent2),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.25),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _overlayIcon(),
                            color: Colors.white.withValues(alpha: 0.95),
                            size: 52,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        height: 1.25,
                      ),
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _chip(_sourceLabel(), accent),
                        _chip(type.toUpperCase(), accent2),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coverFallback(String type, Color a, Color b) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: type == 'dica' ? [a, b] : [a, b],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.ondemand_video_rounded, color: Colors.white, size: 44),
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _DicaGridCard extends StatelessWidget {
  const _DicaGridCard({
    required this.data,
    required this.videoId,
    required this.thumbUrl,
    required this.accent,
    required this.accent2,
    required this.onTap,
  });

  final Map<String, dynamic> data;
  final String? videoId;
  final String? thumbUrl;
  final Color accent;
  final Color accent2;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? 'Dica').toString();
    final body = (data['bodyText'] ?? data['description'] ?? '').toString();
    final thumb = thumbUrl ?? '';
    final thumbFit = _courseThumbFit(data);
    final overlayIcon = videoId != null
        ? Icons.play_circle_fill_rounded
        : ((data['linkUrl'] ?? data['externalUrl'] ?? '').toString().isNotEmpty
            ? Icons.open_in_new_rounded
            : Icons.article_rounded);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.15)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.1),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (thumb.isNotEmpty)
                      CourseCoverImage(
                        url: thumb,
                        fit: thumbFit,
                        fallback: _fallback(accent, accent2),
                      )
                    else
                      _fallback(accent, accent2),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.45),
                          ],
                        ),
                      ),
                    ),
                    Center(
                      child: Icon(
                        overlayIcon,
                        color: Colors.white.withValues(alpha: 0.92),
                        size: 44,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          height: 1.2,
                          color: accent.withValues(alpha: 0.95),
                        ),
                      ),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Expanded(
                          child: Text(
                            body,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.35,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ] else
                        const Spacer(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallback(Color a, Color b) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [a, b]),
      ),
      child: const Center(
        child: Icon(Icons.lightbulb_rounded, color: Colors.white70, size: 36),
      ),
    );
  }
}
