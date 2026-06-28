import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/material.dart';

import '../constants/currency_formats.dart';
import '../constants/date_time_formats.dart';
import '../constants/finance_account_visuals.dart';
import '../models/finance_account.dart';
import '../models/user_profile.dart';
import '../services/finance_accounts_service.dart';
import '../theme/app_colors.dart';
import '../utils/debounced_text_controller.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/finance_transactions_hub.dart';
import '../utils/keyboard_form_scaffold.dart';
import '../utils/premium_upgrade.dart';
import '../widgets/fast_text_field.dart';
import '../widgets/finance_bank_brand_thumb.dart';

enum _PeriodPreset { last30, last90, last365, custom }

enum _MigracaoModo { semConta, transferirBanco }

enum _TipoFiltro { todos, receitas, despesas }

/// Assistente de migração: sem conta → banco, ou transferir lançamentos de um banco para outro.
class FinanceBulkAssignScreen extends StatefulWidget {
  final String uid;
  final UserProfile profile;
  final DateTime? initialRangeFrom;
  final DateTime? initialRangeTo;
  final int? semContaNoPainelFinanceiro;
  /// Se vier do Financeiro com filtro de conta, abre já em «Transferir banco».
  final String? initialSourceAccountId;

  const FinanceBulkAssignScreen({
    super.key,
    required this.uid,
    required this.profile,
    this.initialRangeFrom,
    this.initialRangeTo,
    this.semContaNoPainelFinanceiro,
    this.initialSourceAccountId,
  });

  @override
  State<FinanceBulkAssignScreen> createState() => _FinanceBulkAssignScreenState();
}

class _FinanceBulkAssignScreenState extends State<FinanceBulkAssignScreen> {
  _MigracaoModo _modo = _MigracaoModo.semConta;
  _TipoFiltro _tipoFiltro = _TipoFiltro.todos;
  _PeriodPreset _preset = _PeriodPreset.last30;
  late DateTime _from;
  late DateTime _to;
  final _filterCtrl = DebouncedTextController();
  String? _sourceAccountId;
  String? _destAccountId;
  bool _loadingApply = false;
  bool _loadingList = false;
  String? _listError;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _transactions = [];
  final Set<String> _checkedIds = {};
  StreamSubscription<fa.User?>? _authUidSub;

  CollectionReference<Map<String, dynamic>> get _txRef =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(firestoreUserDocIdForAppShell(widget.uid))
          .collection('transactions');

  @override
  void initState() {
    super.initState();
    _authUidSub = fa.FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted) setState(() {});
    });
    _filterCtrl.debouncedText.addListener(_onFilterDebounced);

    final src = widget.initialSourceAccountId?.trim();
    if (src != null && src.isNotEmpty) {
      _modo = _MigracaoModo.transferirBanco;
      _sourceAccountId = src;
    }

    if (widget.initialRangeFrom != null && widget.initialRangeTo != null) {
      _from = DateTime(
        widget.initialRangeFrom!.year,
        widget.initialRangeFrom!.month,
        widget.initialRangeFrom!.day,
      );
      _to = DateTime(
        widget.initialRangeTo!.year,
        widget.initialRangeTo!.month,
        widget.initialRangeTo!.day,
        23,
        59,
        59,
      );
      _preset = _PeriodPreset.custom;
    } else {
      _applyPresetDates(_PeriodPreset.last30, setPreset: true, reload: false);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _reloadList());
  }

  @override
  void dispose() {
    _authUidSub?.cancel();
    _filterCtrl.debouncedText.removeListener(_onFilterDebounced);
    _filterCtrl.dispose();
    super.dispose();
  }

  void _onFilterDebounced() {
    _retainCheckedInFiltered();
    if (mounted) setState(() {});
  }

  void _applyPresetDates(_PeriodPreset p, {bool setPreset = true, bool reload = true}) {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    DateTime start;
    switch (p) {
      case _PeriodPreset.last30:
        final s = end.subtract(const Duration(days: 29));
        start = DateTime(s.year, s.month, s.day);
        break;
      case _PeriodPreset.last90:
        final s = end.subtract(const Duration(days: 89));
        start = DateTime(s.year, s.month, s.day);
        break;
      case _PeriodPreset.last365:
        final s = end.subtract(const Duration(days: 364));
        start = DateTime(s.year, s.month, s.day);
        break;
      case _PeriodPreset.custom:
        return;
    }
    setState(() {
      if (setPreset) _preset = p;
      _from = start;
      _to = end;
    });
    if (reload) unawaited(_reloadList());
  }

  bool _passesTipo(Map<String, dynamic> d) {
    final income = (d['type'] ?? 'expense').toString() == 'income';
    switch (_tipoFiltro) {
      case _TipoFiltro.todos:
        return true;
      case _TipoFiltro.receitas:
        return income;
      case _TipoFiltro.despesas:
        return !income;
    }
  }

  bool _passesOrigem(Map<String, dynamic> d) {
    final cur = (d['financeAccountId'] ?? '').toString().trim();
    final paidFrom = (d['paidFromFinanceAccountId'] ?? '').toString().trim();
    if (_modo == _MigracaoModo.semConta) {
      return cur.isEmpty;
    }
    final src = _sourceAccountId?.trim() ?? '';
    if (src.isEmpty) return false;
    return cur == src || paidFrom == src;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filteredList() {
    final q = _filterCtrl.text.trim().toLowerCase();
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> list = _transactions;
    if (q.isNotEmpty) {
      list = list.where((doc) {
        final d = doc.data();
        final cat = (d['category'] ?? '').toString();
        final desc = (d['description'] ?? '').toString();
        final tipo = (d['type'] ?? 'expense').toString() == 'income' ? 'receita' : 'despesa';
        final amt = CurrencyFormats.formatBRL((d['amount'] ?? 0) as num?);
        final blob = '$cat $desc $tipo $amt'.toLowerCase();
        return blob.contains(q);
      });
    }
    return list.toList();
  }

  void _retainCheckedInFiltered() {
    final vis = _filteredList().map((e) => e.id).toSet();
    _checkedIds.removeWhere((id) => !vis.contains(id));
  }

  void _selectAllFiltered() {
    setState(() => _checkedIds.addAll(_filteredList().map((e) => e.id)));
  }

  void _deselectFiltered() {
    setState(() {
      for (final id in _filteredList().map((e) => e.id)) {
        _checkedIds.remove(id);
      }
    });
  }

  void _checkAllAfterReload() {
    _checkedIds
      ..clear()
      ..addAll(_transactions.map((e) => e.id));
  }

  Future<void> _reloadList() async {
    if (_modo == _MigracaoModo.transferirBanco &&
        (_sourceAccountId == null || _sourceAccountId!.trim().isEmpty)) {
      setState(() {
        _transactions = [];
        _checkedIds.clear();
        _loadingList = false;
        _listError = null;
      });
      return;
    }

    setState(() {
      _loadingList = true;
      _listError = null;
    });
    try {
      var f = DateTime(_from.year, _from.month, _from.day);
      var t = DateTime(_to.year, _to.month, _to.day, 23, 59, 59);
      if (t.isBefore(f)) {
        final tmp = f;
        f = DateTime(t.year, t.month, t.day);
        t = DateTime(tmp.year, tmp.month, tmp.day, 23, 59, 59);
      }
      final snap = await _txRef
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(f))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(t))
          .orderBy('date', descending: true)
          .get();
      final list = snap.docs.where((doc) {
        final d = doc.data();
        return _passesOrigem(d) && _passesTipo(d);
      }).toList();
      if (!mounted) return;
      setState(() {
        _transactions = list;
        _loadingList = false;
      });
      _checkAllAfterReload();
      _retainCheckedInFiltered();
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _transactions = [];
        _checkedIds.clear();
        _listError = e.toString();
        _loadingList = false;
      });
    }
  }

  FinanceAccount? _accountById(List<FinanceAccount> accounts, String? id) {
    if (id == null || id.isEmpty) return null;
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  String _accountLabel(List<FinanceAccount> accounts, String? id) {
    return _accountById(accounts, id)?.displayName ?? 'Conta';
  }

  Future<bool> _confirmApply(List<FinanceAccount> accounts, int count) async {
    if (_modo == _MigracaoModo.semConta) return true;
    final src = _sourceAccountId!;
    final dest = _destAccountId!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Icon(Icons.swap_horiz_rounded, color: AppColors.primary, size: 40),
        title: const Text('Confirmar transferência', textAlign: TextAlign.center),
        content: Text(
          'Mover $count lançamento(s) de «${_accountLabel(accounts, src)}» '
          'para «${_accountLabel(accounts, dest)}» no período selecionado?',
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.4, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Não')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sim, transferir'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _applyAssign(List<FinanceAccount> accounts) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final dest = _destAccountId?.trim();
    if (dest == null || dest.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escolha o banco de destino.')),
      );
      return;
    }
    if (_modo == _MigracaoModo.transferirBanco) {
      final src = _sourceAccountId?.trim();
      if (src == null || src.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Escolha o banco de origem.')),
        );
        return;
      }
      if (src == dest) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Origem e destino devem ser bancos diferentes.')),
        );
        return;
      }
    }

    final targets = _filteredList().where((d) => _checkedIds.contains(d.id)).toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marque ao menos um lançamento na lista.')),
      );
      return;
    }

    if (!await _confirmApply(accounts, targets.length)) return;

    setState(() => _loadingApply = true);
    try {
      final src = _sourceAccountId?.trim() ?? '';
      const chunk = 450;
      for (var i = 0; i < targets.length; i += chunk) {
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in targets.skip(i).take(chunk)) {
          final d = doc.data();
          final updates = <String, dynamic>{
            'updatedAt': FieldValue.serverTimestamp(),
          };
          if (_modo == _MigracaoModo.semConta) {
            updates['financeAccountId'] = dest;
          } else {
            final cur = (d['financeAccountId'] ?? '').toString().trim();
            final paidFrom = (d['paidFromFinanceAccountId'] ?? '').toString().trim();
            if (cur == src) updates['financeAccountId'] = dest;
            if (paidFrom == src) updates['paidFromFinanceAccountId'] = dest;
            if (updates.length <= 1) continue;
          }
          batch.update(doc.reference, updates);
        }
        await batch.commit();
      }
      FinanceTransactionsHub.notifyMutated(uid: firestoreUserDocIdForAppShell(widget.uid));
      if (!mounted) return;
      final msg = _modo == _MigracaoModo.semConta
          ? '${targets.length} lançamento(s) vinculados a ${_accountLabel(accounts, dest)}.'
          : '${targets.length} lançamento(s) transferidos para ${_accountLabel(accounts, dest)}.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      await _reloadList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingApply = false);
    }
  }

  String _txTitle(Map<String, dynamic> d) {
    final cat = (d['category'] ?? '').toString().trim();
    final desc = (d['description'] ?? '').toString().trim();
    if (desc.isNotEmpty) return desc.length > 60 ? '${desc.substring(0, 60)}…' : desc;
    if (cat.isNotEmpty) return cat;
    return (d['type'] ?? 'expense').toString() == 'income' ? 'Receita' : 'Despesa';
  }

  String _txSubtitle(Map<String, dynamic> d) {
    final ts = d['date'];
    String data = '';
    if (ts is Timestamp) data = DateTimeFormats.dateBR.format(ts.toDate());
    final tipo = (d['type'] ?? 'expense').toString() == 'income' ? 'Receita' : 'Despesa';
    final cat = (d['category'] ?? '').toString().trim();
    final catPart = cat.isEmpty ? '' : ' • $cat';
    return '$data • $tipo$catPart';
  }

  ({int nInc, int nExp, double sumInc, double sumExp}) _stats() {
    var nInc = 0, nExp = 0;
    var sumInc = 0.0, sumExp = 0.0;
    for (final doc in _transactions) {
      final d = doc.data();
      final income = (d['type'] ?? 'expense').toString() == 'income';
      final amt = (d['amount'] ?? 0).toDouble();
      if (income) {
        nInc++;
        sumInc += amt;
      } else {
        nExp++;
        sumExp += amt;
      }
    }
    return (nInc: nInc, nExp: nExp, sumInc: sumInc, sumExp: sumExp);
  }

  Widget _buildHeaderHero() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF0EA5E9), Color(0xFF10B981)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Migrar lançamentos',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _modo == _MigracaoModo.semConta
                ? 'Vincule receitas e despesas sem banco a uma conta de destino.'
                : 'Transfira lançamentos de um banco/cartão para outro — por período, tipo e seleção.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModoSelector() {
    return SegmentedButton<_MigracaoModo>(
      segments: const [
        ButtonSegment(
          value: _MigracaoModo.semConta,
          label: Text('Sem banco'),
          icon: Icon(Icons.link_off_rounded, size: 18),
        ),
        ButtonSegment(
          value: _MigracaoModo.transferirBanco,
          label: Text('Entre bancos'),
          icon: Icon(Icons.swap_horiz_rounded, size: 18),
        ),
      ],
      selected: {_modo},
      onSelectionChanged: (s) {
        setState(() {
          _modo = s.first;
          _checkedIds.clear();
        });
        _reloadList();
      },
    );
  }

  Widget _tipoChip(String label, _TipoFiltro tipo, Color color, IconData icon) {
    final selected = _tipoFiltro == tipo;
    return FilterChip(
      selected: selected,
      avatar: Icon(icon, size: 18, color: selected ? Colors.white : color),
      label: Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: selected ? Colors.white : color)),
      selectedColor: color,
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color.withValues(alpha: 0.45)),
      onSelected: (_) {
        setState(() => _tipoFiltro = tipo);
        _reloadList();
      },
    );
  }

  Widget _buildTipoFilter() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _tipoChip('Todos', _TipoFiltro.todos, AppColors.primary, Icons.payments_rounded),
        _tipoChip('Receitas', _TipoFiltro.receitas, AppColors.financeReceita, Icons.trending_up_rounded),
        _tipoChip('Despesas', _TipoFiltro.despesas, AppColors.financeDespesa, Icons.trending_down_rounded),
      ],
    );
  }

  Widget _accountDropdown({
    required List<FinanceAccount> accounts,
    required String? value,
    required String hint,
    required ValueChanged<String?> onChanged,
    String? excludeId,
  }) {
    final items = accounts.where((a) => excludeId == null || a.id != excludeId).toList();
    return DropdownButtonFormField<String>(
      isExpanded: true,
      value: value != null && items.any((a) => a.id == value) ? value : null,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      hint: Text(hint),
      items: items
          .map(
            (a) => DropdownMenuItem<String>(
              value: a.id,
              child: Row(
                children: [
                  FinanceBankBrandThumb(
                    preset: a.preset,
                    size: 28,
                    fallbackIcon: financeAccountVisualFor(a).icon,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(a.displayName, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildResumoCard() {
    if (_loadingList || _listError != null) return const SizedBox.shrink();
    final n = _transactions.length;
    final periodo =
        '${DateTimeFormats.dateBR.format(_from)}  →  ${DateTimeFormats.dateBR.format(_to)}';
    if (n == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF16A34A).withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green.shade700, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _modo == _MigracaoModo.semConta
                    ? 'Nenhum lançamento sem banco neste período ($periodo).'
                    : 'Nenhum lançamento do banco de origem neste período/filtro.',
                style: TextStyle(fontSize: 13, height: 1.35, color: Colors.grey.shade800),
              ),
            ),
          ],
        ),
      );
    }

    final st = _stats();
    final gradient = _modo == _MigracaoModo.semConta
        ? const [Color(0xFFFFF7ED), Color(0xFFFFEDD5)]
        : const [Color(0xFFEEF2FF), Color(0xFFDBEAFE)];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$n lançamento(s) encontrado(s)',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(periodo, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
          const SizedBox(height: 10),
          Text(
            '• ${st.nInc} receita(s) · ${CurrencyFormats.formatBRL(st.sumInc)}',
            style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.financeReceita),
          ),
          Text(
            '• ${st.nExp} despesa(s) · ${CurrencyFormats.formatBRL(st.sumExp)}',
            style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.financeDespesa),
          ),
          const SizedBox(height: 8),
          Text(
            'Todos já vêm marcados — desmarque os que não quiser mover.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildTxCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final income = (d['type'] ?? 'expense').toString() == 'income';
    final accent = income ? AppColors.financeReceita : AppColors.financeDespesa;
    final checked = _checkedIds.contains(doc.id);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          setState(() {
            if (checked) {
              _checkedIds.remove(doc.id);
            } else {
              _checkedIds.add(doc.id);
            }
          });
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: checked ? accent : Colors.grey.shade300,
              width: checked ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: checked ? 0.15 : 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 5,
                height: 72,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                ),
              ),
              Checkbox(
                value: checked,
                activeColor: accent,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _checkedIds.add(doc.id);
                    } else {
                      _checkedIds.remove(doc.id);
                    }
                  });
                },
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _txTitle(d),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _txSubtitle(d),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Text(
                  CurrencyFormats.formatBRL((d['amount'] ?? 0) as num?),
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredList();
    final visibleIds = filtered.map((e) => e.id).toSet();
    final nSel = _checkedIds.where(visibleIds.contains).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF4FBF6),
      resizeToAvoidBottomInset: scaffoldKeyboardResizeToAvoidBottomInset(),
      appBar: AppBar(
        title: const Text('Migrar lançamentos', style: TextStyle(fontWeight: FontWeight.w800)),
        elevation: 0,
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar lista',
            onPressed: _loadingList ? null : _reloadList,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: keyboardScaffoldBody(
        StreamBuilder<List<FinanceAccount>>(
          stream: FinanceAccountsService().streamAccounts(firestoreUserDocIdForAppShell(widget.uid)),
          builder: (context, accSnap) {
            final accounts = accSnap.data ?? [];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    children: [
                      _buildHeaderHero(),
                      const SizedBox(height: 16),
                      _buildModoSelector(),
                      const SizedBox(height: 14),
                      _buildResumoCard(),
                      const SizedBox(height: 16),
                      Text('Tipo de lançamento', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.primary)),
                      const SizedBox(height: 8),
                      _buildTipoFilter(),
                      const SizedBox(height: 16),
                      Text('Período', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.primary)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('30 dias'),
                            selected: _preset == _PeriodPreset.last30,
                            onSelected: (v) {
                              if (v) _applyPresetDates(_PeriodPreset.last30);
                            },
                          ),
                          ChoiceChip(
                            label: const Text('90 dias'),
                            selected: _preset == _PeriodPreset.last90,
                            onSelected: (v) {
                              if (v) _applyPresetDates(_PeriodPreset.last90);
                            },
                          ),
                          ChoiceChip(
                            label: const Text('365 dias'),
                            selected: _preset == _PeriodPreset.last365,
                            onSelected: (v) {
                              if (v) _applyPresetDates(_PeriodPreset.last365);
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Personalizado'),
                            selected: _preset == _PeriodPreset.custom,
                            onSelected: (v) {
                              if (v) setState(() => _preset = _PeriodPreset.custom);
                            },
                          ),
                        ],
                      ),
                      if (_preset == _PeriodPreset.custom) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final d = await showDatePicker(
                                    context: context,
                                    initialDate: _from,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100),
                                  );
                                  if (d != null) {
                                    setState(() => _from = d);
                                    await _reloadList();
                                  }
                                },
                                icon: const Icon(Icons.event_rounded, size: 18),
                                label: Text('De ${DateTimeFormats.dateBR.format(_from)}'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final first = _from.isBefore(_to) ? _from : _to;
                                  final d = await showDatePicker(
                                    context: context,
                                    initialDate: _to,
                                    firstDate: first,
                                    lastDate: DateTime(2100),
                                  );
                                  if (d != null) {
                                    setState(() => _to = d);
                                    await _reloadList();
                                  }
                                },
                                icon: const Icon(Icons.event_available_rounded, size: 18),
                                label: Text('Até ${DateTimeFormats.dateBR.format(_to)}'),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        const SizedBox(height: 8),
                        Text(
                          '${DateTimeFormats.dateBR.format(_from)} → ${DateTimeFormats.dateBR.format(_to)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                      const SizedBox(height: 18),
                      if (_modo == _MigracaoModo.transferirBanco) ...[
                        Text('Banco de origem', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.primary)),
                        const SizedBox(height: 8),
                        accounts.isEmpty
                            ? const Text('Cadastre contas em Bancos e cartões.')
                            : _accountDropdown(
                                accounts: accounts,
                                value: _sourceAccountId,
                                hint: 'De qual banco/cartão?',
                                excludeId: _destAccountId,
                                onChanged: (v) {
                                  setState(() => _sourceAccountId = v);
                                  _reloadList();
                                },
                              ),
                        const SizedBox(height: 16),
                      ],
                      Text('Banco de destino', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.primary)),
                      const SizedBox(height: 8),
                      accounts.isEmpty
                          ? const Text('Cadastre ao menos uma conta em Bancos e cartões.')
                          : _accountDropdown(
                              accounts: accounts,
                              value: _destAccountId,
                              hint: 'Para qual banco/cartão?',
                              excludeId: _modo == _MigracaoModo.transferirBanco ? _sourceAccountId : null,
                              onChanged: (v) => setState(() => _destAccountId = v),
                            ),
                      const SizedBox(height: 16),
                      FastTextField(
                        controller: _filterCtrl,
                        decoration: InputDecoration(
                          hintText: 'Buscar descrição, categoria, valor…',
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: filtered.isEmpty ? null : _selectAllFiltered,
                            icon: const Icon(Icons.checklist_rounded, size: 20),
                            label: const Text('Marcar todos'),
                          ),
                          TextButton.icon(
                            onPressed: filtered.isEmpty ? null : _deselectFiltered,
                            icon: const Icon(Icons.deselect_rounded, size: 20),
                            label: const Text('Desmarcar'),
                          ),
                        ],
                      ),
                      if (_loadingList)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_listError != null)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(_listError!, style: TextStyle(color: AppColors.error)),
                        )
                      else ...[
                        Text(
                          '${filtered.length} na lista • $nSel selecionado(s)',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey.shade800),
                        ),
                        const SizedBox(height: 8),
                        if (filtered.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Text(
                              _modo == _MigracaoModo.transferirBanco && (_sourceAccountId == null || _sourceAccountId!.isEmpty)
                                  ? 'Selecione o banco de origem para listar os lançamentos.'
                                  : 'Nenhum lançamento neste filtro. Amplie o período ou mude o tipo.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          )
                        else
                          ...filtered.map(_buildTxCard),
                      ],
                    ],
                  ),
                ),
                SafeArea(
                  minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: FilledButton.icon(
                    onPressed: _loadingApply || _loadingList || accounts.isEmpty ? null : () => _applyAssign(accounts),
                    icon: _loadingApply
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(_modo == _MigracaoModo.semConta ? Icons.link_rounded : Icons.swap_horiz_rounded),
                    label: Text(
                      _loadingApply
                          ? 'Aplicando…'
                          : _modo == _MigracaoModo.semConta
                              ? 'Vincular selecionados ao destino'
                              : 'Transferir selecionados para destino',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _modo == _MigracaoModo.semConta ? AppColors.primary : const Color(0xFF7C3AED),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
