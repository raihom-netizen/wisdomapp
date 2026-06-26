import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/currency_formats.dart';
import '../utils/finance_line_opening.dart';
import '../utils/finance_transaction_datetime.dart';
import '../utils/finance_transactions_hub.dart';
import '../utils/firestore_user_doc_id.dart';
import 'logs_service.dart';
import 'smart_category_hints_service.dart';

/// Serviço financeiro para lançamentos especiais (ex.: colagem de SMS).
///
/// **Saldo na UI:** neste app o saldo por conta/período é calculado a partir dos
/// documentos em `users/{uid}/transactions`. Não existe campo `saldo` mutável em
/// `finance_accounts`; ao gravar uma transação, os [StreamBuilder]s existentes
/// atualizam os totais. A API [FirebaseFirestore.runTransaction] garante que o
/// documento da transação seja criado de forma atômica (e permite estender no
/// futuro com leituras + validações antes do commit).
abstract final class FinanceService {
  FinanceService._();

  static CollectionReference<Map<String, dynamic>> _txCol(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(firestoreUserDocIdForAppShell(uid)).collection('transactions');

  /// Apaga lançamentos criados pelo expresso (ex.: «Desfazer» após lote).
  static Future<bool> deleteTransactionsByDocumentIds({
    required String uid,
    required BuildContext context,
    required List<String> documentIds,
  }) async {
    if (documentIds.isEmpty) return true;
    try {
      final col = _txCol(uid);
      final w = FirebaseFirestore.instance.batch();
      for (final id in documentIds) {
        if (id.trim().isEmpty) continue;
        w.delete(col.doc(id.trim()));
      }
      await w.commit();
      FinanceTransactionsHub.notifyMutated(uid: uid);
      return true;
    } on FirebaseException catch (e) {
      if (context.mounted) {
        final msg = (e.message != null && e.message!.isNotEmpty) ? e.message! : 'Não foi possível desfazer.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: const Color(0xFFB00020)),
        );
      }
      return false;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível desfazer. Tente no Financeiro.'),
            backgroundColor: Color(0xFFB00020),
          ),
        );
      }
      return false;
    }
  }

  /// Salva lançamento oriundo do «Lançamento inteligente» dentro de uma transação Firestore.
  /// Devolve o **ID do documento** criado, ou `null` se falhou na entrada/rede.
  static Future<String?> saveSmartPasteTransaction({
    required String uid,
    required BuildContext context,
    required String type,
    required double amount,
    required String category,
    required String description,
    required DateTime date,
    /// Em receitas pode ser vazio (sem conta). Em despesas é obrigatório.
    required String financeAccountId,
    String rawSnippet = '',
    bool saveLearnedMapping = false,
    /// [paid] = entra no saldo agora; [pending] = pendente (crédito / a receber).
    String status = 'paid',
    /// Em gravação em série, só o último item deve mostrar SnackBar/haptic.
    bool showFeedback = true,
    /// ID fixo do documento (lote / desfazer).
    String? documentId,
    /// Agrupa lançamentos do mesmo lote expresso (opcional). Grava [smartPasteBatchId] no documento;
    /// regras permissivas costumam aceitar campos extra — se a whitelist for fechada, inclua esta chave.
    String? smartPasteBatchId,
    /// Parcelas de um plano (ex.: lançamento expresso com N meses).
    int? installmentIndex,
    int? installmentCount,
  }) async {
    if (amount.isNaN || amount.isInfinite || amount <= 0) return null;
    final st = status == 'pending' ? 'pending' : 'paid';
    if (type == 'expense' && financeAccountId.trim().isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Despesa exige conta bancária/cartão selecionada.'),
            backgroundColor: Color(0xFFB00020),
          ),
        );
      }
      return null;
    }

    final mergedDate = FinanceTransactionDatetime.mergeCalendarDayWithClockNow(date);
    final docRef = (documentId != null && documentId.trim().isNotEmpty)
        ? _txCol(uid).doc(documentId.trim())
        : _txCol(uid).doc();

    final idx = installmentIndex ?? 1;
    final cnt = installmentCount ?? 1;
    final safeIdx = idx.clamp(1, 9999);
    final safeCnt = cnt < 1 ? 1 : cnt;

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        tx.set(docRef, {
          'type': type,
          'amount': amount,
          'category': category,
          'description': description,
          'status': st,
          'date': Timestamp.fromDate(mergedDate),
          'effectiveDate': FinanceLineOpening.effectiveTimestampForWrite(
            date: mergedDate,
          ),
          'recurrence': 'none',
          'installmentCount': safeCnt,
          'installmentIndex': safeIdx,
          if (financeAccountId.isNotEmpty) 'financeAccountId': financeAccountId,
          'source': 'smart_paste',
          if (rawSnippet.isNotEmpty)
            'parsedSnippet': rawSnippet.substring(0, rawSnippet.length > 500 ? 500 : rawSnippet.length),
          if (smartPasteBatchId != null && smartPasteBatchId.trim().isNotEmpty)
            'smartPasteBatchId': smartPasteBatchId.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } on FirebaseException catch (e) {
      if (context.mounted) {
        final msg = (e.message != null && e.message!.isNotEmpty)
            ? e.message!
            : 'Não foi possível salvar. Verifique conexão e tente de novo.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: const Color(0xFFB00020),
          ),
        );
      }
      return null;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível salvar o lançamento. Tente novamente.'),
            backgroundColor: Color(0xFFB00020),
          ),
        );
      }
      return null;
    }

    if (saveLearnedMapping && description.trim().length >= 3) {
      try {
        await SmartCategoryHintsService.recordLearnedMapping(uid, description, category);
      } catch (_) {}
    }

    try {
      final pend = st == 'pending' ? ' • pendente' : '';
      await LogsService().saveLog(
        modulo: 'Financeiro',
        acao: type == 'income' ? 'Receita (SMS)' : 'Despesa (SMS)',
        detalhes:
            '${category.isEmpty ? 'Categoria' : category} • ${CurrencyFormats.formatBRL(amount)}$pend',
      );
    } catch (_) {}

    if (showFeedback && context.mounted) {
      HapticFeedback.lightImpact();
      final msg = st == 'pending'
          ? 'Lançamento salvo como pendente. O saldo desta conta não foi alterado até quitar no Financeiro.'
          : 'Lançamento salvo. O saldo da conta foi atualizado.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
    FinanceTransactionsHub.notifyMutated(uid: uid, effectiveDate: mergedDate);
    return docRef.id;
  }
}
