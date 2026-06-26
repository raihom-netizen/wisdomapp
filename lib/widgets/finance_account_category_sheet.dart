import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/currency_formats.dart';
import '../constants/date_time_formats.dart';
import '../models/finance_account.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import 'finance_bank_brand_thumb.dart';
import '../utils/finance_line_opening.dart';
import '../services/finance_opening_balance_service.dart';
import '../utils/finance_transactions_realtime.dart';
import '../utils/premium_upgrade.dart';
import '../utils/finance_transactions_hub.dart';
import '../utils/finance_fatura_transaction_sort.dart';
import '../utils/firestore_user_doc_id.dart';
import '../widgets/finance_transaction_list_tile.dart';
import '../widgets/finance_transaction_sort_bar.dart';

/// Exporta PDF com os mesmos lançamentos visíveis no sheet (período + status + conta).
typedef FinanceAccountCategoryExportPdf = Future<void> Function(
  BuildContext context,
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
);

/// Sheet moderno: saldo no período, gráficos por categoria e edição / exclusão de lançamentos.
/// [account] `null` = **Todas as contas** (consolidado, mesmo critério do painel sem filtro de conta).
class FinanceAccountCategorySheet extends StatefulWidget {
  final String uid;
  final UserProfile profile;
  final FinanceAccount? account;
  final DateTime from;
  final DateTime to;
  /// Mesmo filtro da tela Financeiro: `all` | `paid` | `pending`
  final String statusFilter;
  final Future<void> Function(BuildContext context, String docId, Map<String, dynamic> current, String type) onEditTransaction;
  final Future<void> Function(BuildContext context, String docId) onDeleteTransaction;
  final Future<void> Function(BuildContext context, List<String> docIds) onDeleteBatch;
  final Future<void> Function(BuildContext context, String docId) onConfirmPayment;
  final Future<void> Function(BuildContext context, String docId) onAttachReceipt;
  final FinanceAccountCategoryExportPdf onExportPdf;
  /// Define o filtro de conta no painel (`null` = todas as contas).
  final void Function(String? accountId) onApplyAccountFilter;
  /// Saldo de abertura já calculado no Financeiro/painel — evita piscar zerado ao abrir o sheet.
  final double? openingBalanceHint;
  final List<FinanceAccount> financeAccounts;
  final Set<String> optimisticPaidIds;
  final double sheetInitialChildSize;
  final double sheetMaxChildSize;

  const FinanceAccountCategorySheet({
    super.key,
    required this.uid,
    required this.profile,
    this.account,
    required this.from,
    required this.to,
    required this.statusFilter,
    required this.onEditTransaction,
    required this.onDeleteTransaction,
    required this.onDeleteBatch,
    required this.onConfirmPayment,
    required this.onAttachReceipt,
    required this.onExportPdf,
    required this.onApplyAccountFilter,
    required this.financeAccounts,
    this.openingBalanceHint,
    this.optimisticPaidIds = const {},
    this.sheetInitialChildSize = 0.78,
    this.sheetMaxChildSize = 0.96,
  });

  @override
  State<FinanceAccountCategorySheet> createState() => _FinanceAccountCategorySheetState();
}

class _FinanceAccountCategorySheetState extends State<FinanceAccountCategorySheet> {
  /// 0 = todos (despesas + receitas), 1 = despesas, 2 = receitas — padrão despesas como antes.
  int _tab = 1;
  bool _gridSelectionMode = false;
  final Set<String> _gridSelectedIds = {};
  bool _gridDeleting = false;
  FinanceFaturaTxSortMode _gridSortMode = FinanceFaturaTxSortMode.dateDesc;
  StreamSubscription<fa.User?>? _authUidSub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _periodDocs;
  Object? _periodLoadError;
  bool _periodLoading = true;

  @override
  void initState() {
    super.initState();
    FinanceTransactionsHub.revision.addListener(_onFinanceHubRevision);
    _authUidSub = fa.FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted) setState(() {});
    });
    unawaited(_reloadPeriodDocs());
  }

  @override
  void didUpdateWidget(covariant FinanceAccountCategorySheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.from != widget.from ||
        oldWidget.to != widget.to ||
        oldWidget.statusFilter != widget.statusFilter ||
        oldWidget.account?.id != widget.account?.id) {
      unawaited(_reloadPeriodDocs());
    }
  }

  void _onFinanceHubRevision() => unawaited(_reloadPeriodDocs());

  Future<void> _reloadPeriodDocs() async {
    if (!mounted) return;
    setState(() {
      _periodLoading = true;
      _periodLoadError = null;
    });
    try {
      final docs = await financePeriodMergedDocumentsCollect(
        uid: firestoreUserDocIdForAppShell(widget.uid),
        from: widget.from,
        to: widget.to,
        statusFilter: widget.statusFilter,
      );
      if (!mounted) return;
      setState(() {
        _periodDocs = docs;
        _periodLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _periodLoadError = e;
        _periodLoading = false;
      });
    }
  }

  @override
  void dispose() {
    FinanceTransactionsHub.revision.removeListener(_onFinanceHubRevision);
    _authUidSub?.cancel();
    super.dispose();
  }

  bool _passStatus(Map<String, dynamic> d) {
    if (widget.statusFilter == 'all') return true;
    final st = (d['status'] ?? 'paid').toString();
    return st == widget.statusFilter;
  }

  /// Mesma regra do painel e do Financeiro: data efetiva (effectiveDate / paidAt / date).
  bool _passEffectiveDateInPeriod(Map<String, dynamic> d) {
    final effective = FinanceLineOpening.effectiveDateTimeFromMap(d);
    if (effective == null) return false;
    final rs = DateTime(widget.from.year, widget.from.month, widget.from.day);
    final re = DateTime(widget.to.year, widget.to.month, widget.to.day, 23, 59, 59);
    return !effective.isBefore(rs) && !effective.isAfter(re);
  }

  bool _belongsToAccount(Map<String, dynamic> d) {
    if (widget.account == null) return true;
    return (d['financeAccountId'] ?? '').toString().trim() == widget.account!.id;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return DraggableScrollableSheet(
      expand: widget.sheetInitialChildSize >= 0.92,
      initialChildSize: widget.sheetInitialChildSize,
      minChildSize: 0.38,
      maxChildSize: widget.sheetMaxChildSize,
      builder: (context, scrollController) {
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Expanded(
                child: Builder(
                  builder: (context) {
                    if (_periodLoadError != null) {
                      return ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(24),
                        children: [
                          Icon(Icons.error_outline_rounded, size: 40, color: Colors.orange.shade700),
                          const SizedBox(height: 12),
                          Text('Erro ao carregar: $_periodLoadError', style: const TextStyle(fontSize: 14)),
                        ],
                      );
                    }
                    if (_periodLoading && (_periodDocs == null || _periodDocs!.isEmpty)) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final raw = (_periodDocs ?? []).where((doc) {
                      final d = doc.data();
                      return _belongsToAccount(d) &&
                          _passStatus(d) &&
                          _passEffectiveDateInPeriod(d);
                    }).toList();

                    double inc = 0, exp = 0;
                    for (final doc in raw) {
                      final d = doc.data();
                      final amt = (d['amount'] ?? 0).toDouble();
                      if (d['type'] == 'income') inc += amt;
                      if (d['type'] == 'expense') exp += amt.abs();
                    }
                    final net = inc - exp;
                    final periodStart =
                        DateTime(widget.from.year, widget.from.month, widget.from.day);

                    final expenseDocs = raw.where((doc) => doc.data()['type'] == 'expense').toList();
                    final incomeDocs = raw.where((doc) => doc.data()['type'] == 'income').toList();

                    final expenseByCat = _aggregateByCategory(expenseDocs);
                    final incomeByCat = _aggregateByCategory(incomeDocs);

                    final openingPeek = FinanceOpeningBalanceService.peekCached(
                      uid: widget.uid,
                      periodStart: periodStart,
                      loadAccounts: true,
                    );

                    return FutureBuilder<({double total, Map<String, double> byAccount})>(
                      future: FinanceOpeningBalanceService.load(
                        uid: widget.uid,
                        periodStart: periodStart,
                        loadAccounts: true,
                      ),
                      initialData: openingPeek,
                      builder: (context, openSnap) {
                        final openingTotal = openSnap.data?.total ?? widget.openingBalanceHint ?? 0.0;
                        final openingAccount = widget.account == null
                            ? openingTotal
                            : (openSnap.data?.byAccount[widget.account!.id] ??
                                widget.openingBalanceHint ??
                                0.0);
                        final saldoAcumulado = openingAccount + net;

                        return ListView(
                          controller: scrollController,
                          padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottomInset),
                          children: [
                            _sheetWideVoltar(context, footer: false),
                            _header(
                              net,
                              inc,
                              exp,
                              saldoAbertura: openingAccount,
                              saldoAcumulado: saldoAcumulado,
                            ),
                        const SizedBox(height: 12),
                        if (widget.account != null)
                          FilledButton.tonalIcon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              widget.onApplyAccountFilter(widget.account!.id);
                            },
                            icon: const Icon(Icons.filter_alt_rounded, size: 20),
                            label: const Text('Filtrar lista só desta conta'),
                            style: FilledButton.styleFrom(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                            ),
                          )
                        else
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 22),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Visão consolidada: todas as contas e lançamentos sem vínculo. Toque num banco no carrossel para abrir só aquela conta.',
                                    style: TextStyle(fontSize: 12.5, height: 1.35, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: widget.profile.hasActiveLicense
                              ? () => widget.onExportPdf(context, raw)
                              : () => mostrarAvisoSeLicencaInativa(context, widget.profile),
                          icon: const Icon(Icons.picture_as_pdf_rounded, size: 22),
                          label: const Text('Exportar PDF'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                            backgroundColor: const Color(0xFFE65100),
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (raw.isNotEmpty) ...[
                          _previewStrip(raw),
                          const SizedBox(height: 16),
                        ],
                        SegmentedButton<int>(
                          segments: const [
                            ButtonSegment<int>(
                              value: 0,
                              label: Text('Todos'),
                              icon: Icon(Icons.payments_rounded, size: 18),
                            ),
                            ButtonSegment<int>(
                              value: 1,
                              label: Text('Despesas'),
                              icon: Icon(Icons.trending_down_rounded, size: 18),
                            ),
                            ButtonSegment<int>(
                              value: 2,
                              label: Text('Receitas'),
                              icon: Icon(Icons.trending_up_rounded, size: 18),
                            ),
                          ],
                          selected: {_tab},
                          onSelectionChanged: (s) => setState(() {
                            _tab = s.first;
                            _gridSelectionMode = false;
                            _gridSelectedIds.clear();
                          }),
                        ),
                        const SizedBox(height: 16),
                        if (_tab == 0) ...[
                          _CategoryPanel(
                            type: 'expense',
                            profile: widget.profile,
                            aggregates: expenseByCat,
                            accent: AppColors.financeDespesa,
                            consolidated: widget.account == null,
                          ),
                          const SizedBox(height: 16),
                          _CategoryPanel(
                            type: 'income',
                            profile: widget.profile,
                            aggregates: incomeByCat,
                            accent: AppColors.financeReceita,
                            consolidated: widget.account == null,
                          ),
                        ] else if (_tab == 1)
                          _CategoryPanel(
                            type: 'expense',
                            profile: widget.profile,
                            aggregates: expenseByCat,
                            accent: AppColors.financeDespesa,
                            consolidated: widget.account == null,
                          )
                        else
                          _CategoryPanel(
                            type: 'income',
                            profile: widget.profile,
                            aggregates: incomeByCat,
                            accent: AppColors.financeReceita,
                            consolidated: widget.account == null,
                          ),
                        const SizedBox(height: 18),
                        _lancamentosSectionHeader(_docsForGrid(raw).length),
                        const SizedBox(height: 8),
                        _gridToolbar(_docsForGrid(raw)),
                        const SizedBox(height: 10),
                        ..._buildTransactionGrid(_docsForGrid(raw)),
                        _sheetWideVoltar(context, footer: true),
                      ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  int _docSortMs(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final eff = FinanceLineOpening.effectiveDateTimeFromMap(d);
    if (eff != null) return eff.millisecondsSinceEpoch;
    final ts = d['date'];
    if (ts is Timestamp) return ts.toDate().millisecondsSinceEpoch;
    return 0;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docsForGrid(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> raw,
  ) {
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> filtered = raw;
    if (_tab == 1) {
      filtered = raw.where((doc) => doc.data()['type'] == 'expense');
    } else if (_tab == 2) {
      filtered = raw.where((doc) => doc.data()['type'] == 'income');
    }
    final list = filtered.toList();
    return FinanceFaturaTransactionSort.sortedDocs(list, _gridSortMode);
  }

  Widget _previewStrip(List<QueryDocumentSnapshot<Map<String, dynamic>>> raw) {
    final preview = (raw.toList()..sort((a, b) => _docSortMs(b).compareTo(_docSortMs(a)))).take(3).toList();
    if (preview.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Prévia dos lançamentos',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.grey.shade800),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: preview.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final doc = preview[i];
              final d = doc.data();
              final isIncome = d['type'] == 'income';
              final accent = isIncome ? AppColors.financeReceita : AppColors.financeDespesa;
              final amt = (d['amount'] ?? 0).toDouble();
              final desc = (d['description'] ?? d['category'] ?? '').toString().trim();
              final instant = FinanceFaturaTransactionSort.effectiveInstant(d);
              final dateStr = instant != null
                  ? DateTimeFormats.formatTimeOnly(instant)
                  : '—';
              return Container(
                width: 168,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accent.withValues(alpha: 0.25)),
                  boxShadow: [
                    BoxShadow(color: accent.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      desc.isEmpty ? (isIncome ? 'Receita' : 'Despesa') : desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                    ),
                    const Spacer(),
                    Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    Text(
                      CurrencyFormats.formatBRL(amt),
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: accent),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _lancamentosSectionHeader(int count) {
    return Row(
      children: [
        Icon(Icons.view_list_rounded, size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Lançamentos',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.grey.shade900),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            '$count',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: AppColors.primary),
          ),
        ),
      ],
    );
  }

  void _toggleGridSelectionMode() {
    setState(() {
      if (_gridSelectionMode) {
        _gridSelectionMode = false;
        _gridSelectedIds.clear();
      } else {
        _gridSelectionMode = true;
      }
    });
  }

  void _selectAllGrid(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    setState(() {
      _gridSelectionMode = true;
      _gridSelectedIds
        ..clear()
        ..addAll(docs.map((d) => d.id));
    });
  }

  Future<void> _deleteSelectedGrid() async {
    if (_gridSelectedIds.isEmpty) return;
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final n = _gridSelectedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Excluir $n lançamento(s)?'),
        content: const Text('Esta ação não pode ser desfeita.'),
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
    if (ok != true || !mounted) return;
    setState(() => _gridDeleting = true);
    try {
      await widget.onDeleteBatch(context, _gridSelectedIds.toList());
      if (mounted) {
        setState(() {
          _gridSelectionMode = false;
          _gridSelectedIds.clear();
        });
      }
    } finally {
      if (mounted) setState(() => _gridDeleting = false);
    }
  }

  Widget _gridToolbar(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (docs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          'Nenhum lançamento nesta aba para o período e filtros atuais.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Toque para editar · use Selecionar para excluir em lote',
                  style: TextStyle(fontSize: 11.5, height: 1.35, color: Colors.grey.shade600),
                ),
              ),
              TextButton.icon(
                onPressed: _toggleGridSelectionMode,
                icon: Icon(
                  _gridSelectionMode ? Icons.close_rounded : Icons.checklist_rounded,
                  size: 20,
                ),
                label: Text(_gridSelectionMode ? 'Fechar' : 'Selecionar'),
              ),
            ],
          ),
          if (_gridSelectionMode)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _selectAllGrid(docs),
                  icon: const Icon(Icons.select_all_rounded, size: 18),
                  label: const Text('Todos'),
                ),
                OutlinedButton.icon(
                  onPressed: _gridSelectedIds.isEmpty ? null : () => setState(() => _gridSelectedIds.clear()),
                  icon: const Icon(Icons.deselect_rounded, size: 18),
                  label: const Text('Nenhum'),
                ),
                if (_gridSelectedIds.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: _gridDeleting
                        ? null
                        : () async {
                            HapticFeedback.mediumImpact();
                            await _deleteSelectedGrid();
                          },
                    icon: _gridDeleting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                    label: Text(
                      'Excluir (${_gridSelectedIds.length})',
                      style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 10),
          FinanceTransactionSortBar(
            value: _gridSortMode,
            compact: true,
            onChanged: (mode) => setState(() => _gridSortMode = mode),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTransactionGrid(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (docs.isEmpty) return const [];
    return docs.map((doc) {
      final id = doc.id;
      return FinanceTransactionListTile(
        doc: doc,
        profile: widget.profile,
        financeAccounts: widget.financeAccounts,
        gridSelectionMode: _gridSelectionMode,
        isSelected: _gridSelectedIds.contains(id),
        optimisticPaidIds: widget.optimisticPaidIds,
        onToggleSelection: () {
          setState(() {
            if (_gridSelectedIds.contains(id)) {
              _gridSelectedIds.remove(id);
            } else {
              _gridSelectedIds.add(id);
            }
          });
        },
        onEdit: widget.onEditTransaction,
        onDelete: widget.onDeleteTransaction,
        onConfirmPayment: widget.onConfirmPayment,
        onAttachReceipt: widget.onAttachReceipt,
      );
    }).toList();
  }

  /// Voltar em faixa larga (melhor para polegar no iPhone), início e fim do scroll.
  Widget _sheetWideVoltar(BuildContext context, {required bool footer}) {
    return Padding(
      padding: EdgeInsets.only(bottom: footer ? 6 : 12, top: footer ? 18 : 0),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded, size: 22),
          label: const Text('Voltar'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            foregroundColor: AppColors.primary,
            backgroundColor: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _header(
    double net,
    double inc,
    double exp, {
    double? saldoAbertura,
    double? saldoAcumulado,
  }) {
    final periodo =
        '${DateTimeFormats.dateBR.format(DateTime(widget.from.year, widget.from.month, widget.from.day))} — ${DateTimeFormats.dateBR.format(DateTime(widget.to.year, widget.to.month, widget.to.day))}';

    if (widget.account == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: AppColors.logoGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(color: AppColors.deepBlueDark.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.dashboard_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Todas as contas',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, height: 1.2),
                      ),
                      Text(
                        'Consolidado no período · receitas, despesas e saldo líquido',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  tooltip: 'Fechar',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              periodo,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 14),
            if (saldoAbertura != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Saldo de abertura',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    Text(
                      CurrencyFormats.formatBRL(saldoAbertura),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        shadows: [Shadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4)],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(child: _headerMiniKpi('Receitas', inc, Colors.white)),
                const SizedBox(width: 8),
                Expanded(child: _headerMiniKpi('Despesas', exp, Colors.white)),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Saldo líquido no período', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                  Text(
                    CurrencyFormats.formatBRL(net),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      shadows: [Shadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4)],
                    ),
                  ),
                ],
              ),
            ),
            if (saldoAcumulado != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Saldo acumulado', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                    Text(
                      CurrencyFormats.formatBRL(saldoAcumulado),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        shadows: [Shadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4)],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    }

    final p = widget.account!.preset;
    final c1 = p?.color1 ?? AppColors.primary;
    final c2 = p?.color2 ?? AppColors.accent;
    final fallbackIcon = p?.icon ?? Icons.account_balance_wallet_rounded;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(colors: [c1, c2], begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [
          BoxShadow(color: c1.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: FinanceBankBrandThumb(
                  preset: p,
                  size: 40,
                  onBrandGradient: true,
                  fallbackIcon: fallbackIcon,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.account!.displayName,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17, height: 1.2),
                    ),
                    Text(
                      widget.account!.productTypeLabel,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                tooltip: 'Fechar',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            periodo,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 14),
          if (saldoAbertura != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Saldo de abertura',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  Text(
                    CurrencyFormats.formatBRL(saldoAbertura),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      shadows: [Shadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4)],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: _headerMiniKpi('Receitas', inc, Colors.white),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _headerMiniKpi('Despesas', exp, Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Saldo no período', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                Text(
                  CurrencyFormats.formatBRL(net),
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    shadows: [Shadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4)],
                  ),
                ),
              ],
            ),
          ),
          if (saldoAcumulado != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Saldo acumulado', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                  Text(
                    CurrencyFormats.formatBRL(saldoAcumulado),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      shadows: [Shadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4)],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _headerMiniKpi(String label, double value, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              CurrencyFormats.formatBRL(value),
              style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _CatAgg {
  final String category;
  final double total;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  _CatAgg({required this.category, required this.total, required this.docs});
}

List<_CatAgg> _aggregateByCategory(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  final m = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
  final sums = <String, double>{};
  for (final doc in docs) {
    final d = doc.data();
    final cat = (d['category'] ?? '').toString().trim();
    final key = cat.isEmpty ? 'Sem categoria' : cat;
    m.putIfAbsent(key, () => []).add(doc);
    final amt = (d['amount'] ?? 0).toDouble();
    final signed = (d['type'] ?? 'expense').toString() == 'expense' ? amt.abs() : amt;
    sums[key] = (sums[key] ?? 0) + signed;
  }
  final list = sums.entries.map((e) => _CatAgg(category: e.key, total: e.value, docs: m[e.key]!)).toList();
  list.sort((a, b) => b.total.compareTo(a.total));
  return list;
}

class _CategoryPanel extends StatelessWidget {
  final String type;
  final UserProfile profile;
  final List<_CatAgg> aggregates;
  final Color accent;
  final bool consolidated;

  const _CategoryPanel({
    required this.type,
    required this.profile,
    required this.aggregates,
    required this.accent,
    required this.consolidated,
  });

  static const _palette = <Color>[
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFF0EA5E9),
    Color(0xFF14B8A6),
    Color(0xFFDB2777),
    Color(0xFFEA580C),
    Color(0xFFCA8A04),
    Color(0xFF64748B),
    Color(0xFF059669),
    Color(0xFFDC2626),
    Color(0xFF4F46E5),
    Color(0xFF0891B2),
    Color(0xFF9333EA),
    Color(0xFFD97706),
  ];

  @override
  Widget build(BuildContext context) {
    if (aggregates.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            Icon(Icons.pie_chart_outline_rounded, size: 44, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              consolidated
                  ? (type == 'expense' ? 'Nenhuma despesa no período consolidado.' : 'Nenhuma receita no período consolidado.')
                  : (type == 'expense' ? 'Nenhuma despesa nesta conta no período.' : 'Nenhuma receita nesta conta no período.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    final totalAll = aggregates.fold<double>(0, (a, e) => a + e.total);
    // Todas as categorias no gráfico (ex.: Educação R$ 44) — sem agrupar em «Outros».
    final pieRows = aggregates;
    final pieTotal = totalAll <= 0 ? 0.0 : totalAll;
    final sections = pieTotal <= 0
        ? <PieChartSectionData>[]
        : List.generate(pieRows.length, (i) {
            final val = pieRows[i].total;
            final pct = pieTotal > 0 ? 100 * val / pieTotal : 0.0;
            return PieChartSectionData(
              value: val,
              // Fatias pequenas: rótulo só na legenda, evita sobreposição no donut.
              title: pct >= 1 ? CurrencyFormats.formatPercentBr(pct) : '',
              color: _palette[i % _palette.length],
              radius: 48,
              titleStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white),
            );
          });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 6)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.insights_rounded, color: accent, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      type == 'expense' ? 'Despesas por categoria' : 'Receitas por categoria',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF0F172A)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Gráfico por categoria — role para ver e editar os lançamentos abaixo.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.35),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withValues(alpha: 0.22)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      type == 'expense' ? 'Total despesas' : 'Total receitas',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: accent),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        CurrencyFormats.formatBRL(totalAll),
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: accent),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (sections.isEmpty)
                const SizedBox.shrink()
              else
                LayoutBuilder(
                  builder: (context, bc) {
                    final pie = SizedBox(
                      width: math.min(200.0, bc.maxWidth),
                      height: 200,
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 40,
                          sections: sections,
                        ),
                        duration: const Duration(milliseconds: 600),
                      ),
                    );
                    final legend = ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < pieRows.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: _palette[i % _palette.length],
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        pieRows[i].category,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerRight,
                                            child: Text(
                                              CurrencyFormats.formatBRLTight(pieRows[i].total),
                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: accent),
                                            ),
                                          ),
                                          Text(
                                            CurrencyFormats.formatPercentBr(
                                              pieTotal > 0 ? 100 * pieRows[i].total / pieTotal : 0,
                                            ),
                                            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                    if (bc.maxWidth < 340) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(child: pie),
                          const SizedBox(height: 12),
                          legend,
                        ],
                      );
                    }
                    return SizedBox(
                      height: 200,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          pie,
                          const SizedBox(width: 12),
                          Expanded(child: legend),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
