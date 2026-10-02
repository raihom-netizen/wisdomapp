import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
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
import '../services/course_progress_service.dart';
import '../widgets/course_media_preview.dart';
import '../widgets/course_video/course_module_media_panel.dart';
import '../widgets/course_video/course_youtube_feed_card.dart';
import '../widgets/course/course_showcase_card.dart';
import '../widgets/course/course_yt_palette.dart';
import 'course_detail_screen.dart';

/// Filtros da vitrine de cursos.
enum _CourseFilter { todos, andamento, concluidos, novos, curtidos }

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

  /// Vitrine (padrão) × feed antigo com player inline (mantido como opção).
  var _feedMode = false;
  var _query = '';
  var _filter = _CourseFilter.todos;
  final _searchCtrl = TextEditingController();
  StreamSubscription<String>? _progressSub;
  Timer? _searchDebounce;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cache.addListener(_onCacheUpdate);
    unawaited(_cache.ensureLoaded());
    unawaited(CourseProgressService.instance.bindUser(widget.uid));
    // Só a vitrine reage ao progresso: no feed, reconstruir pararia o vídeo inline.
    _progressSub = CourseProgressService.instance.changes.listen((_) {
      if (!mounted || _feedMode || _tabIndex != 0) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _cache.removeListener(_onCacheUpdate);
    _progressSub?.cancel();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
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
    if (CourseMediaUrlResolver.collectVideoEntries(data).isNotEmpty) {
      return true;
    }
    if (_mp4Url(data) != null) return true;
    if (_videoId(data) != null) return true;
    final source = (data['source'] ?? '').toString().toLowerCase();
    if (source.isNotEmpty && source != 'youtube' && !source.contains('upload')) {
      return false;
    }
    return false;
  }

  String? _mp4Url(Map<String, dynamic> data) {
    final u = (data['mp4Url'] ?? '').toString().trim();
    return u.isEmpty ? null : u;
  }

  bool _isPublishedDica(Map<String, dynamic> data) {
    if (_videoId(data) != null) return true;
    final link = _externalLink(data);
    if (link != null && CourseContentLinkHelper.isValidHttpUrl(link)) {
      return true;
    }
    if ((data['bodyText'] ?? '').toString().trim().isNotEmpty) return true;
    if (CourseMediaUrlResolver.hasResolvableImage(data)) return true;
    return (data['description'] ?? '').toString().trim().isNotEmpty;
  }

  String? _videoId(Map<String, dynamic> data) {
    return YoutubeUrlHelper.videoIdFromData(data);
  }

  String? _externalLink(Map<String, dynamic> data) {
    final link =
        (data['linkUrl'] ?? data['externalUrl'] ?? '').toString().trim();
    return link.isEmpty ? null : link;
  }

  String? _thumbUrl(Map<String, dynamic> data) =>
      CourseThumbResolver.resolveBest(data);

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

    // Carga falhou/passou do prazo e não há nada em cache: erro visível com
    // «Tentar novamente» (antes a tela ficava vazia/girando).
    if (!syncing && allDocs.isEmpty && _cache.lastError != null) {
      return ColoredBox(
        color: CourseYt.background(context),
        child: _errorView(cfg, _cache.lastError),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _cache.ensureLoaded(forceServer: true),
      color: CourseYt.red,
      child: Container(
        // Claro: fundo cinza bem claro (estilo YouTube); escuro: #0F0F0F.
        decoration: BoxDecoration(
          color: CourseYt.background(context),
        ),
        child: ListView(
          controller: widget.shellScrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 28),
          children: [
            _buildHero(cfg, syncing && !_cache.hasCachedData),
            if (cfg.showTipsSection) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _YouTubeTabSelector(
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
              ),
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                layoutBuilder: (current, previous) =>
                    current ?? const SizedBox.shrink(),
                child: _tabIndex == 0 && !_feedMode
                    ? _buildCursosShowcase(
                        key: const ValueKey('cursos-vitrine'),
                        cfg: cfg,
                        docs: cursos,
                        syncing: syncing,
                      )
                    : _tabIndex == 0
                    ? _buildSection(
                        key: const ValueKey('cursos'),
                        cfg: cfg,
                        docs: cursos,
                        syncing: syncing,
                        accent: CourseYt.red,
                        accent2: CourseYt.redDark,
                        icon: Icons.school_rounded,
                        label: 'Cursos',
                      )
                    : _buildSection(
                        key: const ValueKey('dicas'),
                        cfg: cfg,
                        docs: dicas,
                        syncing: syncing,
                        accent: CourseYt.red,
                        accent2: CourseYt.redDark,
                        icon: Icons.lightbulb_rounded,
                        label: 'Dicas',
                      ),
              ),
            ] else if (!_feedMode) ...[
              const SizedBox(height: 12),
              _buildCursosShowcase(
                key: const ValueKey('cursos-vitrine-solo'),
                cfg: cfg,
                docs: cursos,
                syncing: syncing,
              ),
            ] else ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(child: _sectionTitle(cfg.sectionTitle)),
                    _viewToggle(),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (cursos.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _emptyState(cfg, syncing, AppColors.primary),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: [
                      for (final doc in cursos)
                        CourseYoutubeFeedCard(
                          key: ValueKey('curso-solo-${doc.id}'),
                          data: {...doc.data, 'id': doc.id},
                          uid: widget.uid,
                          isActive:
                              (_activeCurso?['id'] ?? cursos.first.id) ==
                                  doc.id,
                          onActivate: () => _selectModuleContent(
                            {...doc.data, 'id': doc.id},
                            isDica: false,
                          ),
                          accent: CourseYt.red,
                          accent2: CourseYt.redDark,
                        ),
                    ],
                  ),
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
        Icon(Icons.cloud_off_rounded,
            size: 48, color: CourseYt.textMuted(context)),
        const SizedBox(height: 12),
        Text(
          'Não foi possível carregar os vídeos.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: CourseYt.text(context),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _retryLoad,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tentar novamente'),
          style: FilledButton.styleFrom(
            backgroundColor: CourseYt.red,
          ),
        ),
      ],
    );
  }

  Widget _buildHero(WisdomCoursesModuleConfig cfg, bool syncing) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(16),
      decoration: CourseYt.cardDecoration(context, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: CourseYt.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.play_circle_fill_rounded,
                    color: CourseYt.red, size: 26),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  cfg.heroTitle,
                  style: TextStyle(
                    color: CourseYt.text(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    height: 1.25,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            cfg.heroMessage,
            style: TextStyle(
              color: CourseYt.textSecondary(context),
              height: 1.35,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
          if (syncing) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              minHeight: 2,
              color: CourseYt.red,
              backgroundColor: CourseYt.track(context),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 18,
          decoration: BoxDecoration(
            color: CourseYt.red,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: CourseYt.text(context),
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
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: _sectionTitle(
                  isDicas ? 'Todas as dicas' : 'Todos os cursos',
                ),
              ),
              if (!isDicas) _viewToggle(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              for (final doc in docs)
                CourseYoutubeFeedCard(
                  key: ValueKey('${isDicas ? 'dica' : 'curso'}-${doc.id}'),
                  data: {...doc.data, 'id': doc.id},
                  uid: widget.uid,
                  isActive: isDicas
                      ? (_activeDica?['id'] ?? docs.first.id) == doc.id
                      : (_activeCurso?['id'] ?? docs.first.id) == doc.id,
                  onActivate: () => _selectModuleContent(
                    {...doc.data, 'id': doc.id},
                    isDica: isDicas,
                  ),
                  accent: CourseYt.red,
                  accent2: CourseYt.redDark,
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Vitrine de cursos ────────────────────────────────────────────────

  Widget _viewToggle() {
    return Tooltip(
      message: _feedMode ? 'Ver vitrine de cursos' : 'Ver como feed (player na lista)',
      child: IconButton(
        onPressed: () => setState(() => _feedMode = !_feedMode),
        icon: Icon(
          _feedMode ? Icons.grid_view_rounded : Icons.view_agenda_rounded,
          color: CourseYt.textSecondary(context),
        ),
      ),
    );
  }

  static String _fold(String s) {
    const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const to = 'aaaaaeeeeiiiiooooouuuucn';
    final low = s.toLowerCase();
    final b = StringBuffer();
    for (final ch in low.split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString();
  }

  bool _matchesQuery(Map<String, dynamic> data) {
    final q = _fold(_query.trim());
    if (q.isEmpty) return true;
    final hay = _fold(
      '${data['title'] ?? ''} ${data['description'] ?? ''} ${data['bodyText'] ?? ''}',
    );
    return q.split(RegExp(r'\s+')).every(hay.contains);
  }

  bool _matchesFilter(CourseShowcaseInfo i) {
    switch (_filter) {
      case _CourseFilter.todos:
        return true;
      case _CourseFilter.andamento:
        return i.inProgress;
      case _CourseFilter.concluidos:
        return i.completed;
      case _CourseFilter.novos:
        return i.isNew;
      case _CourseFilter.curtidos:
        return i.liked;
    }
  }

  void _openCourse(CourseShowcaseInfo info, {bool resume = false}) {
    openCourseDetail(
      context,
      data: {...info.data},
      uid: widget.uid,
      continueWhereStopped: resume,
    );
  }

  Widget _buildCursosShowcase({
    required Key key,
    required WisdomCoursesModuleConfig cfg,
    required List<CourseVideoDoc> docs,
    required bool syncing,
  }) {
    final progress = CourseProgressService.instance;
    final infos = [
      for (final d in docs)
        CourseShowcaseInfo({...d.data, 'id': d.id}, progress.of(d.id)),
    ];
    final counts = {
      _CourseFilter.todos: infos.length,
      _CourseFilter.andamento: infos.where((i) => i.inProgress).length,
      _CourseFilter.concluidos: infos.where((i) => i.completed).length,
      _CourseFilter.novos: infos.where((i) => i.isNew).length,
      _CourseFilter.curtidos: infos.where((i) => i.liked).length,
    };
    final visible = infos
        .where((i) => _matchesQuery(i.data) && _matchesFilter(i))
        .toList();
    final continuing = infos.where((i) => i.inProgress).toList()
      ..sort((a, b) => b.lastOpenedMs.compareTo(a.lastOpenedMs));
    final showContinue = continuing.isNotEmpty &&
        _query.trim().isEmpty &&
        _filter == _CourseFilter.todos;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  // Debounce: filtra 250 ms depois da última tecla (antes
                  // reconstruía a vitrine inteira a cada letra).
                  onChanged: (v) {
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(
                      const Duration(milliseconds: 250),
                      () {
                        if (mounted && _query != v) setState(() => _query = v);
                      },
                    );
                  },
                  style: TextStyle(color: CourseYt.text(context)),
                  cursorColor: CourseYt.red,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: CourseYt.card(context),
                    hintText: 'Buscar curso…',
                    hintStyle:
                        TextStyle(color: CourseYt.textMuted(context)),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: CourseYt.textSecondary(context)),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: Icon(Icons.close_rounded,
                                color: CourseYt.textSecondary(context)),
                            onPressed: () => setState(() {
                              _searchDebounce?.cancel();
                              _query = '';
                              _searchCtrl.clear();
                            }),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide:
                          BorderSide(color: CourseYt.border(context)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide(
                        color: CourseYt.isDark(context)
                            ? CourseYt.border(context)
                            : const Color(0xFFD3D3D3),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide:
                          const BorderSide(color: CourseYt.red, width: 1.4),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _viewToggle(),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final f in _CourseFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _FilterPill(
                    label: _filterLabel(f),
                    icon: _filterIcon(f),
                    count: counts[f] ?? 0,
                    selected: _filter == f,
                    onTap: () => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
        ),
        if (showContinue) ...[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _sectionTitle('Continuar assistindo'),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 205,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: continuing.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => CourseContinueCard(
                info: continuing[i],
                onTap: () => _openCourse(continuing[i], resume: true),
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _sectionTitle(
            _filter == _CourseFilter.todos && _query.trim().isEmpty
                ? cfg.sectionTitle
                : '${visible.length} ${visible.length == 1 ? 'curso' : 'cursos'}',
          ),
        ),
        const SizedBox(height: 10),
        if (docs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _emptyState(cfg, syncing, AppColors.primary),
          )
        else if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _emptyState(
              cfg,
              false,
              AppColors.primary,
              emptyHint: _query.trim().isNotEmpty
                  ? 'Nenhum curso encontrado para «${_query.trim()}».'
                  : 'Nenhum curso neste filtro.',
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;
                final cols = w >= 1150 ? 4 : (w >= 820 ? 3 : (w >= 480 ? 2 : 1));
                final rows = <Widget>[];
                for (var r = 0; r < visible.length; r += cols) {
                  final slice = visible.skip(r).take(cols).toList();
                  rows.add(Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var k = 0; k < cols; k++) ...[
                          if (k > 0) const SizedBox(width: 12),
                          Expanded(
                            child: k < slice.length
                                ? CourseShowcaseCard(
                                    key: ValueKey('vitrine-${slice[k].id}'),
                                    info: slice[k],
                                    onTap: () => _openCourse(slice[k]),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ));
                }
                return Column(children: rows);
              },
            ),
          ),
      ],
    );
  }

  String _filterLabel(_CourseFilter f) {
    switch (f) {
      case _CourseFilter.todos:
        return 'Todos';
      case _CourseFilter.andamento:
        return 'Em andamento';
      case _CourseFilter.concluidos:
        return 'Concluídos';
      case _CourseFilter.novos:
        return 'Novos';
      case _CourseFilter.curtidos:
        return 'Curtidos';
    }
  }

  IconData _filterIcon(_CourseFilter f) {
    switch (f) {
      case _CourseFilter.todos:
        return Icons.apps_rounded;
      case _CourseFilter.andamento:
        return Icons.play_circle_outline_rounded;
      case _CourseFilter.concluidos:
        return Icons.verified_rounded;
      case _CourseFilter.novos:
        return Icons.fiber_new_rounded;
      case _CourseFilter.curtidos:
        return Icons.thumb_up_alt_rounded;
    }
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
            final related =
                allDocs.map((d) => {...d.data, 'id': d.id}).toList();
            return _DicaGridCard(
              data: {...data, 'id': docs[i].id},
              index: i,
              videoId: _videoId(data),
              thumbUrl: _thumbUrl(data),
              accent: accent,
              accent2: accent2,
              selected: (_activeDica?['id'] ??
                      (allDocs.isNotEmpty ? allDocs.first.id : '')) ==
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
        for (var i = 0; i < docs.length; i++)
          _ModernVideoCard(
            data: {...docs[i].data, 'id': docs[i].id},
            index: i,
            videoId: _videoId(docs[i].data),
            thumbUrl: _thumbUrl(docs[i].data),
            accent: accent,
            accent2: accent2,
            selected: (_activeCurso?['id'] ??
                    (allDocs.isNotEmpty ? allDocs.first.id : '')) ==
                docs[i].id,
            onTap: () => _openContent(
              context,
              {...docs[i].data, 'id': docs[i].id},
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
      decoration: CourseYt.cardDecoration(context, radius: 16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: CourseYt.red.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.ondemand_video_rounded,
                size: 36, color: CourseYt.red),
          ),
          const SizedBox(height: 14),
          Text(
            syncing ? 'A carregar conteúdo…' : (emptyHint ?? cfg.emptyMessage),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CourseYt.textSecondary(context),
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

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const accent = CourseYt.red;
    return Material(
      color: selected ? accent : CourseYt.surfaceAlt(context),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 15,
                  color: selected
                      ? Colors.white
                      : CourseYt.textSecondary(context)),
              const SizedBox(width: 5),
              Text(
                count > 0 ? '$label · $count' : label,
                style: TextStyle(
                  color: selected ? Colors.white : CourseYt.text(context),
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _YouTubeTabSelector extends StatelessWidget {
  const _YouTubeTabSelector({
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
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: CourseYt.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CourseYt.border(context)),
        boxShadow: CourseYt.cardShadow(context),
      ),
      child: Row(
        children: [
          Expanded(
            child: _YTPill(
              label: 'Cursos',
              icon: Icons.school_rounded,
              count: cursosCount,
              selected: index == 0,
              accent: CourseYt.red,
              onTap: () => onChanged(0),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _YTPill(
              label: 'Dicas',
              icon: Icons.lightbulb_rounded,
              count: dicasCount,
              selected: index == 1,
              accent: CourseYt.red,
              onTap: () => onChanged(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _YTPill extends StatelessWidget {
  const _YTPill({
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.onTap,
    this.accent = CourseYt.red,
  });

  final String label;
  final IconData icon;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selected ? accent : Colors.transparent,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? Colors.white
                    : CourseYt.textSecondary(context),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: selected ? Colors.white : CourseYt.text(context),
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.25)
                        : CourseYt.surfaceAlt(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: selected
                          ? Colors.white
                          : CourseYt.textSecondary(context),
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
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: CourseYt.cardDecoration(context, radius: 14),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CourseMediaThumbnail.fromData(
                      data,
                      fit: thumbFit,
                      fallback: _coverPlaceholder(context),
                      showPlayButton: isVideo,
                      playIconSize: 56,
                    ),
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: CourseYt.red.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          videoId != null ? 'YouTube' : 'MP4',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: CourseYt.text(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
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
                          color: CourseYt.textSecondary(context),
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
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

  Widget _coverPlaceholder(BuildContext context) {
    return Container(
      color: CourseYt.surfaceAlt(context),
      child: Center(
        child: Icon(Icons.ondemand_video_rounded,
            color: CourseYt.coverFallbackIcon(context), size: 48),
      ),
    );
  }
}

class _ModernVideoCard extends StatelessWidget {
  const _ModernVideoCard({
    required this.data,
    required this.index,
    required this.videoId,
    required this.thumbUrl,
    required this.accent,
    required this.accent2,
    required this.onTap,
    this.selected = false,
  });

  final Map<String, dynamic> data;
  final int index;
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
    if (videoId != null) return 'YouTube';
    final link = (data['linkUrl'] ?? data['externalUrl'] ?? '').toString();
    if (link.isNotEmpty) return CourseContentLinkHelper.linkLabel(link);
    return 'Conteúdo';
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
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 160,
                    height: 90,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (hasThumb)
                          CourseMediaThumbnail.fromData(
                            data,
                            fit: thumbFit,
                            fallback: _coverFallback(context),
                            showPlayButton: isVideo,
                            playIconSize: 36,
                          )
                        else if (isVideo)
                          CourseMediaThumbnail.fromData(
                            data,
                            fit: BoxFit.cover,
                            fallback: _coverFallback(context),
                            showPlayButton: true,
                            playIconSize: 36,
                          )
                        else
                          _coverFallback(context),
                        if (!hasThumb && !isVideo)
                          Center(
                            child: Icon(
                              _overlayIcon(),
                              color: Colors.white.withValues(alpha: 0.85),
                              size: 36,
                            ),
                          ),
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              _sourceLabel(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
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
                        style: TextStyle(
                          color: CourseYt.text(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
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
                            color: CourseYt.textSecondary(context),
                            fontSize: 12,
                            height: 1.3,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        type == 'dica' ? 'Dica Wisdom' : 'Wisdom Cursos',
                        style: TextStyle(
                          color: CourseYt.textMuted(context),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.more_vert_rounded,
                  color: CourseYt.textMuted(context),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _coverFallback(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CourseYt.surfaceAlt(context),
      ),
      child: Center(
        child: Icon(
          Icons.ondemand_video_rounded,
          color: CourseYt.coverFallbackIcon(context),
          size: 32,
        ),
      ),
    );
  }
}

class _DicaGridCard extends StatelessWidget {
  const _DicaGridCard({
    required this.data,
    required this.index,
    required this.videoId,
    required this.thumbUrl,
    required this.accent,
    required this.accent2,
    required this.onTap,
    this.selected = false,
  });

  final Map<String, dynamic> data;
  final int index;
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
    final sourceLabel = videoId != null
        ? 'YouTube'
        : ((data['linkUrl'] ?? data['externalUrl'] ?? '').toString().isNotEmpty
            ? 'Link'
            : 'Texto');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: CourseYt.cardDecoration(
            context,
            radius: 12,
            borderColor: selected ? CourseYt.red : null,
            borderWidth: selected ? 1.5 : 1,
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
                        fallback: _fallback(context),
                        showPlayButton: isVideo,
                        playIconSize: 36,
                      )
                    else
                      _fallback(context),
                    if (!hasThumb)
                      Center(
                        child: Icon(
                          overlayIcon,
                          color: Colors.white.withValues(alpha: 0.85),
                          size: 36,
                        ),
                      ),
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          sourceLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: CourseYt.text(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Expanded(
                          child: Text(
                            body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.3,
                              color: CourseYt.textSecondary(context),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
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

  Widget _fallback(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CourseYt.surfaceAlt(context),
      ),
      child: Center(
        child: Icon(Icons.lightbulb_rounded,
            color: CourseYt.coverFallbackIcon(context), size: 32),
      ),
    );
  }
}
