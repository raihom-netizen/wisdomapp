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
import '../theme/app_colors.dart';
import '../utils/course_content_link_helper.dart';
import '../utils/firestore_retry.dart';
import '../utils/firestore_web_guard.dart';
import '../utils/youtube_url_helper.dart';
import '../widgets/course_media_preview.dart';
import '../widgets/course_mp4_player_dialog.dart';
import '../widgets/fast_text_field.dart';
import '../widgets/module_header_premium.dart';
import '../widgets/youtube_video_player_dialog.dart';

/// Painel Admin → Cursos em vídeo: publicar, editar e pré-visualizar conteúdo.
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
  int _retryGen = 0;
  int _gridTab = 0;
  String _dateFilter = 'recent';
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  Uint8List? _pickedImageBytes;
  String? _pickedImageMime;
  String? _pickedImageName;
  Uint8List? _pickedVideoBytes;
  String? _pickedVideoMime;
  String? _pickedVideoName;
  double _uploadProgress = 0;

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

  Future<void> _pickMp4Video() async {
    try {
      final pick = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp4', 'mov', 'webm'],
        withData: true,
      );
      if (pick == null || pick.files.isEmpty) return;
      final f = pick.files.first;
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) {
        _snack('Não foi possível ler o vídeo. Tente outro arquivo.');
        return;
      }
      if (bytes.lengthInBytes > CourseVideoFileService.maxBytes) {
        _snack('Vídeo grande demais. Máx. 250 MB.');
        return;
      }
      var ext = (f.extension ?? 'mp4').toLowerCase();
      final mime = ext == 'webm'
          ? 'video/webm'
          : (ext == 'mov' ? 'video/quicktime' : 'video/mp4');
      setState(() {
        _pickedVideoBytes = bytes;
        _pickedVideoMime = mime;
        _pickedVideoName = f.name;
      });
    } catch (e) {
      _snack('Erro ao selecionar vídeo: $e');
    }
  }

  void _clearPickedVideo() {
    setState(() {
      _pickedVideoBytes = null;
      _pickedVideoMime = null;
      _pickedVideoName = null;
      _uploadProgress = 0;
    });
  }

  Future<void> _pickCoverImage() async {
    try {
      final pick = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );
      if (pick == null || pick.files.isEmpty) return;
      final f = pick.files.first;
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) {
        _snack('Não foi possível ler a imagem.');
        return;
      }
      if (bytes.lengthInBytes > CourseVideoImageService.maxBytes) {
        _snack('Imagem grande demais. Máx. 5 MB.');
        return;
      }
      var ext = (f.extension ?? 'jpg').toLowerCase();
      if (ext == 'jpeg') ext = 'jpg';
      final mime = ext == 'png'
          ? 'image/png'
          : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
      setState(() {
        _pickedImageBytes = bytes;
        _pickedImageMime = mime;
        _pickedImageName = f.name;
      });
    } catch (e) {
      _snack('Erro ao selecionar imagem: $e');
    }
  }

  void _clearPickedImage() {
    setState(() {
      _pickedImageBytes = null;
      _pickedImageMime = null;
      _pickedImageName = null;
    });
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
    await _courseFirestoreOp(() async {
      final batch = FirebaseFirestore.instance.batch();
      for (final id in _selectedIds) {
        batch.delete(
            FirebaseFirestore.instance.collection('course_videos').doc(id));
      }
      await batch.commit();
    });
    setState(() {
      _selectedIds.clear();
      _selectionMode = false;
    });
    _snack('$n conteúdo(s) removido(s).');
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
      await _courseFirestoreOp(() => FirebaseFirestore.instance
          .collection('app_config')
          .doc(_configDoc)
          .set({
        ...cfg.toFirestore(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByEmail': email,
      }, SetOptions(merge: true)));
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
      final hasMp4 = _pickedVideoBytes != null && _pickedVideoMime != null;
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
          _pickedImageBytes == null &&
          !linkOk) {
        _snack('Informe texto, imagem ou link para a dica.');
        return;
      }
    }

    setState(() => _savingVideo = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final email = FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
      final docRef = FirebaseFirestore.instance.collection('course_videos').doc();

      if (_type == 'curso') {
        final youtubeRaw = _youtubeCtrl.text.trim();
        final hasYoutube = youtubeRaw.isNotEmpty;
        final hasMp4 = _pickedVideoBytes != null && _pickedVideoMime != null;

        String? videoId;
        String? youtubeUrl;
        String? mp4Url;
        String? thumbUrl;

        if (hasYoutube) {
          videoId = YoutubeUrlHelper.extractVideoId(youtubeRaw)!;
          youtubeUrl = YoutubeUrlHelper.watchUrl(videoId);
          thumbUrl = YoutubeUrlHelper.thumbnailUrl(videoId);
        }

        if (hasMp4 && _pickedVideoMime != null) {
          setState(() => _uploadProgress = 0);
          mp4Url = await CourseVideoFileService.uploadVideo(
            bytes: _pickedVideoBytes!,
            mimeType: _pickedVideoMime!,
            docId: docRef.id,
            onProgress: (p) {
              if (mounted) setState(() => _uploadProgress = p);
            },
          );
        }

        if (_pickedImageBytes != null && _pickedImageMime != null) {
          thumbUrl = await CourseVideoImageService.uploadCover(
            bytes: _pickedImageBytes!,
            mimeType: _pickedImageMime!,
            docId: docRef.id,
          );
        }

        final source = hasMp4 && hasYoutube
            ? 'upload_youtube'
            : (hasMp4 ? 'upload' : 'youtube');

        await _courseFirestoreOp(() => docRef.set({
          'title': title,
          'description': _descriptionCtrl.text.trim(),
          'bodyText': '',
          'type': 'curso',
          'source': source,
          if (mp4Url != null) 'mp4Url': mp4Url,
          if (youtubeUrl != null) ...{
            'videoUrl': youtubeUrl,
            'youtubeUrl': youtubeUrl,
            'youtubeVideoId': videoId,
          },
          'thumbnailUrl': thumbUrl ?? '',
          if (thumbUrl != null && thumbUrl.isNotEmpty) 'imageUrl': thumbUrl,
          'published': _published,
          'authorUid': uid,
          'authorEmail': email,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }));
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
        String? imageUrl;
        if (_pickedImageBytes != null && _pickedImageMime != null) {
          imageUrl = await CourseVideoImageService.uploadCover(
            bytes: _pickedImageBytes!,
            mimeType: _pickedImageMime!,
            docId: docRef.id,
          );
        }
        final source = videoId != null
            ? 'youtube'
            : (imageUrl != null && linkUrl != null)
                ? 'image_link'
                : (imageUrl != null ? 'image' : 'link');
        await _courseFirestoreOp(() => docRef.set({
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
          if (imageUrl != null) 'imageUrl': imageUrl,
          'thumbnailUrl': imageUrl ?? ytThumb ?? '',
          'published': _published,
          'authorUid': uid,
          'authorEmail': email,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }));
      }

      _titleCtrl.clear();
      _descriptionCtrl.clear();
      _bodyTextCtrl.clear();
      _youtubeCtrl.clear();
      _clearPickedImage();
      _clearPickedVideo();
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
    Uint8List? newImageBytes,
    String? newImageMime,
    bool removeImage = false,
    Uint8List? newVideoBytes,
    String? newVideoMime,
    bool removeMp4 = false,
  }) async {
    if (title.isEmpty) {
      _snack('Informe o título.');
      return false;
    }

    try {
    final patch = <String, dynamic>{
      'title': title,
      'description': description,
      'bodyText': bodyText,
      'type': type,
      'published': published,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (type == 'curso') {
      final existing = await _courseFirestoreOp(() => FirebaseFirestore.instance
          .collection('course_videos')
          .doc(docId)
          .get());
      final existingData = existing.data() ?? {};
      var mp4Url = (existingData['mp4Url'] ?? '').toString().trim();
      String? videoId;
      String? youtubeUrl;
      String? thumbUrl = (existingData['thumbnailUrl'] ?? '').toString();

      if (removeMp4) mp4Url = '';
      if (newVideoBytes != null && newVideoMime != null) {
        mp4Url = await CourseVideoFileService.uploadVideo(
          bytes: newVideoBytes,
          mimeType: newVideoMime,
          docId: docId,
        );
      }

      if (linkRaw.isNotEmpty) {
        if (!YoutubeUrlHelper.isValidYoutubeUrl(linkRaw)) {
          _snack('URL do YouTube inválida.');
          return false;
        }
        videoId = YoutubeUrlHelper.extractVideoId(linkRaw)!;
        youtubeUrl = YoutubeUrlHelper.watchUrl(videoId);
        if ((existingData['imageUrl'] ?? '').toString().isEmpty) {
          thumbUrl = YoutubeUrlHelper.thumbnailUrl(videoId);
        }
      } else {
        patch['videoUrl'] = FieldValue.delete();
        patch['youtubeUrl'] = FieldValue.delete();
        patch['youtubeVideoId'] = FieldValue.delete();
      }

      if (mp4Url.isEmpty && videoId == null) {
        _snack('Informe vídeo MP4 ou link YouTube.');
        return false;
      }

      if (removeImage) {
        patch['imageUrl'] = FieldValue.delete();
      }
      if (newImageBytes != null && newImageMime != null) {
        thumbUrl = await CourseVideoImageService.uploadCover(
          bytes: newImageBytes,
          mimeType: newImageMime,
          docId: docId,
        );
        patch['imageUrl'] = thumbUrl;
      }

      final hasMp4 = mp4Url.isNotEmpty;
      final hasYt = videoId != null;
      patch['source'] = hasMp4 && hasYt
          ? 'upload_youtube'
          : (hasMp4 ? 'upload' : 'youtube');
      if (hasMp4) {
        patch['mp4Url'] = mp4Url;
      } else {
        patch['mp4Url'] = FieldValue.delete();
      }
      if (hasYt) {
        patch.addAll({
          'videoUrl': youtubeUrl,
          'youtubeUrl': youtubeUrl,
          'youtubeVideoId': videoId,
        });
      }
      patch['thumbnailUrl'] = thumbUrl;
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

      if (removeImage) {
        patch['imageUrl'] = FieldValue.delete();
      }
      if (newImageBytes != null && newImageMime != null) {
        final imageUrl = await CourseVideoImageService.uploadCover(
          bytes: newImageBytes,
          mimeType: newImageMime,
          docId: docId,
        );
        patch['imageUrl'] = imageUrl;
      }

      final imageUrl = (patch['imageUrl'] is String) ? patch['imageUrl'] as String : null;
      final source = videoId != null
          ? 'youtube'
          : (imageUrl != null && linkUrl != null)
              ? 'image_link'
              : (imageUrl != null ? 'image' : (linkUrl != null ? 'link' : 'text'));
      patch['source'] = source;
      patch['thumbnailUrl'] = imageUrl ?? ytThumb ?? '';
    }

    await _courseFirestoreOp(() => FirebaseFirestore.instance
        .collection('course_videos')
        .doc(docId)
        .set(patch, SetOptions(merge: true)));
    _snack('Alterações salvas.');
    return true;
    } catch (e) {
      _snack('Erro ao salvar: ${_formatPublishError(e)}');
      return false;
    }
  }

  Future<void> _togglePublished(String docId, bool value) async {
    await _courseFirestoreOp(() => FirebaseFirestore.instance
        .collection('course_videos')
        .doc(docId)
        .set({
      'published': value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)));
  }

  Future<void> _deleteVideo(String docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir conteúdo?'),
        content: const Text('Remove do módulo Cursos. Esta ação não pode ser desfeita.'),
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
    await _courseFirestoreOp(() => FirebaseFirestore.instance
        .collection('course_videos')
        .doc(docId)
        .delete());
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
    var existingImageUrl = (data['imageUrl'] ?? '').toString();
    var existingMp4Url = (data['mp4Url'] ?? '').toString();
    Uint8List? editImageBytes;
    String? editImageMime;
    Uint8List? editVideoBytes;
    String? editVideoMime;
    String? editVideoName;
    var removeImage = false;
    var removeMp4 = false;

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
                        Text('Imagem da dica', style: TextStyle(fontWeight: FontWeight.w800, color: accent)),
                        const SizedBox(height: 8),
                        if (editImageBytes != null)
                          CourseImagePreview(
                            bytes: editImageBytes,
                            maxHeight: 180,
                            subtitle: 'Nova imagem',
                          )
                        else if (existingImageUrl.isNotEmpty && !removeImage)
                          CourseImagePreview(
                            networkUrl: existingImageUrl,
                            maxHeight: 180,
                          ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () async {
                                final pick = await FilePicker.platform.pickFiles(
                                  type: FileType.custom,
                                  allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
                                  withData: true,
                                );
                                if (pick == null || pick.files.isEmpty) return;
                                final f = pick.files.first;
                                final bytes = f.bytes;
                                if (bytes == null) return;
                                var ext = (f.extension ?? 'jpg').toLowerCase();
                                if (ext == 'jpeg') ext = 'jpg';
                                setLocal(() {
                                  editImageBytes = bytes;
                                  editImageMime = ext == 'png'
                                      ? 'image/png'
                                      : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
                                  removeImage = false;
                                });
                              },
                              icon: const Icon(Icons.image_rounded, size: 18),
                              label: const Text('Trocar imagem'),
                            ),
                            if (existingImageUrl.isNotEmpty || editImageBytes != null)
                              OutlinedButton.icon(
                                onPressed: () => setLocal(() {
                                  editImageBytes = null;
                                  editImageMime = null;
                                  removeImage = true;
                                  existingImageUrl = '';
                                }),
                                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                label: const Text('Remover'),
                              ),
                          ],
                        ),
                      ] else ...[
                        const SizedBox(height: 12),
                        Text('Vídeo MP4 (anexo)', style: TextStyle(fontWeight: FontWeight.w800, color: accent)),
                        const SizedBox(height: 6),
                        if (editVideoBytes != null)
                          CourseVideoFilePreview(
                            fileName: editVideoName ?? 'video.mp4',
                            sizeBytes: editVideoBytes!.lengthInBytes,
                            accent: accent,
                            onRemove: () => setLocal(() {
                              editVideoBytes = null;
                              editVideoMime = null;
                              editVideoName = null;
                            }),
                          )
                        else if (existingMp4Url.isNotEmpty && !removeMp4)
                          CourseVideoFilePreview(
                            fileName: 'Vídeo MP4 publicado',
                            sizeBytes: 0,
                            accent: accent,
                            onRemove: () => setLocal(() {
                              removeMp4 = true;
                              existingMp4Url = '';
                            }),
                          ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () async {
                                final pick = await FilePicker.platform.pickFiles(
                                  type: FileType.custom,
                                  allowedExtensions: ['mp4', 'mov', 'webm'],
                                  withData: true,
                                );
                                if (pick == null || pick.files.isEmpty) return;
                                final f = pick.files.first;
                                final bytes = f.bytes;
                                if (bytes == null || bytes.isEmpty) return;
                                var ext = (f.extension ?? 'mp4').toLowerCase();
                                setLocal(() {
                                  editVideoBytes = bytes;
                                  editVideoMime = ext == 'webm'
                                      ? 'video/webm'
                                      : (ext == 'mov' ? 'video/quicktime' : 'video/mp4');
                                  editVideoName = f.name;
                                  removeMp4 = false;
                                });
                              },
                              icon: const Icon(Icons.upload_file_rounded, size: 18),
                              label: Text(existingMp4Url.isNotEmpty || editVideoBytes != null
                                  ? 'Trocar MP4'
                                  : 'Anexar MP4'),
                            ),
                            if (existingMp4Url.isNotEmpty || editVideoBytes != null)
                              OutlinedButton.icon(
                                onPressed: () => setLocal(() {
                                  editVideoBytes = null;
                                  editVideoMime = null;
                                  removeMp4 = true;
                                  existingMp4Url = '';
                                }),
                                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                label: const Text('Remover MP4'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text('Capa personalizada (opcional)', style: TextStyle(fontWeight: FontWeight.w800, color: accent)),
                        const SizedBox(height: 8),
                        if (editImageBytes != null)
                          CourseImagePreview(
                            bytes: editImageBytes,
                            maxHeight: 160,
                            subtitle: 'Capa do curso',
                          )
                        else if (existingImageUrl.isNotEmpty && !removeImage)
                          CourseImagePreview(
                            networkUrl: existingImageUrl,
                            maxHeight: 160,
                            subtitle: 'Capa atual',
                          ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final pick = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
                              withData: true,
                            );
                            if (pick == null || pick.files.isEmpty) return;
                            final bytes = pick.files.first.bytes;
                            if (bytes == null) return;
                            var ext = (pick.files.first.extension ?? 'jpg').toLowerCase();
                            setLocal(() {
                              editImageBytes = bytes;
                              editImageMime = ext == 'png' ? 'image/png' : 'image/jpeg';
                              removeImage = false;
                            });
                          },
                          icon: const Icon(Icons.image_rounded, size: 18),
                          label: const Text('Capa / thumbnail'),
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
                            newImageBytes: editImageBytes,
                            newImageMime: editImageMime,
                            removeImage: removeImage,
                            newVideoBytes: editVideoBytes,
                            newVideoMime: editVideoMime,
                            removeMp4: removeMp4,
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

  String? _thumbUrl(Map<String, dynamic> data) {
    final img = (data['imageUrl'] ?? '').toString().trim();
    if (img.isNotEmpty) return img;
    final thumb = (data['thumbnailUrl'] ?? '').toString().trim();
    if (thumb.isNotEmpty) return thumb;
    final id = _videoId(data);
    if (id != null) return YoutubeUrlHelper.thumbnailUrl(id);
    return null;
  }

  String? _mp4Url(Map<String, dynamic> data) {
    final u = (data['mp4Url'] ?? '').toString().trim();
    return u.isEmpty ? null : u;
  }

  Future<void> _openContentPreview(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
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
      final img = (data['imageUrl'] ?? '').toString();
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
                if (img.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  CourseImagePreview(networkUrl: img, maxHeight: 220),
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
    // ignore: unused_local_variable
    final _ = _retryGen;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('app_config').doc(_configDoc).snapshots(),
      builder: (context, cfgSnap) {
        _hydrateConfig(cfgSnap.data?.data());
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('course_videos').snapshots(),
          builder: (context, videosSnap) {
            if (videosSnap.hasError) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text('Erro: ${videosSnap.error}', style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => setState(() => _retryGen++),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              );
            }

            final docs = _filterDocs(_sortDocs(videosSnap.data?.docs ?? const []));
            final allCount = _sortDocs(videosSnap.data?.docs ?? const []).length;
            final dicasCount = _sortDocs(videosSnap.data?.docs ?? const [])
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
            Text('Imagem da dica (opcional)', style: TextStyle(fontWeight: FontWeight.w800, color: accent)),
            const SizedBox(height: 8),
            if (_pickedImageBytes != null)
              CourseImagePreview(
                bytes: _pickedImageBytes,
                maxHeight: 180,
                subtitle: _pickedImageName,
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _savingVideo ? null : _pickCoverImage,
                  icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
                  label: Text(_pickedImageBytes == null ? 'Escolher imagem' : 'Trocar imagem'),
                ),
                if (_pickedImageBytes != null)
                  OutlinedButton.icon(
                    onPressed: _savingVideo ? null : _clearPickedImage,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Remover'),
                  ),
                if (_pickedImageName != null)
                  Text(_pickedImageName!, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text('Anexar vídeo MP4', style: TextStyle(fontWeight: FontWeight.w900, color: accent)),
            const SizedBox(height: 4),
            Text(
              'Envie o arquivo do curso. Link YouTube abaixo é opcional.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            if (_pickedVideoBytes != null)
              CourseVideoFilePreview(
                fileName: _pickedVideoName ?? 'video.mp4',
                sizeBytes: _pickedVideoBytes!.lengthInBytes,
                accent: accent,
                busy: _savingVideo,
                onRemove: _savingVideo ? null : _clearPickedVideo,
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _savingVideo ? null : _pickMp4Video,
              icon: const Icon(Icons.upload_file_rounded, size: 20),
              label: Text(_pickedVideoBytes == null ? 'Escolher arquivo MP4' : 'Trocar vídeo'),
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
            Text('Capa / thumbnail (opcional)', style: TextStyle(fontWeight: FontWeight.w800, color: accent)),
            const SizedBox(height: 8),
            if (_pickedImageBytes != null)
              CourseImagePreview(
                bytes: _pickedImageBytes,
                maxHeight: 160,
                subtitle: 'Capa do curso',
              ),
            OutlinedButton.icon(
              onPressed: _savingVideo ? null : _pickCoverImage,
              icon: const Icon(Icons.image_rounded, size: 18),
              label: const Text('Imagem de capa'),
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
    final data = doc.data();
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

    final dicaPhoto = type == 'dica' && (data['imageUrl'] ?? '').toString().trim().isNotEmpty;
    final thumbFit = dicaPhoto ? BoxFit.contain : BoxFit.cover;

    final sourceLabel = hasMp4
        ? (videoId != null ? 'MP4+YT' : 'MP4')
        : (videoId != null ? 'YOUTUBE' : (type == 'dica' ? 'DICA' : 'VÍDEO'));

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
                if (thumbUrl != null && thumbUrl!.isNotEmpty)
                  CourseCoverImage(
                    url: thumbUrl!,
                    fit: thumbFit,
                    fallback: _thumbFallback(accent, accent2),
                  )
                else if (videoId != null)
                  CourseCoverImage(
                    url: YoutubeUrlHelper.thumbnailUrl(videoId!),
                    fit: BoxFit.cover,
                    fallback: _thumbFallback(accent, accent2),
                  )
                else
                  _thumbFallback(accent, accent2),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.5),
                      ],
                    ),
                  ),
                ),
                Material(
                  color: Colors.transparent,
                    child: InkWell(
                    onTap: onPreview,
                    child: Center(
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
