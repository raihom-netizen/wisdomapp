import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';

import '../constants/app_business_rules.dart';
import '../models/finance_account.dart';
import '../models/user_profile.dart';
import '../services/finance_accounts_service.dart';
import '../services/user_categories_service.dart';
import '../theme/app_colors.dart';
import '../widgets/finance_transaction_list_tile.dart';
import '../widgets/finance_transaction_sort_bar.dart';
import '../widgets/finance_premium_ui.dart';
import '../widgets/finance_category_picker.dart';
import '../widgets/skeleton_loader.dart';
import '../utils/finance_category_grouping.dart';
import '../utils/finance_line_opening.dart';
import '../utils/finance_fatura_transaction_sort.dart';
import '../utils/finance_transactions_hub.dart';
import '../utils/finance_transactions_realtime.dart';
import '../constants/currency_formats.dart';
import '../constants/date_time_formats.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/keyboard_form_scaffold.dart';

/// Ações de lançamento delegadas à tela principal do financeiro (editar, excluir, comprovante, etc.).
class FinanceFullscreenHandlers {
  final Future<void> Function(BuildContext context, String docId, Map<String, dynamic> data, String type) onEdit;
  final Future<void> Function(BuildContext context, String docId) onDelete;
  final Future<void> Function(BuildContext context, String docId) onConfirmPayment;
  final Future<void> Function(BuildContext context, String docId) onAttachReceipt;
  final Future<void> Function(BuildContext context, List<String> docIds) onDeleteBatch;

  const FinanceFullscreenHandlers({
    required this.onEdit,
    required this.onDelete,
    required this.onConfirmPayment,
    required this.onAttachReceipt,
    required this.onDeleteBatch,
  });

  /// Agrupa as mesmas callbacks usadas na lista principal do [FinanceScreen] (tiles + fullscreen).
  factory FinanceFullscreenHandlers.fromFinanceScreen({
    required Future<void> Function(BuildContext context, String docId, Map<String, dynamic> data, String type) editTx,
    required Future<void> Function(BuildContext context, String docId) deleteTx,
    required Future<void> Function(BuildContext context, String docId) confirmarPagamento,
    required Future<void> Function(BuildContext context, String docId) attachReceipt,
    required Future<void> Function(BuildContext context, List<String> docIds) deleteTxBatch,
  }) {
    return FinanceFullscreenHandlers(
      onEdit: editTx,
      onDelete: deleteTx,
      onConfirmPayment: confirmarPagamento,
      onAttachReceipt: attachReceipt,
      onDeleteBatch: deleteTxBatch,
    );
  }
}

/// Estado dos filtros ao sair da rota de lançamentos em tela cheia — aplicado na [FinanceScreen].
class FinanceFullscreenFilterSnapshot {
  const FinanceFullscreenFilterSnapshot({
    required this.selectedPeriod,
    this.customRangeStart,
    this.customRangeEnd,
    required this.statusFilter,
    required this.typeFilter,
    this.categoryFilter,
    required this.searchText,
    this.financeAccountFilterId,
  });

  final String selectedPeriod;
  final DateTime? customRangeStart;
  final DateTime? customRangeEnd;
  final String statusFilter;
  final String typeFilter;
  final String? categoryFilter;
  final String searchText;
  final String? financeAccountFilterId;
}

DateTime? _transactionCalendarDay(Map<String, dynamic> d) {
  final instant = FinanceFaturaTransactionSort.effectiveInstant(d);
  if (instant == null) return null;
  return DateTime(instant.year, instant.month, instant.day);
}

Widget _financeFilterChip({
  required String label,
  required IconData icon,
  required Color accent,
  required bool selected,
  required VoidCallback onSelect,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(22),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: selected ? accent.withValues(alpha: 0.12) : const Color(0xFFF8FAFC),
          border: Border.all(
            color: selected ? accent : const Color(0xFFE2E8F0),
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: selected ? accent : AppColors.textMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                color: selected ? accent : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _financePeriodChip({
  required String period,
  required bool selected,
  required VoidCallback onSelect,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: selected
              ? const LinearGradient(
                  colors: [AppColors.deepBlueDark, AppColors.primary, AppColors.accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: selected ? null : Colors.white,
          border: Border.all(
            color: selected ? Colors.transparent : const Color(0xFFE2E8F0),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.deepBlueDark.withValues(alpha: 0.22),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          period,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : AppColors.primary,
          ),
        ),
      ),
    ),
  );
}

/// Lista de lançamentos em tela cheia com filtros (pesquisa, tipo, categoria, status, período, conta).
class FinanceTransactionsFullscreenPage extends StatefulWidget {
  final String uid;
  final UserProfile profile;
  final DateTime initialFrom;
  final DateTime initialTo;
  final String initialStatusFilter;
  final String initialTypeFilter;
  final String? initialCategory;
  final String initialSearch;
  final String? initialFinanceAccountId;
  final FinanceFullscreenHandlers handlers;

  const FinanceTransactionsFullscreenPage({
    super.key,
    required this.uid,
    required this.profile,
    required this.initialFrom,
    required this.initialTo,
    required this.initialStatusFilter,
    required this.initialTypeFilter,
    this.initialCategory,
    required this.initialSearch,
    this.initialFinanceAccountId,
    required this.handlers,
  });

  @override
  State<FinanceTransactionsFullscreenPage> createState() => _FinanceTransactionsFullscreenPageState();
}

class _FinanceTransactionsFullscreenPageState extends State<FinanceTransactionsFullscreenPage> {
  static const List<String> _periods = ['Semanal', 'Mês atual', 'Mês anterior', 'Anual', 'Por período'];
  static const int _txPageSize = 150;

  late DateTime _from;
  late DateTime _to;
  String _selectedPeriod = 'Mês atual';
  DateTime? _customRangeStart;
  DateTime? _customRangeEnd;

  String _statusFilter = 'paid';
  String _typeFilter = 'all';
  String? _categoryFilter;
  String _search = '';
  final _searchCtrl = TextEditingController();
  String? _financeAccountFilterId;

  final Set<String> _optimisticPaidIds = {};
  bool _gridSelectionMode = false;
  final Set<String> _gridSelectedIds = {};
  int _txDisplayLimit = _txPageSize;
  FinanceFaturaTxSortMode _sortMode = FinanceFaturaTxSortMode.dateDesc;

  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _mergedDocs;
  bool _mergedLoading = true;
  Object? _mergedLoadError;

  /// Stream estável — contas do usuário.
  late final Stream<List<FinanceAccount>> _accountsStream;
  Timer? _searchDebounceTimer;

  @override
  void initState() {
    super.initState();
    _accountsStream = FinanceAccountsService().streamAccounts(firestoreUserDocIdForAppShell(widget.uid));
    _from = widget.initialFrom;
    _to = widget.initialTo;
    _statusFilter = widget.initialStatusFilter;
    _typeFilter = widget.initialTypeFilter;
    _categoryFilter = widget.initialCategory;
    _search = widget.initialSearch.toLowerCase();
    _searchCtrl.text = widget.initialSearch;
    _financeAccountFilterId = widget.initialFinanceAccountId;
    _selectedPeriod = 'Por período';
    _customRangeStart = DateTime(_from.year, _from.month, _from.day);
    _customRangeEnd = DateTime(_to.year, _to.month, _to.day);
    FinanceTransactionsHub.revision.addListener(_onFinanceHubRevision);
    unawaited(_reloadMergedDocs());
  }

  void _onFinanceHubRevision() {
    if (!mounted) return;
    unawaited(_reloadMergedDocs());
  }

  Future<void> _reloadMergedDocs() async {
    if (!mounted) return;
    setState(() {
      _mergedLoading = true;
      _mergedLoadError = null;
    });
    try {
      final uid = firestoreUserDocIdForAppShell(widget.uid);
      final docs = await financePeriodMergedDocumentsCollect(
        uid: uid,
        from: _from,
        to: _to,
        statusFilter: _statusFilter,
        typeFilter: 'all',
        financeAccountId: _financeAccountFilterId,
      );
      if (!mounted) return;
      setState(() {
        _mergedDocs = docs;
        _mergedLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mergedLoadError = e;
        _mergedLoading = false;
      });
    }
  }

  void _scheduleMergedReload() {
    unawaited(_reloadMergedDocs());
  }

  @override
  void dispose() {
    FinanceTransactionsHub.revision.removeListener(_onFinanceHubRevision);
    _searchDebounceTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Mesmo padrão da [FinanceScreen]: fundo + contorno explícitos para rótulo/ícone legíveis no M3.
  ButtonStyle _toolbarTonalFilledStyle({
    EdgeInsetsGeometry? padding,
    VisualDensity? visualDensity,
    Size? minimumSize,
  }) {
    return FilledButton.styleFrom(
      foregroundColor: AppColors.primary,
      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.26), width: 1),
      ),
      visualDensity: visualDensity ?? VisualDensity.compact,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      minimumSize: minimumSize ?? const Size(48, 48),
      tapTargetSize: MaterialTapTargetSize.padded,
    );
  }

  FinanceFullscreenFilterSnapshot _captureFilterSnapshot() {
    return FinanceFullscreenFilterSnapshot(
      selectedPeriod: _selectedPeriod,
      customRangeStart: _customRangeStart,
      customRangeEnd: _customRangeEnd,
      statusFilter: _statusFilter,
      typeFilter: _typeFilter,
      categoryFilter: _categoryFilter,
      searchText: _searchCtrl.text,
      financeAccountFilterId: _financeAccountFilterId,
    );
  }

  void _popComFiltrosSincronizados() {
    Navigator.of(context).pop(_captureFilterSnapshot());
  }

  CollectionReference<Map<String, dynamic>> _txRef() =>
      FirebaseFirestore.instance.collection('users').doc(firestoreUserDocIdForAppShell(widget.uid)).collection('transactions');

  (DateTime, DateTime) _rangeForPeriod() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case 'Semanal':
        final start = now.subtract(const Duration(days: 7));
        return (DateTime(start.year, start.month, start.day), DateTime(now.year, now.month, now.day, 23, 59, 59));
      case 'Mês atual':
        return (DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 0, 23, 59, 59));
      case 'Mês anterior':
        final lastMonth = DateTime(now.year, now.month - 1);
        return (DateTime(lastMonth.year, lastMonth.month, 1), DateTime(lastMonth.year, lastMonth.month + 1, 0, 23, 59, 59));
      case 'Anual':
        return (DateTime(now.year, 1, 1), DateTime(now.year, 12, 31, 23, 59, 59));
      case 'Por período':
        final start = _customRangeStart ?? DateTime(now.year, now.month, 1);
        final end = _customRangeEnd ?? now;
        final endNorm = end.isBefore(start) ? start : end;
        return (DateTime(start.year, start.month, start.day), DateTime(endNorm.year, endNorm.month, endNorm.day, 23, 59, 59));
      default:
        return (DateTime(now.year, 1, 1), DateTime(now.year, now.month + 1, 0, 23, 59, 59));
    }
  }

  void _applyPeriod() {
    final (f, t) = _rangeForPeriod();
    setState(() {
      _from = f;
      _to = t;
      _txDisplayLimit = _txPageSize;
    });
    _scheduleMergedReload();
  }

  void _resetFilters() {
    setState(() {
      _statusFilter = 'paid';
      _typeFilter = 'all';
      _categoryFilter = null;
      _search = '';
      _searchCtrl.clear();
      _financeAccountFilterId = null;
      _txDisplayLimit = _txPageSize;
    });
    _scheduleMergedReload();
  }

  Future<void> _openCategoryFilterPicker(List<String> periodCategories) async {
    final picked = await pickFinanceCategoryForFilter(
      context: context,
      uid: firestoreUserDocIdForAppShell(widget.uid),
      typeFilter: _typeFilter,
      currentFilter: _categoryFilter,
      periodExtraCategories: periodCategories,
    );
    if (!mounted || picked == null) return;
    setState(() {
      _categoryFilter = picked;
      _txDisplayLimit = _txPageSize;
    });
  }

  Future<void> _confirmPaymentWithOptimistic(BuildContext context, String docId) async {
    setState(() => _optimisticPaidIds.add(docId));
    try {
      await widget.handlers.onConfirmPayment(context, docId);
    } finally {
      if (mounted) {
        setState(() => _optimisticPaidIds.remove(docId));
        _scheduleMergedReload();
      }
    }
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> raw,
    List<FinanceAccount> accounts,
  ) {
    final list = _baseFiltered(raw, accounts);
    return list.where((doc) {
      final d = doc.data();
      if (_typeFilter != 'all' && (d['type'] ?? 'expense').toString() != _typeFilter) return false;
      if (_categoryFilter != null) {
        final c = (d['category'] ?? '').toString().trim();
        if (!FinanceCategoryMerger.sameCategoryGroup(c, _categoryFilter!)) return false;
      }
      return true;
    }).toList();
  }

  List<String> _categoriesForDropdown(List<QueryDocumentSnapshot<Map<String, dynamic>>> afterBase) {
    final s = <String>{};
    for (final doc in afterBase) {
      final c = (doc.data()['category'] ?? '').toString().trim();
      if (c.isNotEmpty) s.add(c);
    }
    return UserCategoriesService.sortedWithoutIncluirNova(s);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _baseFiltered(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> raw,
    List<FinanceAccount> accounts,
  ) {
    final rs = DateTime(_from.year, _from.month, _from.day);
    final re = DateTime(_to.year, _to.month, _to.day, 23, 59, 59);
    final list = raw.where((doc) {
      final d = doc.data();
      final effective = FinanceLineOpening.effectiveDateTimeFromMap(d);
      if (effective == null || effective.isBefore(rs) || effective.isAfter(re)) return false;
      if (_statusFilter != 'all') {
        final status = (d['status'] ?? 'paid').toString();
        if (status != _statusFilter) return false;
      }
      final accLabel = financeAccountLabelForTx(accounts, d) ?? '';
      if (_search.isNotEmpty) {
        final text = '${d['category'] ?? ''} ${d['description'] ?? ''} $accLabel'.toLowerCase();
        if (!text.contains(_search)) return false;
      }
      if (_financeAccountFilterId != null) {
        final aid = (d['financeAccountId'] ?? '').toString().trim();
        if (aid != _financeAccountFilterId) return false;
      }
      return true;
    }).toList();
    return FinanceFaturaTransactionSort.sortedDocs(list, _sortMode);
  }

  Widget _dayHeader(DateTime? day) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
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
                Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  day == null
                      ? 'Sem data'
                      : DateTimeFormats.formatDate(day),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: 0.2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _popComFiltrosSincronizados();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: scaffoldKeyboardResizeToAvoidBottomInset(),
        backgroundColor: const Color(0xFFF1F5F9),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(8, MediaQuery.paddingOf(context).top + 6, 8, 10),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: _popComFiltrosSincronizados,
                    tooltip: 'Fechar',
                    style: IconButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.14),
                      surfaceTintColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.26), width: 1),
                      ),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 24),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'Lançamentos',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A237E), letterSpacing: -0.2),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _resetFilters,
                    icon: const Icon(Icons.restart_alt_rounded, size: 20),
                    label: Text(
                      'Limpar',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: AppColors.primary,
                        letterSpacing: 0.15,
                      ),
                    ),
                    style: _toolbarTonalFilledStyle(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SafeArea(
                top: false,
                child: StreamBuilder<List<FinanceAccount>>(
                stream: _accountsStream,
                builder: (context, accSnap) {
                  final accounts = accSnap.data ?? const <FinanceAccount>[];

                  if (_mergedLoadError != null) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('Erro ao carregar: $_mergedLoadError', textAlign: TextAlign.center),
                      ),
                    );
                  }
                  if (_mergedLoading && (_mergedDocs == null || _mergedDocs!.isEmpty)) {
                    return const Padding(padding: EdgeInsets.all(16), child: SkeletonListLoader(itemCount: 8, itemHeight: 72));
                  }

                  final raw = _mergedDocs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                      final base = _baseFiltered(raw, accounts);
                      final categoryOptions = _categoriesForDropdown(base);
                      final docs = _filterDocs(raw, accounts);
                      final accountFilterValid =
                          _financeAccountFilterId == null || accounts.any((a) => a.id == _financeAccountFilterId);

                      String? categoryDropdownValue() {
                        if (_categoryFilter == null) return null;
                        for (final o in categoryOptions) {
                          if (FinanceCategoryMerger.sameCategoryGroup(o, _categoryFilter!)) return o;
                        }
                        final stillInPeriod = raw.any((doc) {
                          final c = (doc.data()['category'] ?? '').toString().trim();
                          return FinanceCategoryMerger.sameCategoryGroup(c, _categoryFilter!);
                        });
                        return stillInPeriod ? _categoryFilter : null;
                      }

                      final categoryValue = categoryDropdownValue();
                      final extraCategoryForMenu = <String>[];
                      if (_categoryFilter != null) {
                        final inOptions =
                            categoryOptions.any((o) => FinanceCategoryMerger.sameCategoryGroup(o, _categoryFilter!));
                        if (!inOptions &&
                            raw.any((doc) {
                              final c = (doc.data()['category'] ?? '').toString().trim();
                              return FinanceCategoryMerger.sameCategoryGroup(c, _categoryFilter!);
                            })) {
                          extraCategoryForMenu.add(_categoryFilter!);
                        }
                      }

                      if (!accountFilterValid && _financeAccountFilterId != null) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _financeAccountFilterId = null);
                        });
                      }
                      if (_categoryFilter != null && categoryValue == null) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _categoryFilter = null);
                        });
                      }

                      final bottomPad = MediaQuery.paddingOf(context).bottom + 12;
                      final nShow = docs.length < _txDisplayLimit ? docs.length : _txDisplayLimit;
                      final docsVisible = nShow == docs.length ? docs : docs.sublist(0, nShow);
                      final hasMoreTx = docs.length > docsVisible.length;

                      // Filtros + lista no mesmo scroll (evita o cartão de filtros “comer” a lista no mobile).
                      Widget filterCard() {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white,
                                  AppColors.primary.withValues(alpha: 0.04),
                                  AppColors.accent.withValues(alpha: 0.03),
                                ],
                              ),
                              border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.deepBlueDark.withValues(alpha: 0.14),
                                  blurRadius: 22,
                                  offset: const Offset(0, 8),
                                ),
                                BoxShadow(
                                  color: AppColors.accent.withValues(alpha: 0.08),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              elevation: 0,
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                      const Text('Período', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: AppColors.textSecondary)),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: _periods.map((p) {
                                          return _financePeriodChip(
                                            period: p,
                                            selected: _selectedPeriod == p,
                                            onSelect: () {
                                              setState(() {
                                                _selectedPeriod = p;
                                                if (p == 'Por período' && _customRangeStart == null) {
                                                  final n = DateTime.now();
                                                  _customRangeStart = DateTime(n.year, n.month, 1);
                                                  _customRangeEnd = n;
                                                }
                                                _applyPeriod();
                                              });
                                            },
                                          );
                                        }).toList(),
                                      ),
                                      if (_selectedPeriod == 'Por período') ...[
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: () async {
                                                  final picked = await showDatePicker(
                                                    context: context,
                                                    initialDate: _customRangeStart ?? _from,
                                                    firstDate: DateTime(2020),
                                                    lastDate: DateTime(2100),
                                                  );
                                                  if (picked != null && mounted) {
                                                    setState(() {
                                                      _customRangeStart = picked;
                                                      _applyPeriod();
                                                    });
                                                  }
                                                },
                                                icon: const Icon(Icons.calendar_today_rounded, size: 18),
                                                label: Text('De ${_customRangeStart?.day ?? _from.day}/${_customRangeStart?.month ?? _from.month}'),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: () async {
                                                  final picked = await showDatePicker(
                                                    context: context,
                                                    initialDate: _customRangeEnd ?? _to,
                                                    firstDate: _customRangeStart ?? DateTime(2020),
                                                    lastDate: DateTime(2100),
                                                  );
                                                  if (picked != null && mounted) {
                                                    setState(() {
                                                      _customRangeEnd = picked;
                                                      _applyPeriod();
                                                    });
                                                  }
                                                },
                                                icon: const Icon(Icons.event_rounded, size: 18),
                                                label: Text('Até ${_customRangeEnd?.day ?? _to.day}/${_customRangeEnd?.month ?? _to.month}'),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                      const Divider(height: 22),
                                      DropdownButtonFormField<String>(
                                        value: _typeFilter,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          labelText: 'Tipo de lançamento',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                                          isDense: true,
                                        ),
                                        items: const [
                                          DropdownMenuItem(value: 'all', child: Text('Receitas e despesas')),
                                          DropdownMenuItem(value: 'income', child: Text('Só receitas')),
                                          DropdownMenuItem(value: 'expense', child: Text('Só despesas')),
                                        ],
                                        onChanged: (v) {
                                          if (v == null) return;
                                          setState(() {
                                            _typeFilter = v;
                                            _txDisplayLimit = _txPageSize;
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      DropdownButtonFormField<String>(
                                        value: _statusFilter,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          labelText: 'Status',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                                          isDense: true,
                                        ),
                                        items: const [
                                          DropdownMenuItem(value: 'all', child: Text('Todos os status')),
                                          DropdownMenuItem(value: 'paid', child: Text('Pago')),
                                          DropdownMenuItem(value: 'pending', child: Text('Pendente')),
                                        ],
                                        onChanged: (v) {
                                          if (v == null) return;
                                          setState(() {
                                            _statusFilter = v;
                                            _txDisplayLimit = _txPageSize;
                                          });
                                          _scheduleMergedReload();
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      DropdownButtonFormField<String?>(
                                        key: ValueKey<String?>(accountFilterValid ? _financeAccountFilterId : null),
                                        initialValue: accountFilterValid ? _financeAccountFilterId : null,
                                        decoration: const InputDecoration(
                                          labelText: 'Conta',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                                          isDense: true,
                                        ),
                                        items: [
                                          const DropdownMenuItem<String?>(value: null, child: Text('Todas as contas')),
                                          ...accounts.map(
                                            (a) => DropdownMenuItem<String?>(value: a.id, child: Text(a.displayName, overflow: TextOverflow.ellipsis)),
                                          ),
                                        ],
                                        onChanged: (v) {
                                          setState(() {
                                            _financeAccountFilterId = v;
                                            _txDisplayLimit = _txPageSize;
                                          });
                                          _scheduleMergedReload();
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      Builder(
                                        builder: (context) {
                                          final ordered = <String>[];
                                          final seenLower = <String>{};
                                          void addUnique(String cat) {
                                            final k = cat.toLowerCase().trim();
                                            if (k.isEmpty || !seenLower.add(k)) return;
                                            ordered.add(cat);
                                          }

                                          for (final o in categoryOptions) {
                                            addUnique(o);
                                          }
                                          for (final e in extraCategoryForMenu) {
                                            addUnique(e);
                                          }

                                          return FinanceCategoryFilterTile(
                                            selectedCategory: categoryValue,
                                            onTap: () => _openCategoryFilterPicker(ordered),
                                            onClear: categoryValue == null
                                                ? null
                                                : () => setState(() {
                                                      _categoryFilter = null;
                                                      _txDisplayLimit = _txPageSize;
                                                    }),
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      FinanceFilterSearchField(
                                        controller: _searchCtrl,
                                        hintText: 'Buscar descrição, categoria ou conta…',
                                        showClear: _search.isNotEmpty,
                                        onClear: () {
                                          _searchCtrl.clear();
                                          setState(() => _search = '');
                                        },
                                        onChanged: (v) {
                                          _searchDebounceTimer?.cancel();
                                          _searchDebounceTimer = Timer(
                                            Duration(milliseconds: AppBusinessRules.searchDebounceMs),
                                            () {
                                              if (!mounted) return;
                                              setState(() => _search = v.toLowerCase().trim());
                                            },
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      FinanceTransactionSortBar(
                                        value: _sortMode,
                                        onChanged: (mode) => setState(() {
                                          _sortMode = mode;
                                          _txDisplayLimit = _txPageSize;
                                        }),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                      }

                      final hPad = math.max(12.0, (MediaQuery.sizeOf(context).width - 920) / 2);
                      final toolbar = Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              colors: [
                                Colors.white,
                                AppColors.primary.withValues(alpha: 0.035),
                              ],
                            ),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.deepBlueDark.withValues(alpha: 0.1),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                          color: Colors.transparent,
                          elevation: 0,
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: Row(
                              children: [
                                Icon(Icons.receipt_long_rounded, size: 20, color: AppColors.primary.withValues(alpha: 0.9)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    hasMoreTx ? '${docsVisible.length} de ${docs.length} lançamentos' : '${docs.length} lançamento(s)',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                                  ),
                                ),
                                if (!_gridSelectionMode)
                                  FilledButton.tonalIcon(
                                    onPressed: () => setState(() => _gridSelectionMode = true),
                                    icon: const Icon(Icons.checklist_rounded, size: 20),
                                    label: Text(
                                      'Selecionar',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                        color: AppColors.primary,
                                        letterSpacing: 0.15,
                                      ),
                                    ),
                                    style: _toolbarTonalFilledStyle(),
                                  )
                                else
                                  Expanded(
                                    child: Wrap(
                                      alignment: WrapAlignment.end,
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        FilledButton.tonal(
                                          onPressed: () => setState(() {
                                            _gridSelectionMode = false;
                                            _gridSelectedIds.clear();
                                          }),
                                          style: _toolbarTonalFilledStyle(),
                                          child: Text(
                                            'Cancelar',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13,
                                              color: AppColors.primary,
                                              letterSpacing: 0.15,
                                            ),
                                          ),
                                        ),
                                        if (_gridSelectedIds.isNotEmpty)
                                          FilledButton.icon(
                                            onPressed: () async {
                                              final confirm = await showDialog<bool>(
                                                context: context,
                                                builder: (ctx) => AlertDialog(
                                                  title: const Text('Excluir selecionados?'),
                                                  content: Text('${_gridSelectedIds.length} lançamento(s). Esta ação não pode ser desfeita.'),
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
                                              if (confirm != true) return;
                                              if (!context.mounted) return;
                                              await widget.handlers.onDeleteBatch(context, _gridSelectedIds.toList());
                                              if (!context.mounted) return;
                                              setState(() {
                                                _gridSelectionMode = false;
                                                _gridSelectedIds.clear();
                                              });
                                            },
                                            icon: const Icon(Icons.delete_outline_rounded),
                                            label: Text('Excluir (${_gridSelectedIds.length})'),
                                            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                                          ),
                                      ],
                                    ),
                                  ),
                            ],
                          ),
                        ),
                          ),
                        ),
                      );

                      return Padding(
                        padding: EdgeInsets.symmetric(horizontal: hPad),
                        child: CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          slivers: [
                            SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  filterCard(),
                                  const SizedBox(height: 8),
                                  toolbar,
                                  const SizedBox(height: 10),
                                ],
                              ),
                            ),
                            if (docs.isEmpty)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.receipt_long_rounded, size: 56, color: Colors.grey.shade400),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Nenhum lançamento com estes filtros.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              SliverPadding(
                                padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPad),
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) {
                                      if (hasMoreTx && index == docsVisible.length) {
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          child: Center(
                                            child: FilledButton.tonalIcon(
                                              onPressed: () => setState(() => _txDisplayLimit += _txPageSize),
                                              icon: const Icon(Icons.expand_more_rounded),
                                              label: Text(
                                                'Carregar mais',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 13,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                              style: _toolbarTonalFilledStyle(
                                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                                visualDensity: VisualDensity.standard,
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                      final doc = docsVisible[index];
                                      final showHeader = index == 0 ||
                                          _transactionCalendarDay(docsVisible[index - 1].data()) !=
                                              _transactionCalendarDay(doc.data());
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          if (showHeader) _dayHeader(_transactionCalendarDay(doc.data())),
                                          FinanceTransactionListTile(
                                            doc: doc,
                                            profile: widget.profile,
                                            financeAccounts: accounts,
                                            gridSelectionMode: _gridSelectionMode,
                                            isSelected: _gridSelectedIds.contains(doc.id),
                                            optimisticPaidIds: _optimisticPaidIds,
                                            onToggleSelection: () => setState(() {
                                              if (_gridSelectedIds.contains(doc.id)) {
                                                _gridSelectedIds.remove(doc.id);
                                              } else {
                                                _gridSelectedIds.add(doc.id);
                                              }
                                            }),
                                            onEdit: widget.handlers.onEdit,
                                            onDelete: widget.handlers.onDelete,
                                            onConfirmPayment: _confirmPaymentWithOptimistic,
                                            onAttachReceipt: widget.handlers.onAttachReceipt,
                                          ),
                                        ],
                                      );
                                    },
                                    childCount: docsVisible.length + (hasMoreTx ? 1 : 0),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                },
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }
}
