import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fila local de uploads (ex.: ofício de audiência) quando não há rede.
class PendingStorageUploadService {
  PendingStorageUploadService._();

  static const _kQueueKey = 'pending_storage_uploads_v1';

  static Future<void> enqueueOficio({
    required String userDocId,
    required String reminderDocId,
    required Uint8List bytes,
    required String extension,
    required String mime,
    required String fileName,
  }) async {
    if (kIsWeb || bytes.isEmpty) return;
    final dir = await getApplicationDocumentsDirectory();
    final pendingDir = Directory('${dir.path}/pending_uploads');
    if (!await pendingDir.exists()) {
      await pendingDir.create(recursive: true);
    }
    final ext = extension.toLowerCase();
    final localPath =
        '${pendingDir.path}/${reminderDocId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await File(localPath).writeAsBytes(bytes, flush: true);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kQueueKey) ?? <String>[];
    raw.add(jsonEncode({
      'kind': 'audiencia_oficio',
      'userDocId': userDocId,
      'reminderDocId': reminderDocId,
      'localPath': localPath,
      'mime': mime,
      'fileName': fileName,
      'extension': ext,
    }));
    await prefs.setStringList(_kQueueKey, raw);
  }

  /// Envia pendências e atualiza Firestore. Retorna quantos itens concluíram.
  static Future<int> drainAll() async {
    if (kIsWeb) return 0;
    final prefs = await SharedPreferences.getInstance();
    final raw = List<String>.from(prefs.getStringList(_kQueueKey) ?? const []);
    if (raw.isEmpty) return 0;

    var done = 0;
    final remaining = <String>[];

    for (final entry in raw) {
      try {
        final map = jsonDecode(entry) as Map<String, dynamic>;
        if (map['kind'] != 'audiencia_oficio') continue;
        final userDocId = (map['userDocId'] ?? '').toString();
        final reminderDocId = (map['reminderDocId'] ?? '').toString();
        final localPath = (map['localPath'] ?? '').toString();
        final mime = (map['mime'] ?? 'application/pdf').toString();
        final fileName = (map['fileName'] ?? 'oficio').toString();
        final ext = (map['extension'] ?? 'pdf').toString();
        if (userDocId.isEmpty ||
            reminderDocId.isEmpty ||
            localPath.isEmpty) {
          continue;
        }
        final file = File(localPath);
        if (!await file.exists()) {
          done++;
          continue;
        }
        final bytes = await file.readAsBytes();
        final path = 'users/$userDocId/audiencias/$reminderDocId/oficio.$ext';
        final ref = FirebaseStorage.instance.ref(path);
        await ref.putData(bytes, SettableMetadata(contentType: mime));
        final url = await ref.getDownloadURL();
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userDocId)
            .collection('reminders')
            .doc(reminderDocId)
            .update({
          'oficioUrl': url,
          'oficioFileName': fileName,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        await file.delete();
        done++;
      } catch (_) {
        remaining.add(entry);
      }
    }

    await prefs.setStringList(_kQueueKey, remaining);
    return done;
  }
}
