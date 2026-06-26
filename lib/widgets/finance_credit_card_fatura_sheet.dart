import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../constants/currency_formats.dart';
import '../constants/date_time_formats.dart';
import '../constants/finance_account_visuals.dart';
import '../constants/finance_category_visuals.dart';
import '../models/finance_account.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import 'finance_transaction_sort_bar.dart';
import '../utils/finance_account_balance_utils.dart';
import '../utils/finance_fatura_transaction_sort.dart';
import '../utils/finance_category_grouping.dart';
import '../utils/finance_line_opening.dart';
import '../utils/finance_transactions_hub.dart';
import '../utils/finance_transactions_realtime.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/premium_upgrade.dart';
import '../widgets/app_bar_chart.dart';
import '../widgets/app_pie_chart.dart';
import '../widgets/finance_bank_brand_thumb.dart';
import '../widgets/finance_confirm_payment_sheet.dart';
import '../widgets/finance_premium_ui.dart';
import '../widgets/agenda_period_filter_bar.dart' show agendaParseBrDateInput;
import '../widgets/fast_text_field.dart';
import '../widgets/finance_transaction_list_tile.dart';
import '../widgets/skeleton_loader.dart';

/// Painel da fatura do cartão: lançamentos, seleção parcial e pagamento pelo banco de débito.
class FinanceCreditCardFaturaSheet extends StatefulWidget {
  final String uid;
  final UserProfile profile;
  final FinanceAccount cardAccount;
  final List<FinanceAccount> allAccounts;
  final Set<String> optimisticPaidIds;
  final Future<void> Function(
    BuildContext context,
    List<String> docIds, {
    required FinanceConfirmPaymentSheetResult result,
    required String cardAccountId,
  }) onConfirmFaturaPayment;
  final Future<void> Function(
    BuildContext context,
    String docId,
    Map<String, dynamic> current,
    String type,
  ) onEditTransaction;
  final Future<void> Function(BuildContext context, String docId) onDeleteTransaction;
  final Future<void> Function(BuildContext context, List<String> docIds) onDeleteBatch;
  final Future<void> Function(BuildContext context, String docId) onAttachReceipt;

  const FinanceCreditCardFaturaSheet({
    super.key,
    required this.uid,
    required this.profile,
    required this.cardAccount,
    required this.allAccounts,
    required this.onConfirmFaturaPayment,
    required this.onEditTransaction,
    required this.onDeleteTransaction,
    required this.onDeleteBatch,
    required this.onAttachReceipt,
    this.optimisticPaidIds = const {},
  });

  static Future<void> show(
    BuildContext context, {
    required String uid,
    required UserProfile profile,
    required FinanceAccount cardAccount,
    required List<FinanceAccount> allAccounts,
    required Set<String> optimisticPaidIds,
    required Future<void> Function(
      BuildContext context,
      List<String> docIds, {
      required FinanceConfirmPaymentSheetResult result,
      required String cardAccountId,
    }) onConfirmFaturaPayment,
    required Future<void> Function(
      BuildContext context,
      String docId,
      Map<String, dynamic> current,
      String type,
    ) onEditTransaction,
    required Future<void> Function(BuildContext context, String docId) onDeleteTransaction,
    required Future<void> Function(BuildContext context, List<String> docIds) onDeleteBatch,
    required Future<void> Function(BuildContext context, String docId) onAttachReceipt,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => FinanceCreditCardFaturaSheet(
          uid: uid,
          profile: profile,
          cardAccount: cardAccount,
          allAccounts: allAccounts,
          optimisticPaidIds: optimisticPaidIds,
          onConfirmFaturaPayment: onConfirmFaturaPayment,
          onEditTransaction: onEditTransaction,
          onDeleteTransaction: onDeleteTransaction,
          onDeleteBatch: onDeleteBatch,
          onAttachReceipt: onAttachReceipt,
        ),
      ),
    );
  }

  @override
  State<FinanceCreditCardFaturaSheet> createState() => _FinanceCreditCardFaturaSheetState();
}

class _FinanceCreditCardFaturaSheetState extends State<FinanceCreditCardFaturaSheet> {
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  bool _confirming = false;
  bool _deleting = false;
  FinanceFaturaTxSortMode _sortMode = FinanceFaturaTxSortMode.dateDesc;

  /// Filtros internos do preview — não alteram o painel Financeiro.
  String _periodMode = 'Abertos';
  /// all | pending | paid — padrão abertos no modo Abertos; todos nos demais.
  String _statusFilter = 'pending';
  String? _categoryFilter;
  late DateTime _from;
  late DateTime _to;
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _periodDocs;
  bool _periodLoading = false;
  Object? _periodError;
  late final ScrollController _scrollController;
  late final TextEditingController _startDateCtrl;
  late final TextEditingController _endDateCtrl;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    _startDateCtrl = TextEditingController(text: DateTimeFormats.formatDate(_from));
    _endDateCtrl = TextEditingController(text: DateTimeFormats.formatDate(_to));
    FinanceTransactionsHub.revision.addListener(_onHubRevision);
    unawaited(_reloadDocs());
  }

  @override
  void dispose() {
    FinanceTransactionsHub.revision.removeListener(_onHubRevision);
    _scrollController.dispose();
    _startDateCtrl.dispose();
    _endDateCtrl.dispose();
    super.dispose();
  }

  void _syncDateFieldsToControllers() {
    _startDateCtrl.text = DateTimeFormats.formatDate(_from);
    _endDateCtrl.text = DateTimeFormats.formatDate(_to);
  }

  void _onHubRevision() {
    unawaited(_reloadDocs());
  }

  bool get _isAbertosMode => _periodMode == 'Abertos';

  bool _isPendingDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
      (doc.data()['status'] ?? 'paid').toString() == 'pending';

  bool _isPaidDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) => !_isPendingDoc(doc);

  DateTime get _rangeStart => DateTime(_from.year, _from.month, _from.day);

  DateTime get _rangeEnd => _to;

  /// Pagos entram no período pela data de pagamento (paidAt), não pela compra no cartão.
  bool _docPaidInSelectedPeriod(Map<String, dynamic> d) {
    final paidTs = d['paidAt'];
    if (paidTs is Timestamp) {
      final p = paidTs.toDate();
      return !p.isBefore(_rangeStart) && !p.isAfter(_rangeEnd);
    }
    final eff = FinanceLineOpening.effectiveDateTimeFromMap(d);
    if (eff == null) return false;
    return !eff.isBefore(_rangeStart) && !eff.isAfter(_rangeEnd);
  }

  bool _docPendingInSelectedPeriod(Map<String, dynamic> d) {
    final eff = FinanceLineOpening.effectiveDateTimeFromMap(d);
    if (eff == null) return false;
    return !eff.isBefore(_rangeStart) && !eff.isAfter(_rangeEnd);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _paidDocsInPeriod(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> periodDocs,
  ) {
    return periodDocs.where((doc) => _isPaidDoc(doc) && _docPaidInSelectedPeriod(doc.data())).toList();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _pendingDocsForView({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> periodDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? pendingDocs,
  }) {
    if (_isAbertosMode) {
      return pendingDocs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    }
    return periodDocs
        .where((doc) => _isPendingDoc(doc) && _docPendingInSelectedPeriod(doc.data()))
        .toList();
  }

  /// Stream de pendentes no modo Abertos (exceto quando só Pagos).
  bool get _needsPendingStream => _isAbertosMode && _statusFilter != 'paid';

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _mergeDocsById(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> a,
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> b,
  ) {
    final map = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final d in a) {
      map[d.id] = d;
    }
    for (final d in b) {
      map[d.id] = d;
    }
    return map.values.toList();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sourceDocs({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> periodDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? pendingDocs,
  }) {
    final paidInPeriod = _paidDocsInPeriod(periodDocs);
    final pending = _pendingDocsForView(periodDocs: periodDocs, pendingDocs: pendingDocs);

    if (_statusFilter == 'pending') return pending;
    if (_statusFilter == 'paid') return paidInPeriod;
    if (_isAbertosMode) return _mergeDocsById(pending, paidInPeriod);
    return periodDocs;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyCategoryFilter(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final cat = _categoryFilter?.trim();
    if (cat == null || cat.isEmpty) return docs;
    return docs.where((d) => (d.data()['category'] ?? '').toString().trim() == cat).toList();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _chartDocs({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> periodDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? pendingDocs,
  }) {
    final paidInPeriod = _paidDocsInPeriod(periodDocs);
    final pending = _pendingDocsForView(periodDocs: periodDocs, pendingDocs: pendingDocs);

    if (_statusFilter == 'paid') return paidInPeriod;
    if (_statusFilter == 'pending') return pending;
    if (_isAbertosMode) return _mergeDocsById(pending, paidInPeriod);
    return periodDocs;
  }

  List<String> _categoryOptions(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final cats = <String>{};
    for (final d in docs) {
      final c = (d.data()['category'] ?? '').toString().trim();
      if (c.isNotEmpty) cats.add(c);
    }
    final list = cats.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  void _applyPeriodMode(String mode) {
    final now = DateTime.now();
    setState(() {
      _periodMode = mode;
      _selectionMode = false;
      _selectedIds.clear();
      _categoryFilter = null;
      _statusFilter = mode == 'Abertos' ? 'pending' : 'all';
      if (mode == 'Mensal') {
        _from = DateTime(now.year, now.month, 1);
        _to = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      } else if (mode == 'Anual') {
        _from = DateTime(now.year, 1, 1);
        _to = DateTime(now.year, 12, 31, 23, 59, 59);
      } else if (mode == 'Abertos') {
        _from = DateTime(now.year, now.month, 1);
        _to = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      } else if (mode == 'Período') {
        // Mantém o intervalo atual; usuário ajusta nos campos ou no calendário.
      }
      _syncDateFieldsToControllers();
    });
    if (mode != 'Período') {
      unawaited(_reloadDocs());
    }
  }

  Future<void> _pickDateForRange({required bool isStart}) async {
    final initial = isStart ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: isStart ? 'Data inicial' : 'Data final',
      fieldHintText: 'dd/mm/aaaa',
      fieldLabelText: isStart ? 'Início' : 'Fim',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _from = DateTime(picked.year, picked.month, picked.day);
        if (_to.isBefore(_from)) {
          _to = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        }
      } else {
        _to = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        if (_to.isBefore(_from)) {
          _from = DateTime(picked.year, picked.month, picked.day);
        }
      }
      _periodMode = 'Período';
      _statusFilter = 'all';
      _selectionMode = false;
      _selectedIds.clear();
      _categoryFilter = null;
      _syncDateFieldsToControllers();
    });
    unawaited(_reloadDocs());
  }

  void _applyManualDateRange() {
    final parsedFrom = agendaParseBrDateInput(_startDateCtrl.text);
    final parsedTo = agendaParseBrDateInput(_endDateCtrl.text);
    if (parsedFrom == null || parsedTo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data inválida. Use dd/mm/aaaa (ex.: 15/05/2026).'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    var start = DateTime(parsedFrom.year, parsedFrom.month, parsedFrom.day);
    var end = DateTime(parsedTo.year, parsedTo.month, parsedTo.day, 23, 59, 59);
    if (end.isBefore(start)) {
      final tmp = start;
      start = DateTime(end.year, end.month, end.day);
      end = DateTime(tmp.year, tmp.month, tmp.day, 23, 59, 59);
    }
    setState(() {
      _from = start;
      _to = end;
      _periodMode = 'Período';
      _statusFilter = 'all';
      _selectionMode = false;
      _selectedIds.clear();
      _categoryFilter = null;
      _syncDateFieldsToControllers();
    });
    unawaited(_reloadDocs());
  }

  Widget _faturaDateField({
    required String label,
    required TextEditingController controller,
    required VoidCallback onCalendar,
    required VoidCallback onSubmitted,
  }) {
    return FastTextField(
      controller: controller,
      keyboardType: TextInputType.datetime,
      textInputAction: TextInputAction.done,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d/]')),
        LengthLimitingTextInputFormatter(10),
      ],
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        hintText: 'dd/mm/aaaa',
        filled: true,
        fillColor: AppColors.primary.withValues(alpha: 0.06),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.18)),
        ),
        suffixIcon: IconButton(
          tooltip: 'Calendário',
          onPressed: onCalendar,
          icon: const Icon(Icons.calendar_month_rounded, size: 20),
        ),
      ),
      onSubmitted: (_) => onSubmitted(),
    );
  }

  Widget _periodDateRangeEditor() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 360;
        final fields = narrow
            ? Column(
                children: [
                  _faturaDateField(
                    label: 'Data inicial',
                    controller: _startDateCtrl,
                    onCalendar: () => unawaited(_pickDateForRange(isStart: true)),
                    onSubmitted: _applyManualDateRange,
                  ),
                  const SizedBox(height: 8),
                  _faturaDateField(
                    label: 'Data final',
                    controller: _endDateCtrl,
                    onCalendar: () => unawaited(_pickDateForRange(isStart: false)),
                    onSubmitted: _applyManualDateRange,
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _faturaDateField(
                      label: 'Data inicial',
                      controller: _startDateCtrl,
                      onCalendar: () => unawaited(_pickDateForRange(isStart: true)),
                      onSubmitted: _applyManualDateRange,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _faturaDateField(
                      label: 'Data final',
                      controller: _endDateCtrl,
                      onCalendar: () => unawaited(_pickDateForRange(isStart: false)),
                      onSubmitted: _applyManualDateRange,
                    ),
                  ),
                ],
              );
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.date_range_rounded, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isAbertosMode && _statusFilter == 'pending'
                            ? 'Período (pagos e gráficos) · abertos = todos no cartão'
                            : 'Período selecionado',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                fields,
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: _periodLoading ? null : _applyManualDateRange,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Aplicar período'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _reloadDocs() async {
    if (!mounted) return;
    setState(() {
      _periodLoading = true;
      _periodError = null;
    });
    try {
      final raw = await financePeriodMergedDocumentsCollect(
        uid: widget.uid,
        from: _from,
        to: _to,
        statusFilter: 'all',
        typeFilter: 'expense',
        financeAccountId: widget.cardAccount.id,
      );
      if (!mounted) return;
      final docs = raw
          .where((d) => FinanceAccountBalanceUtils.countsForFaturaCartao(d.data()))
          .toList();
      setState(() {
        _periodDocs = docs;
        _periodLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _periodError = e;
        _periodLoading = false;
      });
    }
  }

  Widget _periodFilterBar() {
    const accent = Color(0xFF4F46E5);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final label in const ['Abertos', 'Mensal', 'Anual', 'Período'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(label, style: const TextStyle(fontSize: 12)),
                  selected: _periodMode == label,
                  onSelected: (_) => _applyPeriodMode(label),
                  selectedColor: accent.withValues(alpha: 0.18),
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _periodMode == label ? accent : AppColors.textSecondary,
                  ),
                  side: BorderSide(
                    color: accent.withValues(alpha: _periodMode == label ? 0.85 : 0.28),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String get _periodRangeLabel =>
      '${DateFormat('dd/MM/yyyy').format(_from)} — ${DateFormat('dd/MM/yyyy').format(_to)}';

  CollectionReference<Map<String, dynamic>> get _txCol {
    final fsId = firestoreUserDocIdForAppShell(widget.uid);
    return FirebaseFirestore.instance.collection('users').doc(fsId).collection('transactions');
  }

  Query<Map<String, dynamic>> get _pendingOnCardQuery => _txCol
      .where('financeAccountId', isEqualTo: widget.cardAccount.id)
      .where('type', isEqualTo: 'expense')
      .where('status', isEqualTo: 'pending')
      .orderBy('date', descending: false)
      .limit(500);

  double _sumDocs(Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {Set<String>? onlyIds}) {
    var s = 0.0;
    for (final doc in docs) {
      if (onlyIds != null && !onlyIds.contains(doc.id)) continue;
      s += (doc.data()['amount'] as num?)?.toDouble().abs() ?? 0;
    }
    return s;
  }

  List<({String category, double total})> _aggregateFaturaByCategory(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final merger = FinanceCategoryMerger();
    final totals = <String, double>{};
    for (final doc in docs) {
      final d = doc.data();
      final cat = (d['category'] ?? '').toString();
      final amt = (d['amount'] as num?)?.toDouble().abs() ?? 0;
      merger.addAmount(totals, cat, amt);
    }
    final list = totals.entries
        .map((e) => (category: e.key, total: e.value))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return list;
  }

  String _shortCategoryLabel(String label, {int max = 11}) {
    final t = label.trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max - 1)}…';
  }

  Widget _categoryChartsSection(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    double totalFatura, {
    String title = 'Fatura por categoria',
  }) {
    if (docs.isEmpty) return const SizedBox.shrink();
    final entries = _aggregateFaturaByCategory(docs);
    if (entries.isEmpty) return const SizedBox.shrink();

    final pieSegments = entries
        .map(
          (e) => (
            label: e.category,
            value: e.total,
            color: financeCategoryVisualFor(e.category, isIncome: false).color,
          ),
        )
        .toList();

    final topBar = entries.take(6).toList();
    final maxCat = entries.first.total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.financeDespesa.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.donut_large_rounded, color: AppColors.financeDespesa, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF0F172A)),
                    ),
                    Text(
                      '${entries.length} categoria(s) · ${CurrencyFormats.formatBRL(totalFatura)} no total',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppPieChart(
          title: 'Distribuição da fatura',
          segments: pieSegments,
        ),
        const SizedBox(height: 12),
        if (topBar.length >= 2)
          AppBarChart(
            title: 'Maiores categorias',
            values: topBar.map((e) => e.total).toList(),
            labels: topBar.map((e) => _shortCategoryLabel(e.category)).toList(),
            barColor: AppColors.financeDespesa,
            height: 168,
          ),
        if (topBar.length >= 2) const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Detalhe por categoria',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 10),
              ...entries.map((e) {
                final vis = financeCategoryVisualFor(e.category, isIncome: false);
                final ratio = maxCat <= 0 ? 0.0 : (e.total / maxCat).clamp(0.0, 1.0);
                final share = totalFatura <= 0 ? 0.0 : (e.total / totalFatura * 100);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      financeCategoryLeadingTile(e.category, isIncome: false, size: 36),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.category,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                value: ratio,
                                minHeight: 6,
                                backgroundColor: const Color(0xFFF1F5F9),
                                color: vis.color,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  CurrencyFormats.formatBRLTight(e.total),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12.5,
                                    color: vis.color,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  CurrencyFormats.formatPercentBr(share),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusSummaryStrip({
    required double openTotal,
    required double paidTotal,
    required int openCount,
    required int paidCount,
  }) {
    if (openCount == 0 && paidCount == 0) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          child: _StatusKpiCard(
            label: 'Em aberto',
            total: openTotal,
            count: openCount,
            color: AppColors.financeDespesa,
            icon: Icons.schedule_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatusKpiCard(
            label: 'Pagos',
            total: paidTotal,
            count: paidCount,
            color: const Color(0xFF059669),
            icon: Icons.check_circle_rounded,
          ),
        ),
      ],
    );
  }

  Widget _statusFilterBar() {
    const accent = Color(0xFF4F46E5);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'all', label: Text('Todos'), icon: Icon(Icons.layers_rounded, size: 18)),
          ButtonSegment(value: 'pending', label: Text('Abertos'), icon: Icon(Icons.schedule_rounded, size: 18)),
          ButtonSegment(value: 'paid', label: Text('Pagos'), icon: Icon(Icons.check_circle_rounded, size: 18)),
        ],
        selected: {_statusFilter},
        onSelectionChanged: (s) => setState(() {
          _statusFilter = s.first;
          _selectionMode = false;
          _selectedIds.clear();
          _categoryFilter = null;
        }),
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return accent;
            return AppColors.textSecondary;
          }),
        ),
      ),
    );
  }

  Widget _categoryFilterBar(List<String> categories) {
    if (categories.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(Icons.category_rounded, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          const Text('Categoria', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _categoryFilter,
                isExpanded: true,
                hint: const Text('Todas', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Todas as categorias', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  for (final c in categories)
                    DropdownMenuItem<String?>(
                      value: c,
                      child: Text(c, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _categoryFilter = v;
                  _selectionMode = false;
                  _selectedIds.clear();
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lancamentosSectionHeader(int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Row(
        children: [
          Icon(Icons.view_list_rounded, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Lançamentos da fatura',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                color: Colors.grey.shade900,
              ),
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
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sortBar() {
    return FinanceTransactionSortBar(
      value: _sortMode,
      onChanged: (v) => setState(() => _sortMode = v),
    );
  }

  Widget _groupHeader(String label, {IconData icon = Icons.calendar_today_rounded}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.12),
                AppColors.accent.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildGroupedTransactionList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (docs.isEmpty) return const [];
    final groups = FinanceFaturaTransactionSort.groupedForUi(docs, _sortMode);
    final out = <Widget>[];
    for (final group in groups) {
      final isDayGroup = _sortMode == FinanceFaturaTxSortMode.dateDesc ||
          _sortMode == FinanceFaturaTxSortMode.dateAsc;
      final isCategoryGroup = _sortMode == FinanceFaturaTxSortMode.category;
      if (isDayGroup || isCategoryGroup) {
        out.add(
          _groupHeader(
            group.headerLabel,
            icon: isCategoryGroup ? Icons.category_rounded : Icons.calendar_today_rounded,
          ),
        );
      }
      for (final doc in group.docs) {
        final id = doc.id;
        out.add(
          FinanceTransactionListTile(
            doc: doc,
            profile: widget.profile,
            financeAccounts: widget.allAccounts,
            gridSelectionMode: _selectionMode,
            isSelected: _selectedIds.contains(id),
            optimisticPaidIds: widget.optimisticPaidIds,
            onToggleSelection: () {
              setState(() {
                if (_selectedIds.contains(id)) {
                  _selectedIds.remove(id);
                } else {
                  _selectedIds.add(id);
                }
              });
            },
            onEdit: widget.onEditTransaction,
            onDelete: widget.onDeleteTransaction,
            onConfirmPayment: (c, docId) async {
              await _confirmPaymentIds([docId], docs);
            },
            onAttachReceipt: widget.onAttachReceipt,
          ),
        );
      }
    }
    return out;
  }

  void _toggleSelectionMode() {
    setState(() {
      if (_selectionMode) {
        _selectionMode = false;
        _selectedIds.clear();
      } else {
        _selectionMode = true;
      }
    });
  }

  void _selectAll(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    setState(() {
      _selectionMode = true;
      _selectedIds
        ..clear()
        ..addAll(docs.map((d) => d.id));
    });
  }

  void _clearSelection() {
    setState(() => _selectedIds.clear());
  }

  Future<void> _confirmPaymentIds(
    List<String> ids,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final unique = ids.toSet().where((e) => e.trim().isNotEmpty).toList();
    if (unique.isEmpty) return;

    final total = _sumDocs(docs, onlyIds: unique.toSet());

    final debitBanks = FinanceAccountBalanceUtils.debitBankAccounts(widget.allAccounts);
    if (debitBanks.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cadastre uma conta corrente ou poupança para registrar de qual banco saiu o pagamento.',
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    final result = await showFinanceConfirmPaymentBatchSheet(
      context: context,
      isIncome: false,
      financeAccounts: debitBanks,
      itemCount: unique.length,
      totalAmountPreview: total,
      creditCardFaturaPayment: true,
      cardDisplayName: widget.cardAccount.displayName,
    );
    if (result == null || !mounted) return;

    setState(() => _confirming = true);
    try {
      await widget.onConfirmFaturaPayment(
        context,
        unique,
        result: result,
        cardAccountId: widget.cardAccount.id,
      );
      if (mounted) {
        setState(() {
          _selectionMode = false;
          _selectedIds.clear();
        });
        if (docs.where((d) => unique.contains(d.id)).length == docs.length) {
          Navigator.of(context).pop();
        }
      }
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final n = _selectedIds.length;
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
    setState(() => _deleting = true);
    try {
      await widget.onDeleteBatch(context, _selectedIds.toList());
      if (mounted) {
        setState(() {
          _selectionMode = false;
          _selectedIds.clear();
        });
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _selectAllPending(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final pending = docs.where(_isPendingDoc).map((d) => d.id).toList();
    setState(() {
      _selectionMode = true;
      _selectedIds
        ..clear()
        ..addAll(pending);
    });
  }

  Future<void> _paySelectedPending(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allPayable,
  ) async {
    final pendingSelected = _selectedIds.where((id) {
      return allPayable.any((d) => d.id == id && _isPendingDoc(d));
    }).toList();
    if (pendingSelected.isEmpty) return;
    await _confirmPaymentIds(pendingSelected, allPayable);
  }

  Widget _toolbar(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> payableDocs,
  }) {
    if (docs.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_rounded, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${docs.length} lançamento(s) na fatura',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _toggleSelectionMode,
                icon: Icon(
                  _selectionMode ? Icons.close_rounded : Icons.checklist_rounded,
                  size: 20,
                ),
                label: Text(_selectionMode ? 'Fechar' : 'Selecionar'),
              ),
            ],
          ),
          if (_selectionMode) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _selectAll(docs),
                  icon: const Icon(Icons.select_all_rounded, size: 18),
                  label: const Text('Todos'),
                ),
                OutlinedButton.icon(
                  onPressed: _selectedIds.isEmpty ? null : _clearSelection,
                  icon: const Icon(Icons.deselect_rounded, size: 18),
                  label: const Text('Nenhum'),
                ),
                if (_selectedIds.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: _deleting
                        ? null
                        : () async {
                            HapticFeedback.mediumImpact();
                            await _deleteSelected();
                          },
                    icon: _deleting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                    label: Text(
                      'Excluir (${_selectedIds.length})',
                      style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700),
                    ),
                  ),
                if (_selectedIds.isNotEmpty && payableDocs.any((d) => _selectedIds.contains(d.id) && _isPendingDoc(d)))
                  FilledButton.tonalIcon(
                    onPressed: _confirming
                        ? null
                        : () async {
                            HapticFeedback.mediumImpact();
                            await _paySelectedPending(payableDocs);
                          },
                    icon: const Icon(Icons.payments_rounded, size: 18),
                    label: Text('Pagar (${_selectedIds.where((id) => payableDocs.any((d) => d.id == id && _isPendingDoc(d))).length})'),
                  ),
              ],
            ),
            if (_selectedIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Selecionados: ${CurrencyFormats.formatBRL(_sumDocs(docs, onlyIds: _selectedIds))}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.financeDespesa,
                  ),
                ),
              ),
          ] else ...[
            Text(
              'Toque para editar · confirme pagamento no item · use Selecionar para pagar ou excluir em lote.',
              style: TextStyle(fontSize: 11.5, height: 1.35, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _periodRangeCaption() {
    if (_isAbertosMode && _statusFilter == 'pending') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          _statusFilter == 'paid' ? 'Pagos em $_periodRangeLabel' : _periodRangeLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  List<Widget> _faturaContentChildren({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> periodDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? pendingDocs,
    required FinanceAccountVisual vis,
    required DateTime? nextClose,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> visibleDocs,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> payableDocs,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> openChart,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> paidChart,
    required double openTotal,
    required double paidTotal,
    required double displayTotal,
    required List<String> categoryOptions,
  }) {
    return [
      _FaturaHeroCard(
        account: widget.cardAccount,
        vis: vis,
        openTotal: openTotal,
        paidTotal: paidTotal,
        openCount: openChart.length,
        paidCount: paidChart.length,
        displayTotal: displayTotal,
        itemCount: visibleDocs.length,
        nextClosing: nextClose,
        periodLabel: _statusFilter == 'pending' && _isAbertosMode
            ? 'Em aberto (todos)'
            : _periodRangeLabel,
      ),
      const SizedBox(height: 14),
      _statusSummaryStrip(
        openTotal: openTotal,
        paidTotal: paidTotal,
        openCount: openChart.length,
        paidCount: paidChart.length,
      ),
      const SizedBox(height: 14),
      if (openChart.isNotEmpty) ...[
        _categoryChartsSection(openChart, openTotal, title: 'Em aberto por categoria'),
        const SizedBox(height: 14),
      ],
      if (paidChart.isNotEmpty) ...[
        _categoryChartsSection(paidChart, paidTotal, title: 'Pagos por categoria'),
        const SizedBox(height: 14),
      ],
      _statusFilterBar(),
      const SizedBox(height: 10),
      _categoryFilterBar(categoryOptions),
      if (categoryOptions.isNotEmpty) const SizedBox(height: 10),
      _lancamentosSectionHeader(visibleDocs.length),
      const SizedBox(height: 8),
      _sortBar(),
      const SizedBox(height: 10),
      _toolbar(visibleDocs, payableDocs: payableDocs),
      const SizedBox(height: 12),
      if (visibleDocs.isEmpty)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Text(
            'Nenhum lançamento nesta aba para os filtros atuais.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        )
      else
        ..._buildGroupedTransactionList(visibleDocs),
      const SizedBox(height: 20),
    ];
  }

  Widget _buildPayFooter({
    required bool canPay,
    required int selectedCount,
    required double selectedTotal,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> payableDocs,
  }) {
    if (!canPay) return const SizedBox.shrink();
    final footerPad = 12 + MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, footerPad),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectionMode ? 'Total selecionado' : 'Total em aberto',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      CurrencyFormats.formatBRL(selectedTotal),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.financeDespesa,
                      ),
                    ),
                    Text(
                      '$selectedCount lançamento(s)',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              if (!_selectionMode)
                TextButton.icon(
                  onPressed: () => _selectAllPending(payableDocs),
                  icon: const Icon(Icons.checklist_rounded, size: 18),
                  label: const Text('Parcial'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: (_confirming || (_selectionMode && _selectedIds.isEmpty))
                ? null
                : () async {
                    HapticFeedback.mediumImpact();
                    final ids = _selectionMode
                        ? _selectedIds.where((id) => payableDocs.any((d) => d.id == id)).toList()
                        : payableDocs.map((d) => d.id).toList();
                    await _confirmPaymentIds(ids, payableDocs);
                  },
            icon: _confirming
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.payments_rounded),
            label: Text(
              _selectionMode
                  ? 'Fechamento (${_selectedIds.length})'
                  : 'Gerar fechamento / Pagar fatura',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.deepBlue,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Filtros só neste preview — ao voltar, a lista principal não muda.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, height: 1.3, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildFaturaLayout({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> periodDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? pendingDocs,
    required FinanceAccountVisual vis,
    required DateTime? nextClose,
  }) {
    final chartBase = _chartDocs(periodDocs: periodDocs, pendingDocs: pendingDocs);
    final openChart = chartBase.where(_isPendingDoc).toList();
    final paidChart = chartBase.where(_isPaidDoc).toList();
    final openTotal = _sumDocs(openChart);
    final paidTotal = _sumDocs(paidChart);

    final sourceDocs = _sourceDocs(periodDocs: periodDocs, pendingDocs: pendingDocs);
    final categoryOptions = _categoryOptions(sourceDocs);
    final visibleDocs = _applyCategoryFilter(sourceDocs);
    final payableDocs = visibleDocs.where(_isPendingDoc).toList();
    final displayTotal = _sumDocs(visibleDocs);
    final selectedCount = _selectionMode ? _selectedIds.length : payableDocs.length;
    final selectedTotal = _selectionMode
        ? _sumDocs(payableDocs, onlyIds: _selectedIds)
        : _sumDocs(payableDocs);
    final canPay = payableDocs.isNotEmpty;

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FinancePremiumSheetHeader(
                  title: 'Fatura — ${widget.cardAccount.displayName}',
                  subtitle: 'Preview isolado · não altera filtros do Financeiro',
                  icon: Icons.credit_card_rounded,
                  iconGradient: vis.gradient,
                  onBack: () => Navigator.pop(context),
                ),
              ),
              _periodFilterBar(),
              _periodDateRangeEditor(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _periodRangeCaption(),
              ),
              if (_periodLoading && periodDocs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: SkeletonListLoader(itemCount: 3, itemHeight: 88),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _faturaContentChildren(
                      periodDocs: periodDocs,
                      pendingDocs: pendingDocs,
                      vis: vis,
                      nextClose: nextClose,
                      visibleDocs: visibleDocs,
                      payableDocs: payableDocs,
                      openChart: openChart,
                      paidChart: paidChart,
                      openTotal: openTotal,
                      paidTotal: paidTotal,
                      displayTotal: displayTotal,
                      categoryOptions: categoryOptions,
                    ),
                  ),
                ),
            ],
          ),
        ),
        _buildPayFooter(
          canPay: canPay,
          selectedCount: selectedCount,
          selectedTotal: selectedTotal,
          payableDocs: payableDocs,
        ),
      ],
    );
  }

  Widget _buildPeriodPane({
    required FinanceAccountVisual vis,
    required DateTime? nextClose,
  }) {
    if (_periodLoading && (_periodDocs == null || _periodDocs!.isEmpty)) {
      return ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
        padding: const EdgeInsets.all(16),
        children: const [
          SkeletonListLoader(itemCount: 6, itemHeight: 88),
        ],
      );
    }
    if (_periodError != null) {
      return ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(24),
        children: [
          Text('Erro ao carregar período: $_periodError', textAlign: TextAlign.center),
        ],
      );
    }
    return _buildFaturaLayout(
      periodDocs: _periodDocs ?? const [],
      vis: vis,
      nextClose: nextClose,
    );
  }

  Widget _buildBody({
    required FinanceAccountVisual vis,
    required DateTime? nextClose,
  }) {
    if (_needsPendingStream) {
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _pendingOnCardQuery.snapshots(includeMetadataChanges: false),
        builder: (context, snap) {
          if (snap.hasError) {
            return ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Erro ao carregar fatura: ${snap.error}',
                  textAlign: TextAlign.center,
                ),
              ],
            );
          }
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData &&
              (_periodDocs == null || _periodDocs!.isEmpty)) {
            return ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              children: const [
                SkeletonListLoader(itemCount: 6, itemHeight: 88),
              ],
            );
          }
          final pendingDocs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
            snap.data?.docs ?? const [],
          )
              .where((doc) => FinanceAccountBalanceUtils.countsForFaturaCartao(doc.data()))
              .toList();
          return _buildFaturaLayout(
            periodDocs: _periodDocs ?? const [],
            pendingDocs: pendingDocs,
            vis: vis,
            nextClose: nextClose,
          );
        },
      );
    }
    return _buildPeriodPane(vis: vis, nextClose: nextClose);
  }

  @override
  Widget build(BuildContext context) {
    final vis = financeAccountVisualFor(widget.cardAccount);
    final closing = widget.cardAccount.statementClosingDay;
    final nextClose = closing != null
        ? FinanceAccount.computeNextStatementClosing(closing)
        : null;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _buildBody(vis: vis, nextClose: nextClose),
      ),
    );
  }
}

class _FaturaHeroCard extends StatelessWidget {
  const _FaturaHeroCard({
    required this.account,
    required this.vis,
    required this.openTotal,
    required this.paidTotal,
    required this.openCount,
    required this.paidCount,
    required this.displayTotal,
    required this.itemCount,
    this.nextClosing,
    this.periodLabel,
  });

  final FinanceAccount account;
  final FinanceAccountVisual vis;
  final double openTotal;
  final double paidTotal;
  final int openCount;
  final int paidCount;
  final double displayTotal;
  final int itemCount;
  final DateTime? nextClosing;
  final String? periodLabel;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy', 'pt_BR');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: vis.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: vis.gradient.first.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          const Positioned.fill(child: FinanceCreditCardPattern()),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  FinanceBankBrandThumb(
                    preset: account.preset,
                    size: 32,
                    onBrandGradient: true,
                    fallbackIcon: vis.icon,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      account.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFBBF24).withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'CRÉDITO',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1E1B4B),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (periodLabel != null) ...[
                Text(
                  periodLabel!,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                'Em aberto',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                CurrencyFormats.formatBRL(openTotal),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$openCount aberto(s) · $paidCount pago(s)',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (paidTotal > 0) ...[
                const SizedBox(height: 4),
                Text(
                  'Pagos: ${CurrencyFormats.formatBRL(paidTotal)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (itemCount > 0 && displayTotal != openTotal) ...[
                const SizedBox(height: 4),
                Text(
                  'Lista filtrada: ${CurrencyFormats.formatBRL(displayTotal)} · $itemCount item(ns)',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (nextClosing != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Fecha ${df.format(nextClosing!)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusKpiCard extends StatelessWidget {
  const _StatusKpiCard({
    required this.label,
    required this.total,
    required this.count,
    required this.color,
    required this.icon,
  });

  final String label;
  final double total;
  final int count;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            CurrencyFormats.formatBRL(total),
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: color),
          ),
          Text(
            '$count lançamento(s)',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
