import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'pending_storage_upload_service.dart';

/// Upload / remoção de anexo (ofício) de audiência.
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
      final path = 'users/$userDocId/audiencias/$reminderDocId/oficio.$ext';
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putData(bytes, SettableMetadata(contentType: mimeType));
      final url = await ref.getDownloadURL();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userDocId)
          .collection('reminders')
          .doc(reminderDocId)
          .update({
        'oficioUrl': url,
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
