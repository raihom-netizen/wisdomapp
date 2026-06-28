import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/wisdom_courses_module_config.dart';
import '../services/course_video_file_service.dart';
import '../services/course_video_image_service.dart';
import '../services/course_media_storage_cleanup.dart';
import '../theme/app_colors.dart';
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
import '../widgets/course_video/course_video_watch_screen.dart';
import '../widgets/fast_text_field.dart';
import '../widgets/module_header_premium.dart';

/// Arquivo escolhido no admin (imagem ou vídeo) antes do upload.
class _PickedMedia {
  const _PickedMedia({required this.bytes, required this.mime, this.name});

  final Uint8List bytes;
  final String mime;
  final String? name;
}

class AdminCursosTab extends StatefulWidget {
  const AdminCursosTab({super.key});

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
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _courseVideosFuture;

  @override
  void initState() {
    super.initState();
    _scheduleExpiryCleanup();
    _reloadCourseVideos();
  }

  void _reloadCourseVideos() {
    setState(() {
      _courseVideosFuture = _fetchCourseVideos();
    });
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetchCourseVideos() async {
    return _courseFirestoreOp(() async {
      final snap = await FirebaseFirestore.instance
          .collection('course_videos')
          .get(const GetOptions(source: Source.server));
      return snap.docs;
    });
  }

  void _scheduleExpiryCleanup() {
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
      fillColor: Colors.white,
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
              color: Colors.grey.shade700,
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
      list = list.where((d) => (d.data()['type'] ?? 'curso').toString() == 'curso').toList();
    } else if (_gridTab == 2) {
      list = list.where((d) => (d.data()['type'] ?? '').toString() == 'dica').toList();
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
        return dt.year == now.year && dt.month == now.month && dt.day == now.day;
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

  Future<void> _pickMp4Videos() async {
    try {
      final remaining = CourseMediaUrlResolver.maxCourseVideos - _pickedVideos.length;
      if (remaining <= 0) {
        _snack('Máximo de ${CourseMediaUrlResolver.maxCourseVideos} vídeos por curso.');
        return;
      }
      final pick = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp4', 'mov', 'webm'],
        withData: true,
        allowMultiple: true,
      );
      if (pick == null || pick.files.isEmpty) return;
      final added = <_PickedMedia>[];
      for (final f in pick.files) {
        if (added.length >= remaining) break;
        final bytes = f.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        if (bytes.lengthInBytes > CourseVideoFileService.maxBytes) {
          _snack('${f.name}: acima de 250 MB — ignorado.');
          continue;
        }
        var ext = (f.extension ?? 'mp4').toLowerCase();
        final mime = ext == 'webm'
            ? 'video/webm'
            : (ext == 'mov' ? 'video/quicktime' : 'video/mp4');
        added.add(_PickedMedia(bytes: bytes, mime: mime, name: f.name));
      }
      if (added.isEmpty) return;
      setState(() => _pickedVideos.addAll(added));
    } catch (e) {
      _snack('Erro ao selecionar vídeo: $e');
    }
  }

  void _clearPickedVideos() {
    setState(() {
      _pickedVideos.clear();
      _uploadProgress = 0;
    });
  }

  void _removePickedVideo(int index) {
    setState(() => _pickedVideos.removeAt(index));
  }

  Future<List<CourseMediaUploadResult>> _uploadPickedVideos(
    String docId, {
    int startIndex = 0,
    void Function(double progress)? onProgress,
  }) async {
    final out = <CourseMediaUploadResult>[];
    for (var i = 0; i < _pickedVideos.length; i++) {
      final p = _pickedVideos[i];
      final result = await CourseVideoFileService.uploadVideo(
        bytes: p.bytes,
        mimeType: p.mime,
        docId: docId,
        index: startIndex + i,
        onProgress: onProgress,
      );
      out.add(result);
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
        added.add(_PickedMedia(bytes: bytes, mime: mime, name: f.name));
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
          bytes: p.bytes,
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
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
      _reloadCourseVideos();
      _snack('$n conteúdo(s) removido(s).');
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

  Future<void> _publishVideo() async {
    if (_savingVideo) return;
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _snack('Informe o título.');
      return;
    }

    if (_type == 'curso') {
      final youtubeRaw = _youtubeCtrl.text.trim();
      final hasYoutube = youtubeRaw.isNotEmpty;
      final hasMp4 = _pickedVideos.isNotEmpty;
      if (!hasMp4 && !hasYoutube) {
        _snack('Anexe um vídeo MP4 ou informe link YouTube (opcional).');
        return;
      }
      if (hasYoutube && !YoutubeUrlHelper.isValidYoutubeUrl(youtubeRaw)) {
        _snack('URL do YouTube inválida.');
        return;
      }
    } else {
      final linkRaw = _youtubeCtrl.text.trim();
      if (linkRaw.isNotEmpty &&
          CourseContentLinkHelper.normalizeLink(linkRaw) == null) {
        _snack('Link inválido. Use YouTube ou site (https://…).');
        return;
      }
      final body = _bodyTextCtrl.text.trim();
      final desc = _descriptionCtrl.text.trim();
      final linkOk = linkRaw.isNotEmpty;
      if (body.isEmpty &&
          desc.isEmpty &&
          _pickedImages.isEmpty &&
          !linkOk) {
        _snack('Informe texto, imagem ou link para a dica.');
        return;
      }
    }

    if (!_validityPermanent && _expiresAtDate == null) {
      _snack('Escolha a data limite ou marque como permanente.');
      return;
    }

    setState(() => _savingVideo = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final email = FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
      final docRef = FirebaseFirestore.instance.collection('course_videos').doc();
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
          final uploads = await _uploadPickedVideos(
            docRef.id,
            onProgress: (p) {
              if (mounted) setState(() => _uploadProgress = p);
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
      _reloadCourseVideos();
      _snack('Conteúdo publicado — já aparece no módulo Cursos.');
    } catch (e) {
      _snack('Erro ao publicar: ${_formatPublishError(e)}');
    } finally {
      if (mounted) {
        setState(() {
          _savingVideo = false;
          _uploadProgress = 0;
        });
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
        ),
      };

      List<CourseMediaUploadResult> uploadedImages = [];
      for (var i = 0; i < newImages.length; i++) {
        uploadedImages.add(
          await CourseVideoImageService.uploadCover(
            bytes: newImages[i].bytes,
            mimeType: newImages[i].mime,
            docId: docId,
            index: CourseMediaUrlResolver.collectHttpUrls(existingData).length + i,
          ),
        );
      }

      List<CourseMediaUploadResult> uploadedVideos = [];
      for (var i = 0; i < newVideos.length; i++) {
        uploadedVideos.add(
          await CourseVideoFileService.uploadVideo(
            bytes: newVideos[i].bytes,
            mimeType: newVideos[i].mime,
            docId: docId,
            index: CourseMediaUrlResolver.collectVideoEntries(existingData).length + i,
          ),
        );
      }

      if (type == 'curso') {
        String? videoId;
        String? youtubeUrl;
        var thumbUrl = (existingData['thumbnailUrl'] ?? '').toString();

        if (removeVideos) {
          patch['mp4Url'] = FieldValue.delete();
          patch['mp4Urls'] = FieldValue.delete();
          patch['mp4StoragePath'] = FieldValue.delete();
        } else if (uploadedVideos.isNotEmpty) {
          patch.addAll(CourseMediaUrlResolver.mergeVideoFields(
            existing: existingData,
            newUploads: uploadedVideos,
          ));
        }

        if (linkRaw.isNotEmpty) {
          if (!YoutubeUrlHelper.isValidYoutubeUrl(linkRaw)) {
            _snack('URL do YouTube inválida.');
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
          patch['videoUrl'] = FieldValue.delete();
          patch['youtubeUrl'] = FieldValue.delete();
          patch['youtubeVideoId'] = FieldValue.delete();
        }

        final hasMp4 = removeVideos
            ? false
            : (uploadedVideos.isNotEmpty ||
                CourseMediaUrlResolver.collectVideoEntries(existingData).isNotEmpty);
        if (!hasMp4 && videoId == null) {
          _snack('Informe vídeo MP4 ou link YouTube.');
          return false;
        }

        if (removeImages) {
          patch['imageUrl'] = FieldValue.delete();
          patch['coverUrl'] = FieldValue.delete();
          patch['imageUrls'] = FieldValue.delete();
          patch['imageStoragePaths'] = FieldValue.delete();
          patch['coverStoragePath'] = FieldValue.delete();
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
          youtubeThumb: videoId != null ? YoutubeUrlHelper.thumbnailUrl(videoId) : null,
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
            patch['videoUrl'] = FieldValue.delete();
            patch['youtubeUrl'] = FieldValue.delete();
            patch['youtubeVideoId'] = FieldValue.delete();
          }
        } else {
          patch['linkUrl'] = FieldValue.delete();
          patch['externalUrl'] = FieldValue.delete();
          patch['videoUrl'] = FieldValue.delete();
          patch['youtubeUrl'] = FieldValue.delete();
          patch['youtubeVideoId'] = FieldValue.delete();
        }

        if (removeImages) {
          patch['imageUrl'] = FieldValue.delete();
          patch['coverUrl'] = FieldValue.delete();
          patch['imageUrls'] = FieldValue.delete();
          patch['imageStoragePaths'] = FieldValue.delete();
          patch['coverStoragePath'] = FieldValue.delete();
        } else if (uploadedImages.isNotEmpty) {
          patch.addAll(CourseMediaUrlResolver.mergeImageFields(
            existing: existingData,
            newUploads: uploadedImages,
            replaceAll: removeImages,
          ));
        }

        final imageUrl = (patch['imageUrl'] as String?) ??
            (removeImages
                ? null
                : (CourseMediaUrlResolver.collectHttpUrls(existingData).isEmpty
                    ? null
                    : CourseMediaUrlResolver.collectHttpUrls(existingData).first));
        patch['source'] = videoId != null
            ? 'youtube'
            : (imageUrl != null && linkUrl != null)
                ? 'image_link'
                : (imageUrl != null ? 'image' : (linkUrl != null ? 'link' : 'text'));
        _applyThumbnailPatch(
          patch,
          existing: existingData,
          explicitThumb: imageUrl,
          youtubeThumb: ytThumb,
        );
        if (imageUrl != null && imageUrl.isNotEmpty) patch['coverUrl'] = imageUrl;
      }

      await AdminCourseFirestoreBridge.upsertCourseVideo(
        docId: docId,
        data: patch,
        create: false,
      );
      _reloadCourseVideos();
      _snack('Alterações salvas.');
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
    _reloadCourseVideos();
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
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
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
      _reloadCourseVideos();
      _snack('Conteúdo excluído.');
    } catch (e) {
      _snack('Erro ao excluir: $e');
    }
  }

  Future<void> _openEditSheet(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    final titleCtrl = TextEditingController(text: (data['title'] ?? '').toString());
    final descCtrl = TextEditingController(text: (data['description'] ?? '').toString());
    final bodyCtrl = TextEditingController(text: (data['bodyText'] ?? '').toString());
    final urlCtrl = TextEditingController(
      text: (data['linkUrl'] ?? data['externalUrl'] ?? data['youtubeUrl'] ?? data['videoUrl'] ?? '')
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

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final accent = type == 'dica' ? const Color(0xFFF59E0B) : const Color(0xFF2563EB);
            final isDica = type == 'dica';
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.92),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'EDITAR CONTEÚDO',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          letterSpacing: 0.8,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FastTextField(controller: titleCtrl, decoration: _fieldDeco('Título', accent: accent)),
                      const SizedBox(height: 10),
                      FastTextField(
                        controller: descCtrl,
                        decoration: _fieldDeco('Resumo curto', accent: accent),
                        kind: FastTextFieldKind.multiline,
                        maxLines: 3,
                      ),
                      if (isDica) ...[
                        const SizedBox(height: 10),
                        FastTextField(
                          controller: bodyCtrl,
                          decoration: _fieldDeco(
                            'Texto completo da dica',
                            hint: 'Conteúdo maior exibido ao abrir a dica…',
                            accent: accent,
                          ),
                          kind: FastTextFieldKind.multiline,
                          maxLines: 8,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Galeria de fotos (até ${CourseMediaUrlResolver.maxGalleryPhotos})',
                          style: TextStyle(fontWeight: FontWeight.w800, color: accent),
                        ),
                        const SizedBox(height: 8),
                        if (!removeImages && CourseMediaUrlResolver.hasResolvableImage(existingData))
                          CoursePhotoGallery(data: existingData, height: 180),
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
                                final pick = await FilePicker.platform.pickFiles(
                                  type: FileType.custom,
                                  allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
                                  withData: true,
                                  allowMultiple: true,
                                );
                                if (pick == null || pick.files.isEmpty) return;
                                setLocal(() {
                                  removeImages = false;
                                  for (final f in pick.files) {
                                    if (editImages.length >= CourseMediaUrlResolver.maxGalleryPhotos) break;
                                    final bytes = f.bytes;
                                    if (bytes == null) continue;
                                    var ext = (f.extension ?? 'jpg').toLowerCase();
                                    if (ext == 'jpeg') ext = 'jpg';
                                    editImages.add(_PickedMedia(
                                      bytes: bytes,
                                      mime: ext == 'png'
                                          ? 'image/png'
                                          : (ext == 'webp' ? 'image/webp' : 'image/jpeg'),
                                      name: f.name,
                                    ));
                                  }
                                });
                              },
                              icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
                              label: const Text('Adicionar fotos'),
                            ),
                            if (!removeImages && CourseMediaUrlResolver.hasResolvableImage(existingData))
                              OutlinedButton.icon(
                                onPressed: () => setLocal(() => removeImages = true),
                                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                label: const Text('Remover galeria'),
                              ),
                          ],
                        ),
                      ] else ...[
                        const SizedBox(height: 12),
                        Text(
                          'Vídeos MP4 (até ${CourseMediaUrlResolver.maxCourseVideos})',
                          style: TextStyle(fontWeight: FontWeight.w800, color: accent),
                        ),
                        const SizedBox(height: 6),
                        if (!removeVideos)
                          for (final v in CourseMediaUrlResolver.collectVideoEntries(existingData))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: CourseVideoFilePreview(
                                fileName: v.label ?? 'Vídeo publicado',
                                sizeBytes: 0,
                                accent: accent,
                              ),
                            ),
                        for (var i = 0; i < editVideos.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: CourseVideoFilePreview(
                              fileName: editVideos[i].name ?? 'video_${i + 1}.mp4',
                              sizeBytes: editVideos[i].bytes.lengthInBytes,
                              accent: accent,
                              onRemove: () => setLocal(() => editVideos.removeAt(i)),
                            ),
                          ),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () async {
                                final pick = await FilePicker.platform.pickFiles(
                                  type: FileType.custom,
                                  allowedExtensions: ['mp4', 'mov', 'webm'],
                                  withData: true,
                                  allowMultiple: true,
                                );
                                if (pick == null || pick.files.isEmpty) return;
                                setLocal(() {
                                  removeVideos = false;
                                  for (final f in pick.files) {
                                    if (editVideos.length >= CourseMediaUrlResolver.maxCourseVideos) break;
                                    final bytes = f.bytes;
                                    if (bytes == null || bytes.isEmpty) continue;
                                    var ext = (f.extension ?? 'mp4').toLowerCase();
                                    editVideos.add(_PickedMedia(
                                      bytes: bytes,
                                      mime: ext == 'webm'
                                          ? 'video/webm'
                                          : (ext == 'mov' ? 'video/quicktime' : 'video/mp4'),
                                      name: f.name,
                                    ));
                                  }
                                });
                              },
                              icon: const Icon(Icons.upload_file_rounded, size: 18),
                              label: const Text('Adicionar vídeos'),
                            ),
                            if (!removeVideos &&
                                CourseMediaUrlResolver.collectVideoEntries(existingData).isNotEmpty)
                              OutlinedButton.icon(
                                onPressed: () => setLocal(() => removeVideos = true),
                                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                label: const Text('Remover vídeos'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Capa / galeria (até ${CourseMediaUrlResolver.maxGalleryPhotos} fotos)',
                          style: TextStyle(fontWeight: FontWeight.w800, color: accent),
                        ),
                        const SizedBox(height: 8),
                        if (!removeImages && CourseMediaUrlResolver.hasResolvableImage(existingData))
                          CoursePhotoGallery(data: existingData, height: 140),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final pick = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
                              withData: true,
                              allowMultiple: true,
                            );
                            if (pick == null || pick.files.isEmpty) return;
                            setLocal(() {
                              removeImages = false;
                              for (final f in pick.files) {
                                if (editImages.length >= CourseMediaUrlResolver.maxGalleryPhotos) break;
                                final bytes = f.bytes;
                                if (bytes == null) continue;
                                var ext = (f.extension ?? 'jpg').toLowerCase();
                                if (ext == 'jpeg') ext = 'jpg';
                                editImages.add(_PickedMedia(
                                  bytes: bytes,
                                  mime: ext == 'png' ? 'image/png' : 'image/jpeg',
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
                          isDica ? 'Link (YouTube ou site)' : 'Link YouTube (opcional)',
                          hint: isDica
                              ? 'https://youtube.com/… ou https://seusite.com/…'
                              : 'https://www.youtube.com/watch?v=...',
                          accent: accent,
                        ),
                        kind: FastTextFieldKind.url,
                      ),
                      const SizedBox(height: 12),
                      _TypePillSelector(value: type, onChanged: (v) => setLocal(() => type = v)),
                      const SizedBox(height: 8),
                      _buildValiditySection(
                        permanent: validityPermanent,
                        expiresAt: expiresAtDate,
                        onPermanentChanged: (v) => setLocal(() {
                          validityPermanent = v;
                          if (v) expiresAtDate = null;
                        }),
                        onDateChanged: (d) => setLocal(() => expiresAtDate = d),
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
                        onPressed: () async {
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
                            newImages: List<_PickedMedia>.from(editImages),
                            removeImages: removeImages,
                            newVideos: List<_PickedMedia>.from(editVideos),
                            removeVideos: removeVideos,
                          );
                          if (ok && ctx.mounted) Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('Salvar alterações'),
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: ctx,
                            builder: (dCtx) => AlertDialog(
                              title: Text('Excluir ${isDica ? 'dica' : 'curso'}?'),
                              content: const Text(
                                'Remove permanentemente do módulo Cursos e apaga arquivos no Storage.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dCtx, false),
                                  child: const Text('Cancelar'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(dCtx, true),
                                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                  child: const Text('Excluir'),
                                ),
                              ],
                            ),
                          );
                          if (confirm != true) return;
                          if (ctx.mounted) Navigator.pop(ctx);
                          await _deleteVideo(doc.id, skipConfirm: true);
                        },
                        icon: const Icon(Icons.delete_forever_rounded),
                        label: Text('Excluir ${isDica ? 'dica' : 'curso'}'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(color: Colors.red.shade300),
                          minimumSize: const Size(double.infinity, 46),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ],
                  ),
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
      if (value is FieldValue) return;
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
    patch['thumbnailUrl'] = FieldValue.delete();
  }

  String _formatPublishError(Object e) {
    if (FirestoreWebGuard.isRecoverableFirestoreWebError(e)) {
      return 'Instabilidade do Firestore na Web. Toque em Publicar de novo '
          'ou atualize a página (F5).';
    }
    final msg = e.toString().split('\n').first.trim();
    return msg.length > 180 ? '${msg.substring(0, 180)}…' : msg;
  }

  Future<T> _courseFirestoreOp<T>(Future<T> Function() fn) async {
    if (kIsWeb) {
      return runFirestoreWithRetry(
        () => FirestoreWebGuard.runWithWebRecovery(fn),
      );
    }
    return runFirestoreWithRetry(fn);
  }

  String? _videoId(Map<String, dynamic> data) {
    final stored = (data['youtubeVideoId'] ?? '').toString().trim();
    if (stored.isNotEmpty) return stored;
    final link = (data['linkUrl'] ?? data['externalUrl'] ?? data['youtubeUrl'] ?? data['videoUrl'] ?? '')
        .toString();
    return YoutubeUrlHelper.extractVideoId(link);
  }

  String? _thumbUrl(Map<String, dynamic> data) => CourseThumbResolver.resolveBest(data);

  String? _mp4Url(Map<String, dynamic> data) {
    final u = (data['mp4Url'] ?? '').toString().trim();
    return u.isEmpty ? null : u;
  }

  Future<void> _openContentPreview(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = CourseMediaUrlResolver.enrichWithDocId(doc.data(), doc.id);
    final type = (data['type'] ?? 'curso').toString();
    if (CourseMediaUrlResolver.collectVideoEntries(data).isNotEmpty ||
        _mp4Url(data) != null ||
        _videoId(data) != null) {
      await openCourseVideoFromData(context, data: data);
      return;
    }
    final link = (data['linkUrl'] ?? data['externalUrl'] ?? '').toString().trim();
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
              padding: const EdgeInsets.all(20),
              children: [
                Text((data['title'] ?? '').toString(),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                if (CourseMediaUrlResolver.hasResolvableImage(data)) ...[
                  const SizedBox(height: 12),
                  CoursePhotoGallery(data: data, height: 240),
                ],
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(body, style: TextStyle(fontSize: 14, height: 1.5, color: Colors.grey.shade800)),
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
      stream: FirebaseFirestore.instance.collection('app_config').doc(_configDoc).snapshots(),
      builder: (context, cfgSnap) {
        _hydrateConfig(cfgSnap.data?.data());
        return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          future: _courseVideosFuture,
          builder: (context, videosSnap) {
            if (videosSnap.hasError) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text('Erro: ${videosSnap.error}', style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _reloadCourseVideos,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              );
            }

            final docs = _filterDocs(_sortDocs(videosSnap.data ?? const []));
            final allCount = _sortDocs(videosSnap.data ?? const []).length;
            final dicasCount = _sortDocs(videosSnap.data ?? const [])
                .where((d) => (d.data()['type'] ?? '').toString() == 'dica')
                .length;
            final cursosCount = allCount - dicasCount;
            final syncing = videosSnap.connectionState == ConnectionState.waiting &&
                !videosSnap.hasData;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                const ModuleHeaderPremium(
                  title: 'Cursos em vídeo',
                  icon: Icons.ondemand_video_rounded,
                  subtitle:
                      'Publique aulas e dicas. O app exibe somente o que estiver marcado como publicado.',
                ),
                const SizedBox(height: 16),
                _buildConfigCard(),
                const SizedBox(height: 16),
                _buildPublishCard(),
                const SizedBox(height: 22),
                _buildGridToolbar(allCount, cursosCount, dicasCount),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F0F0F),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.video_library_rounded, color: Colors.white, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Biblioteca (${docs.length}${docs.length != allCount ? ' / $allCount' : ''})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: Colors.white,
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
                                _selectedIds.length == docs.length && docs.isNotEmpty
                                    ? Icons.deselect_rounded
                                    : Icons.select_all_rounded,
                                size: 18,
                              ),
                              label: Text(
                                _selectedIds.length == docs.length && docs.isNotEmpty
                                    ? 'Desmarcar'
                                    : 'Todos',
                              ),
                              style: TextButton.styleFrom(foregroundColor: Colors.white70),
                            ),
                            TextButton(
                              onPressed: () => setState(() {
                                _selectionMode = false;
                                _selectedIds.clear();
                              }),
                              child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
                            ),
                          ] else
                            IconButton(
                              tooltip: 'Seleção em lote',
                              onPressed: () => setState(() => _selectionMode = true),
                              icon: const Icon(Icons.checklist_rounded, color: Colors.white70),
                            ),
                        ],
                      ),
                      if (syncing)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: LinearProgressIndicator(
                            minHeight: 2,
                            color: Colors.red.shade400,
                            backgroundColor: Colors.white12,
                          ),
                        ),
                      const SizedBox(height: 12),
                      if (docs.isEmpty)
                        _emptyGrid(syncing)
                      else
                        _buildVideoGrid(docs),
                      if (_selectionMode && _selectedIds.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            children: [
                              Text(
                                '${_selectedIds.length} selecionado(s)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              const Spacer(),
                              FilledButton.icon(
                                onPressed: _deleteSelected,
                                icon: const Icon(Icons.delete_sweep_rounded),
                                label: const Text('Excluir selecionados'),
                                style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
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
                  fillColor: Colors.white,
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
        color: const Color(0xFF212121),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Icon(Icons.video_library_outlined, size: 48, color: Colors.grey.shade500),
          const SizedBox(height: 12),
          Text(
            syncing ? 'A carregar…' : 'Nenhum vídeo na biblioteca.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade400,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoGrid(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final crossCount = w >= 900 ? 3 : (w >= 560 ? 2 : 1);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: crossCount >= 3 ? 0.78 : (crossCount == 2 ? 0.82 : 0.92),
          ),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data();
            return _VideoGridCard(
              doc: docs[i],
              thumbUrl: _thumbUrl(data),
              videoId: _videoId(data),
              hasMp4: _mp4Url(data) != null,
              selectionMode: _selectionMode,
              selected: _selectedIds.contains(docs[i].id),
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
            );
          },
        );
      },
    );
  }

  Widget _buildConfigCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
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
          const Text(
            'CONFIGURAÇÃO DO MÓDULO',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
              letterSpacing: 0.5,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 12),
          FastTextField(controller: _heroTitleCtrl, decoration: _fieldDeco('Título do hero')),
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
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_rounded),
            label: Text(_savingConfig ? 'Salvando…' : 'Salvar configuração'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF475569),
              minimumSize: const Size(double.infinity, 46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPublishCard() {
    final accent = _type == 'dica'
        ? const Color(0xFFF59E0B)
        : const Color(0xFF2563EB);
    final accent2 = _type == 'dica'
        ? const Color(0xFFD97706)
        : const Color(0xFF1D4ED8);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [accent.withValues(alpha: 0.12), accent2.withValues(alpha: 0.06)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 6),
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
                  gradient: LinearGradient(colors: [accent, accent2]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.add_circle_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'PUBLICAR NOVO CONTEÚDO',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    letterSpacing: 0.5,
                    color: Color(0xFF0B1B4B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FastTextField(
            controller: _titleCtrl,
            decoration: _fieldDeco('Título', accent: accent),
          ),
          const SizedBox(height: 10),
          FastTextField(
            controller: _descriptionCtrl,
            decoration: _fieldDeco(
              _type == 'dica' ? 'Resumo curto (opcional)' : 'Descrição do curso',
              accent: accent,
            ),
            kind: FastTextFieldKind.multiline,
            maxLines: _type == 'dica' ? 3 : 4,
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
                            p.bytes,
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
                              onTap: _savingVideo ? null : () => _removePickedImage(i),
                              child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
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
            const SizedBox(height: 12),
            Text('Vídeos MP4 (até ${CourseMediaUrlResolver.maxCourseVideos})',
                style: TextStyle(fontWeight: FontWeight.w900, color: accent)),
            const SizedBox(height: 4),
            Text(
              'Envie um ou mais arquivos. Link YouTube abaixo é opcional.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _pickedVideos.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: CourseVideoFilePreview(
                  fileName: _pickedVideos[i].name ?? 'video_${i + 1}.mp4',
                  sizeBytes: _pickedVideos[i].bytes.lengthInBytes,
                  accent: accent,
                  busy: _savingVideo,
                  onRemove: _savingVideo ? null : () => _removePickedVideo(i),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _savingVideo ? null : _pickMp4Videos,
              icon: const Icon(Icons.upload_file_rounded, size: 20),
              label: Text(
                _pickedVideos.isEmpty
                    ? 'Escolher vídeos MP4'
                    : 'Adicionar vídeo (${_pickedVideos.length}/${CourseMediaUrlResolver.maxCourseVideos})',
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 46),
                side: BorderSide(color: accent),
              ),
            ),
            if (_savingVideo && _uploadProgress > 0) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: _uploadProgress,
                minHeight: 6,
                borderRadius: BorderRadius.circular(99),
                color: accent,
              ),
              const SizedBox(height: 4),
              Text(
                'Enviando… ${(_uploadProgress * 100).toStringAsFixed(0)}%',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: accent),
              ),
            ],
            const SizedBox(height: 10),
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
                      _pickedImages[i].bytes,
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
              _type == 'dica' ? 'Link — YouTube ou site (opcional)' : 'Link YouTube (opcional)',
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
            activeThumbColor: accent,
            onChanged: _savingVideo ? null : (v) => setState(() => _published = v),
          ),
          FilledButton.icon(
            onPressed: _savingVideo ? null : _publishVideo,
            icon: _savingVideo
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.smart_display_rounded),
            label: Text(_savingVideo ? 'Publicando…' : (_type == 'dica' ? 'Publicar dica' : 'Publicar curso')),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
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
            color: selected ? null : Colors.white,
            border: Border.all(
              color: selected ? Colors.transparent : gradient.first.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: selected ? Colors.white : gradient.first),
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
            color: selected ? color : Colors.white,
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
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String? thumbUrl;
  final String? videoId;
  final bool hasMp4;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onPreview;
  final VoidCallback onEdit;
  final ValueChanged<bool> onTogglePublished;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final data = {...doc.data(), 'id': doc.id};
    final title = (data['title'] ?? 'Vídeo').toString();
    final description = (data['description'] ?? '').toString();
    final body = (data['bodyText'] ?? '').toString();
    final previewText = body.isNotEmpty ? body : description;
    final type = (data['type'] ?? 'curso').toString();
    final published = data['published'] != false;
    final accent = type == 'dica'
        ? const Color(0xFFF59E0B)
        : const Color(0xFF2563EB);
    final accent2 = type == 'dica'
        ? const Color(0xFFD97706)
        : const Color(0xFF1D4ED8);
    final created = data['createdAt'];
    var dateLabel = '';
    if (created is Timestamp) {
      dateLabel = DateFormat('dd/MM/yyyy').format(created.toDate());
    }

    final hasThumb = CourseThumbResolver.hasVisualThumb(data);
    final isVideo = CourseThumbResolver.isVideoContent(data);
    final thumbFit = CourseThumbResolver.isDicaPhoto(data) ? BoxFit.contain : BoxFit.cover;

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
        borderRadius: BorderRadius.circular(12),
        child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFF212121),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? Colors.red.shade400 : Colors.white.withValues(alpha: 0.06),
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                    showPlayButton: isVideo || videoId != null || hasMp4,
                    playIconSize: 52,
                  )
                else
                  _thumbFallback(accent, accent2),
                Material(
                  color: Colors.transparent,
                    child: InkWell(
                    onTap: onPreview,
                    child: hasThumb
                        ? const SizedBox.expand()
                        : Center(
                      child: Icon(
                        hasMp4
                            ? Icons.movie_rounded
                            : (type == 'dica' && videoId == null
                                ? Icons.article_rounded
                                : Icons.play_circle_fill_rounded),
                        color: Colors.white.withValues(alpha: 0.95),
                        size: 56,
                      ),
                    ),
                  ),
                ),
                if (selectionMode)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: selected ? AppColors.primary : Colors.white,
                      child: Icon(
                        selected ? Icons.check_rounded : Icons.circle_outlined,
                        size: 18,
                        color: selected ? Colors.white : Colors.grey.shade500,
                      ),
                    ),
                  ),
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: published ? Colors.green.shade600 : Colors.grey.shade700,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      published ? 'PUBLICADO' : 'OCULTO',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      height: 1.25,
                      color: Colors.white,
                    ),
                  ),
                  if (previewText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Expanded(
                      child: Text(
                        previewText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _miniChip(sourceLabel, accent),
                      _miniChip(type.toUpperCase(), accent2),
                      _miniChip(
                        validityLabel,
                        expired ? const Color(0xFFDC2626) : const Color(0xFF64748B),
                      ),
                      if (dateLabel.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          dateLabel,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                      const Spacer(),
                      IconButton(
                        tooltip: 'Editar',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.edit_rounded, color: Colors.grey.shade300, size: 18),
                        onPressed: onEdit,
                      ),
                      IconButton(
                        tooltip: published ? 'Ocultar' : 'Publicar',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          published ? Icons.visibility_off_outlined : Icons.visibility_rounded,
                          color: Colors.grey.shade400,
                          size: 18,
                        ),
                        onPressed: () => onTogglePublished(!published),
                      ),
                      IconButton(
                        tooltip: 'Excluir',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.delete_outline_rounded,
                            color: Colors.red.shade300, size: 18),
                        onPressed: onDelete,
                      ),
                    ],
                  ),
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

  Widget _thumbFallback(Color a, Color b) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [a, b]),
      ),
      child: const Center(
        child: Icon(Icons.ondemand_video_rounded, color: Colors.white70, size: 40),
      ),
    );
  }

  Widget _miniChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
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
