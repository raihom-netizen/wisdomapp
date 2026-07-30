import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../utils/connectivity_offline.dart';
import '../utils/firestore_user_doc_id.dart';
import 'functions_service.dart';
import 'pending_storage_upload_service.dart';
import 'transaction_save_service.dart';

/// Comprovante financeiro: upload imediato ou fila local (offline) — sync silencioso ao voltar rede.
class FinanceReceiptUploadService {
  FinanceReceiptUploadService._();

  static Future<bool> _isOffline() async {
    try {
      return isConnectivityOffline(await Connectivity().checkConnectivity());
    } catch (_) {
      return false;
    }
  }

  /// Anexa comprovante ao lançamento. Offline: grava na fila + marca `hasReceipt` localmente.
  static Future<void> attachToTransaction({
    required String uid,
    required String txDocId,
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    BuildContext? context,
    bool showUserFeedback = true,
  }) async {
    if (uid.isEmpty || txDocId.isEmpty || bytes.isEmpty) return;

    final fsUid = firestoreUserDocIdForAppShell(uid);
    final txPath = 'users/$fsUid/transactions/$txDocId';
    final col = TransactionSaveService.txRef(uid);

    final offline = await _isOffline();
    if (!offline) {
      try {
        await FunctionsService().uploadReceiptToStorage(
          txPath: txPath,
          filename: filename,
          bytes: bytes,
          mimeType: mimeType,
        );
        await col.doc(txDocId).update({
          'hasReceipt': true,
          'receiptPendingUpload': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (showUserFeedback && context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Comprovante enviado e vinculado ao lançamento.'),
            ),
          );
        }
        return;
      } catch (_) {
        // Rede instável — cai na fila local.
      }
    }

    await PendingStorageUploadService.enqueueFinanceReceipt(
      userDocId: fsUid,
      transactionDocId: txDocId,
      bytes: bytes,
      fileName: filename,
      mime: mimeType,
    );
    await col.doc(txDocId).update({
      'hasReceipt': true,
      'receiptPendingUpload': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (showUserFeedback && context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            offline
                ? 'Comprovante guardado no aparelho; envia automaticamente quando houver internet.'
                : 'Comprovante na fila local; tentaremos enviar em breve.',
          ),
        ),
      );
    }
  }
}
