import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/wisdom_media_upload.dart';
import 'pending_storage_upload_service.dart';

/// Upload / remocao de anexo (oficio) de audiencia.
///
/// Usa [WisdomMediaUpload] com retry + URL timeout (padrao Controle Total).
class AudienciaOficioUploadService {
  AudienciaOficioUploadService._();

  static Future<void> applyChange({
    required String userDocId,
    required String reminderDocId,
    bool removeOficio = false,
    Uint8List? bytes,
    String? fileName,
    String? mime,
    String? extension,
  }) async {
    if (removeOficio) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userDocId)
            .collection('reminders')
            .doc(reminderDocId)
            .update({
          'oficioUrl': '',
          'oficioFileName': '',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
      return;
    }

    if (bytes == null || bytes.isEmpty) return;

    final ext = (extension ?? 'pdf').toLowerCase();
    final mimeType = mime ?? 'application/pdf';
    final name = fileName ?? 'oficio.$ext';

    try {
      final result = await WisdomMediaUpload.uploadOficio(
        userId: userDocId,
        reminderId: reminderDocId,
        bytes: bytes,
        mimeType: mimeType,
        extension: ext,
      );
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userDocId)
          .collection('reminders')
          .doc(reminderDocId)
          .update({
        'oficioUrl': result.downloadUrl,
        'oficioStoragePath': result.storagePath, // padrao CT: guarda path tambem
        'oficioFileName': name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      if (!kIsWeb) {
        await PendingStorageUploadService.enqueueOficio(
          userDocId: userDocId,
          reminderDocId: reminderDocId,
          bytes: bytes,
          extension: ext,
          mime: mimeType,
          fileName: name,
        );
      }
    }
  }
}
