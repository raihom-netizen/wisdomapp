import 'package:flutter/material.dart';
import 'fast_text_field.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../constants/currency_formats.dart';
import '../models/scale_entry.dart';
import '../models/shift_location.dart';
import '../models/finance_account.dart';
import '../models/user_profile.dart';
import '../services/finance_accounts_service.dart';
import '../services/transaction_save_service.dart';
import '../theme/app_colors.dart';
import '../theme/gemini_theme.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/premium_upgrade.dart';
import '../utils/scale_closure_summary.dart';

const String _kDefaultIncomeCategory = 'Receita (Escalas)';

/// Card compacto: abre o fluxo de fechamento / lançamento de receitas por vínculo.
class ScaleMonthClosureInviteCard extends StatelessWidget {
  final String uid;
  final UserProfile profile;
  final List<ScaleEntry> entriesSource;
  final List<ShiftLocation> locations;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String periodLabel;
  final bool allowEditPeriodFromSource;

  const ScaleMonthClosureInviteCard({
    super.key,
    required this.uid,
    required this.profile,
    required this.entriesSource,
    required this.locations,
    required this.periodStart,
    required this.periodEnd,
    required this.periodLabel,
    this.allowEditPeriodFromSource = false,
  });

  @override
  Widget build(BuildContext context) {
    final ref = scaleDateOnlyLocal(periodEnd);
    final summary = computeScaleClosureSummary(
      entries: entriesSource,
      locations: locations,
      periodStart: periodStart,
      periodEnd: periodEnd,
      referenciaJaTirado: ref,
    );
    final withValue = summary.lines
        .where((l) => l.valueReal > 0.001 || l.countReal > 0)
        .length;
    final fsTitle = 15.0;
    final fsSub = 12.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          if (profile.isLicenseExpired) {
            mostrarAvisoLicencaVencida(context);
            return;
          }
          showScaleMonthClosureSheet(
            context: context,
            uid: uid,
            profile: profile,
            entriesSource: entriesSource,
            locations: locations,
            initialPeriodStart: periodStart,
            initialPeriodEnd: periodEnd,
            periodLabelHint: periodLabel,
            allowEditPeriodFromSource: allowEditPeriodFromSource,
          );
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                AppColors.primary.withValues(alpha: 0.06),
                AppColors.accent.withValues(alpha: 0.08),
              ],
            ),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.22), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppColors.deepBlue.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
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
                      borderRadius: BorderRadius.circular(14),
                      gradient:
                          const LinearGradient(colors: AppColors.logoGradient),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3)),
                      ],
                    ),
                    child: const Icon(Icons.workspace_premium_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Fechamento do período · receitas',
                      style: TextStyle(
                        fontSize: fsTitle,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: AppColors.primary, size: 28),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                periodLabel,
                style: TextStyle(
                    fontSize: fsSub,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                withValue == 0
                    ? 'Nenhum plantão com financeiro ativo e valor realizado neste intervalo. Toque para revisar outro período ou detalhes.'
                    : '${summary.totalRealizados} plantão(ões) realizado(s) no totalizador · toque para marcar vínculos e lançar receita(s) no Financeiro.',
                style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showScaleMonthClosureSheet({
  required BuildContext context,
  required String uid,
  required UserProfile profile,
  required List<ScaleEntry> entriesSource,
  required List<ShiftLocation> locations,
  required DateTime initialPeriodStart,
  required DateTime initialPeriodEnd,
  required String periodLabelHint,
  required bool allowEditPeriodFromSource,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black54,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _ScaleMonthClosureBody(
      uid: uid,
      profile: profile,
      entriesSource: entriesSource,
      locations: locations,
      initialPeriodStart: initialPeriodStart,
      initialPeriodEnd: initialPeriodEnd,
      periodLabelHint: periodLabelHint,
      allowEditPeriodFromSource: allowEditPeriodFromSource,
    ),
  );
}

class _ScaleMonthClosureBody extends StatefulWidget {
  final String uid;
  final UserProfile profile;
  final List<ScaleEntry> entriesSource;
  final List<ShiftLocation> locations;
  final DateTime initialPeriodStart;
  final DateTime initialPeriodEnd;
  final String periodLabelHint;
  final bool allowEditPeriodFromSource;

  const _ScaleMonthClosureBody({
    required this.uid,
    required this.profile,
    required this.entriesSource,
    required this.locations,
    required this.initialPeriodStart,
    required this.initialPeriodEnd,
    required this.periodLabelHint,
    required this.allowEditPeriodFromSource,
  });

  @override
  State<_ScaleMonthClosureBody> createState() => _ScaleMonthClosureBodyState();
}

class _ScaleMonthClosureBodyState extends State<_ScaleMonthClosureBody> {
  late DateTime _periodStart;
  late DateTime _periodEnd;
  final Set<String> _selected = {};
  int _step = 0;
  DateTime? _paymentDate;

  /// Por vínculo no passo 2: `paid` = valor já realizado; `pending` = valor ainda pendente.
  final Map<String, String> _lineIncomeStatus = {};
  String? _financeAccountId;
  List<FinanceAccount> _accounts = const [];
  bool _loadingAccounts = true;
  bool _saving = false;

  /// Por vínculo (Estado / Município / Particular): categoria, descrição e data editáveis no passo 2.
  final Map<String, TextEditingController> _categoryCtrlByType = {};
  final Map<String, TextEditingController> _descriptionCtrlByType = {};
  final Map<String, DateTime> _paymentDateByType = {};
  bool _syncPaymentDatesAcrossLines = true;

  String get _periodHuman {
    final a = scaleDateOnlyLocal(_periodStart);
    final b = scaleDateOnlyLocal(_periodEnd);
    return '${DateFormat('dd/MM/yyyy').format(a)} — ${DateFormat('dd/MM/yyyy').format(b)}';
  }

  List<ScaleEntry> get _entriesFiltered {
    if (!widget.allowEditPeriodFromSource) {
      return widget.entriesSource;
    }
    return widget.entriesSource
        .where(
            (e) => scaleEntryDateInRangeInclusive(e, _periodStart, _periodEnd))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _periodStart = scaleDateOnlyLocal(widget.initialPeriodStart);
    _periodEnd = scaleDateOnlyLocal(widget.initialPeriodEnd);
    _paymentDate = scaleDefaultPaymentDateAfterPeriod(_periodEnd);
    _primeSelection();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final list = await FinanceAccountsService()
        .listOnce(firestoreUserDocIdForAppShell(widget.uid));
    if (!mounted) return;
    setState(() {
      _accounts = list;
      _loadingAccounts = false;
      if (_financeAccountId == null || _financeAccountId!.isEmpty) {
        if (list.isNotEmpty) _financeAccountId = list.first.id;
      }
    });
  }

  void _primeSelection() {
    final ref = scaleDateOnlyLocal(_periodEnd);
    final s = computeScaleClosureSummary(
      entries: _entriesFiltered,
      locations: widget.locations,
      periodStart: _periodStart,
      periodEnd: _periodEnd,
      referenciaJaTirado: ref,
    );
    _selected.clear();
    for (final line in s.lines) {
      if (line.valueReal > 0.001) _selected.add(line.typeKey);
    }
  }

  void _syncAfterPeriodChange() {
    _paymentDate = scaleDefaultPaymentDateAfterPeriod(_periodEnd);
    _primeSelection();
  }

  @override
  void dispose() {
    _disposeLineEditors();
    super.dispose();
  }

  void _disposeLineEditors() {
    for (final c in _categoryCtrlByType.values) {
      c.dispose();
    }
    for (final c in _descriptionCtrlByType.values) {
      c.dispose();
    }
    _categoryCtrlByType.clear();
    _descriptionCtrlByType.clear();
    _paymentDateByType.clear();
    _lineIncomeStatus.clear();
  }

  void _prepareStep1Editors(ScaleClosureSummary summary) {
    _disposeLineEditors();
    final base = _periodHuman;
    final lines = summary.lines
        .where((l) => _selected.contains(l.typeKey) && l.isSelectableForClosure)
        .toList();
    final dPay = _paymentDate ?? DateTime.now();
    for (final l in lines) {
      _categoryCtrlByType[l.typeKey] =
          TextEditingController(text: _kDefaultIncomeCategory);
      final defSt = l.valueReal > 0.001 ? 'paid' : 'pending';
      _lineIncomeStatus[l.typeKey] = defSt;
      final desc = defSt == 'paid'
          ? l.historyDescription(base)
          : l.historyDescriptionPending(base);
      _descriptionCtrlByType[l.typeKey] = TextEditingController(text: desc);
      _paymentDateByType[l.typeKey] = dPay;
    }
  }

  Future<void> _pickStart() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _periodStart,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() {
        _periodStart = scaleDateOnlyLocal(d);
        if (_periodEnd.isBefore(_periodStart)) {
          _periodEnd = _periodStart;
        }
        _syncAfterPeriodChange();
      });
    }
  }

  Future<void> _pickEnd() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _periodEnd,
      firstDate: _periodStart,
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() {
        _periodEnd = scaleDateOnlyLocal(d);
        _syncAfterPeriodChange();
      });
    }
  }

  Future<void> _pickPaymentDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _paymentDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() {
        _paymentDate = scaleDateOnlyLocal(d);
        if (_syncPaymentDatesAcrossLines) {
          for (final k in _paymentDateByType.keys.toList()) {
            _paymentDateByType[k] = _paymentDate!;
          }
        }
      });
    }
  }

  Future<void> _pickPaymentDateForLine(String typeKey) async {
    final cur = _paymentDateByType[typeKey] ?? _paymentDate ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: cur,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() {
        _syncPaymentDatesAcrossLines = false;
        _paymentDateByType[typeKey] = scaleDateOnlyLocal(d);
      });
    }
  }

  Future<void> _generate() async {
    if (widget.profile.isLicenseExpired) {
      mostrarAvisoLicencaVencida(context);
      return;
    }
    final ref = scaleDateOnlyLocal(_periodEnd);
    final summary = computeScaleClosureSummary(
      entries: _entriesFiltered,
      locations: widget.locations,
      periodStart: _periodStart,
      periodEnd: _periodEnd,
      referenciaJaTirado: ref,
    );
    final lines = summary.lines
        .where((l) => _selected.contains(l.typeKey) && l.isSelectableForClosure)
        .toList();
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Selecione ao menos uma linha com valor realizado ou pendente.')),
      );
      return;
    }
    for (final line in lines) {
      final desc = _descriptionCtrlByType[line.typeKey]?.text.trim() ?? '';
      if (desc.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Preencha a descrição para ${line.label}.')),
        );
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final fsId = firestoreUserDocIdForAppShell(widget.uid);
      final groupId = Uuid().v4();
      var skipped = 0;
      final dedups = <String>[];
      final payloads = <Map<String, dynamic>>[];

      for (final line in lines) {
        final st = _lineIncomeStatus[line.typeKey] ?? 'pending';
        final amount = st == 'paid' ? line.valueReal : line.valuePend;
        if (amount <= 0.001) {
          skipped++;
          continue;
        }
        final ledger = st == 'paid' ? 'realized' : 'pending';
        final dedup = scaleClosureDedupKey(
          userFirestoreDocId: fsId,
          periodStart: _periodStart,
          periodEnd: _periodEnd,
          employerTypeKey: line.typeKey,
          ledger: ledger,
        );
        if (!mounted) return;
        final catCtrl = _categoryCtrlByType[line.typeKey];
        final descCtrl = _descriptionCtrlByType[line.typeKey];
        if (catCtrl == null || descCtrl == null) continue;
        final cat = catCtrl.text.trim().isEmpty
            ? _kDefaultIncomeCategory
            : catCtrl.text.trim();
        final desc = descCtrl.text.trim();
        final lineDate =
            _paymentDateByType[line.typeKey] ?? _paymentDate ?? DateTime.now();
        dedups.add(dedup);
        payloads.add({
          'type': 'income',
          'amount': amount,
          'category': cat,
          'description': desc,
          'status': st,
          'date': lineDate,
          'recurrence': 'none',
          'installments': 1,
          if (_financeAccountId != null && _financeAccountId!.trim().isNotEmpty)
            'financeAccountId': _financeAccountId!.trim(),
          'source': 'scale_closure',
          'scaleClosureDedupKey': dedup,
          'scaleClosureGroupId': groupId,
          'scaleClosureEmployerType': line.typeKey,
        });
      }

      final existing =
          await TransactionSaveService.existingScaleClosureDedupKeys(
              widget.uid, dedups);
      final toSave = <Map<String, dynamic>>[];
      for (var i = 0; i < dedups.length; i++) {
        if (existing.contains(dedups[i])) {
          skipped++;
          continue;
        }
        toSave.add(payloads[i]);
      }

      final saved = await TransactionSaveService.saveScaleClosureIncomeBatch(
        uid: widget.uid,
        items: toSave,
      );
      if (mounted) {
        final buf = StringBuffer();
        if (saved == 1) {
          buf.write(
              '1 receita registada no Financeiro (fechamento de Escalas).');
        } else if (saved > 1) {
          buf.write(
              '$saved receitas registadas no Financeiro (fechamento de Escalas).');
        }
        if (skipped > 0) {
          if (buf.isNotEmpty) buf.write(' ');
          buf.write(
            skipped == 1
                ? '1 linha ignorada — já existe receita para o mesmo vínculo, período e tipo (realizado ou pendente).'
                : '$skipped linhas ignoradas — já existiam receitas para o mesmo vínculo, período e tipo.',
          );
        }
        if (saved == 0 && skipped > 0) {
          buf.clear();
          buf.write(
            skipped == 1
                ? 'Nada registado: já existe fechamento para este vínculo, período e tipo. Apague ou ajuste no Financeiro, ou altere o período / situação da linha.'
                : 'Nada registado: todas as combinações selecionadas já tinham fechamento.',
          );
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(buf.toString())));
        if (saved > 0) HapticFeedback.lightImpact();
      }
      if (mounted && saved > 0) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final ref = scaleDateOnlyLocal(_periodEnd);
    final summary = computeScaleClosureSummary(
      entries: _entriesFiltered,
      locations: widget.locations,
      periodStart: _periodStart,
      periodEnd: _periodEnd,
      referenciaJaTirado: ref,
    );

    final sheetH = MediaQuery.sizeOf(context).height * 0.9;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: sheetH,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _step == 0
                          ? 'Fechamento & receitas'
                          : 'Confirmar lançamentos',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: _step == 0
                    ? _buildStep0(context, summary)
                    : _buildStep1(context, summary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildStep0(BuildContext context, ScaleClosureSummary summary) {
    final congrats = summary.allDoneNoPending
        ? 'Parabéns, profissional! Você concluiu todos os plantões com financeiro ativo neste período — ótimo momento para registrar suas receitas.'
        : 'Resumo do período para lançar receitas no Financeiro. Ainda há plantões pendentes neste intervalo; os valores abaixo são só dos já realizados.';

    return [
      Text(congrats,
          style: TextStyle(
              fontSize: 13, height: 1.4, color: Colors.grey.shade800)),
      const SizedBox(height: 14),
      if (!widget.allowEditPeriodFromSource)
        Text(
          'Período (filtro atual): ${widget.periodLabelHint}',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: GeminiTheme.textMuted),
        )
      else ...[
        Text('Período do fechamento',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade800)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickStart,
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(DateFormat('dd/MM/yyyy').format(_periodStart)),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('até', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickEnd,
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(DateFormat('dd/MM/yyyy').format(_periodEnd)),
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 6),
      Text(_periodHuman,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      const SizedBox(height: 16),
      Text(
        'Marque uma ou mais linhas (várias ao mesmo tempo). Cada vínculo gera um lançamento separado no passo seguinte.',
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            height: 1.35),
      ),
      const SizedBox(height: 10),
      ...summary.lines.map((line) => _lineCard(line)),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: _selected.isEmpty
            ? null
            : () {
                final ref = scaleDateOnlyLocal(_periodEnd);
                final summary = computeScaleClosureSummary(
                  entries: _entriesFiltered,
                  locations: widget.locations,
                  periodStart: _periodStart,
                  periodEnd: _periodEnd,
                  referenciaJaTirado: ref,
                );
                _prepareStep1Editors(summary);
                setState(() => _step = 1);
              },
        icon: const Icon(Icons.arrow_forward_rounded),
        label: Text(
          _selected.length <= 1
              ? 'Lançar receita'
              : 'Lançar ${_selected.length} receitas',
        ),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: AppColors.deepBlue,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: AppColors.deepBlue.withValues(alpha: 0.45),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    ];
  }

  Widget _lineCard(ScaleClosureLine line) {
    final sel = _selected.contains(line.typeKey);
    final enabled = line.isSelectableForClosure;
    final color = line.typeKey == 'state'
        ? AppColors.deepBlue
        : line.typeKey == 'municipality'
            ? AppColors.accent
            : const Color(0xFF7C3AED);
    final hd = scaleFormatHours(line.hoursDayReal);
    final hn = scaleFormatHours(line.hoursNightReal);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: !enabled
              ? null
              : () {
                  setState(() {
                    if (sel) {
                      _selected.remove(line.typeKey);
                    } else {
                      _selected.add(line.typeKey);
                    }
                  });
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: sel
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color.withValues(alpha: 0.14),
                        Colors.white,
                        color.withValues(alpha: 0.06),
                      ],
                    )
                  : null,
              color: sel ? null : Colors.white,
              border: Border.all(
                color: enabled
                    ? (sel
                        ? color
                        : AppColors.logoSilver.withValues(alpha: 0.55))
                    : Colors.grey.shade300,
                width: sel ? 2.2 : 1.1,
              ),
              boxShadow: [
                BoxShadow(
                  color: (enabled ? color : Colors.black)
                      .withValues(alpha: sel ? 0.14 : 0.05),
                  blurRadius: sel ? 16 : 8,
                  offset: Offset(0, sel ? 6 : 3),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    !enabled
                        ? Icons.remove_circle_outline_rounded
                        : (sel
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded),
                    color: !enabled
                        ? Colors.grey.shade400
                        : (sel ? color : Colors.grey.shade500),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.label,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: color,
                            letterSpacing: -0.2),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${line.countReal} serviço(s) realizado(s) · ${hd}h diurnas · ${hn}h noturnas',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            height: 1.25,
                            fontWeight: FontWeight.w600),
                      ),
                      if (line.countPend > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${line.countPend} pendente(s) · ${CurrencyFormats.formatBRL(line.valuePend)}',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.financePendente,
                              fontWeight: FontWeight.w800),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Realizado: ${CurrencyFormats.formatBRL(line.valueReal)}',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: AppColors.deepBlue),
                      ),
                      if (line.valuePend > 0.001) ...[
                        const SizedBox(height: 2),
                        Text(
                          'A receber (pendente): ${CurrencyFormats.formatBRL(line.valuePend)}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textMuted),
                        ),
                      ],
                      if (!enabled)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Sem valor neste período para lançar.',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                                fontStyle: FontStyle.italic),
                          ),
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
  }

  Widget _buildLineEditorCard(ScaleClosureLine l) {
    final color = l.typeKey == 'state'
        ? AppColors.deepBlue
        : l.typeKey == 'municipality'
            ? AppColors.accent
            : const Color(0xFF7C3AED);
    final catC = _categoryCtrlByType[l.typeKey];
    final descC = _descriptionCtrlByType[l.typeKey];
    if (catC == null || descC == null) return const SizedBox.shrink();
    final lineDate = _paymentDateByType[l.typeKey] ?? _paymentDate;
    final fsId = firestoreUserDocIdForAppShell(widget.uid);
    final st = _lineIncomeStatus[l.typeKey] ?? 'pending';
    final ledger = st == 'paid' ? 'realized' : 'pending';
    final dedupPreview = scaleClosureDedupKey(
      userFirestoreDocId: fsId,
      periodStart: _periodStart,
      periodEnd: _periodEnd,
      employerTypeKey: l.typeKey,
      ledger: ledger,
    );
    final amountPreview = st == 'paid' ? l.valueReal : l.valuePend;
    final baseHuman = _periodHuman;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            color.withValues(alpha: 0.07),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                        colors: [color, color.withValues(alpha: 0.75)]),
                    boxShadow: [
                      BoxShadow(
                          color: color.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3)),
                    ],
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${l.label} · banco de horas',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: color,
                            letterSpacing: -0.2),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        CurrencyFormats.formatBRL(amountPreview),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: st == 'paid'
                              ? AppColors.deepBlue
                              : AppColors.financePendente,
                        ),
                      ),
                      Text(
                        st == 'paid'
                            ? 'Valor já realizado no período'
                            : 'Valor ainda pendente (a receber)',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Situação deste lançamento',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: [
                ButtonSegment<String>(
                  value: 'paid',
                  enabled: l.valueReal > 0.001,
                  label: const Text('Recebido'),
                  icon:
                      const Icon(Icons.check_circle_outline_rounded, size: 18),
                ),
                ButtonSegment<String>(
                  value: 'pending',
                  enabled: l.valuePend > 0.001,
                  label: const Text('Pendente'),
                  icon: const Icon(Icons.schedule_rounded, size: 18),
                ),
              ],
              emptySelectionAllowed: false,
              multiSelectionEnabled: false,
              showSelectedIcon: false,
              selected: {st},
              onSelectionChanged: (s) {
                if (s.isEmpty) return;
                setState(() {
                  final next = s.first;
                  _lineIncomeStatus[l.typeKey] = next;
                  final nextDesc = next == 'paid'
                      ? l.historyDescription(baseHuman)
                      : l.historyDescriptionPending(baseHuman);
                  descC.text = nextDesc;
                });
              },
            ),
            const SizedBox(height: 10),
            Text(
              'Anti-duplicação: $dedupPreview',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 10,
                  color: AppColors.textMuted,
                  height: 1.25,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            FastTextField(
              controller: catC,
              decoration: InputDecoration(
                labelText: 'Categoria',
                filled: true,
                fillColor: Colors.white,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: AppColors.logoSilver.withValues(alpha: 0.55)),
                ),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            FastTextField(
              controller: descC,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Descrição / histórico',
                alignLabelWithHint: true,
                filled: true,
                fillColor: Colors.white,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: AppColors.logoSilver.withValues(alpha: 0.55)),
                ),
                isDense: true,
              ),
            ),
            if (!_syncPaymentDatesAcrossLines) ...[
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('Data (${l.label})',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                subtitle: Text(
                  lineDate != null
                      ? DateFormat('dd/MM/yyyy').format(lineDate)
                      : '—',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
                trailing: IconButton.filledTonal(
                  onPressed: () => _pickPaymentDateForLine(l.typeKey),
                  icon: const Icon(Icons.calendar_month_rounded, size: 20),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildStep1(BuildContext context, ScaleClosureSummary summary) {
    final lines = summary.lines
        .where((l) => _selected.contains(l.typeKey) && l.isSelectableForClosure)
        .toList();
    final total = lines.fold<double>(0, (s, l) {
      final st = _lineIncomeStatus[l.typeKey] ?? 'pending';
      return s + (st == 'paid' ? l.valueReal : l.valuePend);
    });

    return [
      TextButton.icon(
        onPressed: () {
          _disposeLineEditors();
          setState(() => _step = 0);
        },
        icon: const Icon(Icons.arrow_back_rounded),
        label: const Text('Voltar'),
      ),
      Text(
        'Cada vínculo vira um lançamento separado. Em cada cartão escolha Recebido (valor já realizado) ou Pendente (valor a receber). '
        'A anti-duplicação distingue realizado e pendente para o mesmo período.',
        style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            height: 1.4,
            fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ActionChip(
            avatar: Icon(Icons.done_all_rounded,
                size: 18, color: AppColors.deepBlue),
            label: const Text('Recebido em todas'),
            onPressed: lines.every((l) => l.valueReal <= 0.001)
                ? null
                : () {
                    setState(() {
                      for (final l in lines) {
                        if (l.valueReal > 0.001) {
                          _lineIncomeStatus[l.typeKey] = 'paid';
                          final d = _descriptionCtrlByType[l.typeKey];
                          if (d != null) {
                            d.text = l.historyDescription(_periodHuman);
                          }
                        }
                      }
                    });
                  },
          ),
          ActionChip(
            avatar: Icon(Icons.schedule_rounded,
                size: 18, color: AppColors.financePendente),
            label: const Text('Pendente em todas'),
            onPressed: lines.every((l) => l.valuePend <= 0.001)
                ? null
                : () {
                    setState(() {
                      for (final l in lines) {
                        if (l.valuePend > 0.001) {
                          _lineIncomeStatus[l.typeKey] = 'pending';
                          final d = _descriptionCtrlByType[l.typeKey];
                          if (d != null) {
                            d.text = l.historyDescriptionPending(_periodHuman);
                          }
                        }
                      }
                    });
                  },
          ),
        ],
      ),
      const SizedBox(height: 10),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Mesma data em todas as linhas'),
        subtitle: Text(
          'Desligue para escolher uma data por vínculo.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        value: _syncPaymentDatesAcrossLines,
        onChanged: (v) {
          setState(() {
            _syncPaymentDatesAcrossLines = v;
            if (v && _paymentDate != null) {
              for (final k in _paymentDateByType.keys.toList()) {
                _paymentDateByType[k] = _paymentDate!;
              }
            }
          });
        },
      ),
      if (_syncPaymentDatesAcrossLines) ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Data do lançamento (todas as linhas)',
              style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(
            _paymentDate != null
                ? DateFormat('dd/MM/yyyy').format(_paymentDate!)
                : '—',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          trailing: IconButton.filledTonal(
            onPressed: _pickPaymentDate,
            icon: const Icon(Icons.calendar_month_rounded),
          ),
        ),
      ] else
        Text(
          'Datas por vínculo: use o botão no cartão de cada linha.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
      const SizedBox(height: 16),
      Text('Conta (depósito / destino)',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade800)),
      const SizedBox(height: 6),
      if (_loadingAccounts)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_accounts.isEmpty)
        Text(
          'Cadastre uma conta em Financeiro para vincular o depósito.',
          style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
        )
      else
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Conta',
            border: OutlineInputBorder(),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _financeAccountId != null &&
                      _accounts.any((a) => a.id == _financeAccountId)
                  ? _financeAccountId
                  : _accounts.first.id,
              items: [
                for (final a in _accounts)
                  DropdownMenuItem<String>(
                    value: a.id,
                    child: Text(a.displayName),
                  ),
              ],
              onChanged: (v) => setState(() => _financeAccountId = v),
            ),
          ),
        ),
      const SizedBox(height: 8),
      Text('Categoria e descrição por vínculo',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      ...lines.map((l) => _buildLineEditorCard(l)),
      const Divider(height: 28),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              AppColors.deepBlue.withValues(alpha: 0.08),
              AppColors.accent.withValues(alpha: 0.06)
            ],
          ),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Valor total (linhas)',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                Text(
                  '${lines.length} lançamento(s)',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
            Text(
              CurrencyFormats.formatBRL(total),
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.deepBlue),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed:
            _saving || _loadingAccounts || _accounts.isEmpty ? null : _generate,
        icon: _saving
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.savings_rounded),
        label: Text(_saving ? 'Salvando…' : 'Gerar lançamento(s) de receita'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: AppColors.deepBlue,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: AppColors.deepBlue.withValues(alpha: 0.45),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    ];
  }
}
