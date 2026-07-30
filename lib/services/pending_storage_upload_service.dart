import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'functions_service.dart';

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

  /// Comprovante de lançamento financeiro — fila local (Android/iOS offline).
  static Future<void> enqueueFinanceReceipt({
    required String userDocId,
    required String transactionDocId,
    required Uint8List bytes,
    required String fileName,
    required String mime,
  }) async {
    if (kIsWeb || bytes.isEmpty) return;
    final dir = await getApplicationDocumentsDirectory();
    final pendingDir = Directory('${dir.path}/pending_uploads');
    if (!await pendingDir.exists()) {
      await pendingDir.create(recursive: true);
    }
    final ext = _extensionFromName(fileName, mime);
    final localPath =
        '${pendingDir.path}/finance_${transactionDocId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await File(localPath).writeAsBytes(bytes, flush: true);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kQueueKey) ?? <String>[];
    raw.add(jsonEncode({
      'kind': 'finance_receipt',
      'userDocId': userDocId,
      'transactionDocId': transactionDocId,
      'localPath': localPath,
      'mime': mime,
      'fileName': fileName,
    }));
    await prefs.setStringList(_kQueueKey, raw);
  }

  static String _extensionFromName(String fileName, String mime) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'pdf';
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'jpg';
    if (mime.contains('pdf')) return 'pdf';
    if (mime.contains('png')) return 'png';
    return 'jpg';
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
        final kind = (map['kind'] ?? '').toString();
        if (kind == 'audiencia_oficio') {
          final ok = await _drainAudienciaOficio(map);
          if (ok) {
            done++;
          } else {
            remaining.add(entry);
          }
        } else if (kind == 'finance_receipt') {
          final ok = await _drainFinanceReceipt(map);
          if (ok) {
            done++;
          } else {
            remaining.add(entry);
          }
        } else {
          remaining.add(entry);
        }
      } catch (_) {
        remaining.add(entry);
      }
    }

    await prefs.setStringList(_kQueueKey, remaining);
    return done;
  }

  static Future<bool> _drainAudienciaOficio(Map<String, dynamic> map) async {
    final userDocId = (map['userDocId'] ?? '').toString();
    final reminderDocId = (map['reminderDocId'] ?? '').toString();
    final localPath = (map['localPath'] ?? '').toString();
    final mime = (map['mime'] ?? 'application/pdf').toString();
    final fileName = (map['fileName'] ?? 'oficio').toString();
    final ext = (map['extension'] ?? 'pdf').toString();
    if (userDocId.isEmpty || reminderDocId.isEmpty || localPath.isEmpty) {
      return true;
    }
    final file = File(localPath);
    if (!await file.exists()) return true;
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
    return true;
  }

  static Future<bool> _drainFinanceReceipt(Map<String, dynamic> map) async {
    final userDocId = (map['userDocId'] ?? '').toString();
    final txId = (map['transactionDocId'] ?? '').toString();
    final localPath = (map['localPath'] ?? '').toString();
    final mime = (map['mime'] ?? 'application/pdf').toString();
    final fileName = (map['fileName'] ?? 'comprovante').toString();
    if (userDocId.isEmpty || txId.isEmpty || localPath.isEmpty) return true;
    final file = File(localPath);
    if (!await file.exists()) return true;
    final bytes = await file.readAsBytes();
    final txPath = 'users/$userDocId/transactions/$txId';
    await FunctionsService().uploadReceiptToStorage(
      txPath: txPath,
      filename: fileName,
      bytes: bytes,
      mimeType: mime,
    );
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userDocId)
        .collection('transactions')
        .doc(txId)
        .update({
      'hasReceipt': true,
      'receiptPendingUpload': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await file.delete();
    return true;
  }
}
