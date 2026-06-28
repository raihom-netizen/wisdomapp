import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/wisdom_courses_module_config.dart';
import '../theme/app_colors.dart';
import '../services/course_videos_cache_service.dart';
import '../utils/course_video_validity.dart';
import '../utils/course_content_link_helper.dart';
import '../utils/course_thumb_resolver.dart';
import '../utils/youtube_url_helper.dart';
import '../utils/course_media_url_resolver.dart';
import '../widgets/course_media_preview.dart';
import '../widgets/course_video/course_module_media_panel.dart';

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

class _CursosVideosScreenState extends State<CursosVideosScreen>
    with AutomaticKeepAliveClientMixin {
  int _tabIndex = 0;
  int _retryGen = 0;
  Map<String, dynamic>? _activeCurso;
  Map<String, dynamic>? _activeDica;
  final _cache = CourseVideosCacheService.instance;
  String _cacheFingerprint = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cache.addListener(_onCacheUpdate);
    unawaited(_cache.ensureLoaded());
  }

  @override
  void dispose() {
    _cache.removeListener(_onCacheUpdate);
    super.dispose();
  }

  String _fingerprint() {
    final ids = _cache.docs.map((d) => d.id).join(',');
    return '$ids|${_cache.config.showTipsSection}|${_cache.refreshing}|${_cache.hasServerSync}';
  }

  void _onCacheUpdate() {
    if (!mounted) return;
    final fp = _fingerprint();

    final published = _cache.docs.where((d) => _isPublished(d.data)).toList();
    final cursos = _filterAndSort(published, 'curso');
    final dicas = _filterAndSort(published, 'dica');
    var changed = false;
    if (_activeCurso == null && cursos.isNotEmpty) {
      final d = cursos.first;
      _activeCurso = {...d.data, 'id': d.id};
      changed = true;
    }
    if (_activeDica == null && dicas.isNotEmpty) {
      final d = dicas.first;
      _activeDica = {...d.data, 'id': d.id};
      changed = true;
    }
    if (!changed && fp == _cacheFingerprint) return;
    _cacheFingerprint = fp;
    setState(() {});
  }

  String _contentType(Map<String, dynamic> data) =>
      (data['type'] ?? 'curso').toString().trim().toLowerCase();

  bool _isPublished(Map<String, dynamic> data) {
    if (!CourseVideoValidity.isStillValid(data)) return false;
    if (data['published'] == false) return false;
    if (_contentType(data) == 'curso') return _isPublishedCurso(data);
    return _isPublishedDica(data);
  }

  bool _isPublishedCurso(Map<String, dynamic> data) {
    if (CourseMediaUrlResolver.collectVideoEntries(data).isNotEmpty) return true;
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
    if (CourseMediaUrlResolver.hasResolvableImage(data)) return true;
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

  String? _thumbUrl(Map<String, dynamic> data) => CourseThumbResolver.resolveBest(data);

  List<CourseVideoDoc> _filterAndSort(
    List<CourseVideoDoc> docs,
    String type,
  ) {
    final out = docs.where((d) {
      final data = d.data;
      if (!_isPublished(data)) return false;
      return _contentType(data) == type;
    }).toList();

    out.sort((a, b) {
      final ta = a.data['createdAt'];
      final tb = b.data['createdAt'];
      if (ta is Timestamp && tb is Timestamp) {
        return tb.compareTo(ta);
      }
      return 0;
    });
    return out;
  }

  void _retryLoad() {
    setState(() => _retryGen++);
    unawaited(_cache.ensureLoaded(forceServer: true));
  }

  void _selectModuleContent(Map<String, dynamic> data, {required bool isDica}) {
    setState(() {
      if (isDica) {
        _activeDica = data;
      } else {
        _activeCurso = data;
      }
    });
    final sc = widget.shellScrollController;
    if (sc != null && sc.hasClients) {
      sc.animateTo(
        0,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Map<String, dynamic>? _panelData(
    List<CourseVideoDoc> docs,
    Map<String, dynamic>? active,
  ) {
    if (docs.isEmpty) return null;
    if (active != null) {
      final activeId = active['id']?.toString();
      if (activeId != null && activeId.isNotEmpty) {
        for (final d in docs) {
          if (d.id == activeId) return active;
        }
      } else {
        return active;
      }
    }
    final first = docs.first;
    return {...first.data, 'id': first.id};
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // ignore: unused_local_variable
    final _ = _retryGen;

    final cfg = _cache.config;
    final allDocs = _cache.docs;
    final published = allDocs.where((d) => _isPublished(d.data)).toList();
    final cursos = _filterAndSort(published, 'curso');
    final dicas = _filterAndSort(published, 'dica');
    final syncing = _cache.showInitialLoading;

    return RefreshIndicator(
      onRefresh: () => _cache.ensureLoaded(forceServer: true),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF0F4FF), Color(0xFFF8FAFC), Color(0xFFEFFDF9)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: ListView(
          controller: widget.shellScrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            _buildHero(cfg, syncing && !_cache.hasCachedData),
            if (cfg.showTipsSection) ...[
              const SizedBox(height: 16),
              _ModernTabSelector(
                index: _tabIndex,
                cursosCount: cursos.length,
                dicasCount: dicas.length,
                onChanged: (i) => setState(() {
                  _tabIndex = i;
                  if (i == 1 && _activeDica == null && dicas.isNotEmpty) {
                    final d = dicas.first;
                    _activeDica = {...d.data, 'id': d.id};
                  }
                  if (i == 0 && _activeCurso == null && cursos.isNotEmpty) {
                    final d = cursos.first;
                    _activeCurso = {...d.data, 'id': d.id};
                  }
                }),
              ),
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                layoutBuilder: (current, previous) => current ?? const SizedBox.shrink(),
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
                allDocs: cursos,
                syncing: syncing,
                accent: AppColors.primary,
                accent2: AppColors.deepBlue,
              ),
            ],
          ],
        ),
      ),
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
    required List<CourseVideoDoc> docs,
    required bool syncing,
    required Color accent,
    required Color accent2,
    required IconData icon,
    required String label,
  }) {
    final isDicas = label == 'Dicas';
    if (docs.isEmpty) {
      return Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _emptyState(
            cfg,
            syncing,
            accent,
            emptyHint: isDicas
                ? 'Nenhuma dica publicada no momento. Volte em breve!'
                : null,
          ),
        ],
      );
    }
    final related = docs.map((d) => {...d.data, 'id': d.id}).toList();
    final panelData = _panelData(docs, isDicas ? _activeDica : _activeCurso)!;
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (docs.isNotEmpty) ...[
          if (courseShowModulePanel(panelData))
            RepaintBoundary(
              child: CourseModuleMediaPanel(
                key: ValueKey('panel-${panelData['id']}'),
                data: panelData,
                accent: accent,
                accent2: accent2,
                badge: 'DESTAQUE · $label',
                related: related,
                onSelectRelated: (item) => _selectModuleContent(item, isDica: isDicas),
              ),
            )
          else
            _FeaturedVideoHighlight(
              data: panelData,
              videoId: _videoId(panelData),
              thumbUrl: _thumbUrl(panelData),
              accent: accent,
              accent2: accent2,
              badge: 'DESTAQUE · $label',
              onTap: () => _selectModuleContent(panelData, isDica: isDicas),
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
            allDocs: docs,
            syncing: syncing,
            accent: accent,
            accent2: accent2,
            showEmptyWhenNoFeatured: docs.isEmpty,
          )
        else
          _buildListBody(
            cfg: cfg,
            docs: docs.length > 1 ? docs.sublist(1) : (docs.isEmpty ? docs : []),
            allDocs: docs,
            syncing: syncing,
            accent: accent,
            accent2: accent2,
            showEmptyWhenNoFeatured: docs.isEmpty,
          ),
      ],
    );
  }

  Future<void> _openContent(
    BuildContext context,
    Map<String, dynamic> data, {
    List<Map<String, dynamic>> related = const [],
    required bool isDica,
  }) async {
    if (courseShowModulePanel(data)) {
      _selectModuleContent(data, isDica: isDica);
      return;
    }
    final type = (data['type'] ?? 'curso').toString();
    final link = _externalLink(data);
    if (link != null && CourseContentLinkHelper.isValidHttpUrl(link)) {
      final uri = Uri.parse(link.startsWith('http') ? link : 'https://$link');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }
    if (type == 'dica') {
      _selectModuleContent(data, isDica: true);
    }
  }

  Widget _buildDicasGrid({
    required WisdomCoursesModuleConfig cfg,
    required List<CourseVideoDoc> docs,
    required List<CourseVideoDoc> allDocs,
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
            final data = docs[i].data;
            final related = allDocs.map((d) => {...d.data, 'id': d.id}).toList();
            return _DicaGridCard(
              data: {...data, 'id': docs[i].id},
              videoId: _videoId(data),
              thumbUrl: _thumbUrl(data),
              accent: accent,
              accent2: accent2,
              selected: (_activeDica?['id'] ?? (allDocs.isNotEmpty ? allDocs.first.id : '')) ==
                  docs[i].id,
              onTap: () => _openContent(
                context,
                {...data, 'id': docs[i].id},
                related: related,
                isDica: true,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildListBody({
    required WisdomCoursesModuleConfig cfg,
    required List<CourseVideoDoc> docs,
    required List<CourseVideoDoc> allDocs,
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
            data: {...doc.data, 'id': doc.id},
            videoId: _videoId(doc.data),
            thumbUrl: _thumbUrl(doc.data),
            accent: accent,
            accent2: accent2,
            selected: (_activeCurso?['id'] ?? (allDocs.isNotEmpty ? allDocs.first.id : '')) == doc.id,
            onTap: () => _openContent(
              context,
              {...doc.data, 'id': doc.id},
              related: allDocs.map((d) => {...d.data, 'id': d.id}).toList(),
              isDica: false,
            ),
          ),
      ],
    );
  }

  Widget _emptyState(
    WisdomCoursesModuleConfig cfg,
    bool syncing,
    Color accent, {
    String? emptyHint,
  }) {
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
            syncing ? 'A carregar conteúdo…' : (emptyHint ?? cfg.emptyMessage),
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
    final thumbFit = _courseThumbFit(data);
    final isVideo = CourseThumbResolver.isVideoContent(data);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: Colors.white,
            border: Border.all(color: accent.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 6),
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
                      CourseMediaThumbnail.fromData(
                        data,
                        fit: thumbFit,
                        fallback: _coverPlaceholder(accent),
                        showPlayButton: isVideo,
                        playIconSize: kIsWeb ? 52 : 64,
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
                      style: TextStyle(
                        color: Colors.grey.shade900,
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
                          color: Colors.grey.shade700,
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
    this.selected = false,
  });

  final Map<String, dynamic> data;
  final String? videoId;
  final String? thumbUrl;
  final Color accent;
  final Color accent2;
  final VoidCallback onTap;
  final bool selected;

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
    final hasThumb = CourseThumbResolver.hasVisualThumb(data);
    final isVideo = CourseThumbResolver.isVideoContent(data);
    final thumbFit = _courseThumbFit(data);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? accent : accent.withValues(alpha: 0.12),
          width: selected ? 2.2 : 1,
        ),
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
                      if (hasThumb)
                        CourseMediaThumbnail.fromData(
                          data,
                          fit: thumbFit,
                          fallback: _coverFallback(type, accent, accent2),
                          showPlayButton: isVideo,
                        )
                      else if (isVideo)
                        CourseMediaThumbnail.fromData(
                          data,
                          fit: BoxFit.cover,
                          fallback: _coverFallback(type, accent, accent2),
                          showPlayButton: true,
                        )
                      else
                        _coverFallback(type, accent, accent2),
                      if (!hasThumb && !isVideo)
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
    this.selected = false,
  });

  final Map<String, dynamic> data;
  final String? videoId;
  final String? thumbUrl;
  final Color accent;
  final Color accent2;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? 'Dica').toString();
    final body = (data['bodyText'] ?? data['description'] ?? '').toString();
    final thumbFit = _courseThumbFit(data);
    final hasThumb = CourseThumbResolver.hasVisualThumb(data);
    final isVideo = CourseThumbResolver.isVideoContent(data);
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
            border: Border.all(
              color: selected ? accent : accent.withValues(alpha: 0.15),
              width: selected ? 2.2 : 1,
            ),
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
                    if (hasThumb)
                      CourseMediaThumbnail.fromData(
                        data,
                        fit: thumbFit,
                        fallback: _fallback(accent, accent2),
                        showPlayButton: isVideo,
                        playIconSize: 44,
                      )
                    else
                      _fallback(accent, accent2),
                    if (!hasThumb)
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
