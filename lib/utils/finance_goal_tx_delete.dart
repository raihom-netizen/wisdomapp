import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/goal_deposit_service.dart';
import '../utils/firestore_user_doc_id.dart';
import '../widgets/goal_deposit_ui.dart';

/// Confirma exclusão de lançamento — aviso Meta / semanas (padrão integrado).
Future<bool> confirmFinanceTransactionDelete({
  required BuildContext context,
  GoalLinkedTransactionInfo? metaInfo,
  int batchCount = 1,
  List<GoalLinkedTransactionInfo>? batchMetaInfos,
}) async {
  final metas = batchMetaInfos ?? (metaInfo != null ? [metaInfo] : const []);
  final title = batchCount > 1 ? 'Excluir lançamentos?' : 'Excluir lançamento?';
  final baseText = batchCount > 1
      ? '$batchCount lançamento(s) serão excluídos. Esta ação não pode ser desfeita.'
      : 'Esta ação não pode ser desfeita.';

  return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(baseText, style: const TextStyle(height: 1.35)),
                if (metas.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  for (final m in metas) ...[
                    GoalDepositWeeksUnmarkBanner(info: m),
                    const SizedBox(height: 8),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
              ),
              child: const Text('Excluir'),
            ),
          ],
        ),
      ) ??
      false;
}

/// Desvincula Meta e apaga documento(s) de transação (sem transferência).
Future<void> deleteFinanceTransactionWithMetaSync({
  required String uid,
  required String docId,
  required Map<String, dynamic> txData,
  required CollectionReference<Map<String, dynamic>> txCol,
}) async {
  await GoalDepositService.unlinkBeforeTransactionDelete(
    uid: uid,
    txId: docId,
    txData: txData,
  );
  await txCol.doc(docId).delete();
  await _markFixedMonthExcludedIfNeeded(uid, txData);
}

/// Quando o usuário exclui uma parcela de despesa/receita fixa, marca o mês
/// correspondente como "excluído manualmente" no documento da fixa. Isso evita
/// que [FixedExpenseService]/[FixedIncomeService] recriem a mesma parcela no
/// próximo ciclo, mas mantém geração dos meses seguintes que ainda não foram
/// removidos.
Future<void> _markFixedMonthExcludedIfNeeded(
  String uid,
  Map<String, dynamic> txData,
) async {
  final feId = (txData['fixedExpenseId'] ?? '').toString().trim();
  final fiId = (txData['fixedIncomeId'] ?? '').toString().trim();
  final fixedId = feId.isNotEmpty ? feId : fiId;
  if (fixedId.isEmpty) return;

  String? monthKey =
      (txData['fixedExpenseMonthKey'] ?? txData['fixedIncomeMonthKey'])
          ?.toString();
  if (monthKey == null || monthKey.isEmpty) {
    final dateTs = txData['date'];
    if (dateTs is Timestamp) {
      final dt = dateTs.toDate();
      monthKey = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
    }
  }
  if (monthKey == null || monthKey.isEmpty) return;

  final fsUid = firestoreUserDocIdForAppShell(uid);
  if (fsUid.isEmpty) return;

  final collection = feId.isNotEmpty ? 'fixed_expenses' : 'fixed_incomes';
  final ref = FirebaseFirestore.instance
      .collection('users')
      .doc(fsUid)
      .collection(collection)
      .doc(fixedId);

  try {
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final data = snap.data() ?? {};
      final existing = List<String>.from(data['excludedMonths'] ?? const []);
      if (existing.contains(monthKey)) return;
      existing.add(monthKey!);
      tx.update(ref, {
        'excludedMonths': existing,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  } catch (_) {
    // Falha silenciosa: a exclusão do lançamento já aconteceu; o pior cenário
    // é a parcela voltar a ser recriada (comportamento anterior).
  }
}

/// Apaga par de transferência ou lançamento único (Meta desvinculada antes).
Future<void> deleteFinanceTransactionRecord({
  required String uid,
  required String docId,
  required Map<String, dynamic> txData,
  required CollectionReference<Map<String, dynamic>> txCol,
}) async {
  final pairId = (txData['transferPairId'] ?? '').toString().trim();
  if (pairId.isNotEmpty) {
    final pairSnap = await txCol
        .where('transferPairId', isEqualTo: pairId)
        .get(const GetOptions(source: Source.serverAndCache));
    for (final pairDoc in pairSnap.docs) {
      final pairData = pairDoc.data();
      await GoalDepositService.unlinkBeforeTransactionDelete(
        uid: uid,
        txId: pairDoc.id,
        txData: pairData,
      );
      await pairDoc.reference.delete();
      await _markFixedMonthExcludedIfNeeded(uid, pairData);
    }
    return;
  }
  await deleteFinanceTransactionWithMetaSync(
    uid: uid,
    docId: docId,
    txData: txData,
    txCol: txCol,
  );
}
