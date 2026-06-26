import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import '../utils/keyboard_form_scaffold.dart';
import '../constants/currency_formats.dart';
import '../constants/date_time_formats.dart';
import '../models/finance_account.dart';
import '../models/user_profile.dart';
import '../services/finance_accounts_service.dart';
import '../theme/app_colors.dart';
import '../utils/premium_upgrade.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/debounced_text_controller.dart';
import '../constants/app_business_rules.dart';

enum _PeriodPreset { last30, last90, last365, custom }

/// Assistente de migração: período rápido, lista filtrável de lançamentos sem conta e conta de destino.
class FinanceBulkAssignScreen extends StatefulWidget {
  final String uid;
  final UserProfile profile;
  /// Alinha o intervalo ao período do Financeiro (quando aberto a partir dali).
  final DateTime? initialRangeFrom;
  final DateTime? initialRangeTo;
  /// Quantos “sem conta” o painel do Financeiro mostrou na lista filtrada (só referência; a migração usa o intervalo abaixo).
  final int? semContaNoPainelFinanceiro;

  const FinanceBulkAssignScreen({
    super.key,
    required this.uid,
    required this.profile,
    this.initialRangeFrom,
    this.initialRangeTo,
    this.semContaNoPainelFinanceiro,
  });

  @override
  State<FinanceBulkAssignScreen> createState() => _FinanceBulkAssignScreenState();
}

class _FinanceBulkAssignScreenState extends State<FinanceBulkAssignScreen> {
  _PeriodPreset _preset = _PeriodPreset.last30;
  late DateTime _from;
  late DateTime _to;
  final _filterCtrl = DebouncedTextController();
  String? _accountId;
  bool _loadingApply = false;
  bool _loadingList = false;
  String? _listError;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _semConta = [];
  final Set<String> _checkedIds = {};
  StreamSubscription<fa.User?>? _authUidSub;

  CollectionReference<Map<String, dynamic>> get _txRef =>
      FirebaseFirestore.instance.collection('users').doc(firestoreUserDocIdForAppShell(widget.uid)).collection('transactions');

  @override
  void initState() {
    super.initState();
    _authUidSub = fa.FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted) setState(() {});
    });
    _filterCtrl.debouncedText.addListener(_onFilterDebounced);
    _applyPresetDates(_PeriodPreset.last30);
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

  void _applyPresetDates(_PeriodPreset p, {bool setPreset = true}) {
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
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filteredList() {
    final q = _filterCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(_semConta);
    return _semConta.where((doc) {
      final d = doc.data();
      final cat = (d['category'] ?? '').toString();
      final desc = (d['description'] ?? '').toString();
      final tipo = (d['type'] ?? 'expense').toString() == 'income' ? 'receita' : 'despesa';
      final amt = CurrencyFormats.formatBRL((d['amount'] ?? 0) as num?);
      final blob = '$cat $desc $tipo $amt'.toLowerCase();
      return blob.contains(q);
    }).toList();
  }

  /// Ao filtrar, desmarca lançamentos que saíram da lista visível.
  void _retainCheckedInFiltered() {
    final vis = _filteredList().map((e) => e.id).toSet();
    _checkedIds.removeWhere((id) => !vis.contains(id));
  }

  void _selectAllFiltered() {
    setState(() {
      _checkedIds.addAll(_filteredList().map((e) => e.id));
    });
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
      ..addAll(_semConta.map((e) => e.id));
  }

  Future<void> _reloadList() async {
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
        final cur = (doc.data()['financeAccountId'] ?? '').toString().trim();
        return cur.isEmpty;
      }).toList();
      if (!mounted) return;
      setState(() {
        _semConta = list;
        _loadingList = false;
      });
      _checkAllAfterReload();
      _retainCheckedInFiltered();
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _semConta = [];
        _checkedIds.clear();
        _listError = e.toString();
        _loadingList = false;
      });
    }
  }

  Future<void> _applyAssign() async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final aid = _accountId?.trim();
    if (aid == null || aid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escolha a conta de destino.')));
      return;
    }
    final filtered = _filteredList();
    final targets = filtered.where((d) => _checkedIds.contains(d.id)).toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marque ao menos um lançamento na lista filtrada.')),
      );
      return;
    }
    setState(() => _loadingApply = true);
    try {
      const chunk = 450;
      for (var i = 0; i < targets.length; i += chunk) {
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in targets.skip(i).take(chunk)) {
          batch.update(doc.reference, {
            'financeAccountId': aid,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${targets.length} lançamento(s) vinculados à conta selecionada.')),
      );
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

  ({int nInc, int nExp, double sumInc, double sumExp}) _statsSemConta() {
    var nInc = 0, nExp = 0;
    var sumInc = 0.0, sumExp = 0.0;
    for (final doc in _semConta) {
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

  Widget _buildMigracaoAvisoCard() {
    if (_loadingList || _listError != null) return const SizedBox.shrink();
    final n = _semConta.length;
    final periodo =
        '${DateTimeFormats.dateBR.format(_from)}  →  ${DateTimeFormats.dateBR.format(_to)}';
    final alinhadoFinanceiro =
        widget.initialRangeFrom != null && widget.initialRangeTo != null;

    if (n == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF16A34A).withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green.shade700, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nada para migrar neste período',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.green.shade900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    alinhadoFinanceiro
                        ? 'No intervalo $periodo não há receitas nem despesas sem conta vinculada.'
                        : 'Não há lançamentos sem conta vinculada entre $periodo.',
                    style: TextStyle(fontSize: 13, height: 1.35, color: Colors.grey.shade800),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final st = _statsSemConta();
    final panel = widget.semContaNoPainelFinanceiro;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFF7ED),
            const Color(0xFFFFEDD5),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEA580C).withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEA580C).withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade800.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.warning_amber_rounded, color: Colors.orange.shade900, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Migrar de uma vez',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.orange.shade900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      alinhadoFinanceiro
                          ? 'Período alinhado ao Financeiro: $periodo.'
                          : 'Período selecionado: $periodo.',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.grey.shade900),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: 14, height: 1.4, color: Colors.grey.shade900),
                    children: [
                      const TextSpan(text: 'Encontrados '),
                      TextSpan(
                        text: '$n',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF9A3412)),
                      ),
                      const TextSpan(
                        text: ' lançamentos sem conta (receitas e despesas). Todos já estão ',
                      ),
                      const TextSpan(
                        text: 'marcados',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const TextSpan(text: ' para vincular à mesma conta de destino.'),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '• ${st.nInc} receita(s) · ${CurrencyFormats.formatBRL(st.sumInc)}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF166534)),
                ),
                Text(
                  '• ${st.nExp} despesa(s) · ${CurrencyFormats.formatBRL(st.sumExp)}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF991B1B)),
                ),
                if (panel != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Referência: no painel do Financeiro (lista com filtros atuais) apareciam $panel lançamento(s) sem conta — '
                    'aqui listamos todos os sem conta no intervalo de datas (receitas e despesas, todos os status).',
                    style: TextStyle(fontSize: 12, height: 1.35, color: Colors.grey.shade800),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Escolha a conta de destino abaixo e toque em «Atribuir conta aos selecionados».',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
          ),
        ],
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
        title: const Text('Atribuir conta em massa', style: TextStyle(fontWeight: FontWeight.w800)),
        elevation: 0,
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.maybePop(context),
          style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.maybePop(context),
            child: const Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          IconButton(
            tooltip: 'Atualizar lista',
            onPressed: _loadingList
                ? null
                : () async {
                    await _reloadList();
                  },
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
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  children: [
                    _buildMigracaoAvisoCard(),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
                      ),
                      child: Text(
                        'Use o período para incluir todos os lançamentos antigos sem conta. Filtre a lista se quiser um subconjunto; «Marcar todos filtrados» respeita a busca.',
                        style: TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Período', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.primary)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Últimos 30 dias'),
                          selected: _preset == _PeriodPreset.last30,
                          onSelected: (v) {
                            if (!v) return;
                            _applyPresetDates(_PeriodPreset.last30);
                            _reloadList();
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Últimos 90 dias'),
                          selected: _preset == _PeriodPreset.last90,
                          onSelected: (v) {
                            if (!v) return;
                            _applyPresetDates(_PeriodPreset.last90);
                            _reloadList();
                          },
                        ),
                        ChoiceChip(
                          label: const Text('365 dias'),
                          selected: _preset == _PeriodPreset.last365,
                          onSelected: (v) {
                            if (!v) return;
                            _applyPresetDates(_PeriodPreset.last365);
                            _reloadList();
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Personalizado'),
                          selected: _preset == _PeriodPreset.custom,
                          onSelected: (v) {
                            if (!v) return;
                            setState(() => _preset = _PeriodPreset.custom);
                          },
                        ),
                      ],
                    ),
                    if (_preset == _PeriodPreset.custom) ...[
                      const SizedBox(height: 12),
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
                              label: Text('De ${DateTimeFormats.dateBR.format(_from)}', style: const TextStyle(fontWeight: FontWeight.w700)),
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
                              label: Text('Até ${DateTimeFormats.dateBR.format(_to)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          '${DateTimeFormats.dateBR.format(_from)}  →  ${DateTimeFormats.dateBR.format(_to)}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text('Conta de destino', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.primary)),
                    const SizedBox(height: 8),
                    if (accounts.isEmpty)
                      const Text('Cadastre ao menos uma conta em Bancos e cartões.', style: TextStyle(fontSize: 13))
                    else
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        key: ValueKey<String?>(_accountId != null && accounts.any((a) => a.id == _accountId) ? _accountId : null),
                        initialValue: _accountId != null && accounts.any((a) => a.id == _accountId) ? _accountId : null,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        hint: const Text('Selecione a conta'),
                        items: accounts
                            .map(
                              (a) => DropdownMenuItem<String>(
                                value: a.id,
                                child: Text(a.displayName, overflow: TextOverflow.ellipsis),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _accountId = v),
                      ),
                    const SizedBox(height: 18),
                    FastTextField(
                      controller: _filterCtrl,
                      decoration: InputDecoration(
                        hintText: 'Filtrar por descrição, categoria, valor…',
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
                          label: const Text('Marcar todos filtrados'),
                        ),
                        TextButton.icon(
                          onPressed: filtered.isEmpty ? null : _deselectFiltered,
                          icon: const Icon(Icons.deselect_rounded, size: 20),
                          label: const Text('Desmarcar filtrados'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
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
                        '${filtered.length} sem conta neste período${_filterCtrl.text.trim().isNotEmpty ? ' (filtrado)' : ''} • $nSel selecionado(s)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade800),
                      ),
                      const SizedBox(height: 8),
                      if (filtered.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            _semConta.isEmpty
                                ? 'Nenhum lançamento sem conta no período.'
                                : 'Nenhum resultado para o filtro. Limpe a busca ou amplie o período.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        )
                      else
                        ...filtered.map((doc) {
                          final d = doc.data();
                          final income = (d['type'] ?? 'expense').toString() == 'income';
                          final checked = _checkedIds.contains(doc.id);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: Colors.grey.shade300),
                            ),
                            child: CheckboxListTile(
                              value: checked,
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _checkedIds.add(doc.id);
                                  } else {
                                    _checkedIds.remove(doc.id);
                                  }
                                });
                              },
                              title: Text(
                                _txTitle(d),
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                              ),
                              subtitle: Text(_txSubtitle(d)),
                              secondary: Text(
                                CurrencyFormats.formatBRL((d['amount'] ?? 0) as num?),
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  color: income ? const Color(0xFF166534) : const Color(0xFF991B1B),
                                ),
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                          );
                        }),
                    ],
                  ],
                ),
              ),
              SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.maybePop(context),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        side: BorderSide(color: Colors.grey.shade400),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _loadingApply || _loadingList || accounts.isEmpty ? null : _applyAssign,
                      icon: _loadingApply
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.link_rounded),
                      label: Text(_loadingApply ? 'Aplicando…' : 'Atribuir conta aos selecionados'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
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
