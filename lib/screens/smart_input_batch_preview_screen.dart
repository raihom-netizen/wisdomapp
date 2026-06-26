import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide showDatePicker;
import '../widgets/fast_text_field.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../constants/currency_formats.dart';
import '../constants/finance_category_visuals.dart';
import '../models/finance_account.dart';
import '../models/smart_input_pop_result.dart';
import '../models/user_profile.dart';
import '../services/bank_notification_parser.dart';
import '../services/finance_service.dart';
import '../services/functions_service.dart';
import '../services/smart_category_hints_service.dart';
import '../services/user_categories_service.dart';
import '../theme/app_colors.dart';
import '../utils/date_picker_a11y.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/premium_upgrade.dart';
import '../widgets/brl_amount_text_field.dart';
import '../widgets/finance_bank_brand_thumb.dart';

enum SmartInputBatchGroupMode {
  lista,
  porData,
  porCategoria,
}

/// Um documento por linha ou fundir mesma categoria + dia + conta + estado.
enum SmartBatchPersistMode {
  umPorLinha,
  agruparIguais,
}

/// Pré-visualização em massa do lançamento expresso (vários SMS / linhas / PDF).
class SmartInputBatchPreviewScreen extends StatefulWidget {
  final String uid;
  final UserProfile profile;
  final List<BankNotificationParseResult> initialParsed;
  final List<String> incomeCategories;
  final List<String> expenseCategories;
  final List<FinanceAccount> accounts;
  final String? defaultFinanceAccountId;
  /// Ex.: preset `bradesco` inferido do nome do PDF — só informativo na UI.
  final String? importPresetIdHint;

  const SmartInputBatchPreviewScreen({
    super.key,
    required this.uid,
    required this.profile,
    required this.initialParsed,
    required this.incomeCategories,
    required this.expenseCategories,
    required this.accounts,
    required this.defaultFinanceAccountId,
    this.importPresetIdHint,
  });

  @override
  State<SmartInputBatchPreviewScreen> createState() => _SmartInputBatchPreviewScreenState();
}

class _BatchRow {
  _BatchRow({
    required this.id,
    required this.descCtrl,
    required this.amountCtrl,
    required this.date,
    required this.isIncome,
    required this.settlement,
    required this.category,
    required this.financeAccountId,
    required this.rawSnippet,
    this.suggestedPresetId,
    this.accountMatchesSuggestedPreset = false,
  }) : selected = true;

  final String id;
  bool selected;
  final TextEditingController descCtrl;
  final TextEditingController amountCtrl;
  DateTime date;
  bool isIncome;
  /// `paid` ou `pending`
  String settlement;
  String category;
  String? financeAccountId;
  final String rawSnippet;
  final String? suggestedPresetId;
  bool accountMatchesSuggestedPreset;
  bool possibleDuplicate = false;
  /// Linha compacta na lista; detalhes (categoria, conta, segmentos) ao expandir.
  bool listUiExpanded = false;

  void dispose() {
    descCtrl.dispose();
    amountCtrl.dispose();
  }

  List<String> catsForType(List<String> inc, List<String> exp) => isIncome ? inc : exp;
}

class _PersistJob {
  _PersistJob({
    required this.documentId,
    required this.type,
    required this.amount,
    required this.category,
    required this.description,
    required this.date,
    required this.financeAccountId,
    required this.status,
    required this.rawSnippet,
  });

  final String documentId;
  final String type;
  final double amount;
  final String category;
  final String description;
  final DateTime date;
  final String financeAccountId;
  final String status;
  final String rawSnippet;
}

class _SmartInputBatchPreviewScreenState extends State<SmartInputBatchPreviewScreen> {
  static const _uuid = Uuid();

  final List<_BatchRow> _rows = [];
  late List<String> _incomeCats;
  late List<String> _expenseCats;
  bool _loading = true;
  bool _saving = false;
  SmartInputBatchGroupMode _groupMode = SmartInputBatchGroupMode.porData;
  SmartBatchPersistMode _persistMode = SmartBatchPersistMode.umPorLinha;
  bool _onlyUncategorized = false;

  String get _fsUid => firestoreUserDocIdForAppShell(widget.uid);

  bool _isInstallmentOrFinancingText(String text) {
    final t = text.toLowerCase();
    return RegExp(
      r'\b(parcelad[oa]?|parcela(?:s)?|financiament[oa]|emprestim[oa]s?|consignad[oa]|credi[aá]rio|carn[eê])\b',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(t);
  }

  bool _shouldDefaultPendingFromParsed(BankNotificationParseResult p) {
    final merged = '${p.descricao ?? ''} ${p.rawSnippet}'.trim();
    if (merged.isEmpty) return false;
    return _isInstallmentOrFinancingText(merged);
  }

  bool _accountMatchesPreset(String? accountId, String? presetId) {
    if (accountId == null || accountId.isEmpty || presetId == null || presetId.isEmpty) return false;
    for (final a in widget.accounts) {
      if (a.id == accountId) return a.presetId == presetId;
    }
    return false;
  }

  String? _pickAccountId(BankNotificationParseResult p, bool isIncome) {
    if (widget.accounts.isEmpty) return isIncome ? null : '';
    final sid = p.suggestedPresetId;
    if (sid != null && sid.isNotEmpty) {
      final match = widget.accounts.where((a) => a.presetId == sid).toList();
      if (match.isNotEmpty) return match.first.id;
    }
    final def = widget.defaultFinanceAccountId;
    if (def != null && def.isNotEmpty && widget.accounts.any((a) => a.id == def)) {
      return def;
    }
    if (isIncome) return null;
    return widget.accounts.first.id;
  }

  @override
  void initState() {
    super.initState();
    _incomeCats = List<String>.from(widget.incomeCategories);
    _expenseCats = List<String>.from(widget.expenseCategories);
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    for (final r in widget.initialParsed) {
      if (!r.hasMinimumForConfirmation) continue;
      final isInc = r.type == 'income';
      final allowed = isInc ? _incomeCats : _expenseCats;
      final cat = await _resolveInitialCategory(
        descricao: (r.descricao ?? '').trim(),
        allowed: allowed,
      );
      final aid = _pickAccountId(r, isInc);
      _rows.add(
        _BatchRow(
          id: _uuid.v4(),
          descCtrl: TextEditingController(text: r.descricao ?? ''),
          amountCtrl: TextEditingController(text: CurrencyFormats.formatBRLInput(r.valor)),
          date: r.data ?? DateTime.now(),
          isIncome: isInc,
          settlement: _shouldDefaultPendingFromParsed(r) ? 'pending' : 'paid',
          category: cat,
          financeAccountId: aid,
          rawSnippet: r.rawSnippet,
          suggestedPresetId: r.suggestedPresetId,
          accountMatchesSuggestedPreset: _accountMatchesPreset(aid, r.suggestedPresetId),
        ),
      );
    }
    _recomputeDuplicates();
    if (mounted) setState(() => _loading = false);
  }

  Future<String> _resolveInitialCategory({
    required String descricao,
    required List<String> allowed,
  }) async {
    if (allowed.isEmpty || descricao.isEmpty) return '';
    final direct = SmartCategoryHintsService.matchAllowedCategoryInDescription(descricao, allowed);
    if (direct != null && direct.trim().isNotEmpty) return direct.trim();
    final hinted = await SmartCategoryHintsService.suggestCategory(widget.uid, descricao, allowed);
    if (hinted != null && hinted.trim().isNotEmpty) return hinted.trim();
    return '';
  }

  void _recomputeDuplicates() {
    final counts = <String, int>{};
    for (final r in _rows) {
      final v = CurrencyFormats.parseBRLInput(r.amountCtrl.text);
      final fp = BankNotificationParser.duplicateFingerprint(
        BankNotificationParseResult(
          valor: v,
          data: r.date,
          descricao: r.descCtrl.text.trim(),
          type: r.isIncome ? 'income' : 'expense',
          suggestedPresetId: r.suggestedPresetId,
          rawSnippet: r.rawSnippet,
        ),
      );
      counts[fp] = (counts[fp] ?? 0) + 1;
    }
    for (final r in _rows) {
      final v = CurrencyFormats.parseBRLInput(r.amountCtrl.text);
      final fp = BankNotificationParser.duplicateFingerprint(
        BankNotificationParseResult(
          valor: v,
          data: r.date,
          descricao: r.descCtrl.text.trim(),
          type: r.isIncome ? 'income' : 'expense',
          suggestedPresetId: r.suggestedPresetId,
          rawSnippet: r.rawSnippet,
        ),
      );
      r.possibleDuplicate = (counts[fp] ?? 0) > 1;
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _leaveScreen([Object? result]) {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop(result);
    }
  }

  void _removeRow(_BatchRow row) {
    setState(() {
      _rows.remove(row);
      row.dispose();
    });
  }

  double _sumListed() {
    var s = 0.0;
    for (final r in _rows) {
      final v = CurrencyFormats.parseBRLInput(r.amountCtrl.text) ?? 0;
      s += v;
    }
    return s;
  }

  double _sumSelected() {
    var s = 0.0;
    for (final r in _rows) {
      if (!r.selected) continue;
      final v = CurrencyFormats.parseBRLInput(r.amountCtrl.text) ?? 0;
      s += v;
    }
    return s;
  }

  int get _selectedCount => _rows.where((e) => e.selected).length;

  int _previewDocumentCount() {
    final sel = _rows.where((r) => r.selected).toList();
    if (sel.isEmpty) return 0;
    if (_persistMode == SmartBatchPersistMode.umPorLinha) return sel.length;
    return _buildPersistJobs(sel).length;
  }

  ({double expense, double income, double pendingSelected}) _breakdownSelected() {
    var expense = 0.0;
    var income = 0.0;
    var pending = 0.0;
    for (final r in _rows.where((e) => e.selected)) {
      final v = CurrencyFormats.parseBRLInput(r.amountCtrl.text) ?? 0;
      if (r.isIncome) {
        income += v;
      } else {
        expense += v;
      }
      if (r.settlement == 'pending') pending += v;
    }
    return (expense: expense, income: income, pendingSelected: pending);
  }

  List<int> _orderedIndices() {
    final idx = List.generate(_rows.length, (i) => i);
    idx.sort((a, b) {
      final ra = _rows[a];
      final rb = _rows[b];
      final raUncat = ra.category.trim().isEmpty;
      final rbUncat = rb.category.trim().isEmpty;
      final raSusp = _isSuspicious(ra);
      final rbSusp = _isSuspicious(rb);
      switch (_groupMode) {
        case SmartInputBatchGroupMode.lista:
          if (raUncat != rbUncat) return raUncat ? -1 : 1;
          if (raSusp != rbSusp) return raSusp ? -1 : 1;
          return a.compareTo(b);
        case SmartInputBatchGroupMode.porData:
          if (raUncat != rbUncat) return raUncat ? -1 : 1;
          if (raSusp != rbSusp) return raSusp ? -1 : 1;
          final c = ra.date.compareTo(rb.date);
          if (c != 0) return c;
          return ra.category.compareTo(rb.category);
        case SmartInputBatchGroupMode.porCategoria:
          if (raUncat != rbUncat) return raUncat ? -1 : 1;
          if (raSusp != rbSusp) return raSusp ? -1 : 1;
          final c2 = ra.category.compareTo(rb.category);
          if (c2 != 0) return c2;
          return ra.date.compareTo(rb.date);
      }
    });
    return idx;
  }

  List<int> _visibleOrderedIndices() {
    final ordered = _orderedIndices();
    if (!_onlyUncategorized) return ordered;
    return ordered.where((i) => _rows[i].category.trim().isEmpty).toList();
  }

  Future<void> _pickRowDate(_BatchRow row) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: row.date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        row.date = picked;
        _recomputeDuplicates();
      });
    }
  }

  Future<void> _addCategory(_BatchRow row) async {
    final isIncome = row.isIncome;
    final c = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Nova categoria'),
          content: FastTextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nome'),
            onSubmitted: (_) {
              final t = ctrl.text.trim();
              if (t.isNotEmpty) Navigator.of(ctx).pop(t);
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final t = ctrl.text.trim();
                if (t.isNotEmpty) Navigator.of(ctx).pop(t);
              },
              child: const Text('Criar'),
            ),
          ],
        );
      },
    );
    if (c == null || !mounted || c.isEmpty) return;
    try {
      await UserCategoriesService().addCustom(widget.uid, isIncome, c);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível guardar a categoria.'), backgroundColor: Color(0xFFB00020)),
        );
      }
      return;
    }
    setState(() {
      if (isIncome) {
        if (!_incomeCats.contains(c)) _incomeCats = [..._incomeCats, c]..sort(UserCategoriesService.compareNamesPt);
      } else {
        if (!_expenseCats.contains(c)) _expenseCats = [..._expenseCats, c]..sort(UserCategoriesService.compareNamesPt);
      }
      row.category = c;
    });
  }

  String _bucketKey(_BatchRow row) {
    final d = '${row.date.year}-${row.date.month}-${row.date.day}';
    return '${row.isIncome}|${row.category.trim()}|$d|${row.financeAccountId ?? ''}|${row.settlement}';
  }

  _PersistJob _jobFromRow(_BatchRow row, String docId) {
    final amount = CurrencyFormats.parseBRLInput(row.amountCtrl.text)!;
    return _PersistJob(
      documentId: docId,
      type: row.isIncome ? 'income' : 'expense',
      amount: amount,
      category: row.category.trim(),
      description: row.descCtrl.text.trim(),
      date: row.date,
      financeAccountId: (row.financeAccountId ?? '').trim(),
      status: row.settlement == 'pending' ? 'pending' : 'paid',
      rawSnippet: row.rawSnippet,
    );
  }

  List<_PersistJob> _buildPersistJobs(List<_BatchRow> selected) {
    if (_persistMode == SmartBatchPersistMode.umPorLinha) {
      return [for (final row in selected) _jobFromRow(row, _uuid.v4())];
    }
    final map = <String, List<_BatchRow>>{};
    for (final row in selected) {
      map.putIfAbsent(_bucketKey(row), () => []).add(row);
    }
    final jobs = <_PersistJob>[];
    for (final list in map.values) {
      final first = list.first;
      var sum = 0.0;
      for (final r in list) {
        sum += CurrencyFormats.parseBRLInput(r.amountCtrl.text) ?? 0;
      }
      final parts = list.map((r) => r.descCtrl.text.trim()).where((s) => s.isNotEmpty).toList();
      var desc = parts.join(' | ');
      if (desc.length > 450) desc = '${desc.substring(0, 447)}…';
      var raw = list.map((r) => r.rawSnippet).where((s) => s.isNotEmpty).join('\n');
      if (raw.length > 500) raw = raw.substring(0, 500);
      jobs.add(
        _PersistJob(
          documentId: _uuid.v4(),
          type: first.isIncome ? 'income' : 'expense',
          amount: sum,
          category: first.category.trim(),
          description: desc.isEmpty ? 'Agrupado (${list.length} itens)' : desc,
          date: first.date,
          financeAccountId: (first.financeAccountId ?? '').trim(),
          status: first.settlement == 'pending' ? 'pending' : 'paid',
          rawSnippet: raw,
        ),
      );
    }
    return jobs;
  }

  Future<void> _offerBatchReceipt(List<String> txIds) async {
    if (!widget.profile.temAcessoPremium || txIds.isEmpty) return;
    final go = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Comprovante para os ${txIds.length} lançamentos?', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('O mesmo ficheiro será associado a cada lançamento (opcional).', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.attach_file_rounded),
                label: const Text('Escolher ficheiro'),
              ),
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Agora não')),
            ],
          ),
        ),
      ),
    );
    if (go != true || !mounted) return;
    const maxBytes = 5 * 1024 * 1024;
    final pick = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'], withData: true);
    if (pick == null || pick.files.isEmpty) return;
    final f = pick.files.first;
    final bytes = f.bytes;
    if (bytes == null || bytes.isEmpty) return;
    if (bytes.lengthInBytes > maxBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ficheiro demasiado grande (máx. 5 MB).')));
      }
      return;
    }
    final ext = (f.extension ?? '').toLowerCase();
    final mime = ext == 'pdf' ? 'application/pdf' : (ext == 'png' ? 'image/png' : 'image/jpeg');
    final fn = FunctionsService();
    final basePath = 'users/$_fsUid/transactions';
    var okCount = 0;
    for (final id in txIds) {
      try {
        await fn.uploadReceiptToStorage(txPath: '$basePath/$id', filename: f.name, bytes: bytes, mimeType: mime);
        okCount++;
      } catch (_) {}
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(okCount == txIds.length ? 'Comprovante associado a todos.' : 'Comprovante enviado para $okCount de ${txIds.length}.')),
      );
    }
  }

  Future<void> _saveSelected() async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final selected = _rows.where((r) => r.selected).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marque pelo menos um lançamento.')));
      return;
    }

    for (var i = 0; i < selected.length; i++) {
      final row = selected[i];
      final amount = CurrencyFormats.parseBRLInput(row.amountCtrl.text);
      final desc = row.descCtrl.text.trim();
      if (amount == null || amount <= 0 || desc.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Linha ${i + 1}: valor ou descrição inválidos.'), backgroundColor: const Color(0xFFB00020)),
        );
        return;
      }
      if (desc.length < 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Linha ${i + 1}: histórico deve ter pelo menos 3 caracteres.'), backgroundColor: const Color(0xFFB00020)),
        );
        return;
      }
      if (row.category.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Linha ${i + 1}: escolha uma categoria.'), backgroundColor: const Color(0xFFB00020)),
        );
        return;
      }
      final aid = (row.financeAccountId ?? '').trim();
      if (!row.isIncome && (aid.isEmpty || !widget.accounts.any((a) => a.id == aid))) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Linha ${i + 1}: selecione a conta para despesa.'), backgroundColor: const Color(0xFFB00020)),
        );
        return;
      }
    }

    final jobs = _buildPersistJobs(selected);
    final batchId = _uuid.v4();
    final createdIds = <String>[];

    setState(() => _saving = true);
    try {
      for (var i = 0; i < jobs.length; i++) {
        final j = jobs[i];
        final id = await FinanceService.saveSmartPasteTransaction(
          uid: widget.uid,
          context: context,
          type: j.type,
          amount: j.amount,
          category: j.category,
          description: j.description,
          date: j.date,
          financeAccountId: j.financeAccountId,
          rawSnippet: j.rawSnippet,
          saveLearnedMapping: true,
          status: j.status,
          showFeedback: false,
          documentId: j.documentId,
          smartPasteBatchId: batchId,
        );
        if (id == null) {
          if (mounted) setState(() => _saving = false);
          return;
        }
        createdIds.add(id);
      }
      await _offerBatchReceipt(createdIds);
      if (mounted) {
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(SmartInputPopResult(createdTransactionIds: createdIds));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static final ButtonStyle _kCompactSegmentStyle = SegmentedButton.styleFrom(
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
  );

  String _compactRowSubtitle(_BatchRow row) {
    final d = '${row.date.day.toString().padLeft(2, '0')}/${row.date.month.toString().padLeft(2, '0')}/${row.date.year}';
    final t = row.isIncome ? 'Receita' : 'Despesa';
    final st = row.settlement == 'pending' ? 'Pendente' : 'Pago';
    final c = row.category.trim().isEmpty ? 'Sem categoria' : row.category.trim();
    return '$d · $t · $st · $c · Conf. ${_confidenceScore(row)}%';
  }

  int _confidenceScore(_BatchRow row) {
    var score = 100;
    final desc = row.descCtrl.text.trim();
    final amount = CurrencyFormats.parseBRLInput(row.amountCtrl.text);
    if (row.category.trim().isEmpty) score -= 45;
    if (row.possibleDuplicate) score -= 25;
    if (desc.length < 5) score -= 18;
    if (desc.length >= 5 && desc.length < 10) score -= 8;
    if (amount == null || amount <= 0) score -= 20;
    if (!row.isIncome && ((row.financeAccountId ?? '').trim().isEmpty)) score -= 12;
    if (row.rawSnippet.trim().isEmpty) score -= 6;
    if (score < 0) return 0;
    if (score > 100) return 100;
    return score;
  }

  bool _isSuspicious(_BatchRow row) => _confidenceScore(row) < 70;

  String _confidenceLabel(_BatchRow row) {
    final s = _confidenceScore(row);
    if (s >= 85) return 'Alta';
    if (s >= 70) return 'Média';
    return 'Baixa';
  }

  Color _confidenceColor(_BatchRow row) {
    final s = _confidenceScore(row);
    if (s >= 85) return Colors.green.shade700;
    if (s >= 70) return Colors.orange.shade700;
    return Colors.red.shade700;
  }

  String _headerDateCategory(_BatchRow row) {
    final d = '${row.date.day.toString().padLeft(2, '0')}/${row.date.month.toString().padLeft(2, '0')}';
    final c = row.category.trim().isEmpty ? 'Sem categoria' : row.category.trim();
    return '$d • $c';
  }

  Widget _rowExpandedBlock(
    _BatchRow row,
    ColorScheme scheme,
    List<String> sortedCats,
    String? safeCat,
    String? accountVal,
    List<FinanceAccount> accounts,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (row.possibleDuplicate || _isSuspicious(row) || (row.accountMatchesSuggestedPreset && (row.suggestedPresetId ?? '').isNotEmpty)) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (row.possibleDuplicate)
                Chip(
                  avatar: Icon(Icons.copy_all_rounded, size: 14, color: Colors.orange.shade900),
                  label: const Text('Possível duplicado', style: TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  backgroundColor: Colors.orange.shade50,
                ),
              if (row.accountMatchesSuggestedPreset && (row.suggestedPresetId ?? '').isNotEmpty)
                Chip(
                  avatar: Icon(Icons.verified_rounded, size: 14, color: scheme.primary),
                  label: Text('Conta = sugestão (${row.suggestedPresetId})', style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
              if (_isSuspicious(row))
                Chip(
                  avatar: Icon(Icons.rule_folder_outlined, size: 14, color: _confidenceColor(row)),
                  label: Text(
                    'Revisar: confiança ${_confidenceScore(row)}% (${_confidenceLabel(row)})',
                    style: const TextStyle(fontSize: 12),
                  ),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  backgroundColor: _confidenceColor(row).withValues(alpha: 0.12),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            InkWell(
              onTap: () => _pickRowDate(row),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_rounded, size: 16, color: scheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      '${row.date.day.toString().padLeft(2, '0')}/${row.date.month.toString().padLeft(2, '0')}/${row.date.year}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            SegmentedButton<bool>(
              style: _kCompactSegmentStyle,
              segments: const [
                ButtonSegment(value: false, label: Text('Despesa'), icon: Icon(Icons.north_east_rounded, size: 13)),
                ButtonSegment(value: true, label: Text('Receita'), icon: Icon(Icons.south_west_rounded, size: 13)),
              ],
              selected: {row.isIncome},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                if (s.isEmpty) return;
                setState(() {
                  row.isIncome = s.first;
                  final list = row.catsForType(_incomeCats, _expenseCats);
                  if (!list.contains(row.category)) {
                    row.category = list.isNotEmpty ? list.first : '';
                  }
                  final synthetic = BankNotificationParseResult(
                    valor: CurrencyFormats.parseBRLInput(row.amountCtrl.text),
                    data: row.date,
                    descricao: row.descCtrl.text,
                    type: row.isIncome ? 'income' : 'expense',
                    suggestedPresetId: row.suggestedPresetId,
                    rawSnippet: row.rawSnippet,
                  );
                  row.financeAccountId = _pickAccountId(synthetic, row.isIncome);
                  row.accountMatchesSuggestedPreset = _accountMatchesPreset(row.financeAccountId, row.suggestedPresetId);
                  _recomputeDuplicates();
                });
              },
            ),
            SegmentedButton<String>(
              style: _kCompactSegmentStyle,
              segments: const [
                ButtonSegment(value: 'paid', label: Text('Pago')),
                ButtonSegment(value: 'pending', label: Text('Pendente')),
              ],
              selected: {row.settlement},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                if (s.isEmpty) return;
                setState(() {
                  row.settlement = s.first;
                  _recomputeDuplicates();
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Categoria',
                  isDense: true,
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    isDense: true,
                    value: safeCat,
                    hint: const Text('Sem categoria'),
                    selectedItemBuilder: (ctx) => [
                      for (final c in sortedCats)
                        financeCategoryDropdownMenuRow(c, isIncome: row.isIncome, isIncluirNovaOption: false),
                    ],
                    items: [
                      for (final c in sortedCats)
                        DropdownMenuItem(
                          value: c,
                          child: financeCategoryDropdownMenuRow(c, isIncome: row.isIncome, isIncluirNovaOption: false),
                        ),
                    ],
                    onChanged: sortedCats.isEmpty
                        ? null
                        : (v) {
                            if (v != null) {
                              setState(() {
                                row.category = v;
                                _recomputeDuplicates();
                              });
                            }
                          },
                  ),
                ),
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Nova categoria',
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              padding: EdgeInsets.zero,
              onPressed: () => _addCategory(row),
              icon: const Icon(Icons.add_rounded, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 6),
        InputDecorator(
          decoration: InputDecoration(
            labelText: 'Conta',
            isDense: true,
            filled: true,
            fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              isExpanded: true,
              isDense: true,
              value: accountVal,
              hint: Text(row.isIncome ? 'Sem conta' : 'Conta'),
              items: [
                if (row.isIncome)
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Saldo geral (sem conta)', style: TextStyle(fontSize: 13)),
                  ),
                ...accounts.map(
                  (a) => DropdownMenuItem<String?>(
                    value: a.id,
                    child: Row(
                      children: [
                        FinanceBankBrandThumb(preset: a.preset, size: 20),
                        const SizedBox(width: 6),
                        Expanded(child: Text(a.displayName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  ),
                ),
              ],
              onChanged: accounts.isEmpty && !row.isIncome
                  ? null
                  : (v) => setState(() {
                        row.financeAccountId = v;
                        row.accountMatchesSuggestedPreset = _accountMatchesPreset(v, row.suggestedPresetId);
                      }),
            ),
          ),
        ),
      ],
    );
  }

  Widget _rowCard(_BatchRow row, ColorScheme scheme) {
    final cats = row.catsForType(_incomeCats, _expenseCats);
    var sortedCats = List<String>.from(cats)..sort(UserCategoriesService.compareNamesPt);
    if (row.category.trim().isNotEmpty && !sortedCats.contains(row.category)) {
      sortedCats = [...sortedCats, row.category]..sort(UserCategoriesService.compareNamesPt);
    }
    final safeCat = row.category.trim().isNotEmpty && sortedCats.contains(row.category) ? row.category : (sortedCats.isNotEmpty ? sortedCats.first : null);

    final accounts = widget.accounts;
    String? accountVal = row.financeAccountId;
    if (row.isIncome) {
      if (accountVal != null && accountVal.isNotEmpty && !accounts.any((a) => a.id == accountVal)) accountVal = null;
    } else {
      if (accounts.isEmpty) {
        accountVal = null;
      } else if (accountVal == null || !accounts.any((a) => a.id == accountVal)) {
        accountVal = accounts.first.id;
      }
    }

    final uncategorized = row.category.trim().isEmpty;
    final borderColor = uncategorized
        ? Colors.orange.shade400
        : row.selected
            ? scheme.primary.withValues(alpha: 0.42)
            : scheme.outlineVariant.withValues(alpha: 0.32);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        elevation: row.listUiExpanded ? 1.5 : 0,
        shadowColor: AppColors.deepBlue.withValues(alpha: 0.14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: row.listUiExpanded ? 1.25 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      value: row.selected,
                      onChanged: (v) => setState(() => row.selected = v ?? false),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FastTextField(
                            controller: row.descCtrl,
                            maxLines: row.listUiExpanded ? 2 : 1,
                            onChanged: (_) => setState(_recomputeDuplicates),
                            autocorrect: false,
                            enableSuggestions: false,
                            smartDashesType: SmartDashesType.disabled,
                            smartQuotesType: SmartQuotesType.disabled,
                            spellCheckConfiguration: SpellCheckConfiguration.disabled(),
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: 'Histórico',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          if (!row.listUiExpanded)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                _compactRowSubtitle(row),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600, height: 1.2),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 78,
                      child: BrlAmountTextField(
                        controller: row.amountCtrl,
                        useNativeAndroidKeypad: false,
                        onChanged: (_) => setState(_recomputeDuplicates),
                        textAlign: TextAlign.right,
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: row.isIncome ? AppColors.success : AppColors.error),
                        scrollPadding: EdgeInsets.zero,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: '0,00',
                          filled: true,
                          fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.2),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remover',
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: EdgeInsets.zero,
                      onPressed: () => _removeRow(row),
                      icon: Icon(Icons.delete_outline_rounded, size: 20, color: scheme.error.withValues(alpha: 0.85)),
                    ),
                    IconButton(
                      tooltip: row.listUiExpanded ? 'Recolher' : 'Editar detalhes',
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: EdgeInsets.zero,
                      onPressed: () => setState(() => row.listUiExpanded = !row.listUiExpanded),
                      icon: Icon(row.listUiExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: scheme.primary),
                    ),
                  ],
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox(width: double.infinity),
                secondChild: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: _rowExpandedBlock(row, scheme, sortedCats, safeCat, accountVal, accounts),
                ),
                crossFadeState: row.listUiExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 220),
                sizeCurve: Curves.easeOutCubic,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _batchScrollChildren(ColorScheme scheme) {
    final ordered = _visibleOrderedIndices();
    final children = <Widget>[];

    String? lastHeader;
    for (final i in ordered) {
      final row = _rows[i];
      String header;
      switch (_groupMode) {
        case SmartInputBatchGroupMode.lista:
          header = '';
        case SmartInputBatchGroupMode.porData:
          header = _headerDateCategory(row);
        case SmartInputBatchGroupMode.porCategoria:
          header = _headerDateCategory(row);
      }
      if (_groupMode != SmartInputBatchGroupMode.lista && header != lastHeader) {
        lastHeader = header;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              header,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, letterSpacing: 0.2, color: scheme.primary),
            ),
          ),
        );
      }
      children.add(_rowCard(row, scheme));
    }
    return children;
  }

  Widget _compactBatchToolbar(ColorScheme scheme) {
    final uncategorizedTotal = _rows.where((r) => r.category.trim().isEmpty).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if ((widget.importPresetIdHint ?? '').isNotEmpty) ...[
            Material(
              color: scheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: scheme.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Instituição sugerida: ${widget.importPresetIdHint}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              selected: _onlyUncategorized,
              onSelected: _rows.isEmpty
                  ? null
                  : (v) {
                      setState(() => _onlyUncategorized = v);
                    },
              avatar: const Icon(Icons.filter_alt_rounded, size: 16),
              label: Text(
                _onlyUncategorized
                    ? 'Somente sem categoria ($uncategorizedTotal)'
                    : 'Filtrar: sem categoria ($uncategorizedTotal)',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
              visualDensity: VisualDensity.compact,
            ),
          ),
          SegmentedButton<SmartInputBatchGroupMode>(
            style: _kCompactSegmentStyle,
            segments: const [
              ButtonSegment(value: SmartInputBatchGroupMode.lista, label: Text('Lista'), icon: Icon(Icons.view_list_rounded, size: 15)),
              ButtonSegment(value: SmartInputBatchGroupMode.porData, label: Text('Data'), icon: Icon(Icons.calendar_month_rounded, size: 15)),
              ButtonSegment(
                value: SmartInputBatchGroupMode.porCategoria,
                label: Text('Categoria'),
                icon: Icon(Icons.category_rounded, size: 15),
              ),
            ],
            selected: {_groupMode},
            onSelectionChanged: (s) {
              if (s.isEmpty) return;
              setState(() => _groupMode = s.first);
            },
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text('Ao gravar', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: scheme.onSurfaceVariant)),
              ),
              TextButton(
                onPressed: _saving
                    ? null
                    : () {
                        setState(() {
                          for (final r in _rows) {
                            r.selected = true;
                          }
                        });
                      },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Marcar todos', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              ),
              TextButton(
                onPressed: _saving
                    ? null
                    : () {
                        setState(() {
                          for (final r in _rows) {
                            r.selected = r.category.trim().isEmpty;
                          }
                        });
                      },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Marcar sem cat.', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              ),
              TextButton(
                onPressed: _saving
                    ? null
                    : () {
                        setState(() {
                          for (final r in _rows) {
                            r.selected = false;
                          }
                        });
                      },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Desmarcar', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ],
          ),
          SegmentedButton<SmartBatchPersistMode>(
            style: _kCompactSegmentStyle,
            segments: const [
              ButtonSegment(value: SmartBatchPersistMode.umPorLinha, label: Text('1 doc / linha')),
              ButtonSegment(value: SmartBatchPersistMode.agruparIguais, label: Text('Agrupar iguais')),
            ],
            selected: {_persistMode},
            onSelectionChanged: (s) {
              if (s.isEmpty) return;
              setState(() => _persistMode = s.first);
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Lista compacta: ícone à direita para mostrar categoria, conta e tipo.',
              style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600, height: 1.25),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: true,
      child: Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Voltar',
          onPressed: () => _leaveScreen(),
          icon: const Icon(Icons.arrow_back_rounded, size: 24),
        ),
        title: const Text('Pré-visualização em massa'),
        centerTitle: true,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
        actions: [
          TextButton(
            onPressed: () => _leaveScreen(),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ],
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.deepBlueDark, AppColors.deepBlue, AppColors.primary],
            ),
          ),
        ),
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _rows.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Nenhum lançamento válido.', style: TextStyle(color: scheme.onSurfaceVariant)),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 6),
                        children: [
                          _compactBatchToolbar(scheme),
                          ..._batchScrollChildren(scheme),
                        ],
                      ),
                    ),
                    Builder(
                      builder: (ctx) {
                        final b = _breakdownSelected();
                        return _SummaryBar(
                          listedCount: _rows.length,
                          listedTotal: _sumListed(),
                          selectedCount: _selectedCount,
                          selectedTotal: _sumSelected(),
                          uncategorizedCount: _rows.where((r) => r.selected && r.category.trim().isEmpty).length,
                          selectedExpense: b.expense,
                          selectedIncome: b.income,
                          selectedPendingTotal: b.pendingSelected,
                          duplicateHints: _rows.where((r) => r.selected && r.possibleDuplicate).length,
                          suspiciousCount: _rows.where((r) => r.selected && _isSuspicious(r)).length,
                        );
                      },
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: FilledButton.icon(
                          onPressed: _saving || _selectedCount == 0 ? null : _saveSelected,
                          icon: _saving
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.save_rounded),
                          label: Text(
                            _saving
                                ? 'A gravar…'
                                : 'Gravar ${_previewDocumentCount()} documento(s) ($_selectedCount linha(s))',
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: AppColors.deepBlue,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  final int listedCount;
  final double listedTotal;
  final int selectedCount;
  final double selectedTotal;
  final int uncategorizedCount;
  final double selectedExpense;
  final double selectedIncome;
  final double selectedPendingTotal;
  final int duplicateHints;
  final int suspiciousCount;

  const _SummaryBar({
    required this.listedCount,
    required this.listedTotal,
    required this.selectedCount,
    required this.selectedTotal,
    required this.uncategorizedCount,
    required this.selectedExpense,
    required this.selectedIncome,
    required this.selectedPendingTotal,
    required this.duplicateHints,
    required this.suspiciousCount,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35))),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, -3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('Resumo', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: scheme.primary)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$listedCount list. · ${CurrencyFormats.formatBRL(listedTotal)}  ·  $selectedCount sel. · ${CurrencyFormats.formatBRL(selectedTotal)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: scheme.onSurface),
                ),
              ),
            ],
          ),
          if (selectedCount > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Desp. ${CurrencyFormats.formatBRL(selectedExpense)} · Rec. ${CurrencyFormats.formatBRL(selectedIncome)} · Pend. ${CurrencyFormats.formatBRL(selectedPendingTotal)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
            ),
          ],
          if (duplicateHints > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '$duplicateHints possível duplicado — confira.',
                style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w700, fontSize: 11),
              ),
            ),
          if (suspiciousCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '$suspiciousCount linha(s) com baixa confiança — revise antes de gravar.',
                style: TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.w700, fontSize: 11),
              ),
            ),
          if (uncategorizedCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '$uncategorizedCount sem categoria — corrija antes de gravar.',
                style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.w700, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
