import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/currency_formats.dart';
import '../models/finance_account.dart';
import '../utils/finance_transaction_datetime.dart';
import '../utils/firestore_user_doc_id.dart';
import 'functions_service.dart';
import 'logs_service.dart';

/// Cria transferência entre contas (Cloud Function com fallback em batch local).
class FinanceTransferService {
  FinanceTransferService._();
  static final FinanceTransferService instance = FinanceTransferService._();

  Future<void> createTransfer({
    required String uid,
    required FinanceAccount fromAcc,
    required FinanceAccount toAcc,
    required double amount,
    required DateTime selectedCalendarDay,
    String note = '',
    String logModulo = 'Financeiro',
    Uint8List? receiptBytes,
    String? receiptName,
    String? receiptMime,
  }) async {
    final fsUid = firestoreUserDocIdForAppShell(uid);
    final transferAt = FinanceTransactionDatetime.mergeCalendarDayWithClockNow(selectedCalendarDay);
    final histLine = '${fromAcc.displayName} → ${toAcc.displayName}';

    String? outId;
    String? inId;
    try {
      final res = await FunctionsService().createFinanceTransfer(
        amount: amount,
        fromAccountId: fromAcc.id,
        toAccountId: toAcc.id,
        fromLabel: fromAcc.displayName,
        toLabel: toAcc.displayName,
        dateISO: transferAt.toIso8601String(),
        note: note,
      );
      outId = (res['outId'] ?? '').toString();
      inId = (res['inId'] ?? '').toString();
    } catch (_) {
      final local = await _createTransferBatchLocal(
        fsUid: fsUid,
        fromId: fromAcc.id,
        toId: toAcc.id,
        fromLabel: fromAcc.displayName,
        toLabel: toAcc.displayName,
        amount: amount,
        transferAt: transferAt,
        note: note,
      );
      outId = local.outId;
      inId = local.inId;
    }

    if (receiptBytes != null &&
        receiptBytes.isNotEmpty &&
        (receiptName ?? '').trim().isNotEmpty &&
        (receiptMime ?? '').trim().isNotEmpty) {
      await _attachReceiptToLegs(
        fsUid: fsUid,
        outId: outId,
        inId: inId,
        bytes: receiptBytes,
        name: receiptName!.trim(),
        mime: receiptMime!.trim(),
      );
    }

    await LogsService().saveLog(
      modulo: logModulo,
      acao: 'Transferência entre contas',
      detalhes: '$histLine • ${CurrencyFormats.formatBRL(amount)}',
    );
  }

  Future<void> attachReceiptToTransferLegs({
    required String uid,
    required List<String> docIds,
    required Uint8List bytes,
    required String name,
    required String mime,
  }) async {
    final fsUid = firestoreUserDocIdForAppShell(uid);
    final fn = FunctionsService();
    final col = FirebaseFirestore.instance.collection('users').doc(fsUid).collection('transactions');
    for (final id in docIds) {
      if (id.trim().isEmpty) continue;
      final txPath = 'users/$fsUid/transactions/$id';
      await fn.uploadReceiptToStorage(txPath: txPath, filename: name, bytes: bytes, mimeType: mime);
      await col.doc(id).update({'hasReceipt': true, 'updatedAt': FieldValue.serverTimestamp()});
    }
  }

  Future<void> removeReceiptFromTransferLegs({
    required String uid,
    required List<String> docIds,
  }) async {
    if (docIds.isEmpty) return;
    final fsUid = firestoreUserDocIdForAppShell(uid);
    final col = FirebaseFirestore.instance.collection('users').doc(fsUid).collection('transactions');
    final batch = FirebaseFirestore.instance.batch();
    for (final id in docIds) {
      if (id.trim().isEmpty) continue;
      batch.update(col.doc(id), {
        'receipt': FieldValue.delete(),
        'hasReceipt': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> _attachReceiptToLegs({
    required String fsUid,
    required String? outId,
    required String? inId,
    required Uint8List bytes,
    required String name,
    required String mime,
  }) async {
    final fn = FunctionsService();
    final col = FirebaseFirestore.instance.collection('users').doc(fsUid).collection('transactions');
    for (final id in [outId, inId]) {
      if (id == null || id.trim().isEmpty) continue;
      final txPath = 'users/$fsUid/transactions/$id';
      await fn.uploadReceiptToStorage(txPath: txPath, filename: name, bytes: bytes, mimeType: mime);
      await col.doc(id).update({
        'hasReceipt': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<({String pairId, String outId, String inId})> _createTransferBatchLocal({
    required String fsUid,
    required String fromId,
    required String toId,
    required String fromLabel,
    required String toLabel,
    required double amount,
    required DateTime transferAt,
    required String note,
  }) async {
    final pairId = 'tr_${DateTime.now().microsecondsSinceEpoch}';
    final notePart = note.trim().isEmpty ? '' : ' • ${note.trim()}';
    final histLine = '$fromLabel → $toLabel';
    final descOut = 'Saída • Transferência • $histLine$notePart';
    final descIn = 'Entrada • Transferência • $histLine$notePart';
    final transferTs = Timestamp.fromDate(transferAt);

    final col = FirebaseFirestore.instance.collection('users').doc(fsUid).collection('transactions');
    final batch = FirebaseFirestore.instance.batch();
    final outRef = col.doc();
    final inRef = col.doc();
    batch.set(outRef, {
      'type': 'expense',
      'amount': amount,
      'category': 'Transferência',
      'description': descOut,
      'status': 'paid',
      'date': transferTs,
      'paidAt': transferTs,
      'effectiveDate': transferTs,
      'financeAccountId': fromId,
      'transferPairId': pairId,
      'transferDirection': 'out',
      'transferCounterpartyAccountId': toId,
      'transferCounterpartyLabel': toLabel,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(inRef, {
      'type': 'income',
      'amount': amount,
      'category': 'Transferência',
      'description': descIn,
      'status': 'paid',
      'date': transferTs,
      'paidAt': transferTs,
      'effectiveDate': transferTs,
      'financeAccountId': toId,
      'transferPairId': pairId,
      'transferDirection': 'in',
      'transferCounterpartyAccountId': fromId,
      'transferCounterpartyLabel': fromLabel,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return (pairId: pairId, outId: outRef.id, inId: inRef.id);
  }
}
