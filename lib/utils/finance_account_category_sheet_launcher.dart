import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/currency_formats.dart';
import '../constants/date_time_formats.dart';
import '../models/finance_account.dart';
import '../models/user_profile.dart';
import '../screens/report_preview_screen.dart';
import '../services/finance_accounts_service.dart';
import '../services/finance_opening_balance_service.dart';
import '../services/logs_service.dart';
import '../services/relatorio_service.dart';
import '../services/transaction_save_service.dart';
import '../theme/app_colors.dart';
import '../utils/finance_account_balance_utils.dart';
import '../utils/finance_transactions_hub.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/pdf_financeiro_super_extrato.dart';
import '../utils/premium_upgrade.dart';
import '../widgets/finance_confirm_payment_sheet.dart';
import '../widgets/finance_transaction_edit_dialog.dart';
import '../widgets/finance_transfer_bottom_sheet.dart';
import '../screens/finance_screen.dart' show FinanceInsightSheet, FinanceInsightScope;
import '../widgets/finance_account_category_sheet.dart';

/// Abre o mesmo painel de conta do módulo Financeiro (gráficos, edição, comprovantes).
abstract final class FinanceAccountCategorySheetLauncher {
  FinanceAccountCategorySheetLauncher._();

  static String _fsUid(String uid) => firestoreUserDocIdForAppShell(uid);

  static CollectionReference<Map<String, dynamic>> _txCol(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_fsUid(uid))
          .collection('transactions');

  static void show({
    required BuildContext context,
    required String uid,
    required UserProfile profile,
    required DateTime from,
    required DateTime to,
    FinanceAccount? account,
    double? openingBalanceHint,
    required List<FinanceAccount> financeAccounts,
    VoidCallback? onOpenFinanceModule,
    String statusFilter = 'paid',
    bool nearlyFullScreen = false,
  }) {
    final sheetInitial = nearlyFullScreen ? 0.96 : 0.78;
    final sheetMax = nearlyFullScreen ? 0.98 : 0.96;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FinanceAccountCategorySheet(
        sheetInitialChildSize: sheetInitial,
        sheetMaxChildSize: sheetMax,
        uid: _fsUid(uid),
        profile: profile,
        account: account,
        from: from,
        to: to,
        statusFilter: statusFilter,
        financeAccounts: financeAccounts,
        openingBalanceHint: openingBalanceHint,
        onEditTransaction: (c, docId, current, type) =>
            _editTx(c, uid: uid, profile: profile, docId: docId, current: current, type: type),
        onDeleteTransaction: (c, docId) => _deleteTx(c, uid: uid, profile: profile, docId: docId),
        onDeleteBatch: (c, ids) => _deleteBatch(c, uid: uid, profile: profile, docIds: ids),
        onConfirmPayment: (c, docId) => _confirmPayment(c, uid: uid, profile: profile, docId: docId),
        onAttachReceipt: (c, docId) => _attachReceipt(c, uid: uid, profile: profile, docId: docId),
        onExportPdf: (c, docs) => _exportPdf(
          c,
          uid: uid,
          profile: profile,
          docs: docs,
          account: account,
          from: from,
          to: to,
          financeAccounts: financeAccounts,
          openingBalanceHint: openingBalanceHint,
        ),
        onApplyAccountFilter: (_) {
          Navigator.of(ctx).pop();
          onOpenFinanceModule?.call();
        },
      ),
    );
  }

  /// Grid moderna com gráficos, filtros e edição de lançamentos (Receitas / Despesas / Saldo).
  static Future<void> showInsight({
    required BuildContext context,
    required String uid,
    required UserProfile profile,
    required FinanceInsightScope scope,
    required DateTime from,
    required DateTime to,
    String? financeAccountFilterId,
    String? financeAccountFilterLabel,
    double? openingBalanceHint,
    Map<String, double>? openingByAccountHint,
    String statusFilter = 'paid',
  }) async {
    if (!profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, profile);
      return;
    }
    final fromNorm = DateTime(from.year, from.month, from.day);
    final toNorm = DateTime(to.year, to.month, to.day, 23, 59, 59);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.96,
        child: FinanceInsightSheet(
          uid: _fsUid(uid),
          initialScope: scope,
          initialFrom: fromNorm,
          initialTo: toNorm,
          statusFilter: statusFilter,
          search: '',
          financeAccountFilterId: financeAccountFilterId,
          financeAccountFilterLabel: financeAccountFilterLabel,
          openingBalanceHint: openingBalanceHint,
          openingByAccountHint: openingByAccountHint,
          onEdit: (docId, current, type) => _editTx(
            ctx,
            uid: uid,
            profile: profile,
            docId: docId,
            current: current,
            type: type,
          ),
          onDelete: (docId) => _deleteTx(
            ctx,
            uid: uid,
            profile: profile,
            docId: docId,
          ),
        ),
      ),
    );
  }

  static Future<void> _editTx(
    BuildContext context, {
    required String uid,
    required UserProfile profile,
    required String docId,
    required Map<String, dynamic> current,
    required String type,
  }) async {
    if (!profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, profile);
      return;
    }
    final pairId = (current['transferPairId'] ?? '').toString().trim();
    if (pairId.isNotEmpty) {
      final accounts = await FinanceAccountsService().listOnce(_fsUid(uid));
      if (!context.mounted) return;
      final saved = await FinanceTransferBottomSheet.showEdit(
        context,
        uid: uid,
        profile: profile,
        pairId: pairId,
        accounts: accounts,
        logModulo: 'Início',
      );
      if (saved) FinanceTransactionsHub.notifyMutated(uid: _fsUid(uid));
      return;
    }
    final saved = await showFinanceTransactionEditDialog(
      context: context,
      uid: uid,
      profile: profile,
      docId: docId,
      current: current,
      type: type,
      logModulo: 'Início',
    );
    if (saved) FinanceTransactionsHub.notifyMutated(uid: _fsUid(uid));
  }

  static Future<void> _deleteTx(
    BuildContext context, {
    required String uid,
    required UserProfile profile,
    required String docId,
  }) async {
    if (!profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, profile);
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir lançamento?'),
        content: const Text('Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    final col = _txCol(uid);
    final snap = await col.doc(docId).get();
    final data = snap.data() ?? {};
    final type = (data['type'] ?? 'expense').toString();
    final amount = (data['amount'] ?? 0).toDouble();
    final category = (data['category'] ?? '').toString();
    final pairId = (data['transferPairId'] ?? '').toString().trim();
    if (pairId.isNotEmpty) {
      final pairSnap = await col.where('transferPairId', isEqualTo: pairId).get();
      for (final pairDoc in pairSnap.docs) {
        await pairDoc.reference.delete();
      }
    } else {
      await col.doc(docId).delete();
    }
    FinanceTransactionsHub.notifyMutated(uid: _fsUid(uid));
    HapticFeedback.lightImpact();
    await LogsService().saveLog(
      modulo: 'Início',
      acao: type == 'income' ? 'Excluiu receita' : 'Excluiu despesa',
      detalhes: '${category.isEmpty ? 'Categoria' : category} • ${CurrencyFormats.formatBRL(amount)}',
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lançamento excluído.')),
      );
    }
  }

  static Future<void> _deleteBatch(
    BuildContext context, {
    required String uid,
    required UserProfile profile,
    required List<String> docIds,
  }) async {
    if (!profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, profile);
      return;
    }
    if (docIds.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir lançamentos?'),
        content: Text(
          '${docIds.length} lançamento(s) serão excluídos. Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    final col = _txCol(uid);
    var deleted = 0;
    for (final id in docIds) {
      try {
        await col.doc(id).delete();
        deleted++;
      } catch (_) {}
    }
    FinanceTransactionsHub.notifyMutated(uid: _fsUid(uid));
    if (context.mounted) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$deleted lançamento(s) excluído(s).')),
      );
    }
  }

  static Future<void> _confirmPayment(
    BuildContext context, {
    required String uid,
    required UserProfile profile,
    required String docId,
  }) async {
    if (!profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, profile);
      return;
    }
    if (docId.isEmpty) return;
    final txRef = _txCol(uid).doc(docId);
    final preSnap = await txRef.get();
    if (!preSnap.exists || !context.mounted) return;
    final preData = preSnap.data() ?? {};
    final txType = (preData['type'] ?? 'expense').toString();
    final isIncome = txType == 'income';
    final rawAid = (preData['financeAccountId'] ?? '').toString().trim();
    final financeAccounts = await FinanceAccountsService().listOnce(_fsUid(uid));
    if (!context.mounted) return;

    FinanceAccount? cardAccount;
    for (final a in financeAccounts) {
      if (a.id == rawAid && a.isCreditCardProduct) {
        cardAccount = a;
        break;
      }
    }
    final isCardFatura = !isIncome &&
        cardAccount != null &&
        (preData['status'] ?? 'paid').toString() == 'pending';

    final FinanceConfirmPaymentSheetResult? result;
    if (isCardFatura) {
      final debitBanks = FinanceAccountBalanceUtils.debitBankAccounts(financeAccounts);
      result = await showFinanceConfirmPaymentBatchSheet(
        context: context,
        isIncome: false,
        financeAccounts: debitBanks,
        itemCount: 1,
        totalAmountPreview: (preData['amount'] as num?)?.toDouble(),
        creditCardFaturaPayment: true,
        cardDisplayName: cardAccount.displayName,
      );
    } else {
      result = await showFinanceConfirmPaymentSheet(
        context: context,
        isIncome: isIncome,
        financeAccounts: financeAccounts,
        initialFinanceAccountId: rawAid.isEmpty ? null : rawAid,
        orphanAccountId: rawAid,
        canAttachReceipt: profile.temAcessoPremium,
        amountPreview: (preData['amount'] as num?)?.toDouble(),
        categoryPreview: (preData['category'] ?? '').toString(),
        descriptionPreview: (preData['description'] ?? '').toString(),
      );
    }
    if (result == null || !context.mounted) return;

    try {
      await commitFinanceConfirmPayment(
        txRef: txRef,
        uid: uid,
        result: result,
        creditCardFaturaPayment: isCardFatura,
      );
      FinanceTransactionsHub.notifyMutated(uid: _fsUid(uid));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isIncome ? 'Recebimento confirmado.' : 'Pagamento confirmado.'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao confirmar: ${e.toString().split('\n').first}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  static Future<void> _attachReceipt(
    BuildContext context, {
    required String uid,
    required UserProfile profile,
    required String docId,
  }) async {
    if (!profile.temAcessoPremium) {
      mostrarAvisoSeLicencaInativa(context, profile);
      return;
    }
    final pick = await FilePicker.platform.pickFiles(withData: true);
    const maxBytes = 5 * 1024 * 1024;
    if (pick == null || pick.files.isEmpty) return;
    final f = pick.files.first;
    final bytes = f.bytes;
    if (bytes == null || bytes.isEmpty) return;
    final ext = (f.extension ?? '').toLowerCase();
    const allowed = ['pdf', 'png', 'jpg', 'jpeg'];
    if (!allowed.contains(ext)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Arquivo inválido. Use PDF/PNG/JPG.')),
        );
      }
      return;
    }
    if (bytes.lengthInBytes > maxBytes) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Arquivo grande demais. Limite: 5 MB.')),
        );
      }
      return;
    }
    final mime = ext == 'pdf'
        ? 'application/pdf'
        : (ext == 'png' ? 'image/png' : 'image/jpeg');
    try {
      await TransactionSaveService.attachReceiptToTransaction(
        uid: uid,
        docId: docId,
        bytes: bytes,
        name: f.name,
        mime: mime,
      );
      FinanceTransactionsHub.notifyMutated(uid: _fsUid(uid));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comprovante enviado e vinculado.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  static int _sortMs(dynamic ts) {
    if (ts is Timestamp) return ts.toDate().millisecondsSinceEpoch;
    if (ts is DateTime) return ts.millisecondsSinceEpoch;
    return 0;
  }

  static String _dataStr(dynamic ts) {
    if (ts == null) return '';
    if (ts is Timestamp) return DateTimeFormats.dateBR.format(ts.toDate());
    if (ts is DateTime) return DateTimeFormats.dateBR.format(ts);
    return '';
  }

  static Future<void> _exportPdf(
    BuildContext context, {
    required String uid,
    required UserProfile profile,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required FinanceAccount? account,
    required DateTime from,
    required DateTime to,
    required List<FinanceAccount> financeAccounts,
    double? openingBalanceHint,
  }) async {
    if (!profile.hasActiveLicense) {
      if (context.mounted) mostrarAvisoSeLicencaInativa(context, profile);
      return;
    }
    if (docs.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhum lançamento para exportar.')),
        );
      }
      return;
    }
    final f = DateTime(from.year, from.month, from.day);
    final tEnd = DateTime(to.year, to.month, to.day, 23, 59, 59);
    try {
      double saldoAberturaResolved;
      if (openingBalanceHint != null) {
        saldoAberturaResolved = openingBalanceHint;
      } else {
        final loaded = await FinanceOpeningBalanceService.load(
          uid: uid,
          periodStart: f,
          loadAccounts: account != null,
        );
        saldoAberturaResolved = account != null
            ? (loaded.byAccount[account.id] ?? 0.0)
            : loaded.total;
      }

      double totalIncome = 0, totalExpense = 0;
      for (final doc in docs) {
        final d = doc.data();
        final amount = ((d['amount'] ?? 0) as num).toDouble().abs();
        if ((d['type'] ?? 'expense').toString() == 'income') {
          totalIncome += amount;
        } else {
          totalExpense += amount;
        }
      }

      String? suffix;
      if (account != null) {
        var s = account.displayName.replaceAll(RegExp(r'[<>:"/\\|?*\n\r]'), '_').trim();
        if (s.isEmpty) s = 'conta';
        suffix = s.length > 48 ? s.substring(0, 48) : s;
      }
      final periodo =
          '${DateTimeFormats.dateBR.format(f)} a ${DateTimeFormats.dateBR.format(tEnd)}';
      final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs)
        ..sort((a, b) => _sortMs(a.data()['date']).compareTo(_sortMs(b.data()['date'])));
      final txRows = <Map<String, dynamic>>[];
      for (final doc in sorted) {
        final e = doc.data();
        final isIncome = (e['type'] ?? 'expense').toString() == 'income';
        final cat = (e['category'] ?? '').toString().trim();
        final desc = (e['description'] ?? '').toString().trim();
        final rawDesc = (cat.isNotEmpty ? 'Categoria: $cat' : '') +
            (cat.isNotEmpty && desc.isNotEmpty ? ' — ' : '') +
            (desc.isNotEmpty
                ? 'Descrição: $desc'
                : (cat.isEmpty ? (isIncome ? 'Receita' : 'Despesa') : ''));
        final descricao = rawDesc.trim().isEmpty
            ? (isIncome ? 'Receita' : 'Despesa')
            : RelatorioService.sanitizeForReport(rawDesc);
        final tituloLinha = desc.isNotEmpty ? desc : (isIncome ? 'Receita' : 'Despesa');
        txRows.add({
          'sortMs': _sortMs(e['date']),
          'data': _dataStr(e['date']),
          'categoria': cat,
          'titulo': tituloLinha,
          'descricao': descricao,
          'tipo': isIncome ? 'receita' : 'despesa',
          'valor': ((e['amount'] ?? 0) as num).toDouble(),
        });
      }
      final filenameBase = RelatorioService.reportFilenameFromPeriod(
        'despesa_receita',
        f,
        tEnd,
        suffix != null && suffix.isNotEmpty ? '— $suffix' : null,
      );
      final contaLabel = account?.displayName ?? 'Todas as contas';
      final logo = await RelatorioService.loadPdfLogoBytesOnce();
      final bytes = await gerarPdfFinanceiroSuperExtrato(
        transacoes: txRows,
        nomeUsuario: profile.name,
        conta: contaLabel,
        periodo: periodo,
        saldoAbertura: saldoAberturaResolved,
        totalReceitas: totalIncome,
        totalDespesas: totalExpense,
        logoPngBytes: logo,
      );
      if (!context.mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ReportPreviewScreen(bytes: bytes, filename: filenameBase),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao exportar PDF: ${e.toString().split('\n').first}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
