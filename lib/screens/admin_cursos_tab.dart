import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/wisdom_courses_module_config.dart';
import '../services/course_video_file_service.dart';
import '../services/course_video_image_service.dart';
import '../services/course_media_storage_cleanup.dart';
import '../services/course_videos_cache_service.dart';
import '../services/course_analytics_service.dart';
import '../services/youtube_oembed_service.dart';
import '../utils/admin_load_guard.dart';
import '../widgets/admin/course_admin_analytics_panel.dart';
import '../widgets/admin/course_comments_moderation_sheet.dart';
import '../widgets/admin/course_content_sheet_header.dart';
import '../theme/app_colors.dart';
import '../theme/theme_context.dart';
import '../utils/course_content_link_helper.dart';
import '../utils/course_media_url_resolver.dart';
import '../utils/admin_course_firestore_bridge.dart';
import '../utils/firestore_retry.dart';
import '../utils/firestore_web_guard.dart';
import '../services/course_videos_expiry_cleanup_service.dart';
import '../utils/course_video_validity.dart';
import '../utils/course_thumb_resolver.dart';
import '../utils/youtube_url_helper.dart';
import '../widgets/course_media_preview.dart';
import '../widgets/course/course_content_card_header.dart';
import '../widgets/course_video/course_video_watch_screen.dart';
import '../widgets/fast_text_field.dart';
import '../widgets/module_header_premium.dart';

/// Arquivo escolhido no admin (imagem ou vídeo) antes do upload.
class _PickedMedia {
  const _PickedMedia({
    this.bytes,
    this.file,
    required this.mime,
    this.name,
    this.sizeBytes,
    this.width,
    this.height,
  });

  final Uint8List? bytes;
  final int? width;
  final int? height;
  final File? file;
  final String mime;
  final String? name;
  final int? sizeBytes;

  int get effectiveSize => sizeBytes ?? bytes?.lengthInBytes ?? 0;

  bool get isFile => file != null;
}

class AdminCursosTab extends StatefulWidget {
  const AdminCursosTab({super.key, this.somenteVideos = false});

  /// Editor de conteúdo (`role: editor_conteudo`): publica/edita/exclui os
  /// vídeos e nada mais — sem métricas de quem assistiu (`course_stats`, que
  /// mostra usuários) e sem os textos do módulo. As regras e a function
  /// também recusam; aqui só não se pede o que vai dar permission-denied.
  final bool somenteVideos;

  @override
  State<AdminCursosTab> createState() => _AdminCursosTabState();
}

class _AdminCursosTabState extends State<AdminCursosTab> {
  static const _configDoc = 'wisdom_courses_module';

  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _bodyTextCtrl = TextEditingController();
  final _youtubeCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _heroTitleCtrl = TextEditingController();
  final _heroMessageCtrl = TextEditingController();
  final _sectionTitleCtrl = TextEditingController();
  final _emptyMessageCtrl = TextEditingController();

  String _type = 'curso';
  bool _published = true;
  bool _showTipsSection = true;
  bool _savingVideo = false;
  bool _savingConfig = false;
  bool _configLoaded = false;
  int _gridTab = 0;
  String _dateFilter = 'recent';
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  final List<_PickedMedia> _pickedImages = [];
  final List<_PickedMedia> _pickedVideos = [];
  double _uploadProgress = 0;
  bool _validityPermanent = true;
  DateTime? _expiresAtDate;
  bool _expiryCleanupScheduled = false;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _courseDocs = const [];
  bool _courseDocsLoading = true;
  Object? _courseDocsError;

  // ── Envio rápido (colar link → prévia → Publicar) ──
  CourseUploadCancelToken? _uploadCancel;
  Timer? _linkDebounce;
  String? _quickVideoId;
  YoutubeOembedInfo? _quickInfo;
  bool _quickLoading = false;
  String _autoTitle = '';
  /// idle | saving | done
  String _publishState = 'idle';
  Timer? _publishStateTimer;
  bool _compactList = true;

  /// Streams guardados (Firestore Web: nunca `.snapshots()` dentro do build).
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _configStream =
      FirebaseFirestore.instance
          .collection('app_config')
          .doc(_configDoc)
          .snapshots();
  late final Stream<List<CourseStatSummary>> _statsStream = widget.somenteVideos
      ? Stream<List<CourseStatSummary>>.value(const <CourseStatSummary>[])
      : CourseAnalyticsService.instance.watchAllStats();

  @override
  void initState() {
    super.initState();
    _scheduleExpiryCleanup();
    unawaited(_reloadCourseVideos());
    _youtubeCtrl.addListener(_onLinkChanged);
  }

  void _onLinkChanged() {
    _linkDebounce?.cancel();
    _linkDebounce = Timer(const Duration(milliseconds: 450), _resolveQuickLink);
  }

  /// Link colado → ID → prévia (oEmbed) → título preenchido sozinho.
  Future<void> _resolveQuickLink() async {
    if (!mounted) return;
    final id = YoutubeUrlHelper.extractVideoId(_youtubeCtrl.text);
    if (id == null) {
      if (_quickVideoId != null || _quickInfo != null) {
        setState(() {
          _quickVideoId = null;
          _quickInfo = null;
          _quickLoading = false;
        });
      } else {
        setState(() {});
      }
      return;
    }
    if (id == _quickVideoId) return;
    setState(() {
      _quickVideoId = id;
      _quickInfo = YoutubeOembedInfo(videoId: id);
      _quickLoading = true;
    });
    final info = await YoutubeOembedService.fetch(id);
    if (!mounted || _quickVideoId != id) return;
    setState(() {
      _quickInfo = info;
      _quickLoading = false;
      final atual = _titleCtrl.text.trim();
      if (info.title.isNotEmpty && (atual.isEmpty || atual == _autoTitle)) {
        _titleCtrl.text = info.title;
        _autoTitle = info.title;
      }
    });
  }

  Future<void> _afterContentMutation({String? snack}) async {
    await _reloadCourseVideos();
    try {
      // Só conclui a publicação depois de atualizar o catálogo compartilhado.
      // Assim o conteúdo já aparece ao abrir o módulo Cursos do usuário.
      await CourseVideosCacheService.instance.ensureLoaded(forceServer: true);
    } catch (_) {
      // O documento já foi gravado; uma falha de cache não deve duplicá-lo
      // caso o administrador tente publicar novamente.
    }
    if (snack != null) _snack(snack);
  }

  Future<void> _reloadCourseVideos() async {
    if (_courseDocs.isEmpty) {
      if (mounted) setState(() => _courseDocsLoading = true);
    }
    try {
      final docs = await _fetchCourseVideos();
      if (!mounted) return;
      setState(() {
        _courseDocs = docs;
        _courseDocsLoading = false;
        _courseDocsError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _courseDocsLoading = false;
        _courseDocsError = e;
      });
    }
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _fetchCourseVideos() async {
    return _courseFirestoreOp(() async {
      // Com prazo: sem resposta vira erro com «Tentar novamente» (nunca
      // spinner eterno — ver AdminLoadGuard).
      final snap = await AdminLoadGuard.comPrazo(
        FirebaseFirestore.instance
            .collection('course_videos')
            .get(const GetOptions(source: Source.serverAndCache)),
        oQue: 'os cursos',
      );
      return snap.docs;
    });
  }

  void _scheduleExpiryCleanup() {
    // Editor de conteúdo não apaga direto no Firestore (regra); a limpeza
    // diária do servidor (courseVideosExpiryCleanupScheduled) cuida disso.
    if (widget.somenteVideos) return;
    if (_expiryCleanupScheduled) return;
    _expiryCleanupScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final n = await CourseVideosExpiryCleanupService.purgeExpired();
      if (n > 0 && mounted) {
        _snack('$n conteúdo(s) expirado(s) removido(s) automaticamente.');
      }
    });
  }

  @override
  void dispose() {
    _linkDebounce?.cancel();
    _publishStateTimer?.cancel();
    _uploadCancel?.cancel();
    _youtubeCtrl.removeListener(_onLinkChanged);
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _bodyTextCtrl.dispose();
    _youtubeCtrl.dispose();
    _searchCtrl.dispose();
    _heroTitleCtrl.dispose();
    _heroMessageCtrl.dispose();
    _sectionTitleCtrl.dispose();
    _emptyMessageCtrl.dispose();
    super.dispose();
  }

  void _hydrateConfig(Map<String, dynamic>? data) {
    if (_configLoaded) return;
    final cfg = WisdomCoursesModuleConfig.fromMap(data);
    _heroTitleCtrl.text = cfg.heroTitle;
    _heroMessageCtrl.text = cfg.heroMessage;
    _sectionTitleCtrl.text = cfg.sectionTitle;
    _emptyMessageCtrl.text = cfg.emptyMessage;
    _showTipsSection = cfg.showTipsSection;
    _configLoaded = true;
  }

  InputDecoration _fieldDeco(String label, {String? hint, Color? accent}) {
    final c = accent ?? AppColors.primary;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: context.isDarkMode ? context.appInputFill : Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.withValues(alpha: 0.25)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c, width: 2),
      ),
    );
  }

  Widget _buildValiditySection({
    required bool permanent,
    required DateTime? expiresAt,
    required ValueChanged<bool> onPermanentChanged,
    required ValueChanged<DateTime?> onDateChanged,
    required Color accent,
    bool enabled = true,
  }) {
    final dateLabel = expiresAt == null
        ? 'Escolher data limite'
        : DateFormat('dd/MM/yyyy', 'pt_BR').format(expiresAt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Validade no módulo Cursos',
          style: TextStyle(fontWeight: FontWeight.w900, color: accent),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ValidityPill(
                label: 'Permanente',
                icon: Icons.all_inclusive_rounded,
                selected: permanent,
                color: accent,
                onTap: enabled ? () => onPermanentChanged(true) : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ValidityPill(
                label: 'Com prazo',
                icon: Icons.event_busy_rounded,
                selected: !permanent,
                color: const Color(0xFFDC2626),
                onTap: enabled ? () => onPermanentChanged(false) : null,
              ),
            ),
          ],
        ),
        if (!permanent) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: enabled
                ? () async {
                    final initial = expiresAt ??
                        DateTime.now().add(const Duration(days: 30));
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: initial,
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2035, 12, 31),
                      helpText: 'Validade até (inclusive)',
                      locale: const Locale('pt', 'BR'),
                    );
                    if (picked != null) {
                      onDateChanged(
                        DateTime(picked.year, picked.month, picked.day),
                      );
                    }
                  }
                : null,
            icon: const Icon(Icons.calendar_month_rounded, size: 18),
            label: Text(dateLabel),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
              side: BorderSide(color: accent.withValues(alpha: 0.45)),
            ),
          ),
          Text(
            'Após essa data o conteúdo é removido automaticamente do banco.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: context.isDarkMode ? context.appTextSecondary : Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 4),
      ],
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final out = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    out.sort((a, b) {
      final ta = a.data()['createdAt'];
      final tb = b.data()['createdAt'];
      if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
      return 0;
    });
    return out;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var list = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    if (_gridTab == 1) {
      list = list
          .where((d) => (d.data()['type'] ?? 'curso').toString() == 'curso')
          .toList();
    } else if (_gridTab == 2) {
      list = list
          .where((d) => (d.data()['type'] ?? '').toString() == 'dica')
          .toList();
    }

    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((d) {
        final data = d.data();
        final hay = [
          data['title'],
          data['description'],
          data['bodyText'],
        ].whereType<Object>().map((e) => e.toString()).join(' ').toLowerCase();
        return hay.contains(q);
      }).toList();
    }

    final now = DateTime.now();
    if (_dateFilter == 'today') {
      list = list.where((d) {
        final ts = d.data()['createdAt'];
        if (ts is! Timestamp) return false;
        final dt = ts.toDate();
        return dt.year == now.year &&
            dt.month == now.month &&
            dt.day == now.day;
      }).toList();
    } else if (_dateFilter == 'week') {
      final start = now.subtract(const Duration(days: 7));
      list = list.where((d) {
        final ts = d.data()['createdAt'];
        return ts is Timestamp && ts.toDate().isAfter(start);
      }).toList();
    } else if (_dateFilter == 'month') {
      final start = DateTime(now.year, now.month, 1);
      list = list.where((d) {
        final ts = d.data()['createdAt'];
        return ts is Timestamp && !ts.toDate().isBefore(start);
      }).toList();
    }

    list.sort((a, b) {
      final ta = a.data()['createdAt'];
      final tb = b.data()['createdAt'];
      if (ta is Timestamp && tb is Timestamp) {
        return _dateFilter == 'oldest' ? ta.compareTo(tb) : tb.compareTo(ta);
      }
      return 0;
    });
    return list;
  }

  Future<void> _pickMp4Videos({VoidCallback? onStateChanged}) async {
    try {
      final remaining =
          CourseMediaUrlResolver.maxCourseVideos - _pickedVideos.length;
      if (remaining <= 0) {
        _snack(
            'Máximo de ${CourseMediaUrlResolver.maxCourseVideos} vídeos por curso.');
        return;
      }
      final isWeb = kIsWeb;
      final pick = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp4', 'mov', 'webm'],
        withData: isWeb,
        allowMultiple: true,
      );
      if (pick == null || pick.files.isEmpty) return;
      final added = <_PickedMedia>[];
      for (final f in pick.files) {
        if (added.length >= remaining) break;
        var ext = (f.extension ?? 'mp4').toLowerCase();
        final invalid = CourseVideoFileService.validate(
          name: f.name,
          sizeBytes: f.size,
        );
        if (invalid != null) {
          _snack(invalid);
          continue;
        }
        final mime = ext == 'webm'
            ? 'video/webm'
            : (ext == 'mov' ? 'video/quicktime' : 'video/mp4');
        if (isWeb) {
          final bytes = f.bytes;
          if (bytes == null || bytes.isEmpty) continue;
          if (bytes.lengthInBytes > CourseVideoFileService.maxBytes) {
            _snack('${f.name}: acima de 250 MB — ignorado.');
            continue;
          }
          added.add(_PickedMedia(
              bytes: bytes,
              mime: mime,
              name: f.name,
              sizeBytes: bytes.lengthInBytes));
        } else {
          final path = f.path;
          if (path == null) continue;
          final file = File(path);
          final size = await file.length();
          if (size > CourseVideoFileService.maxBytes) {
            _snack('${f.name}: acima de 250 MB — ignorado.');
            continue;
          }
          added.add(_PickedMedia(
              file: file, mime: mime, name: f.name, sizeBytes: size));
        }
      }
      if (added.isEmpty) return;
      setState(() => _pickedVideos.addAll(added));
      onStateChanged?.call();
    } catch (e) {
      _snack('Erro ao selecionar vídeo: $e');
    }
  }

  /// Grava vídeo diretamente da câmera (resolve o bug de “não finaliza”).
  Future<void> _recordVideoFromCamera({VoidCallback? onStateChanged}) async {
    try {
      final remaining =
          CourseMediaUrlResolver.maxCourseVideos - _pickedVideos.length;
      if (remaining <= 0) {
        _snack(
            'Máximo de ${CourseMediaUrlResolver.maxCourseVideos} vídeos por curso.');
        return;
      }
      final picker = ImagePicker();
      final video = await picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 10),
      );
      if (video == null) return;
      final file = File(video.path);
      final size = await file.length();
      if (size > CourseVideoFileService.maxBytes) {
        _snack('Vídeo acima de 250 MB — ignorado.');
        return;
      }
      final ext = video.path.toLowerCase().endsWith('.mov') ? 'mov' : 'mp4';
      final mime = ext == 'mov' ? 'video/quicktime' : 'video/mp4';
      setState(() => _pickedVideos.add(_PickedMedia(
            file: file,
            mime: mime,
            name: video.name,
            sizeBytes: size,
          )));
      onStateChanged?.call();
    } catch (e) {
      _snack('Erro ao gravar vídeo: $e');
    }
  }

  /// Mostra opções: galeria ou câmera (na web pula direto para galeria).
  Future<void> _addVideoWithChoice({VoidCallback? onStateChanged}) async {
    if (!mounted) return;
    if (kIsWeb) {
      await _pickMp4Videos(onStateChanged: onStateChanged);
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: ctx.isDarkMode ? ctx.appSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: ctx.isDarkMode ? ctx.appChipIdleBorder : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Adicionar vídeo',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading:
                  const Icon(Icons.videocam_rounded, color: Color(0xFF2563EB)),
              title: const Text('Gravar com a câmera',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Grava até 10 min direto no app'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_rounded,
                  color: Color(0xFF7C3AED)),
              title: const Text('Escolher da galeria',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('MP4, MOV ou WebM (até 250 MB)'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'camera') {
      await _recordVideoFromCamera(onStateChanged: onStateChanged);
    } else if (choice == 'gallery') {
      await _pickMp4Videos(onStateChanged: onStateChanged);
    }
  }

  void _clearPickedVideos({VoidCallback? onStateChanged}) {
    setState(() {
      _pickedVideos.clear();
      _uploadProgress = 0;
    });
    onStateChanged?.call();
  }

  void _removePickedVideo(int index, {VoidCallback? onStateChanged}) {
    setState(() => _pickedVideos.removeAt(index));
    onStateChanged?.call();
  }

  Future<List<CourseMediaUploadResult>> _uploadPickedVideos(
    String docId, {
    int startIndex = 0,
    void Function(double progress)? onProgress,
  }) async {
    final out = <CourseMediaUploadResult>[];
    for (var i = 0; i < _pickedVideos.length; i++) {
      final p = _pickedVideos[i];
      void reportVideoProgress(double progress) {
        if (_pickedVideos.isEmpty) return;
        onProgress?.call((i + progress) / _pickedVideos.length);
      }

      if (p.isFile) {
        out.add(await CourseVideoFileService.uploadVideoFile(
          file: p.file!,
          docId: docId,
          index: startIndex + i,
          onProgress: reportVideoProgress,
          cancelToken: _uploadCancel,
        ));
      } else {
        out.add(await CourseVideoFileService.uploadVideo(
          bytes: p.bytes!,
          mimeType: p.mime,
          docId: docId,
          index: startIndex + i,
          onProgress: reportVideoProgress,
          cancelToken: _uploadCancel,
        ));
      }
    }
    return out;
  }

  Future<void> _pickCoverImages() async {
    try {
      final remaining =
          CourseMediaUrlResolver.maxGalleryPhotos - _pickedImages.length;
      if (remaining <= 0) {
        _snack('Máximo de ${CourseMediaUrlResolver.maxGalleryPhotos} fotos.');
        return;
      }
      final pick = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
        withData: true,
        allowMultiple: true,
      );
      if (pick == null || pick.files.isEmpty) return;
      final added = <_PickedMedia>[];
      for (final f in pick.files) {
        if (added.length >= remaining) break;
        final bytes = f.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        if (bytes.lengthInBytes > CourseVideoImageService.maxBytes) {
          _snack('${f.name}: acima de 12 MB — ignorado.');
          continue;
        }
        var ext = (f.extension ?? 'jpg').toLowerCase();
        if (ext == 'jpeg') ext = 'jpg';
        final mime = ext == 'png'
            ? 'image/png'
            : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
        int? w, h;
        try {
          final info = img.findDecoderForData(bytes)?.startDecode(bytes);
          w = info?.width;
          h = info?.height;
        } catch (_) {}
        if (w == null || h == null || w <= 0 || h <= 0) {
          _snack('${f.name}: imagem inválida ou formato não suportado.');
          continue;
        }
        if (w > 3840 || h > 3840) {
          _snack('${f.name}: ${w}x$h — será reduzida para até 3840 px no envio.');
        }
        added.add(_PickedMedia(
          bytes: bytes,
          mime: mime,
          name: f.name,
          sizeBytes: bytes.lengthInBytes,
          width: w,
          height: h,
        ));
      }
      if (added.isEmpty) return;
      setState(() => _pickedImages.addAll(added));
    } catch (e) {
      _snack('Erro ao selecionar imagem: $e');
    }
  }

  void _clearPickedImages() {
    setState(() => _pickedImages.clear());
  }

  void _removePickedImage(int index) {
    setState(() => _pickedImages.removeAt(index));
  }

  Future<List<CourseMediaUploadResult>> _uploadPickedImages(
    String docId, {
    int startIndex = 0,
  }) async {
    final out = <CourseMediaUploadResult>[];
    for (var i = 0; i < _pickedImages.length; i++) {
      final p = _pickedImages[i];
      out.add(
        await CourseVideoImageService.uploadCover(
          bytes: p.bytes!,
          mimeType: p.mime,
          docId: docId,
          index: startIndex + i,
        ),
      );
    }
    return out;
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final n = _selectedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir selecionados?'),
        content: Text('Remove $n item(ns) permanentemente.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Excluir $n'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final ids = _selectedIds.toList();
      await _courseFirestoreOp(() async {
        for (final id in ids) {
          final snap = await FirebaseFirestore.instance
              .collection('course_videos')
              .doc(id)
              .get();
          await CourseMediaStorageCleanup.deleteForCourseDoc(
            id,
            data: snap.data(),
          );
        }
      });
      await AdminCourseFirestoreBridge.deleteCourseVideos(ids);
      setState(() {
        _selectedIds.clear();
        _selectionMode = false;
      });
      await _afterContentMutation(snack: '$n conteúdo(s) removido(s).');
    } catch (e) {
      _snack('Erro ao excluir: $e');
    }
  }

  Future<void> _saveModuleConfig() async {
    if (_savingConfig) return;
    setState(() => _savingConfig = true);
    try {
      final email = FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
      final cfg = WisdomCoursesModuleConfig(
        heroTitle: _heroTitleCtrl.text.trim(),
        heroMessage: _heroMessageCtrl.text.trim(),
        sectionTitle: _sectionTitleCtrl.text.trim(),
        emptyMessage: _emptyMessageCtrl.text.trim(),
        showTipsSection: _showTipsSection,
      );
      await AdminCourseFirestoreBridge.saveWisdomCoursesModuleConfig({
        ...cfg.toFirestore(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByEmail': email,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuração do módulo Cursos salva.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingConfig = false);
    }
  }

  Future<bool> _publishVideo({VoidCallback? onStateChanged}) async {
    if (_savingVideo) return false;
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _snack('Informe o título.');
      return false;
    }

    if (_type == 'curso') {
      final youtubeRaw = _youtubeCtrl.text.trim();
      final hasYoutube = youtubeRaw.isNotEmpty;
      final hasMp4 = _pickedVideos.isNotEmpty;
      if (!hasMp4 && !hasYoutube) {
        _snack('Envie pelo menos um vídeo ou cole um link do YouTube.');
        return false;
      }
      if (hasYoutube && !YoutubeUrlHelper.isValidYoutubeUrl(youtubeRaw)) {
        _snack(YoutubeUrlHelper.validationMessage(youtubeRaw) ??
            'URL do YouTube inválida.');
        return false;
      }
    } else {
      final linkRaw = _youtubeCtrl.text.trim();
      if (linkRaw.isNotEmpty &&
          CourseContentLinkHelper.normalizeLink(linkRaw) == null) {
        _snack('Link inválido. Use YouTube ou site (https://…).');
        return false;
      }
      final body = _bodyTextCtrl.text.trim();
      final desc = _descriptionCtrl.text.trim();
      final linkOk = linkRaw.isNotEmpty;
      if (body.isEmpty && desc.isEmpty && _pickedImages.isEmpty && !linkOk) {
        _snack('Informe texto, imagem ou link para a dica.');
        return false;
      }
    }

    if (!_validityPermanent && _expiresAtDate == null) {
      _snack('Escolha a data limite ou marque como permanente.');
      return false;
    }

    _publishStateTimer?.cancel();
    setState(() {
      _savingVideo = true;
      _uploadProgress = 0;
      _publishState = 'saving';
      _uploadCancel = CourseUploadCancelToken();
    });
    onStateChanged?.call();
    var publicado = false;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final email = FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
      final docRef =
          FirebaseFirestore.instance.collection('course_videos').doc();
      final validityFields = CourseVideoValidity.firestoreFields(
        permanent: _validityPermanent,
        expiresAt: _expiresAtDate,
      );

      if (_type == 'curso') {
        final youtubeRaw = _youtubeCtrl.text.trim();
        final hasYoutube = youtubeRaw.isNotEmpty;
        final hasMp4 = _pickedVideos.isNotEmpty;

        String? videoId;
        String? youtubeUrl;
        String? thumbUrl;
        Map<String, dynamic> videoFields = {};
        Map<String, dynamic> imageFields = {};

        if (hasYoutube) {
          videoId = YoutubeUrlHelper.extractVideoId(youtubeRaw)!;
          youtubeUrl = YoutubeUrlHelper.watchUrl(videoId);
          thumbUrl = YoutubeUrlHelper.thumbnailUrl(videoId);
        }

        if (hasMp4) {
          setState(() => _uploadProgress = 0);
          onStateChanged?.call();
          final uploads = await _uploadPickedVideos(
            docRef.id,
            onProgress: (p) {
              if (!mounted) return;
              setState(() => _uploadProgress = p);
              onStateChanged?.call();
            },
          );
          videoFields = CourseMediaUrlResolver.videoFieldsFromUploads(uploads);
        }

        if (_pickedImages.isNotEmpty) {
          final uploads = await _uploadPickedImages(docRef.id);
          imageFields = CourseMediaUrlResolver.imageFieldsFromUploads(uploads);
          thumbUrl = uploads.first.downloadUrl;
        }

        final source = hasMp4 && hasYoutube
            ? 'upload_youtube'
            : (hasMp4 ? 'upload' : 'youtube');

        final docPayload = CourseMediaUrlResolver.finalizeImageFields({
          'title': title,
          'description': _descriptionCtrl.text.trim(),
          'bodyText': '',
          'type': 'curso',
          'source': source,
          ...videoFields,
          if (youtubeUrl != null) ...{
            'videoUrl': youtubeUrl,
            'youtubeUrl': youtubeUrl,
            'youtubeVideoId': videoId,
          },
          if (thumbUrl != null) 'thumbnailUrl': thumbUrl,
          ...imageFields,
          'published': _published,
          ...validityFields,
          'authorUid': uid,
          'authorEmail': email,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        await AdminCourseFirestoreBridge.upsertCourseVideo(
          docId: docRef.id,
          data: docPayload,
          create: true,
        );
      } else {
        final linkRaw = _youtubeCtrl.text.trim();
        String? linkUrl;
        String? videoId;
        String? ytThumb;
        if (linkRaw.isNotEmpty) {
          linkUrl = CourseContentLinkHelper.normalizeLink(linkRaw);
          videoId = YoutubeUrlHelper.extractVideoId(linkUrl!);
          if (videoId != null) ytThumb = YoutubeUrlHelper.thumbnailUrl(videoId);
        }
        final body = _bodyTextCtrl.text.trim();
        final desc = _descriptionCtrl.text.trim();
        Map<String, dynamic> imageFields = {};
        if (_pickedImages.isNotEmpty) {
          final uploads = await _uploadPickedImages(docRef.id);
          imageFields = CourseMediaUrlResolver.imageFieldsFromUploads(uploads);
        }
        final imageUrl = imageFields['imageUrl'] as String?;
        final source = videoId != null
            ? 'youtube'
            : (imageUrl != null && linkUrl != null)
                ? 'image_link'
                : (imageUrl != null ? 'image' : 'link');
        await AdminCourseFirestoreBridge.upsertCourseVideo(
          docId: docRef.id,
          data: CourseMediaUrlResolver.finalizeImageFields({
            'title': title,
            'description': desc,
            'bodyText': body,
            'type': 'dica',
            'source': source,
            if (linkUrl != null) ...{
              'linkUrl': linkUrl,
              'externalUrl': linkUrl,
            },
            if (videoId != null) ...{
              'videoUrl': linkUrl,
              'youtubeUrl': linkUrl,
              'youtubeVideoId': videoId,
            },
            ...imageFields,
            if (ytThumb != null) 'thumbnailUrl': ytThumb,
            'published': _published,
            ...validityFields,
            'authorUid': uid,
            'authorEmail': email,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }),
          create: true,
        );
      }

      _titleCtrl.clear();
      _descriptionCtrl.clear();
      _bodyTextCtrl.clear();
      _youtubeCtrl.clear();
      _clearPickedImages();
      _clearPickedVideos();
      setState(() {
        _validityPermanent = true;
        _expiresAtDate = null;
      });
      _autoTitle = '';
      publicado = true;
      await _afterContentMutation(
          snack: 'Conteúdo publicado — já aparece no módulo Cursos.');
      return true;
    } catch (e) {
      _snack(e is CourseUploadCancelledException
          ? 'Envio cancelado — nada foi publicado.'
          : 'Erro ao publicar: ${_formatPublishError(e)}');
      return false;
    } finally {
      _uploadCancel = null;
      if (mounted) {
        setState(() {
          _savingVideo = false;
          _uploadProgress = 0;
          _publishState = publicado ? 'done' : 'idle';
        });
        if (publicado) {
          _publishStateTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) setState(() => _publishState = 'idle');
          });
        }
        onStateChanged?.call();
      }
    }
  }

  Future<bool> _saveEditedVideo(
    String docId, {
    required String title,
    required String description,
    required String bodyText,
    required String linkRaw,
    required String type,
    required bool published,
    required bool validityPermanent,
    DateTime? expiresAtDate,
    List<_PickedMedia> newImages = const [],
    bool removeImages = false,
    List<_PickedMedia> newVideos = const [],
    bool removeVideos = false,
    void Function(double progress)? onUploadProgress,
  }) async {
    if (title.isEmpty) {
      _snack('Informe o título.');
      return false;
    }
    if (!validityPermanent && expiresAtDate == null) {
      _snack('Escolha a data limite ou marque como permanente.');
      return false;
    }

    try {
      final existing = await _courseFirestoreOp(() => FirebaseFirestore.instance
          .collection('course_videos')
          .doc(docId)
          .get());
      final existingData = existing.data() ?? {};

      if (removeVideos) {
        await CourseMediaStorageCleanup.deleteMediaFromDoc(existingData,
            videos: true);
      }
      if (removeImages) {
        await CourseMediaStorageCleanup.deleteMediaFromDoc(existingData,
            images: true);
      }

      final patch = <String, dynamic>{
        'title': title,
        'description': description,
        'bodyText': bodyText,
        'type': type,
        'published': published,
        'updatedAt': FieldValue.serverTimestamp(),
        ...CourseVideoValidity.firestoreFields(
          permanent: validityPermanent,
          expiresAt: expiresAtDate,
          forUpdate: true,
          deleteValue: AdminCourseFirestoreBridge.cfDelete,
        ),
      };

      List<CourseMediaUploadResult> uploadedImages = [];
      for (var i = 0; i < newImages.length; i++) {
        uploadedImages.add(
          await CourseVideoImageService.uploadCover(
            bytes: newImages[i].bytes!,
            mimeType: newImages[i].mime,
            docId: docId,
            index:
                CourseMediaUrlResolver.collectHttpUrls(existingData).length + i,
          ),
        );
      }

      List<CourseMediaUploadResult> uploadedVideos = [];
      for (var i = 0; i < newVideos.length; i++) {
        final v = newVideos[i];
        void reportProgress(double progress) {
          if (newVideos.isEmpty) return;
          onUploadProgress?.call((i + progress) / newVideos.length);
        }

        if (v.isFile) {
          uploadedVideos.add(
            await CourseVideoFileService.uploadVideoFile(
              file: v.file!,
              docId: docId,
              index: CourseMediaUrlResolver.collectVideoEntries(existingData)
                      .length +
                  i,
              onProgress: reportProgress,
            ),
          );
        } else {
          uploadedVideos.add(
            await CourseVideoFileService.uploadVideo(
              bytes: v.bytes!,
              mimeType: v.mime,
              docId: docId,
              index: CourseMediaUrlResolver.collectVideoEntries(existingData)
                      .length +
                  i,
              onProgress: reportProgress,
            ),
          );
        }
      }

      if (type == 'curso') {
        String? videoId;
        String? youtubeUrl;
        var thumbUrl = (existingData['thumbnailUrl'] ?? '').toString();

        if (removeVideos) {
          patch['mp4Url'] = AdminCourseFirestoreBridge.cfDelete;
          patch['mp4Urls'] = AdminCourseFirestoreBridge.cfDelete;
          patch['mp4StoragePath'] = AdminCourseFirestoreBridge.cfDelete;
        } else if (uploadedVideos.isNotEmpty) {
          patch.addAll(CourseMediaUrlResolver.mergeVideoFields(
            existing: existingData,
            newUploads: uploadedVideos,
          ));
        }

        if (linkRaw.isNotEmpty) {
          if (!YoutubeUrlHelper.isValidYoutubeUrl(linkRaw)) {
            _snack(YoutubeUrlHelper.validationMessage(linkRaw) ??
                'URL do YouTube inválida.');
            return false;
          }
          videoId = YoutubeUrlHelper.extractVideoId(linkRaw)!;
          youtubeUrl = YoutubeUrlHelper.watchUrl(videoId);
          if (!CourseMediaUrlResolver.hasResolvableImage(existingData) &&
              uploadedImages.isEmpty &&
              !removeImages) {
            thumbUrl = YoutubeUrlHelper.thumbnailUrl(videoId);
          }
        } else {
          patch['videoUrl'] = AdminCourseFirestoreBridge.cfDelete;
          patch['youtubeUrl'] = AdminCourseFirestoreBridge.cfDelete;
          patch['youtubeVideoId'] = AdminCourseFirestoreBridge.cfDelete;
        }

        final hasMp4 = removeVideos
            ? false
            : (uploadedVideos.isNotEmpty ||
                CourseMediaUrlResolver.collectVideoEntries(existingData)
                    .isNotEmpty);
        if (!hasMp4 && videoId == null) {
          _snack('Informe vídeo MP4 ou link YouTube.');
          return false;
        }

        if (removeImages) {
          patch['imageUrl'] = AdminCourseFirestoreBridge.cfDelete;
          patch['coverUrl'] = AdminCourseFirestoreBridge.cfDelete;
          patch['imageUrls'] = AdminCourseFirestoreBridge.cfDelete;
          patch['imageStoragePaths'] = AdminCourseFirestoreBridge.cfDelete;
          patch['coverStoragePath'] = AdminCourseFirestoreBridge.cfDelete;
        } else if (uploadedImages.isNotEmpty) {
          patch.addAll(CourseMediaUrlResolver.mergeImageFields(
            existing: existingData,
            newUploads: uploadedImages,
          ));
          thumbUrl = uploadedImages.first.downloadUrl;
        }

        patch['source'] = hasMp4 && videoId != null
            ? 'upload_youtube'
            : (hasMp4 ? 'upload' : 'youtube');
        if (videoId != null) {
          patch.addAll({
            'videoUrl': youtubeUrl,
            'youtubeUrl': youtubeUrl,
            'youtubeVideoId': videoId,
          });
        }
        _applyThumbnailPatch(
          patch,
          existing: existingData,
          explicitThumb: thumbUrl,
          youtubeThumb:
              videoId != null ? YoutubeUrlHelper.thumbnailUrl(videoId) : null,
        );
      } else {
        String? linkUrl;
        String? videoId;
        String? ytThumb;
        if (linkRaw.isNotEmpty) {
          linkUrl = CourseContentLinkHelper.normalizeLink(linkRaw);
          if (linkUrl == null) {
            _snack('Link inválido.');
            return false;
          }
          videoId = YoutubeUrlHelper.extractVideoId(linkUrl);
          if (videoId != null) ytThumb = YoutubeUrlHelper.thumbnailUrl(videoId);
          patch['linkUrl'] = linkUrl;
          patch['externalUrl'] = linkUrl;
          if (videoId != null) {
            patch['videoUrl'] = linkUrl;
            patch['youtubeUrl'] = linkUrl;
            patch['youtubeVideoId'] = videoId;
          } else {
            patch['videoUrl'] = AdminCourseFirestoreBridge.cfDelete;
            patch['youtubeUrl'] = AdminCourseFirestoreBridge.cfDelete;
            patch['youtubeVideoId'] = AdminCourseFirestoreBridge.cfDelete;
          }
        } else {
          patch['linkUrl'] = AdminCourseFirestoreBridge.cfDelete;
          patch['externalUrl'] = AdminCourseFirestoreBridge.cfDelete;
          patch['videoUrl'] = AdminCourseFirestoreBridge.cfDelete;
          patch['youtubeUrl'] = AdminCourseFirestoreBridge.cfDelete;
          patch['youtubeVideoId'] = AdminCourseFirestoreBridge.cfDelete;
        }

        if (removeImages) {
          patch['imageUrl'] = AdminCourseFirestoreBridge.cfDelete;
          patch['coverUrl'] = AdminCourseFirestoreBridge.cfDelete;
          patch['imageUrls'] = AdminCourseFirestoreBridge.cfDelete;
          patch['imageStoragePaths'] = AdminCourseFirestoreBridge.cfDelete;
          patch['coverStoragePath'] = AdminCourseFirestoreBridge.cfDelete;
        } else if (uploadedImages.isNotEmpty) {
          patch.addAll(CourseMediaUrlResolver.mergeImageFields(
            existing: existingData,
            newUploads: uploadedImages,
            replaceAll: removeImages,
          ));
        }

        final patchedImageUrl = patch['imageUrl'];
        final imageUrl = (patchedImageUrl is String &&
                patchedImageUrl != AdminCourseFirestoreBridge.cfDelete)
            ? patchedImageUrl
            : (removeImages
                ? null
                : (CourseMediaUrlResolver.collectHttpUrls(existingData).isEmpty
                    ? null
                    : CourseMediaUrlResolver.collectHttpUrls(existingData)
                        .first));
        patch['source'] = videoId != null
            ? 'youtube'
            : (imageUrl != null && linkUrl != null)
                ? 'image_link'
                : (imageUrl != null
                    ? 'image'
                    : (linkUrl != null ? 'link' : 'text'));
        _applyThumbnailPatch(
          patch,
          existing: existingData,
          explicitThumb: imageUrl,
          youtubeThumb: ytThumb,
        );
        if (imageUrl != null && imageUrl.isNotEmpty) {
          patch['coverUrl'] = imageUrl;
        }
      }

      await AdminCourseFirestoreBridge.upsertCourseVideo(
        docId: docId,
        data: patch,
        create: false,
      );
      await _afterContentMutation();
      return true;
    } catch (e) {
      _snack('Erro ao salvar: ${_formatPublishError(e)}');
      return false;
    }
  }

  Future<void> _togglePublished(String docId, bool value) async {
    await AdminCourseFirestoreBridge.upsertCourseVideo(
      docId: docId,
      data: {
        'published': value,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      create: false,
    );
    unawaited(_afterContentMutation());
  }

  Future<void> _deleteVideo(String docId, {bool skipConfirm = false}) async {
    if (!skipConfirm) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Excluir conteúdo?'),
          content: const Text(
            'Remove do módulo Cursos e apaga arquivos no Storage. Esta ação não pode ser desfeita.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Excluir'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      final snap = await _courseFirestoreOp(() => FirebaseFirestore.instance
          .collection('course_videos')
          .doc(docId)
          .get());
      await CourseMediaStorageCleanup.deleteForCourseDoc(
        docId,
        data: snap.data(),
      );
      await AdminCourseFirestoreBridge.deleteCourseVideos([docId]);
      await _afterContentMutation(snack: 'Conteúdo excluído.');
    } catch (e) {
      _snack('Erro ao excluir: $e');
    }
  }

  Future<void> _openEditSheet(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    final titleCtrl =
        TextEditingController(text: (data['title'] ?? '').toString());
    final descCtrl =
        TextEditingController(text: (data['description'] ?? '').toString());
    final bodyCtrl =
        TextEditingController(text: (data['bodyText'] ?? '').toString());
    final urlCtrl = TextEditingController(
      text: (data['linkUrl'] ??
              data['externalUrl'] ??
              data['youtubeUrl'] ??
              data['videoUrl'] ??
              '')
          .toString(),
    );
    var type = (data['type'] ?? 'curso').toString();
    var published = data['published'] != false;
    var validityPermanent = CourseVideoValidity.isPermanent(data);
    var expiresAtDate = CourseVideoValidity.expiresAtDay(data);
    final existingData = CourseMediaUrlResolver.enrichWithDocId(
      Map<String, dynamic>.from(data),
      doc.id,
    );
    final List<_PickedMedia> editImages = [];
    final List<_PickedMedia> editVideos = [];
    var removeImages = false;
    var removeVideos = false;
    var saving = false;
    var editUploadProgress = 0.0;

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final accent = type == 'dica'
                ? const Color(0xFFF59E0B)
                : const Color(0xFF2563EB);
            final accent2 = type == 'dica'
                ? const Color(0xFFD97706)
                : const Color(0xFF1D4ED8);
            final isDica = type == 'dica';
            final navBottom = MediaQuery.viewPaddingOf(ctx).bottom;
            return Padding(
              padding:
                  EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
              child: Container(
                margin: EdgeInsets.fromLTRB(10, 0, 10, 10 + navBottom),
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(ctx).height * 0.94),
                decoration: BoxDecoration(
                  color: ctx.isDarkMode ? ctx.appScaffold : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.2),
                      blurRadius: 24,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                      child: CourseContentSheetHeader(
                        title: 'EDITAR CONTEÚDO',
                        subtitle: isDica
                            ? 'Dica · módulo Cursos'
                            : 'Curso · módulo Cursos',
                        accent: accent,
                        accent2: accent2,
                        icon: isDica
                            ? Icons.lightbulb_rounded
                            : Icons.school_rounded,
                        onBack: saving ? () {} : () => Navigator.pop(ctx),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FastTextField(
                                controller: titleCtrl,
                                decoration:
                                    _fieldDeco('Título', accent: accent)),
                            const SizedBox(height: 10),
                            FastTextField(
                              controller: descCtrl,
                              decoration: _fieldDeco(
                                isDica
                                    ? 'Resumo curto'
                                    : 'Descrição completa do curso',
                                hint: isDica
                                    ? null
                                    : 'Explique o conteúdo, objetivo e o que o aluno aprenderá.',
                                accent: accent,
                              ),
                              kind: FastTextFieldKind.multiline,
                              maxLines: isDica ? 3 : 8,
                            ),
                            if (isDica) ...[
                              const SizedBox(height: 10),
                              FastTextField(
                                controller: bodyCtrl,
                                decoration: _fieldDeco(
                                  'Texto completo da dica',
                                  hint:
                                      'Conteúdo maior exibido ao abrir a dica…',
                                  accent: accent,
                                ),
                                kind: FastTextFieldKind.multiline,
                                maxLines: 8,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Galeria de fotos (até ${CourseMediaUrlResolver.maxGalleryPhotos})',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, color: accent),
                              ),
                              const SizedBox(height: 8),
                              if (!removeImages &&
                                  CourseMediaUrlResolver.hasResolvableImage(
                                      existingData))
                                CoursePhotoGallery(
                                    data: existingData, height: 180),
                              for (var i = 0; i < editImages.length; i++)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: CourseImagePreview(
                                    bytes: editImages[i].bytes,
                                    maxHeight: 120,
                                    subtitle: editImages[i].name ?? 'Nova foto',
                                  ),
                                ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      final pick =
                                          await FilePicker.platform.pickFiles(
                                        type: FileType.custom,
                                        allowedExtensions: [
                                          'jpg',
                                          'jpeg',
                                          'png',
                                          'webp'
                                        ],
                                        withData: true,
                                        allowMultiple: true,
                                      );
                                      if (pick == null || pick.files.isEmpty) {
                                        return;
                                      }
                                      setLocal(() {
                                        removeImages = false;
                                        for (final f in pick.files) {
                                          if (editImages.length >=
                                              CourseMediaUrlResolver
                                                  .maxGalleryPhotos) {
                                            break;
                                          }
                                          final bytes = f.bytes;
                                          if (bytes == null) continue;
                                          var ext = (f.extension ?? 'jpg')
                                              .toLowerCase();
                                          if (ext == 'jpeg') ext = 'jpg';
                                          editImages.add(_PickedMedia(
                                            bytes: bytes,
                                            mime: ext == 'png'
                                                ? 'image/png'
                                                : (ext == 'webp'
                                                    ? 'image/webp'
                                                    : 'image/jpeg'),
                                            name: f.name,
                                          ));
                                        }
                                      });
                                    },
                                    icon: const Icon(
                                        Icons.add_photo_alternate_rounded,
                                        size: 18),
                                    label: const Text('Adicionar fotos'),
                                  ),
                                  if (!removeImages &&
                                      CourseMediaUrlResolver.hasResolvableImage(
                                          existingData))
                                    OutlinedButton.icon(
                                      onPressed: () =>
                                          setLocal(() => removeImages = true),
                                      icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 18),
                                      label: const Text('Remover galeria'),
                                    ),
                                ],
                              ),
                            ] else ...[
                              const SizedBox(height: 14),
                              // Seção de vídeo estilo YouTube (edição)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _Yt.bg(ctx),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color:
                                          _Yt.line(ctx)),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(5),
                                          decoration: BoxDecoration(
                                            color: Colors.red
                                                .withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: const Icon(
                                              Icons.smart_display_rounded,
                                              color: Color(0xFFEF4444),
                                              size: 18),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Vídeos do curso',
                                            style: TextStyle(
                                              color: _Yt.fg(ctx),
                                              fontWeight: FontWeight.w900,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    if (!removeVideos) ...[
                                      for (final v in CourseMediaUrlResolver
                                          .collectVideoEntries(existingData))
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 6),
                                          child: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: _Yt.card(ctx),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(Icons.videocam_rounded,
                                                    color: _Yt.fgA(ctx, 0.5),
                                                    size: 18),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    v.label ??
                                                        'Vídeo publicado',
                                                    style: TextStyle(
                                                        color: _Yt.fgA(ctx, 0.7),
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                    for (var i = 0; i < editVideos.length; i++)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 6),
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: _Yt.card(ctx),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(Icons.movie_rounded,
                                                  color: accent.withValues(
                                                      alpha: 0.7),
                                                  size: 18),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  editVideos[i].name ??
                                                      'video_${i + 1}.mp4',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                      color: _Yt.fg(ctx),
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w700),
                                                ),
                                              ),
                                              InkWell(
                                                onTap: () => setLocal(() =>
                                                    editVideos.removeAt(i)),
                                                child: Padding(
                                                  padding: EdgeInsets.all(4),
                                                  child: Icon(
                                                      Icons.close_rounded,
                                                      color: _Yt.fgA(ctx, 0.54),
                                                      size: 16),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    if (saving && editVideos.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(99),
                                        child: LinearProgressIndicator(
                                          value: editUploadProgress > 0
                                              ? editUploadProgress
                                              : null,
                                          minHeight: 6,
                                          color: const Color(0xFFEF4444),
                                          backgroundColor: _Yt.line(ctx),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        editUploadProgress > 0
                                            ? 'Enviando vídeo… ${(editUploadProgress * 100).toStringAsFixed(0)}%'
                                            : 'Preparando vídeo para envio…',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Color(0xFFEF4444),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildVideoActionButton(
                                            icon: Icons.videocam_rounded,
                                            label: 'Gravar vídeo',
                                            color: const Color(0xFFEF4444),
                                            onTap: () async {
                                              final picker = ImagePicker();
                                              final video =
                                                  await picker.pickVideo(
                                                source: ImageSource.camera,
                                                maxDuration:
                                                    const Duration(minutes: 10),
                                              );
                                              if (video == null) return;
                                              final file = File(video.path);
                                              final size = await file.length();
                                              final ext = video.path
                                                      .toLowerCase()
                                                      .endsWith('.mov')
                                                  ? 'mov'
                                                  : 'mp4';
                                              final mime = ext == 'mov'
                                                  ? 'video/quicktime'
                                                  : 'video/mp4';
                                              setLocal(() {
                                                removeVideos = false;
                                                editVideos.add(_PickedMedia(
                                                  file: file,
                                                  mime: mime,
                                                  name: video.name,
                                                  sizeBytes: size,
                                                ));
                                              });
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _buildVideoActionButton(
                                            icon: Icons.upload_file_rounded,
                                            label: 'Arquivo',
                                            color: const Color(0xFF3B82F6),
                                            onTap: () async {
                                              final pick = await FilePicker
                                                  .platform
                                                  .pickFiles(
                                                type: FileType.custom,
                                                allowedExtensions: [
                                                  'mp4',
                                                  'mov',
                                                  'webm'
                                                ],
                                                withData: kIsWeb,
                                                allowMultiple: true,
                                              );
                                              if (pick == null ||
                                                  pick.files.isEmpty) {
                                                return;
                                              }
                                              setLocal(() {
                                                removeVideos = false;
                                                for (final f in pick.files) {
                                                  if (editVideos.length >=
                                                      CourseMediaUrlResolver
                                                          .maxCourseVideos) {
                                                    break;
                                                  }
                                                  var ext =
                                                      (f.extension ?? 'mp4')
                                                          .toLowerCase();
                                                  final mime = ext == 'webm'
                                                      ? 'video/webm'
                                                      : (ext == 'mov'
                                                          ? 'video/quicktime'
                                                          : 'video/mp4');
                                                  if (kIsWeb) {
                                                    final bytes = f.bytes;
                                                    if (bytes == null) continue;
                                                    editVideos.add(_PickedMedia(
                                                      bytes: bytes,
                                                      mime: mime,
                                                      name: f.name,
                                                      sizeBytes:
                                                          bytes.lengthInBytes,
                                                    ));
                                                  } else {
                                                    final path = f.path;
                                                    if (path == null) continue;
                                                    editVideos.add(_PickedMedia(
                                                      file: File(path),
                                                      mime: mime,
                                                      name: f.name,
                                                    ));
                                                  }
                                                }
                                              });
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (!removeVideos &&
                                        CourseMediaUrlResolver
                                                .collectVideoEntries(
                                                    existingData)
                                            .isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      _buildVideoActionButton(
                                        icon: Icons.delete_sweep_rounded,
                                        label: 'Remover vídeos existentes',
                                        color: Colors.red.shade400,
                                        onTap: () =>
                                            setLocal(() => removeVideos = true),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Capa / galeria (até ${CourseMediaUrlResolver.maxGalleryPhotos} fotos)',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, color: accent),
                              ),
                              const SizedBox(height: 8),
                              if (!removeImages &&
                                  CourseMediaUrlResolver.hasResolvableImage(
                                      existingData))
                                CoursePhotoGallery(
                                    data: existingData, height: 140),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final pick =
                                      await FilePicker.platform.pickFiles(
                                    type: FileType.custom,
                                    allowedExtensions: [
                                      'jpg',
                                      'jpeg',
                                      'png',
                                      'webp'
                                    ],
                                    withData: true,
                                    allowMultiple: true,
                                  );
                                  if (pick == null || pick.files.isEmpty) {
                                    return;
                                  }
                                  setLocal(() {
                                    removeImages = false;
                                    for (final f in pick.files) {
                                      if (editImages.length >=
                                          CourseMediaUrlResolver
                                              .maxGalleryPhotos) {
                                        break;
                                      }
                                      final bytes = f.bytes;
                                      if (bytes == null) continue;
                                      var ext =
                                          (f.extension ?? 'jpg').toLowerCase();
                                      if (ext == 'jpeg') ext = 'jpg';
                                      editImages.add(_PickedMedia(
                                        bytes: bytes,
                                        mime: ext == 'png'
                                            ? 'image/png'
                                            : 'image/jpeg',
                                        name: f.name,
                                      ));
                                    }
                                  });
                                },
                                icon: const Icon(Icons.image_rounded, size: 18),
                                label: const Text('Adicionar capa / fotos'),
                              ),
                            ],
                            const SizedBox(height: 10),
                            FastTextField(
                              controller: urlCtrl,
                              decoration: _fieldDeco(
                                isDica
                                    ? 'Link (YouTube ou site)'
                                    : 'Link YouTube (opcional)',
                                hint: isDica
                                    ? 'https://youtube.com/… ou https://seusite.com/…'
                                    : 'https://www.youtube.com/watch?v=...',
                                accent: accent,
                              ),
                              kind: FastTextFieldKind.url,
                            ),
                            const SizedBox(height: 12),
                            _TypePillSelector(
                                value: type,
                                onChanged: (v) => setLocal(() => type = v)),
                            const SizedBox(height: 8),
                            _buildValiditySection(
                              permanent: validityPermanent,
                              expiresAt: expiresAtDate,
                              onPermanentChanged: (v) => setLocal(() {
                                validityPermanent = v;
                                if (v) expiresAtDate = null;
                              }),
                              onDateChanged: (d) =>
                                  setLocal(() => expiresAtDate = d),
                              accent: accent,
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Publicado no módulo Cursos'),
                              value: published,
                              activeThumbColor: accent,
                              onChanged: (v) => setLocal(() => published = v),
                            ),
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      setLocal(() {
                                        saving = true;
                                        editUploadProgress = 0;
                                      });
                                      final ok = await _saveEditedVideo(
                                        doc.id,
                                        title: titleCtrl.text.trim(),
                                        description: descCtrl.text.trim(),
                                        bodyText: bodyCtrl.text.trim(),
                                        linkRaw: urlCtrl.text.trim(),
                                        type: type,
                                        published: published,
                                        validityPermanent: validityPermanent,
                                        expiresAtDate: expiresAtDate,
                                        newImages:
                                            List<_PickedMedia>.from(editImages),
                                        removeImages: removeImages,
                                        newVideos:
                                            List<_PickedMedia>.from(editVideos),
                                        removeVideos: removeVideos,
                                        onUploadProgress: (progress) {
                                          if (ctx.mounted) {
                                            setLocal(() =>
                                                editUploadProgress = progress);
                                          }
                                        },
                                      );
                                      if (!ctx.mounted) return;
                                      if (ok) {
                                        Navigator.pop(ctx);
                                        if (mounted) {
                                          _snack('Alterações salvas.');
                                        }
                                      } else {
                                        setLocal(() => saving = false);
                                      }
                                    },
                              icon: saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.save_rounded),
                              label: Text(
                                  saving ? 'Salvando…' : 'Salvar alterações'),
                              style: FilledButton.styleFrom(
                                backgroundColor: accent,
                                minimumSize: const Size(double.infinity, 48),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      final confirm = await showDialog<bool>(
                                        context: ctx,
                                        builder: (dCtx) => AlertDialog(
                                          title: Text(
                                              'Excluir ${isDica ? 'dica' : 'curso'}?'),
                                          content: const Text(
                                            'Remove permanentemente do módulo Cursos e apaga arquivos no Storage.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(dCtx, false),
                                              child: const Text('Cancelar'),
                                            ),
                                            FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(dCtx, true),
                                              style: FilledButton.styleFrom(
                                                  backgroundColor: Colors.red),
                                              child: const Text('Excluir'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm != true) return;
                                      if (ctx.mounted) Navigator.pop(ctx);
                                      await _deleteVideo(doc.id,
                                          skipConfirm: true);
                                    },
                              icon: const Icon(Icons.delete_forever_rounded),
                              label:
                                  Text('Excluir ${isDica ? 'dica' : 'curso'}'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                                side: BorderSide(color: Colors.red.shade300),
                                minimumSize: const Size(double.infinity, 46),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    titleCtrl.dispose();
    descCtrl.dispose();
    bodyCtrl.dispose();
    urlCtrl.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Nunca grava [thumbnailUrl] vazio — prioriza imagens do patch/Firestore, depois YouTube.
  void _applyThumbnailPatch(
    Map<String, dynamic> patch, {
    required Map<String, dynamic> existing,
    String? explicitThumb,
    String? youtubeThumb,
  }) {
    final merged = <String, dynamic>{...existing};
    patch.forEach((key, value) {
      // Ignora deleções (FieldValue ou sentinel da Cloud Function).
      if (value is FieldValue) return;
      if (value == AdminCourseFirestoreBridge.cfDelete) return;
      merged[key] = value;
    });
    final urls = CourseMediaUrlResolver.collectHttpUrls(merged);
    if (urls.isNotEmpty) {
      patch['thumbnailUrl'] = urls.first;
      return;
    }
    final thumb = explicitThumb?.trim();
    if (thumb != null && thumb.isNotEmpty) {
      patch['thumbnailUrl'] = thumb;
      return;
    }
    final yt = youtubeThumb?.trim();
    if (yt != null && yt.isNotEmpty) {
      patch['thumbnailUrl'] = yt;
      return;
    }
    patch['thumbnailUrl'] = AdminCourseFirestoreBridge.cfDelete;
  }

  String _formatPublishError(Object e) {
    if (FirestoreWebGuard.isRecoverableFirestoreWebError(e)) {
      return 'Instabilidade do Firestore na Web. Toque em Publicar de novo '
          'ou atualize a página (F5).';
    }
    if (e is FirebaseFunctionsException) {
      switch (e.code) {
        case 'permission-denied':
          return 'Sem permissão para gravar cursos. A conta precisa ser '
              'admin, master ou gestor (campo role no cadastro).';
        case 'unauthenticated':
          return 'Sessão expirada. Saia e entre de novo no painel.';
        case 'not-found':
          return 'Função de gravação de cursos não publicada no servidor '
              '(ctAdminUpsertCourseVideo). Faça o deploy das functions.';
        case 'invalid-argument':
          return 'Dados inválidos: ${e.message ?? 'verifique os campos'}.';
        case 'deadline-exceeded':
        case 'unavailable':
          return 'Servidor demorou a responder. Tente de novo em instantes.';
      }
      final m = (e.message ?? '').trim();
      if (m.isNotEmpty) return '${e.code}: $m';
    }
    final msg = e.toString().split('\n').first.trim();
    return msg.length > 180 ? '${msg.substring(0, 180)}…' : msg;
  }

  Future<T> _courseFirestoreOp<T>(Future<T> Function() fn) async {
    if (kIsWeb) {
      return runFirestoreWithRetry(
        () => FirestoreWebGuard.runFirestoreOpSafe(fn),
      );
    }
    return runFirestoreWithRetry(fn);
  }

  String? _videoId(Map<String, dynamic> data) {
    return YoutubeUrlHelper.videoIdFromData(data);
  }

  String? _thumbUrl(Map<String, dynamic> data) =>
      CourseThumbResolver.resolveBest(data);

  String? _mp4Url(Map<String, dynamic> data) {
    final u = (data['mp4Url'] ?? '').toString().trim();
    return u.isEmpty ? null : u;
  }

  Future<void> _openContentPreview(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = CourseMediaUrlResolver.enrichWithDocId(doc.data(), doc.id);
    final type = (data['type'] ?? 'curso').toString();
    if (CourseMediaUrlResolver.collectVideoEntries(data).isNotEmpty ||
        _mp4Url(data) != null ||
        _videoId(data) != null) {
      await openCourseVideoFromData(context, data: data);
      return;
    }
    final link =
        (data['linkUrl'] ?? data['externalUrl'] ?? '').toString().trim();
    if (link.isNotEmpty && CourseContentLinkHelper.isValidHttpUrl(link)) {
      final uri = Uri.parse(link.startsWith('http') ? link : 'https://$link');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }
    if (type == 'dica') {
      final body = (data['bodyText'] ?? data['description'] ?? '').toString();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.78,
          minChildSize: 0.45,
          maxChildSize: 0.96,
          builder: (_, scroll) => Container(
            decoration: BoxDecoration(
              color: _Yt.bg(ctx),
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _Yt.line(ctx),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'DICA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  (data['title'] ?? '').toString(),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: _Yt.fg(ctx),
                  ),
                ),
                if (CourseMediaUrlResolver.hasResolvableImage(data)) ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: CoursePhotoGallery(
                      data: data,
                      height: 240,
                      accent: const Color(0xFFF59E0B),
                    ),
                  ),
                ],
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _Yt.card(ctx),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _Yt.line(ctx),
                      ),
                    ),
                    child: Text(
                      body,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.5,
                        color: _Yt.fgA(ctx, 0.8),
                        fontWeight: FontWeight.w500,
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _configStream,
      builder: (context, cfgSnap) {
        _hydrateConfig(cfgSnap.data?.data());

        if (_courseDocsError != null && _courseDocs.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Erro: ${AdminLoadGuard.mensagem(_courseDocsError)}',
                  style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _reloadCourseVideos,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
              ),
            ],
          );
        }

        final docs = _filterDocs(_sortDocs(_courseDocs));
        final allCount = _sortDocs(_courseDocs).length;
        final dicasCount = _sortDocs(_courseDocs)
            .where((d) => (d.data()['type'] ?? '').toString() == 'dica')
            .length;
        final cursosCount = allCount - dicasCount;
        final syncing = _courseDocsLoading && _courseDocs.isEmpty;
        final titleMap = <String, String>{
          for (final d in _courseDocs)
            d.id: (d.data()['title'] ?? 'Conteúdo').toString(),
        };

        return StreamBuilder<List<CourseStatSummary>>(
          stream: _statsStream,
          builder: (context, statsSnap) {
            final stats = statsSnap.data ?? const <CourseStatSummary>[];
            final statsById = {
              for (final s in stats) s.courseId: s,
            };

            return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            const ModuleHeaderPremium(
              title: 'Cursos e Dicas',
              icon: Icons.ondemand_video_rounded,
              subtitle:
                  'Publique conteúdos, acompanhe quem assistiu e quantos curtiram — visual alinhado ao app.',
            ),
            const SizedBox(height: 16),
            _buildQuickPublishCard(),
            const SizedBox(height: 16),
            if (!widget.somenteVideos) ...[
              CourseAdminAnalyticsPanel(
                stats: stats,
                courseTitles: titleMap,
                error: statsSnap.hasError ? statsSnap.error : null,
                onOpenViewers: (id, title) => showCourseViewersSheet(
                  context,
                  courseId: id,
                  title: title,
                ),
              ),
              const SizedBox(height: 16),
              _buildConfigCard(),
              const SizedBox(height: 16),
            ],
            _buildNewContentLauncher(),
            const SizedBox(height: 22),
            _buildGridToolbar(allCount, cursosCount, dicasCount),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: _Yt.bg(context),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _Yt.line(context)),
              ),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.smart_display_rounded,
                          color: Color(0xFFFF0000), size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Biblioteca YouTube (${docs.length}${docs.length != allCount ? ' / $allCount' : ''})',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: _Yt.fg(context),
                          ),
                        ),
                      ),
                      if (_selectionMode) ...[
                        TextButton.icon(
                          onPressed: docs.isEmpty
                              ? null
                              : () => setState(() {
                                    if (_selectedIds.length == docs.length) {
                                      _selectedIds.clear();
                                    } else {
                                      _selectedIds
                                        ..clear()
                                        ..addAll(docs.map((d) => d.id));
                                    }
                                  }),
                          icon: Icon(
                            _selectedIds.length == docs.length &&
                                    docs.isNotEmpty
                                ? Icons.deselect_rounded
                                : Icons.select_all_rounded,
                            size: 18,
                          ),
                          label: Text(
                            _selectedIds.length == docs.length &&
                                    docs.isNotEmpty
                                ? 'Desmarcar'
                                : 'Todos',
                          ),
                          style: TextButton.styleFrom(
                              foregroundColor: _Yt.fgA(context, 0.7)),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            _selectionMode = false;
                            _selectedIds.clear();
                          }),
                          child: Text('Cancelar',
                              style: TextStyle(color: _Yt.fgA(context, 0.7))),
                        ),
                      ] else ...[
                        IconButton(
                          tooltip: _compactList
                              ? 'Ver como cards grandes'
                              : 'Ver lista compacta',
                          onPressed: () =>
                              setState(() => _compactList = !_compactList),
                          icon: Icon(
                            _compactList
                                ? Icons.view_agenda_rounded
                                : Icons.view_list_rounded,
                            color: _Yt.fgA(context, 0.7),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Seleção em lote',
                          onPressed: () =>
                              setState(() => _selectionMode = true),
                          icon: Icon(Icons.checklist_rounded,
                              color: _Yt.fgA(context, 0.7)),
                        ),
                      ],
                    ],
                  ),
                  if (syncing)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        color: Colors.red.shade400,
                        backgroundColor: _Yt.line(context),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (docs.isEmpty)
                    _emptyGrid(syncing)
                  else if (_compactList)
                    _buildCompactList(docs, statsById)
                  else
                    _buildVideoGrid(docs, statsById),
                  if (_selectionMode && _selectedIds.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          Text(
                            '${_selectedIds.length} selecionado(s)',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: _Yt.fg(context),
                            ),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: _deleteSelected,
                            icon: const Icon(Icons.delete_sweep_rounded),
                            label: const Text('Excluir selecionados'),
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.red.shade700),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
            );
          },
        );
      },
    );
  }

  Widget _buildGridToolbar(int all, int cursos, int dicas) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _gridTabChip('Todos ($all)', 0),
              const SizedBox(width: 8),
              _gridTabChip('Cursos ($cursos)', 1),
              const SizedBox(width: 8),
              _gridTabChip('Dicas ($dicas)', 2),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Pesquisar título ou texto…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: context.isDarkMode ? context.appInputFill : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _dateFilter,
              items: const [
                DropdownMenuItem(value: 'recent', child: Text('Mais recentes')),
                DropdownMenuItem(value: 'oldest', child: Text('Mais antigos')),
                DropdownMenuItem(value: 'today', child: Text('Hoje')),
                DropdownMenuItem(value: 'week', child: Text('7 dias')),
                DropdownMenuItem(value: 'month', child: Text('Este mês')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _dateFilter = v);
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _gridTabChip(String label, int index) {
    final sel = _gridTab == index;
    return FilterChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) => setState(() {
        _gridTab = index;
        _selectedIds.clear();
      }),
      selectedColor: AppColors.primary.withValues(alpha: 0.15),
      checkmarkColor: AppColors.primary,
    );
  }

  Widget _emptyGrid(bool syncing) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: _Yt.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Yt.line(context)),
      ),
      child: Column(
        children: [
          Icon(Icons.video_library_outlined,
              size: 48, color: _Yt.fgA(context, 0.5)),
          const SizedBox(height: 12),
          Text(
            syncing ? 'A carregar…' : 'Nenhum vídeo na biblioteca.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _Yt.fgA(context, 0.6),
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoGrid(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Map<String, CourseStatSummary> statsById,
  ) {
    // Feed vertical alinhado ao módulo do app (cards YouTube 16:9).
    return Column(
      children: [
        for (var i = 0; i < docs.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          _VideoGridCard(
            doc: docs[i],
            index: i,
            thumbUrl: _thumbUrl(docs[i].data()),
            videoId: _videoId(docs[i].data()),
            hasMp4: _mp4Url(docs[i].data()) != null,
            selectionMode: _selectionMode,
            selected: _selectedIds.contains(docs[i].id),
            feedStyle: true,
            viewCount: statsById[docs[i].id]?.viewCount ?? 0,
            likeCount: statsById[docs[i].id]?.likeCount ?? 0,
            onTap: () {
              if (_selectionMode) {
                setState(() {
                  if (_selectedIds.contains(docs[i].id)) {
                    _selectedIds.remove(docs[i].id);
                  } else {
                    _selectedIds.add(docs[i].id);
                  }
                });
              } else {
                _openContentPreview(docs[i]);
              }
            },
            onLongPress: () => setState(() {
              _selectionMode = true;
              _selectedIds.add(docs[i].id);
            }),
            onPreview: () => _openContentPreview(docs[i]),
            onEdit: () => _openEditSheet(docs[i]),
            onTogglePublished: (v) => _togglePublished(docs[i].id, v),
            onDelete: () => _deleteVideo(docs[i].id),
            onOpenStats: () => showCourseViewersSheet(
              context,
              courseId: docs[i].id,
              title: (docs[i].data()['title'] ?? 'Conteúdo').toString(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildConfigCard() {
    return Container(
      decoration: BoxDecoration(
        color: context.isDarkMode ? context.appSurface : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.isDarkMode ? context.appChipIdleBorder : Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'CONFIGURAÇÃO DO MÓDULO',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
              letterSpacing: 0.5,
              color: context.isDarkMode ? context.appTextSecondary : const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 12),
          FastTextField(
              controller: _heroTitleCtrl,
              decoration: _fieldDeco('Título do hero')),
          const SizedBox(height: 8),
          FastTextField(
            controller: _heroMessageCtrl,
            decoration: _fieldDeco('Mensagem de destaque'),
            kind: FastTextFieldKind.multiline,
            maxLines: 3,
          ),
          const SizedBox(height: 8),
          FastTextField(
            controller: _sectionTitleCtrl,
            decoration: _fieldDeco('Título da lista de vídeos'),
          ),
          const SizedBox(height: 8),
          FastTextField(
            controller: _emptyMessageCtrl,
            decoration: _fieldDeco('Mensagem quando não há vídeos'),
            maxLines: 2,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Separar dicas e cursos'),
            subtitle: const Text('Exibe abas «Cursos» e «Dicas» no módulo.'),
            value: _showTipsSection,
            onChanged: (v) => setState(() => _showTipsSection = v),
          ),
          FilledButton.icon(
            onPressed: _savingConfig ? null : _saveModuleConfig,
            icon: _savingConfig
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_rounded),
            label: Text(_savingConfig ? 'Salvando…' : 'Salvar configuração'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF475569),
              minimumSize: const Size(double.infinity, 46),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openCreateSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final accent = _type == 'dica'
                ? const Color(0xFFF59E0B)
                : const Color(0xFF2563EB);
            final accent2 = _type == 'dica'
                ? const Color(0xFFD97706)
                : const Color(0xFF1D4ED8);
            final navBottom = MediaQuery.viewPaddingOf(ctx).bottom;
            return Padding(
              padding:
                  EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
              child: Container(
                margin: EdgeInsets.fromLTRB(10, 0, 10, 10 + navBottom),
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(ctx).height * 0.94),
                decoration: BoxDecoration(
                  color: ctx.isDarkMode ? ctx.appScaffold : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.2),
                      blurRadius: 28,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                      child: CourseContentSheetHeader(
                        title: 'NOVO CONTEÚDO',
                        subtitle: _type == 'dica'
                            ? 'Publicar dica'
                            : 'Publicar curso',
                        accent: accent,
                        accent2: accent2,
                        icon: _type == 'dica'
                            ? Icons.lightbulb_rounded
                            : Icons.school_rounded,
                        onBack: _savingVideo ? () {} : () => Navigator.pop(ctx),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                        child: _buildPublishFormColumn(
                          onStateChanged: () {
                            if (ctx.mounted) setSheetState(() {});
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + navBottom),
                      child: FilledButton.icon(
                        onPressed: _savingVideo
                            ? null
                            : () async {
                                final ok = await _publishVideo(
                                  onStateChanged: () {
                                    if (ctx.mounted) setSheetState(() {});
                                  },
                                );
                                if (ok && ctx.mounted) Navigator.pop(ctx);
                              },
                        icon: _savingVideo
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(_type == 'dica'
                                ? Icons.lightbulb_rounded
                                : Icons.smart_display_rounded),
                        label: Text(
                          _savingVideo
                              ? 'Enviando e publicando…'
                              : (_type == 'dica'
                                  ? 'Gravar e publicar dica'
                                  : 'Gravar e publicar curso'),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Envio rápido ─────────────────────────────────────────────────────

  Future<void> _pasteLink() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final t = data?.text?.trim() ?? '';
      if (t.isEmpty) {
        _snack('A área de transferência está vazia.');
        return;
      }
      _youtubeCtrl.text = t;
      _youtubeCtrl.selection =
          TextSelection.collapsed(offset: _youtubeCtrl.text.length);
      _linkDebounce?.cancel();
      await _resolveQuickLink();
    } catch (_) {
      _snack('Não foi possível colar. Use Ctrl+V / segure e cole no campo.');
    }
  }

  void _clearQuickForm() {
    _youtubeCtrl.clear();
    _titleCtrl.clear();
    _descriptionCtrl.clear();
    _bodyTextCtrl.clear();
    _clearPickedImages();
    _clearPickedVideos();
    setState(() {
      _autoTitle = '';
      _quickVideoId = null;
      _quickInfo = null;
      _validityPermanent = true;
      _expiresAtDate = null;
      _published = true;
    });
  }

  String _mb(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).toStringAsFixed(0)} KB';

  Widget _buildQuickPublishCard() {
    final isDica = _type == 'dica';
    final accent = isDica ? const Color(0xFFF59E0B) : const Color(0xFFEF4444);
    final link = _youtubeCtrl.text.trim();
    final linkError = (!isDica && link.isNotEmpty && _quickVideoId == null)
        ? YoutubeUrlHelper.validationMessage(link)
        : null;
    final saving = _savingVideo;
    final done = _publishState == 'done';

    return Container(
      decoration: BoxDecoration(
        color: context.isDarkMode ? context.appSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabeçalho com gradiente discreto
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accent.withValues(alpha: 0.14),
                  accent.withValues(alpha: 0.03),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accent, accent.withValues(alpha: 0.75)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.bolt_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isDica ? 'Publicar dica rápida' : 'Publicar curso',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: context.isDarkMode ? context.appTextPrimary : const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        isDica
                            ? 'Título, texto e (se quiser) link ou imagem'
                            : 'Envie os vídeos, a capa e a descrição — link do YouTube é opcional',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.isDarkMode ? context.appTextSecondary : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!saving &&
                    (link.isNotEmpty ||
                        _titleCtrl.text.trim().isNotEmpty ||
                        _pickedVideos.isNotEmpty ||
                        _pickedImages.isNotEmpty))
                  IconButton(
                    tooltip: 'Limpar',
                    onPressed: _clearQuickForm,
                    icon: const Icon(Icons.restart_alt_rounded),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TypePillSelector(
                  value: _type,
                  onChanged: saving ? (_) {} : (v) => setState(() => _type = v),
                ),
                const SizedBox(height: 12),
                if (isDica) ...[
                // 1) Link
                TextField(
                  controller: _youtubeCtrl,
                  enabled: !saving,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: isDica
                        ? 'Link (YouTube ou site) — opcional'
                        : 'Link do YouTube',
                    hintText: 'https://youtu.be/… ou youtube.com/watch?v=…',
                    prefixIcon: Icon(Icons.link_rounded, color: accent),
                    suffixIcon: link.isEmpty
                        ? IconButton(
                            tooltip: 'Colar',
                            onPressed: saving ? null : _pasteLink,
                            icon: const Icon(Icons.content_paste_rounded),
                          )
                        : IconButton(
                            tooltip: 'Apagar link',
                            onPressed: saving ? null : () => _youtubeCtrl.clear(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                    errorText: linkError,
                    errorMaxLines: 3,
                    filled: true,
                    fillColor: context.appChipIdleBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                // 2) Prévia
                if (_quickVideoId != null) ...[
                  const SizedBox(height: 10),
                  _buildQuickPreview(accent),
                ],
                const SizedBox(height: 12),
                // 3) Essenciais
                FastTextField(
                  controller: _titleCtrl,
                  decoration: _fieldDeco('Título', accent: accent),
                ),
                const SizedBox(height: 10),
                FastTextField(
                  controller: _descriptionCtrl,
                  decoration: _fieldDeco(
                    'Descrição curta (opcional)',
                    accent: accent,
                  ),
                  kind: FastTextFieldKind.multiline,
                  maxLines: 3,
                ),
                if (isDica) ...[
                  const SizedBox(height: 10),
                  FastTextField(
                    controller: _bodyTextCtrl,
                    decoration: _fieldDeco('Texto da dica', accent: accent),
                    kind: FastTextFieldKind.multiline,
                    maxLines: 5,
                  ),
                ],
                const SizedBox(height: 10),
                // 4) Capa opcional
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: saving ? null : _pickCoverImages,
                      icon: const Icon(Icons.image_rounded, size: 18),
                      label: Text(_pickedImages.isEmpty
                          ? 'Capa própria (opcional)'
                          : 'Mais fotos'),
                    ),
                    for (var i = 0; i < _pickedImages.length; i++)
                      InputChip(
                        avatar: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.memory(
                            _pickedImages[i].bytes!,
                            width: 28,
                            height: 28,
                            fit: BoxFit.cover,
                          ),
                        ),
                        label: Text(
                          [
                            if (_pickedImages[i].width != null)
                              '${_pickedImages[i].width}x${_pickedImages[i].height}',
                            _mb(_pickedImages[i].effectiveSize),
                          ].join(' · '),
                          style: const TextStyle(fontSize: 12),
                        ),
                        onDeleted: saving ? null : () => _removePickedImage(i),
                      ),
                  ],
                ),
                if (_pickedImages.isEmpty && _quickVideoId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Sem capa própria, usamos a do YouTube. Aceita JPG, PNG '
                      'ou WebP até 3840x2160 (12 MB).',
                      style: TextStyle(fontSize: 11, color: context.isDarkMode ? context.appTextSecondary : Colors.grey.shade600),
                    ),
                  ),
                ] else ...[
                  // 1) Vídeos em destaque (o curso nasce dos vídeos enviados)
                  _buildQuickUploadCard(accent, saving),
                  const SizedBox(height: 14),
                  // 2) Título
                  FastTextField(
                    controller: _titleCtrl,
                    decoration: _fieldDeco('Título do curso', accent: accent),
                  ),
                  const SizedBox(height: 10),
                  // 3) Descrição moderna (maior, com contador)
                  FastTextField(
                    controller: _descriptionCtrl,
                    decoration: _fieldDeco(
                      'Descrição do curso',
                      hint: 'Explique o conteúdo, para quem é e o que o aluno '
                          'vai aprender.',
                      accent: accent,
                    ).copyWith(
                      alignLabelWithHint: true,
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(bottom: 60),
                        child: Icon(Icons.notes_rounded, color: accent),
                      ),
                    ),
                    kind: FastTextFieldKind.multiline,
                    minLines: 5,
                    maxLines: 10,
                    maxLength: 2000,
                  ),
                  const SizedBox(height: 6),
                  // 4) Capa com prévia grande (inteira, sem cortar)
                  _buildQuickCoverCard(accent, saving),
                  const SizedBox(height: 14),
                  // 5) Link do YouTube — opcional, secundário
                  TextField(
                    controller: _youtubeCtrl,
                    enabled: !saving,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Link do YouTube (opcional)',
                      hintText: 'https://youtu.be/… ou youtube.com/watch?v=…',
                      helperText: _pickedVideos.isEmpty
                          ? 'Sem vídeo enviado? Cole aqui um link do YouTube.'
                          : 'Opcional — os vídeos enviados já bastam.',
                      prefixIcon: Icon(Icons.smart_display_rounded,
                          color: _Yt.fgA(context, 0.5)),
                      suffixIcon: link.isEmpty
                          ? IconButton(
                              tooltip: 'Colar',
                              onPressed: saving ? null : _pasteLink,
                              icon: const Icon(Icons.content_paste_rounded),
                            )
                          : IconButton(
                              tooltip: 'Apagar link',
                              onPressed:
                                  saving ? null : () => _youtubeCtrl.clear(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                      errorText: linkError,
                      errorMaxLines: 3,
                      isDense: true,
                      filled: true,
                      fillColor: context.appChipIdleBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  if (_quickVideoId != null) ...[
                    const SizedBox(height: 10),
                    _buildQuickPreview(accent),
                  ],
                ],
                const SizedBox(height: 6),
                // 5) Mais opções (recolhido)
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    leading: Icon(Icons.tune_rounded, color: accent),
                    title: const Text(
                      'Mais opções',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    subtitle: Text(
                      [
                        if (_pickedVideos.isNotEmpty)
                          '${_pickedVideos.length} vídeo(s) MP4',
                        _validityPermanent ? 'permanente' : 'com validade',
                        _published ? 'publicado' : 'oculto',
                      ].join(' · '),
                      style: TextStyle(fontSize: 11.5, color: context.isDarkMode ? context.appTextSecondary : Colors.grey.shade600),
                    ),
                    children: [
                      _buildValiditySection(
                        permanent: _validityPermanent,
                        expiresAt: _expiresAtDate,
                        onPermanentChanged: (v) => setState(() {
                          _validityPermanent = v;
                          if (v) _expiresAtDate = null;
                        }),
                        onDateChanged: (d) => setState(() => _expiresAtDate = d),
                        accent: accent,
                        enabled: !saving,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Publicar já no módulo Cursos'),
                        subtitle: const Text('Desligado = fica oculto (rascunho).'),
                        value: _published,
                        activeThumbColor: accent,
                        onChanged: saving
                            ? null
                            : (v) => setState(() => _published = v),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: saving ? null : _openCreateSheet,
                          icon: const Icon(Icons.open_in_full_rounded, size: 18),
                          label: const Text('Abrir editor completo'),
                        ),
                      ),
                    ],
                  ),
                ),
                // Progresso do envio (sem bloquear a tela)
                if (saving) ...[
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: _uploadProgress > 0 ? _uploadProgress : null,
                      minHeight: 6,
                      color: accent,
                      backgroundColor: accent.withValues(alpha: 0.12),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _pickedVideos.isNotEmpty && _uploadProgress < 1
                              ? 'Enviando vídeo… ${(_uploadProgress * 100).round()}%'
                              : 'Salvando…',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: context.isDarkMode ? context.appTextSecondary : Colors.grey.shade700,
                          ),
                        ),
                      ),
                      if (_pickedVideos.isNotEmpty && _uploadCancel != null)
                        TextButton.icon(
                          onPressed: () => _uploadCancel?.cancel(),
                          icon: const Icon(Icons.cancel_rounded, size: 18),
                          label: const Text('Cancelar envio'),
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.red.shade700),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                // Botão principal
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: FilledButton.icon(
                    key: ValueKey(_publishState),
                    onPressed: saving ? null : () => _publishVideo(),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          done ? const Color(0xFF16A34A) : accent,
                      disabledBackgroundColor: accent.withValues(alpha: 0.55),
                      disabledForegroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    icon: saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.4, color: Colors.white),
                          )
                        : Icon(done
                            ? Icons.check_circle_rounded
                            : Icons.rocket_launch_rounded),
                    label: Text(saving
                        ? 'Salvando…'
                        : (done ? 'Publicado ✓' : 'Publicar')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Área de envio dos vídeos do curso — em destaque no topo do formulário
  /// (antes ficava escondida em «Mais opções»). Cada vídeo vira uma aula.
  Widget _buildQuickUploadCard(Color accent, bool saving) {
    final n = _pickedVideos.length;
    final max = CourseMediaUrlResolver.maxCourseVideos;
    final pct = (_uploadProgress * 100).clamp(0, 100).round();
    final atual = n == 0 ? 0 : ((_uploadProgress * n).floor() + 1).clamp(1, n);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appAccentSurface(accent, lightAlpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.video_library_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vídeos do curso',
                      style: TextStyle(
                        color: _Yt.fg(context),
                        fontWeight: FontWeight.w900,
                        fontSize: 15.5,
                      ),
                    ),
                    Text(
                      'Até $max vídeos · 250 MB cada · cada vídeo vira uma aula',
                      style: TextStyle(
                        color: _Yt.fgA(context, 0.55),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$n/$max',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (n < max && !saving)
            Material(
              color: _Yt.bg(context),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => kIsWeb ? _pickMp4Videos() : _addVideoWithChoice(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 22, horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.45),
                      width: 1.4,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.cloud_upload_rounded, color: accent, size: 38),
                      const SizedBox(height: 8),
                      Text(
                        n == 0 ? 'Escolher vídeos' : 'Adicionar mais vídeos',
                        style: TextStyle(
                          color: _Yt.fg(context),
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        kIsWeb
                            ? 'MP4, MOV ou WebM do computador'
                            : 'Galeria (MP4, MOV, WebM) ou gravar com a câmera',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _Yt.fgA(context, 0.55),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (n > 0) ...[
            const SizedBox(height: 10),
            for (var i = 0; i < n; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildYouTubeStyleCard(i, accent),
              ),
          ],
          if (saving && n > 0) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: _uploadProgress > 0 ? _uploadProgress : null,
                minHeight: 6,
                color: accent,
                backgroundColor: accent.withValues(alpha: 0.12),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _uploadProgress > 0
                  ? 'Enviando vídeo $atual de $n… $pct%'
                  : 'Preparando o envio…',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
          if (!saving && n > 0)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _clearPickedVideos(),
                icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                label: const Text('Limpar vídeos'),
              ),
            ),
        ],
      ),
    );
  }

  /// Troca a capa (1ª foto) sem perder as outras fotos; se cancelar, mantém.
  Future<void> _replaceCover() async {
    final old = List<_PickedMedia>.from(_pickedImages);
    setState(() => _pickedImages.clear());
    await _pickCoverImages();
    if (!mounted) return;
    setState(() {
      if (_pickedImages.isEmpty) {
        _pickedImages.addAll(old);
        return;
      }
      for (final o in old.skip(1)) {
        if (_pickedImages.length >= CourseMediaUrlResolver.maxGalleryPhotos) {
          break;
        }
        _pickedImages.add(o);
      }
    });
  }

  /// Capa com prévia grande, enquadrada inteira (BoxFit.contain, sem cortar).
  Widget _buildQuickCoverCard(Color accent, bool saving) {
    final temCapa = _pickedImages.isNotEmpty;
    final ytCover = _quickVideoId == null
        ? null
        : (_quickInfo?.coverUrl ??
            YoutubeUrlHelper.safeThumbnailUrl(_quickVideoId!));
    Widget preview;
    if (temCapa) {
      preview = Image.memory(_pickedImages.first.bytes!, fit: BoxFit.contain);
    } else if (ytCover != null) {
      preview = Image.network(
        ytCover,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    } else {
      preview = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_photo_alternate_rounded,
              size: 40, color: _Yt.fgA(context, 0.45)),
          const SizedBox(height: 6),
          Text(
            'Adicionar capa (opcional)',
            style: TextStyle(
              color: _Yt.fgA(context, 0.7),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'JPG, PNG ou WebP · até 3840x2160 (12 MB)',
            style: TextStyle(color: _Yt.fgA(context, 0.5), fontSize: 11),
          ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _Yt.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Yt.line(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.image_rounded, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  temCapa
                      ? 'Capa do curso'
                      : (ytCover != null
                          ? 'Capa do YouTube (automática)'
                          : 'Capa do curso'),
                  style: TextStyle(
                    color: _Yt.fg(context),
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              if (temCapa)
                Text(
                  [
                    if (_pickedImages.first.width != null)
                      '${_pickedImages.first.width}x${_pickedImages.first.height}',
                    _mb(_pickedImages.first.effectiveSize),
                  ].join(' · '),
                  style:
                      TextStyle(color: _Yt.fgA(context, 0.5), fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Material(
                color: _Yt.thumb(context),
                child: InkWell(
                  onTap: saving
                      ? null
                      : (temCapa ? _replaceCover : _pickCoverImages),
                  child: Center(child: preview),
                ),
              ),
            ),
          ),
          if (_pickedImages.length > 1) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 1; i < _pickedImages.length; i++)
                  InputChip(
                    avatar: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.memory(
                        _pickedImages[i].bytes!,
                        width: 28,
                        height: 28,
                        fit: BoxFit.cover,
                      ),
                    ),
                    label: Text('Foto ${i + 1}',
                        style: const TextStyle(fontSize: 12)),
                    onDeleted: saving ? null : () => _removePickedImage(i),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: saving
                    ? null
                    : (temCapa ? _replaceCover : _pickCoverImages),
                icon: Icon(
                    temCapa
                        ? Icons.swap_horiz_rounded
                        : Icons.add_photo_alternate_rounded,
                    size: 18),
                label: Text(temCapa ? 'Trocar capa' : 'Escolher capa'),
              ),
              if (temCapa)
                OutlinedButton.icon(
                  onPressed: saving ? null : () => _removePickedImage(0),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Remover'),
                ),
              if (temCapa &&
                  _pickedImages.length <
                      CourseMediaUrlResolver.maxGalleryPhotos)
                TextButton.icon(
                  onPressed: saving ? null : _pickCoverImages,
                  icon: const Icon(Icons.collections_rounded, size: 18),
                  label: const Text('Mais fotos'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickPreview(Color accent) {
    final info = _quickInfo;
    final id = _quickVideoId!;
    final cover = info?.coverUrl ?? YoutubeUrlHelper.safeThumbnailUrl(id);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _Yt.card(context),
        border: Border.all(color: _Yt.line(context)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 136,
              height: 76,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    cover,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const ColoredBox(
                      color: Color(0xFF272727),
                      child: Icon(Icons.smart_display_rounded,
                          color: Colors.white38),
                    ),
                  ),
                  const Center(
                    child: Icon(Icons.play_circle_fill_rounded,
                        color: Colors.white, size: 30),
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
                  _quickLoading
                      ? 'Buscando dados do vídeo…'
                      : ((info?.title.isNotEmpty ?? false)
                          ? info!.title
                          : 'Vídeo encontrado'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _Yt.fg(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if ((info?.author ?? '').isNotEmpty) info!.author,
                    'ID $id',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _Yt.fgA(context, 0.6), fontSize: 11.5),
                ),
                if (!_quickLoading && (info?.title.isEmpty ?? true))
                  Text(
                    'Não deu para ler o título — digite abaixo.',
                    style: TextStyle(color: (context.isDarkMode ? Colors.amber.shade300 : Colors.amber.shade900), fontSize: 11),
                  ),
              ],
            ),
          ),
          if (_quickLoading)
            Padding(
              padding: EdgeInsets.only(left: 8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: _Yt.fgA(context, 0.54)),
              ),
            )
          else
            IconButton(
              tooltip: 'Assistir prévia',
              onPressed: () => openYoutubeWatchScreen(
                context,
                videoId: id,
                title: _titleCtrl.text.trim().isEmpty
                    ? 'Prévia'
                    : _titleCtrl.text.trim(),
              ),
              icon: Icon(Icons.open_in_new_rounded, color: _Yt.fgA(context, 0.7)),
            ),
        ],
      ),
    );
  }

  // ── Lista compacta da biblioteca ─────────────────────────────────────

  Widget _buildCompactList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Map<String, CourseStatSummary> statsById,
  ) {
    return Column(
      children: [
        for (final doc in docs)
          _CompactCourseRow(
            key: ValueKey('compact-${doc.id}'),
            data: {...doc.data(), 'id': doc.id},
            views: statsById[doc.id]?.viewCount ?? 0,
            likes: statsById[doc.id]?.likeCount ?? 0,
            selectionMode: _selectionMode,
            selected: _selectedIds.contains(doc.id),
            onTap: () {
              if (_selectionMode) {
                setState(() {
                  if (!_selectedIds.remove(doc.id)) _selectedIds.add(doc.id);
                });
              } else {
                _openContentPreview(doc);
              }
            },
            onLongPress: () => setState(() {
              _selectionMode = true;
              _selectedIds.add(doc.id);
            }),
            onEdit: () => _openEditSheet(doc),
            onDelete: () => _deleteVideo(doc.id),
            onTogglePublished: (v) => _togglePublished(doc.id, v),
          ),
      ],
    );
  }

  Widget _buildNewContentLauncher() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: context.isDarkMode
              ? const [Color(0xFF0F0F0F), Color(0xFF1A1A2E), Color(0xFF16213E)]
              : const [Colors.white, Color(0xFFF8FAFC), Color(0xFFEFF6FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: context.isDarkMode
            ? null
            : Border.all(color: context.appChipIdleBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.add_rounded,
                    color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Criar curso ou dica',
                      style: TextStyle(
                        color: _Yt.fg(context),
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Vídeo da câmera, MP4, YouTube, galeria e validade',
                      style: TextStyle(
                        color: _Yt.fgA(context, 0.65),
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Quick action buttons
          Row(
            children: [
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.videocam_rounded,
                  label: 'Curso com vídeo',
                  color: const Color(0xFFEF4444),
                  onTap: () {
                    setState(() => _type = 'curso');
                    _openCreateSheet();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.lightbulb_rounded,
                  label: 'Dica rápida',
                  color: const Color(0xFFF59E0B),
                  onTap: () {
                    setState(() => _type = 'dica');
                    _openCreateSheet();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.auto_awesome_rounded,
                  label: 'Editor completo',
                  color: const Color(0xFF7C3AED),
                  onTap: _openCreateSheet,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPublishFormColumn({VoidCallback? onStateChanged}) {
    final accent =
        _type == 'dica' ? const Color(0xFFF59E0B) : const Color(0xFF2563EB);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FastTextField(
          controller: _titleCtrl,
          decoration: _fieldDeco('Título', accent: accent),
        ),
        const SizedBox(height: 10),
        FastTextField(
          controller: _descriptionCtrl,
          decoration: _fieldDeco(
            _type == 'dica'
                ? 'Resumo curto (opcional)'
                : 'Descrição completa do curso',
            hint: _type == 'curso'
                ? 'Explique o conteúdo, objetivo e o que o aluno aprenderá.'
                : null,
            accent: accent,
          ),
          kind: FastTextFieldKind.multiline,
          maxLines: _type == 'dica' ? 3 : 8,
        ),
        if (_type == 'dica') ...[
          const SizedBox(height: 10),
          FastTextField(
            controller: _bodyTextCtrl,
            decoration: _fieldDeco(
              'Texto completo da dica',
              hint: 'Conteúdo maior — exibido ao abrir a dica no app.',
              accent: accent,
            ),
            kind: FastTextFieldKind.multiline,
            maxLines: 8,
          ),
          const SizedBox(height: 10),
          Text(
            'Galeria de fotos (até ${CourseMediaUrlResolver.maxGalleryPhotos})',
            style: TextStyle(fontWeight: FontWeight.w800, color: accent),
          ),
          const SizedBox(height: 8),
          if (_pickedImages.isNotEmpty)
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _pickedImages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final p = _pickedImages[i];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          p.bytes!,
                          width: 110,
                          height: 110,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.black54,
                          child: InkWell(
                            onTap: _savingVideo
                                ? null
                                : () => _removePickedImage(i),
                            child: const Icon(Icons.close_rounded,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _savingVideo ? null : _pickCoverImages,
                icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
                label: Text(
                  _pickedImages.isEmpty
                      ? 'Adicionar fotos'
                      : 'Adicionar (${_pickedImages.length}/${CourseMediaUrlResolver.maxGalleryPhotos})',
                ),
              ),
              if (_pickedImages.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: _savingVideo ? null : _clearPickedImages,
                  icon: const Icon(Icons.clear_all_rounded, size: 18),
                  label: const Text('Limpar fotos'),
                ),
            ],
          ),
        ] else ...[
          const SizedBox(height: 14),
          // ── Seção de vídeo estilo YouTube ──
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _Yt.bg(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _Yt.line(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.smart_display_rounded,
                          color: Color(0xFFEF4444), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vídeos do curso',
                            style: TextStyle(
                              color: _Yt.fg(context),
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            'Até ${CourseMediaUrlResolver.maxCourseVideos} vídeos · MP4, MOV ou câmera',
                            style: TextStyle(
                              color: _Yt.fgA(context, 0.6),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _Yt.line(context),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '${_pickedVideos.length}/${CourseMediaUrlResolver.maxCourseVideos}',
                        style: TextStyle(
                          color: _Yt.fgA(context, 0.7),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Vídeos adicionados — cards estilo YouTube
                if (_pickedVideos.isNotEmpty) ...[
                  for (var i = 0; i < _pickedVideos.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildYouTubeStyleCard(
                        i,
                        accent,
                        onStateChanged: onStateChanged,
                      ),
                    ),
                ],
                // Progresso visível desde a preparação até concluir o upload.
                if (_savingVideo && _pickedVideos.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: _uploadProgress > 0 ? _uploadProgress : null,
                      minHeight: 6,
                      color: const Color(0xFFEF4444),
                      backgroundColor: _Yt.line(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _uploadProgress > 0
                        ? 'Enviando vídeo… ${(_uploadProgress * 100).toStringAsFixed(0)}%'
                        : 'Preparando vídeo para envio…',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                // Botões de ação
                if (!_savingVideo) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _buildVideoActionButton(
                          icon: Icons.videocam_rounded,
                          label: 'Gravar vídeo',
                          color: const Color(0xFFEF4444),
                          onTap: () => _addVideoWithChoice(
                            onStateChanged: onStateChanged,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildVideoActionButton(
                          icon: Icons.upload_file_rounded,
                          label: 'Arquivo',
                          color: const Color(0xFF3B82F6),
                          onTap: () => _pickMp4Videos(
                            onStateChanged: onStateChanged,
                          ),
                        ),
                      ),
                      if (_pickedVideos.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _buildVideoActionButton(
                          icon: Icons.delete_sweep_rounded,
                          label: 'Limpar',
                          color: Colors.grey.shade600,
                          onTap: () => _clearPickedVideos(
                            onStateChanged: onStateChanged,
                          ),
                          compact: true,
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Capa / galeria (até ${CourseMediaUrlResolver.maxGalleryPhotos} fotos)',
            style: TextStyle(fontWeight: FontWeight.w800, color: accent),
          ),
          const SizedBox(height: 8),
          if (_pickedImages.isNotEmpty)
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _pickedImages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(
                    _pickedImages[i].bytes!,
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: _savingVideo ? null : _pickCoverImages,
            icon: const Icon(Icons.image_rounded, size: 18),
            label: const Text('Adicionar capa / fotos'),
          ),
        ],
        const SizedBox(height: 10),
        FastTextField(
          controller: _youtubeCtrl,
          decoration: _fieldDeco(
            _type == 'dica'
                ? 'Link — YouTube ou site (opcional)'
                : 'Link YouTube (opcional)',
            hint: _type == 'dica'
                ? 'https://youtube.com/… ou https://seusite.com/…'
                : 'https://www.youtube.com/watch?v=...',
            accent: accent,
          ),
          kind: FastTextFieldKind.url,
        ),
        const SizedBox(height: 12),
        _TypePillSelector(
          value: _type,
          onChanged: _savingVideo ? (_) {} : (v) => setState(() => _type = v),
        ),
        const SizedBox(height: 10),
        _buildValiditySection(
          permanent: _validityPermanent,
          expiresAt: _expiresAtDate,
          onPermanentChanged: (v) => setState(() {
            _validityPermanent = v;
            if (v) _expiresAtDate = null;
          }),
          onDateChanged: (d) => setState(() => _expiresAtDate = d),
          accent: accent,
          enabled: !_savingVideo,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Publicado'),
          subtitle: const Text('Desligado = oculto no módulo Cursos.'),
          value: _published,
          activeThumbColor: _type == 'dica'
              ? const Color(0xFFF59E0B)
              : const Color(0xFF2563EB),
          onChanged:
              _savingVideo ? null : (v) => setState(() => _published = v),
        ),
      ],
    );
  }

  /// Card estilo YouTube para vídeo selecionado (create/edit).
  Widget _buildYouTubeStyleCard(
    int index,
    Color accent, {
    VoidCallback? onStateChanged,
  }) {
    final v = _pickedVideos[index];
    final name = v.name ?? 'video_${index + 1}.mp4';
    final sizeMB = (v.effectiveSize / (1024 * 1024)).toStringAsFixed(1);
    final ext = name.split('.').last.toUpperCase();
    return Container(
      decoration: BoxDecoration(
        color: _Yt.bg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _Yt.line(context)),
      ),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          // Thumbnail placeholder estilo YouTube
          Container(
            width: 72,
            height: 44,
            decoration: BoxDecoration(
              color: _Yt.thumb(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.videocam_rounded,
                    color: _Yt.fgA(context, 0.5), size: 22),
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      ext,
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _Yt.fg(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$sizeMB MB',
                  style: TextStyle(
                    color: _Yt.fgA(context, 0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (!_savingVideo)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _removePickedVideo(
                  index,
                  onStateChanged: onStateChanged,
                ),
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.close_rounded,
                    color: _Yt.fgA(context, 0.5),
                    size: 18,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Botão de ação de vídeo (Gravar / Arquivo / Limpar).
  Widget _buildVideoActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool compact = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: 12,
            horizontal: compact ? 10 : 14,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypePillSelector extends StatelessWidget {
  const _TypePillSelector({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Pill(
            label: 'Curso',
            icon: Icons.school_rounded,
            selected: value == 'curso',
            gradient: const [Color(0xFF2563EB), Color(0xFF1D4ED8)],
            onTap: () => onChanged('curso'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Pill(
            label: 'Dica',
            icon: Icons.lightbulb_rounded,
            selected: value == 'dica',
            gradient: const [Color(0xFFF59E0B), Color(0xFFD97706)],
            onTap: () => onChanged('dica'),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.gradient,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final List<Color> gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: selected ? LinearGradient(colors: gradient) : null,
            color: selected ? null : (context.isDarkMode ? context.appSurface : Colors.white),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : gradient.first.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18, color: selected ? Colors.white : gradient.first),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: selected ? Colors.white : gradient.first,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ValidityPill extends StatelessWidget {
  const _ValidityPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: selected ? color : (context.isDarkMode ? context.appSurface : Colors.white),
            border: Border.all(
              color: selected ? color : color.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? Colors.white : color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: selected ? Colors.white : color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoGridCard extends StatelessWidget {
  const _VideoGridCard({
    required this.doc,
    required this.index,
    required this.thumbUrl,
    required this.videoId,
    required this.hasMp4,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onPreview,
    required this.onEdit,
    required this.onTogglePublished,
    required this.onDelete,
    this.feedStyle = false,
    this.viewCount = 0,
    this.likeCount = 0,
    this.onOpenStats,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final int index;
  final String? thumbUrl;
  final String? videoId;
  final bool hasMp4;
  final bool selectionMode;
  final bool selected;
  final bool feedStyle;
  final int viewCount;
  final int likeCount;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onPreview;
  final VoidCallback onEdit;
  final ValueChanged<bool> onTogglePublished;
  final VoidCallback onDelete;
  final VoidCallback? onOpenStats;

  @override
  Widget build(BuildContext context) {
    final data = {...doc.data(), 'id': doc.id};
    final title = (data['title'] ?? 'Vídeo').toString();
    final description = (data['description'] ?? '').toString();
    final body = (data['bodyText'] ?? '').toString();
    final previewText = body.isNotEmpty ? body : description;
    final type = (data['type'] ?? 'curso').toString();
    final published = data['published'] != false;
    final (accent, accent2) =
        CourseContentCardHeader.colorsFor(type: type, index: index);
    final created = data['createdAt'];
    var dateLabel = '';
    if (created is Timestamp) {
      dateLabel = DateFormat('dd/MM/yyyy').format(created.toDate());
    }

    final hasThumb = CourseThumbResolver.hasVisualThumb(data);
    final isVideo = CourseThumbResolver.isVideoContent(data);
    final thumbFit =
        CourseThumbResolver.isDicaPhoto(data) ? BoxFit.contain : BoxFit.cover;

    final sourceLabel = hasMp4
        ? (videoId != null ? 'MP4+YT' : 'MP4')
        : (videoId != null ? 'YOUTUBE' : (type == 'dica' ? 'DICA' : 'VÍDEO'));
    final validityLabel = CourseVideoValidity.labelFor(data);
    final expired = CourseVideoValidity.shouldDeleteExpired(data);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: _Yt.bg(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.8)
                  : _Yt.line(context),
              width: selected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Thumbnail area — 16:9 YouTube style
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (hasThumb)
                        CourseMediaThumbnail.fromData(
                          data,
                          fit: thumbFit,
                          fallback: _thumbFallback(accent, accent2),
                          showPlayButton: false,
                        )
                      else
                        _thumbFallback(accent, accent2),
                      // Dark gradient overlay at bottom
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.7)
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ),
                      // Play / abrir — botão estilo YouTube
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onPreview,
                          child: Center(
                            child: Container(
                              width: (isVideo || videoId != null || hasMp4)
                                  ? 72
                                  : 64,
                              height: (isVideo || videoId != null || hasMp4)
                                  ? 52
                                  : 64,
                              decoration: BoxDecoration(
                                color: type == 'dica'
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFFFF0000),
                                borderRadius: BorderRadius.circular(
                                  (isVideo || videoId != null || hasMp4)
                                      ? 14
                                      : 999,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        Colors.black.withValues(alpha: 0.45),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Icon(
                                (isVideo || videoId != null || hasMp4)
                                    ? Icons.play_arrow_rounded
                                    : (type == 'dica'
                                        ? Icons.lightbulb_rounded
                                        : Icons.visibility_rounded),
                                color: Colors.white,
                                size: (isVideo || videoId != null || hasMp4)
                                    ? 40
                                    : 28,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Top badges
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Row(
                          children: [
                            _badgeChip(
                              published ? 'PUBLICADO' : 'OCULTO',
                              bg: published
                                  ? const Color(0xFF16A34A)
                                  : Colors.black.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 4),
                            _badgeChip(type.toUpperCase()),
                            if (sourceLabel != 'VÍDEO' &&
                                sourceLabel != 'DICA') ...[
                              const SizedBox(width: 4),
                              _badgeChip(sourceLabel),
                            ],
                          ],
                        ),
                      ),
                      // Selection checkbox
                      if (selectionMode)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: CircleAvatar(
                            radius: 14,
                            backgroundColor: selected ? accent : Colors.black54,
                            child: Icon(
                              selected
                                  ? Icons.check_rounded
                                  : Icons.circle_outlined,
                              size: 18,
                              color: selected ? Colors.white : Colors.white70,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Info area — feedStyle = altura natural (igual app)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    feedStyle ? 14 : 10,
                    feedStyle ? 12 : 8,
                    feedStyle ? 14 : 10,
                    feedStyle ? 12 : 6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: feedStyle ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _Yt.fg(context),
                          fontWeight: FontWeight.w900,
                          fontSize: feedStyle ? 16 : 13.5,
                          height: 1.25,
                        ),
                      ),
                      if (previewText.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          previewText,
                          maxLines: feedStyle
                              ? (type == 'dica' ? 5 : 3)
                              : 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: feedStyle ? 13 : 11,
                            height: 1.4,
                            color: _Yt.fgA(context, 0.55),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onOpenStats,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: _Yt.soft(context),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _Yt.line(context),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.visibility_rounded,
                                    size: 16,
                                    color: Colors.blue.shade300),
                                const SizedBox(width: 6),
                                Text(
                                  '$viewCount assistiram',
                                  style: TextStyle(
                                    color: _Yt.fg(context),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                const Icon(Icons.thumb_up_alt_rounded,
                                    size: 15, color: Color(0xFFFF0000)),
                                const SizedBox(width: 6),
                                Text(
                                  '$likeCount curtiram',
                                  style: TextStyle(
                                    color: _Yt.fg(context),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'Ver quem',
                                  style: TextStyle(
                                    color: _Yt.fgA(context, 0.55),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18,
                                  color: _Yt.fgA(context, 0.45),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _miniChip(
                            validityLabel,
                            expired
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF94A3B8),
                          ),
                          if (dateLabel.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text(
                              dateLabel,
                              style: TextStyle(
                                fontSize: 10,
                                color: _Yt.fgA(context, 0.35),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const Spacer(),
                          _actionIcon(
                            Icons.edit_rounded,
                            accent.withValues(alpha: 0.85),
                            onEdit,
                            'Editar',
                          ),
                          _actionIcon(
                            Icons.forum_outlined,
                            _Yt.fgA(context, 0.5),
                            () => showCourseCommentsModeration(context,
                                data: data),
                            'Comentários',
                          ),
                          _actionIcon(
                            published
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_rounded,
                            _Yt.fgA(context, 0.5),
                            () => onTogglePublished(!published),
                            published ? 'Ocultar' : 'Publicar',
                          ),
                          _actionIcon(
                            Icons.delete_outline_rounded,
                            Colors.red.shade400.withValues(alpha: 0.8),
                            onDelete,
                            'Excluir',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badgeChip(String text, {Color? bg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg ?? Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _actionIcon(
      IconData icon, Color color, VoidCallback onPressed, String tooltip) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: color, size: 17),
        ),
      ),
    );
  }

  Widget _thumbFallback(Color a, Color b) {
    final isDica = (doc.data()['type'] ?? '').toString() == 'dica';
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [a.withValues(alpha: 0.75), b.withValues(alpha: 0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          isDica ? Icons.lightbulb_rounded : Icons.ondemand_video_rounded,
          color: Colors.white.withValues(alpha: 0.65),
          size: 40,
        ),
      ),
    );
  }

  Widget _miniChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

/// Linha compacta da biblioteca do admin — capa pequena, título, selos e ações.
class _CompactCourseRow extends StatelessWidget {
  const _CompactCourseRow({
    super.key,
    required this.data,
    required this.views,
    required this.likes,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePublished,
  });

  final Map<String, dynamic> data;
  final int views;
  final int likes;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onTogglePublished;

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? 'Sem título').toString();
    final isDica = (data['type'] ?? 'curso').toString() == 'dica';
    final published = data['published'] != false;
    final yt = YoutubeUrlHelper.videoIdFromData(data) != null;
    final mp4 = CourseMediaUrlResolver.collectVideoEntries(data).length;
    final valid = CourseVideoValidity.isStillValid(data);
    DateTime? created;
    final c = data['createdAt'];
    if (c is Timestamp) created = c.toDate();
    final accent = isDica ? const Color(0xFFF59E0B) : const Color(0xFFEF4444);
    final narrow = MediaQuery.sizeOf(context).width < 640;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? accent.withValues(alpha: 0.18)
            : _Yt.card(context),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                if (selectionMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      selected
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      color: selected ? accent : _Yt.fgA(context, 0.38),
                    ),
                  ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox(
                    width: narrow ? 84 : 104,
                    height: narrow ? 48 : 58,
                    child: CourseMediaThumbnail.fromData(
                      data,
                      fit: BoxFit.cover,
                      showPlayButton: false,
                      fallback: ColoredBox(
                        color: const Color(0xFF272727),
                        child: Icon(
                          isDica
                              ? Icons.lightbulb_rounded
                              : Icons.smart_display_rounded,
                          color: Colors.white38,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _Yt.fg(context),
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          _tag(isDica ? 'DICA' : 'CURSO', accent),
                          if (yt) _tag('YouTube', const Color(0xFFFF4D4D)),
                          if (mp4 > 0)
                            _tag(mp4 > 1 ? '$mp4 MP4' : 'MP4',
                                const Color(0xFF60A5FA)),
                          if (!published) _tag('OCULTO', Colors.grey),
                          if (!valid) _tag('EXPIRADO', Colors.redAccent),
                          _tag('$views views · $likes curtidas',
                              _Yt.fgA(context, 0.54)),
                          if (created != null)
                            _tag(DateFormat('dd/MM/yy').format(created),
                                _Yt.fgA(context, 0.38)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!selectionMode && narrow)
                  PopupMenuButton<String>(
                    iconColor: _Yt.fgA(context, 0.7),
                    tooltip: 'Ações',
                    onSelected: (v) {
                      if (v == 'pub') onTogglePublished(!published);
                      if (v == 'edit') onEdit();
                      if (v == 'comments') {
                        showCourseCommentsModeration(context, data: data);
                      }
                      if (v == 'del') onDelete();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'pub',
                        child: Text(published ? 'Ocultar' : 'Publicar'),
                      ),
                      const PopupMenuItem(value: 'edit', child: Text('Editar')),
                      const PopupMenuItem(
                          value: 'comments', child: Text('Comentários')),
                      const PopupMenuItem(value: 'del', child: Text('Excluir')),
                    ],
                  ),
                if (!selectionMode && !narrow) ...[
                  Tooltip(
                    message: published ? 'Ocultar' : 'Publicar',
                    child: Switch(
                      value: published,
                      onChanged: onTogglePublished,
                      activeThumbColor: accent,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Editar',
                    visualDensity: VisualDensity.compact,
                    onPressed: onEdit,
                    icon: Icon(Icons.edit_rounded, color: _Yt.fgA(context, 0.7)),
                  ),
                  IconButton(
                    tooltip: 'Comentários (moderar)',
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        showCourseCommentsModeration(context, data: data),
                    icon: Icon(Icons.forum_outlined,
                        color: _Yt.fgA(context, 0.7)),
                  ),
                  IconButton(
                    tooltip: 'Excluir',
                    visualDensity: VisualDensity.compact,
                    onPressed: onDelete,
                    icon: Icon(Icons.delete_outline_rounded,
                        color: Colors.red.shade300),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tag(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          t,
          style: TextStyle(
            color: c,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}

/// Paleta do admin de Cursos (02/10/2026): grafite estilo YouTube só no modo
/// escuro; no claro, superfícies brancas/cinza-claro e texto escuro (antes era
/// preto fixo e aparecia escuro mesmo com o app no modo claro).
/// Player e capas continuam escuros — aqui é só a moldura do painel.
class _Yt {
  _Yt._();

  static Color bg(BuildContext c) =>
      c.isDarkMode ? const Color(0xFF0F0F0F) : Colors.white;

  static Color card(BuildContext c) =>
      c.isDarkMode ? const Color(0xFF1A1A1A) : const Color(0xFFF8FAFC);

  static Color soft(BuildContext c) => c.isDarkMode
      ? Colors.white.withValues(alpha: 0.04)
      : const Color(0xFFF1F5F9);

  static Color thumb(BuildContext c) =>
      c.isDarkMode ? const Color(0xFF282828) : const Color(0xFFE2E8F0);

  static Color fg(BuildContext c) =>
      c.isDarkMode ? Colors.white : c.appTextPrimary;

  static Color fgA(BuildContext c, double a) => c.isDarkMode
      ? Colors.white.withValues(alpha: a)
      : c.appTextPrimary.withValues(alpha: (a + 0.25).clamp(0.0, 1.0));

  static Color line(BuildContext c) => c.isDarkMode
      ? Colors.white.withValues(alpha: 0.08)
      : c.appChipIdleBorder;
}
