import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/currency_formats.dart';
import '../utils/finance_line_opening.dart';
import '../utils/finance_transaction_datetime.dart';
import '../utils/finance_transactions_hub.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/connectivity_offline.dart';
import '../utils/receipt_attachment_utils.dart';
import 'functions_service.dart';
import 'logs_service.dart';

/// Resultado de [TransactionSaveService.saveFromNovoLancamentoResult] para UI otimista.
class TransactionSaveResult {
  final List<String> docIds;
  const TransactionSaveResult({required this.docIds});
}

/// Persistência de lançamentos (receita/despesa) compartilhada entre Financeiro e atalhos (ex.: Início).
class TransactionSaveService {
  TransactionSaveService._();

  static CollectionReference<Map<String, dynamic>> txRef(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(firestoreUserDocIdForAppShell(uid))
          .collection('transactions');

  /// Evita segundo lançamento de fechamento de Escalas para o mesmo vínculo + período.
  static Future<bool> transactionExistsWithScaleClosureDedupKey(
      String uid, String dedupKey) async {
    final k = dedupKey.trim();
    if (k.isEmpty) return false;
    final q = await txRef(uid)
        .where('scaleClosureDedupKey', isEqualTo: k)
        .limit(1)
        .get();
    return q.docs.isNotEmpty;
  }

  /// Uma leitura em lote (chunks de 30 — limite `whereIn` do Firestore) em vez de N queries.
  static Future<Set<String>> existingScaleClosureDedupKeys(
    String uid,
    Iterable<String> dedupKeys,
  ) async {
    final want =
        dedupKeys.map((k) => k.trim()).where((k) => k.isNotEmpty).toSet();
    if (want.isEmpty) return {};
    final found = <String>{};
    final list = want.toList();
    const chunkSize = 30;
    for (var i = 0; i < list.length; i += chunkSize) {
      final chunk = list.sublist(i, math.min(i + chunkSize, list.length));
      final snap =
          await txRef(uid).where('scaleClosureDedupKey', whereIn: chunk).get();
      for (final d in snap.docs) {
        final k = d.data()['scaleClosureDedupKey']?.toString().trim();
        if (k != null && k.isNotEmpty) found.add(k);
      }
    }
    return found;
  }

  /// Fechamento Escalas: grava várias receitas com poucos round-trips (batch ≤500 ops cada).
  /// Cada item usa o mesmo formato que [saveFromNovoLancamentoResult] com parcela única e tipo receita.
  static Future<int> saveScaleClosureIncomeBatch({
    required String uid,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) return 0;
    final col = txRef(uid);
    var totalWritten = 0;

    for (var start = 0; start < items.length; start += 500) {
      final end = math.min(start + 500, items.length);
      final slice = items.sublist(start, end);
      final batch = FirebaseFirestore.instance.batch();
      var ops = 0;
      for (final data in slice) {
        final rawAmount = data['amount'];
        double amount;
        if (rawAmount is num) {
          amount = rawAmount.toDouble();
        } else if (rawAmount is String) {
          amount = CurrencyFormats.parseBRLInput(rawAmount) ?? 0;
        } else {
          amount = 0;
        }
        if (amount.isNaN || amount.isInfinite || amount <= 0) continue;

        final category = (data['category'] ?? '').toString();
        final description = (data['description'] ?? '').toString();
        final status = (data['status'] ?? 'paid').toString();
        DateTime date = data['date'] is DateTime
            ? data['date'] as DateTime
            : DateTime.now();
        if ((data['source'] ?? '').toString() != 'open_finance') {
          date = FinanceTransactionDatetime.mergeCalendarDayWithClockNow(date);
        }
        final recurrence = (data['recurrence'] ?? 'none').toString();
        final financeAccountId =
            (data['financeAccountId'] ?? '').toString().trim();

        final ref = col.doc();
        batch.set(ref, {
          'type': 'income',
          'amount': amount,
          'category': category,
          'description': description,
          'status': status,
          'date': Timestamp.fromDate(date),
          'effectiveDate':
              FinanceLineOpening.effectiveTimestampForWrite(date: date),
          'recurrence': recurrence,
          'installmentCount': 1,
          'installmentIndex': 1,
          if (financeAccountId.isNotEmpty) 'financeAccountId': financeAccountId,
          ..._optionalClosureAndSourceFields(data),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        ops++;
      }
      if (ops > 0) {
        await batch.commit();
        totalWritten += ops;
      }
    }

    if (totalWritten > 0) {
      unawaited(
        LogsService()
            .saveLog(
              modulo: 'Financeiro',
              acao: 'Criou receitas (fechamento Escalas)',
              detalhes: '$totalWritten lançamento(s)',
            )
            .catchError((_) {}),
      );
    }
    return totalWritten;
  }

  static Map<String, dynamic> _optionalClosureAndSourceFields(
      Map<String, dynamic> data) {
    final o = <String, dynamic>{};
    void putStr(String key) {
      final v = data[key];
      if (v == null) return;
      final s = v.toString().trim();
      if (s.isEmpty) return;
      o[key] = s;
    }

    putStr('source');
    putStr('scaleClosureDedupKey');
    putStr('scaleClosureGroupId');
    putStr('scaleClosureEmployerType');
    return o;
  }

  static DateTime addMonths(DateTime d, int months) {
    final year = d.year + ((d.month - 1 + months) ~/ 12);
    final month = ((d.month - 1 + months) % 12) + 1;
    final lastDayOfMonth = DateTime(year, month + 1, 0).day;
    final day = d.day.clamp(1, lastDayOfMonth);
    return DateTime(year, month, day, d.hour, d.minute, d.second);
  }

  static bool _isFirestoreInternalAssertion(Object e) {
    final msg = e.toString();
    return msg.contains('INTERNAL ASSERTION FAILED') ||
        msg.contains('Unexpected state');
  }

  /// Web Firestore 11.x: retry curto após assert de listeners concorrentes.
  static Future<void> _firestoreWriteWithRetry(Future<void> Function() write) async {
    Object? last;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await write();
        return;
      } catch (e) {
        last = e;
        if (!kIsWeb || !_isFirestoreInternalAssertion(e) || attempt >= 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 160 * (attempt + 1)));
      }
    }
    throw last ?? StateError('firestore write failed');
  }

  static Future<void> attachReceiptToTransaction({
    required String uid,
    required String docId,
    required Uint8List bytes,
    required String name,
    required String mime,
    BuildContext? context,
  }) async {
    if (bytes.isEmpty) {
      throw StateError('Arquivo vazio.');
    }
    if (bytes.lengthInBytes > ReceiptAttachmentUtils.maxBytes) {
      throw StateError('Arquivo acima de 5 MB.');
    }
    final fn = FunctionsService();
    final fsUid = firestoreUserDocIdForAppShell(uid);
    final txPath = 'users/$fsUid/transactions/$docId';
    final result = await fn.uploadReceiptToStorage(
      txPath: txPath,
      filename: name,
      bytes: bytes,
      mimeType: mime,
    );
    if (result['ok'] != true) {
      throw StateError((result['error'] ?? 'Falha ao enviar comprovante.').toString());
    }
    // Cloud Function já grava `receipt` no documento; reforça hasReceipt para listeners antigos.
    await _firestoreWriteWithRetry(
      () => txRef(uid).doc(docId).update({
        'hasReceipt': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }),
    );
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Comprovante enviado e vinculado ao lançamento.'),
        ),
      );
    }
  }

  /// Cordex: validação rigorosa para evitar RangeError (Invalid Value) no Firestore.
  /// Mesma lógica que o módulo Financeiro (Firestore + log + comprovante premium).
  /// [showSuccessSnack]: em gravações em lote (ex.: fechamento de Escalas), use `false` e mostre um único SnackBar no fim.
  static Future<TransactionSaveResult?> saveFromNovoLancamentoResult({
    required String uid,
    required Map<String, dynamic> data,
    required BuildContext context,
    bool showSuccessSnack = true,
  }) async {
    final type = (data['type'] ?? 'expense').toString();
    final rawAmount = data['amount'];
    double amount;
    if (rawAmount is num) {
      amount = rawAmount.toDouble();
    } else if (rawAmount is String) {
      amount = CurrencyFormats.parseBRLInput(rawAmount) ?? 0;
    } else {
      amount = 0;
    }
    if (amount.isNaN || amount.isInfinite || amount <= 0) return null;

    final category = (data['category'] ?? '').toString();
    final description = (data['description'] ?? '').toString();
    final status = (data['status'] ?? 'paid').toString();
    DateTime date =
        data['date'] is DateTime ? data['date'] as DateTime : DateTime.now();
    if ((data['source'] ?? '').toString() != 'open_finance' &&
        data['useExplicitTime'] != true) {
      date = FinanceTransactionDatetime.mergeCalendarDayWithClockNow(date);
    }
    final recurrence = (data['recurrence'] ?? 'none').toString();
    final installments = (data['installments'] is int)
        ? (data['installments'] as int).clamp(1, 999)
        : 1;
    final rawStart = data['installmentStartIndex'];
    final installmentStartIndex = (rawStart is int)
        ? rawStart.clamp(1, installments)
        : (int.tryParse(rawStart?.toString() ?? '') ?? 1)
            .clamp(1, installments);
    final receipt = data['receipt'] as Map<String, dynamic>?;
    final financeAccountId = (data['financeAccountId'] ?? '').toString().trim();
    if (type == 'expense' && financeAccountId.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Despesa sem conta. Cadastre e selecione uma conta no lançamento.'),
            backgroundColor: Color(0xFFB00020),
          ),
        );
      }
      return null;
    }

    final col = txRef(uid);
    final savedIds = <String>[];
    String? firstDocId;
    if (installments <= 1) {
      final ref = col.doc();
      await _firestoreWriteWithRetry(
        () => ref.set({
          'type': type,
          'amount': amount,
          'category': category,
          'description': description,
          'status': status,
          'date': Timestamp.fromDate(date),
          'effectiveDate':
              FinanceLineOpening.effectiveTimestampForWrite(date: date),
          'recurrence': recurrence,
          'installmentCount': 1,
          'installmentIndex': 1,
          if (financeAccountId.isNotEmpty) 'financeAccountId': financeAccountId,
          ..._optionalClosureAndSourceFields(data),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      );
      firstDocId = ref.id;
      savedIds.add(ref.id);
      unawaited(
        LogsService()
            .saveLog(
              modulo: 'Financeiro',
              acao: type == 'income' ? 'Criou receita' : 'Criou despesa',
              detalhes:
                  '${category.isEmpty ? 'Categoria' : category} • ${CurrencyFormats.formatBRL(amount)}',
            )
            .catchError((_) {}),
      );
      if (context.mounted && showSuccessSnack) {
        HapticFeedback.lightImpact();
        final offline =
            isConnectivityOffline(await Connectivity().checkConnectivity());
        final base = type == 'income'
            ? 'Receita registada no Financeiro.'
            : 'Despesa registada no Financeiro.';
        final msg = offline
            ? '$base Guardado no aparelho; sincroniza quando houver internet.'
            : base;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } else {
      final batch = FirebaseFirestore.instance.batch();
      final groupId = col.doc().id;
      final valueIsPerParcel = data['installmentValueIsPerParcel'] == true;
      final amountPerParcel = valueIsPerParcel ? amount : amount / installments;
      final parcelCount = installments - installmentStartIndex + 1;
      for (var k = 0; k < parcelCount; k++) {
        final i = installmentStartIndex + k;
        final d = addMonths(date, k);
        final ref = col.doc();
        if (k == 0) firstDocId = ref.id;
        savedIds.add(ref.id);
        batch.set(ref, {
          'type': type,
          'amount': amountPerParcel,
          'category': category,
          'description': description,
          'status': status,
          'date': Timestamp.fromDate(d),
          'effectiveDate':
              FinanceLineOpening.effectiveTimestampForWrite(date: d),
          'recurrence': recurrence,
          'installmentCount': installments,
          'installmentIndex': i,
          'installmentGroupId': groupId,
          if (financeAccountId.isNotEmpty) 'financeAccountId': financeAccountId,
          ..._optionalClosureAndSourceFields(data),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await _firestoreWriteWithRetry(() => batch.commit());
      unawaited(
        LogsService()
            .saveLog(
              modulo: 'Financeiro',
              acao: type == 'income'
                  ? 'Criou receita parcelada'
                  : 'Criou despesa parcelada',
              detalhes:
                  '${category.isEmpty ? 'Categoria' : category} • $parcelCount de $installments parcelas • ${valueIsPerParcel ? '${CurrencyFormats.formatBRL(amount)}/parcela' : 'Total ${CurrencyFormats.formatBRL(amount)}'}',
            )
            .catchError((_) {}),
      );
      if (context.mounted && showSuccessSnack) {
        HapticFeedback.lightImpact();
        final offline =
            isConnectivityOffline(await Connectivity().checkConnectivity());
        final base = type == 'income'
            ? 'Receitas parceladas registadas no Financeiro.'
            : 'Despesas parceladas registadas no Financeiro.';
        final msg = offline
            ? '$base Guardado no aparelho; sincroniza quando houver internet.'
            : base;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    }

    if (savedIds.isEmpty) return null;
    final result = TransactionSaveResult(docIds: savedIds);

    // Comprovante: na web aguarda upload+update antes de notificar listeners (evita assert SDK).
    if (receipt != null && firstDocId != null) {
      final bytes = receipt['bytes'] as Uint8List?;
      final name = receipt['name'] as String?;
      final mime = receipt['mime'] as String?;
      if (bytes != null &&
          name != null &&
          mime != null &&
          bytes.lengthInBytes > 0) {
        if (kIsWeb) {
          try {
            await attachReceiptToTransaction(
              uid: uid,
              docId: firstDocId!,
              bytes: bytes,
              name: name,
              mime: mime,
              context: context.mounted ? context : null,
            );
          } catch (e) {
            debugPrint('TransactionSaveService receipt (web): $e');
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Lançamento registado. O comprovante não foi anexado agora — '
                    'pode anexar depois na lista (menu ⋮ no item).',
                  ),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 5),
                ),
              );
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 120));
        } else {
          unawaited(() async {
            try {
              await attachReceiptToTransaction(
                uid: uid,
                docId: firstDocId!,
                bytes: bytes,
                name: name,
                mime: mime,
                context: context.mounted ? context : null,
              );
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Lançamento registado. O comprovante não foi anexado agora — '
                      'pode anexar depois na lista (menu ⋮ no item).',
                    ),
                    backgroundColor: Colors.orange,
                    duration: Duration(seconds: 5),
                  ),
                );
              }
            }
          }());
        }
      }
    }

    FinanceTransactionsHub.notifyMutated(
      uid: uid,
      effectiveDate: date,
    );

    return result;
  }
}
