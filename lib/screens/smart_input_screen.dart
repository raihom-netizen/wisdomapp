import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' hide showDatePicker;
import '../widgets/fast_text_field.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../constants/currency_formats.dart';
import '../constants/finance_category_visuals.dart';
import '../models/finance_account.dart';
import '../models/smart_input_pop_result.dart';
import '../models/user_profile.dart';
import '../services/bank_notification_parser.dart';
import '../services/finance_accounts_service.dart';
import '../services/finance_advanced_settings_service.dart';
import '../services/finance_service.dart';
import '../services/smart_category_hints_service.dart';
import '../services/smart_input_pdf_text_service.dart';
import '../services/user_categories_service.dart';
import '../theme/app_colors.dart';
import '../utils/date_picker_a11y.dart';
import '../utils/keyboard_form_scaffold.dart';
import '../utils/premium_upgrade.dart';
import '../utils/smart_input_heavy_parse.dart';
import '../utils/smart_input_voice_text.dart';
import '../widgets/finance_bank_brand_thumb.dart';
import 'smart_input_batch_preview_screen.dart';

const String _kSmartInputGuideCardText =
    'Escreva em linguagem natural: «compra supermercado 100 reais», «6× 250», «10 parcelas de 250». O assistente sugere a categoria (ex.: Supermercado) e você confirma. Vírgulas entre itens viram | no resumo. CSV / TXT: importe acima.';

bool _bytesLookLikePdf(Uint8List b) =>
    b.length >= 5 && b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46; // %PDF

/// Só para recusar import de imagem (OCR desativado — texto/CSV only).
bool _importBytesLookLikeImage(Uint8List bytes, String name) {
  final u = name.toLowerCase();
  if (u.endsWith('.jpg') ||
      u.endsWith('.jpeg') ||
      u.endsWith('.png') ||
      u.endsWith('.webp') ||
      u.endsWith('.gif') ||
      u.endsWith('.bmp')) {
    return true;
  }
  final b = bytes;
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8) return true;
  if (b.length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return true;
  if (b.length >= 6 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return true;
  if (b.length >= 12 && b[0] == 0x52 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
    return true;
  }
  return false;
}

/// Modelo mínimo aceite por [BankNotificationParser.parseFromCsvText] (cabeçalhos em português).
const String _kSmartInputCsvTemplateBody = 'Data,Descrição,Valor\n'
    '24/04/2026,Supermercado exemplo,"85,50"\n'
    '24/04/2026,Combustível,"120,00"\n';

/// Cola SMS ou push do banco, extrai dados com regex e confirma o lançamento (Material 3).
class SmartInputScreen extends StatefulWidget {
  final String uid;
  final UserProfile profile;

  const SmartInputScreen({
    super.key,
    required this.uid,
    required this.profile,
  });

  @override
  State<SmartInputScreen> createState() => _SmartInputScreenState();
}

/// Último foco: texto (campo) ou ficheiro CSV/TXT.
enum _SmartInputMode { texto, csv }

class _SmartInputScreenState extends State<SmartInputScreen> {
  /// Mesmo limite na web e nos apps (paridade).
  static const int _kMaxFieldChars = 75000;

  final _textCtrl = TextEditingController();
  final FocusNode _fieldFocus = FocusNode();
  BankNotificationParseResult? _parsed;
  bool _saving = false;
  /// Enquanto busca categoria sugerida (há await no aparelho).
  bool _reparsing = false;

  /// Invalida resultados de [_reparse] quando o utilizador continua a escrever.
  int _reparseGen = 0;
  bool _suppressTextListener = false;

  /// Quantidade de lançamentos detetados no texto (para botão de massa).
  int _batchCandidateCount = 0;
  /// Texto exatamente como estava quando o utilizador carregou em «Gerar lançamentos» (evita confirmar com texto desatualizado).
  String? _parsedSourceText;
  /// Resumo multi-linha calculado na última geração (não recalcula a cada frame).
  String? _cachedMultiSummary;
  /// Lista em massa da última análise (evita re-parse ao abrir pré-visualização).
  List<BankNotificationParseResult>? _cachedBatchList;
  bool _importBusy = false;
  bool get _ioBusy => _importBusy;

  _SmartInputMode _modeHighlight = _SmartInputMode.texto;
  /// Último texto do campo antes de colagem/import/ditado (um nível de desfazer).
  String? _undoFieldSnapshot;

  bool _loadingLists = true;
  int _hydrateSeq = 0;
  StreamSubscription<fa.User?>? _authSubscription;
  List<String> _incomeCategories = [];
  List<String> _expenseCategories = [];
  List<FinanceAccount> _accounts = [];

  String _category = '';
  /// null em receitas = «sem conta» (igual novo lançamento).
  String? _financeAccountId;
  String? _defaultFinanceAccountId;
  DateTime _paymentDate = DateTime.now();
  /// `paid` = saldo imediato (débito na conta); `pending` = crédito / a receber (fica pendente).
  String _settlement = 'paid';
  /// null = segue o tipo inferido do texto; se preenchido, o utilizador escolheu Receita/Despesa à mão.
  bool? _incomeUserOverride;
  String? _lastParsedTypeForOverride;

  bool get _effectiveIsIncome =>
      _incomeUserOverride ?? (_parsed != null && _parsed!.type == 'income');

  List<String> get _catsForType =>
      _effectiveIsIncome ? _incomeCategories : _expenseCategories;

  int get _maxFieldChars => _kMaxFieldChars;

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

  /// Corta PDF bruto e limita tamanho (web fica fluido com menos texto no canvas).
  ({String text, bool strippedPdf, bool truncated}) _normalizeFieldText(String raw) {
    var t = raw;
    var strippedPdf = false;
    final pdfIdx = t.indexOf('%PDF');
    if (pdfIdx == 0) {
      strippedPdf = true;
      t = '';
    } else if (pdfIdx > 0) {
      strippedPdf = true;
      t = t.substring(0, pdfIdx).trimRight();
    } else if (SmartInputPdfTextService.textLooksLikePdfBinary(t)) {
      strippedPdf = true;
      t = '';
    }
    if (t.isNotEmpty) {
      t = SmartInputVoiceText.forSmartInputField(t);
    }
    var truncated = false;
    if (t.length > _maxFieldChars) {
      truncated = true;
      t = t.substring(0, _maxFieldChars);
    }
    return (text: t, strippedPdf: strippedPdf, truncated: truncated);
  }

  @override
  void initState() {
    super.initState();
    _hydrateCategoriesAndAccounts();
    _textCtrl.addListener(_onTextChanged);
    _authSubscription = fa.FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        unawaited(_hydrateCategoriesAndAccounts());
      }
    });
  }

  Future<void> _hydrateCategoriesAndAccounts() async {
    final seq = ++_hydrateSeq;
    final cats = await UserCategoriesService().load(widget.uid);
    final accounts = await FinanceAccountsService().listOnce(widget.uid);
    final defId = await FinanceAdvancedSettingsService().getDefaultFinanceAccountId(widget.uid);
    if (!mounted || seq != _hydrateSeq) return;
    setState(() {
      _incomeCategories = cats.income
          .where((e) => e != UserCategoriesService.kIncluirNova)
          .toList()
        ..sort(UserCategoriesService.compareNamesPt);
      _expenseCategories = cats.expense
          .where((e) => e != UserCategoriesService.kIncluirNova)
          .toList()
        ..sort(UserCategoriesService.compareNamesPt);
      _accounts = accounts;
      _defaultFinanceAccountId =
          defId != null && accounts.any((a) => a.id == defId) ? defId : null;
      _loadingLists = false;
    });
  }

  @override
  void dispose() {
    _cancelPendingWork();
    _authSubscription?.cancel();
    _textCtrl.removeListener(_onTextChanged);
    _fieldFocus.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  /// Invalida parse/hidratação em curso (voltar não pode depender de await).
  void _cancelPendingWork() {
    _reparseGen++;
    _hydrateSeq++;
  }

  /// Sai da tela com prioridade sobre análise/gravação em curso.
  void _leaveScreen([Object? result]) {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _cancelPendingWork();
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop(result);
    }
  }

  void _selectAllInField() {
    if (_saving || _importBusy) return;
    HapticFeedback.selectionClick();
    _fieldFocus.requestFocus();
    final t = _textCtrl.text;
    _textCtrl.selection = TextSelection(baseOffset: 0, extentOffset: t.length);
  }

  void _clearField() {
    if (_saving || _importBusy) return;
    HapticFeedback.lightImpact();
    _saveUndoSnapshot();
    _suppressTextListener = true;
    _textCtrl.clear();
    _textCtrl.selection = const TextSelection.collapsed(offset: 0);
    _suppressTextListener = false;
    _clearGeneratedPreview();
    if (mounted) setState(() {});
  }

  void _clearGeneratedPreview() {
    _parsed = null;
    _batchCandidateCount = 0;
    _parsedSourceText = null;
    _cachedMultiSummary = null;
    _cachedBatchList = null;
    _incomeUserOverride = null;
    _lastParsedTypeForOverride = null;
  }

  void _onTextChanged() {
    if (_suppressTextListener) return;

    if (_parsedSourceText != null && _parsedSourceText != _textCtrl.text) {
      setState(_clearGeneratedPreview);
    }
  }

  Future<void> _reparse() async {
    final gen = ++_reparseGen;
    if (mounted) setState(() => _reparsing = true);
    try {
      var raw = _textCtrl.text;
      final norm = _normalizeFieldText(raw);
      if (norm.text != raw) {
        if (!mounted || gen != _reparseGen) return;
        _suppressTextListener = true;
        _textCtrl.value = TextEditingValue(
          text: norm.text,
          selection: TextSelection.collapsed(offset: norm.text.length),
        );
        _suppressTextListener = false;
        raw = norm.text;
        if (norm.strippedPdf && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                kIsWeb
                    ? 'Removido trecho em formato PDF bruto. Copie só o texto dos lançamentos ou importe .csv / .txt.'
                    : 'Removido trecho em formato PDF bruto. Copie o texto dos lançamentos ou importe .csv / .txt.',
              ),
            ),
          );
        } else if (norm.truncated && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Texto limitado a $_maxFieldChars caracteres no campo.',
              ),
            ),
          );
        }
      } else {
        raw = norm.text;
      }

      final text = raw;

      // Cede o frame para toques (voltar/fechar) antes de parse pesado na UI thread.
      await Future<void>.delayed(Duration.zero);
      if (!mounted || gen != _reparseGen) return;

      late BankNotificationParseResult p;
      late int batchCount;
      List<BankNotificationParseResult> batch = const [];
      // Em isolate só em mobile/desktop — `compute` não existe na web; lá fazemos parse direto (mesmo resultado).
      final heavyNative = !kIsWeb && text.length >= 9000;
      if (heavyNative) {
        try {
          final r = await runSmartInputHeavyParse(text);
          p = r.parsed;
          batchCount = r.batchCount;
        } catch (_) {
          batch = BankNotificationParser.parseManyForBatch(text);
          p = batch.isNotEmpty ? batch.first : BankNotificationParser.parse(text);
          batchCount = batch.length;
        }
      } else {
        batch = BankNotificationParser.parseManyForBatch(text);
        p = batch.isNotEmpty ? batch.first : BankNotificationParser.parse(text);
        batchCount = batch.length;
      }

      if (!mounted || gen != _reparseGen) return;

      final isInc = _incomeUserOverride ?? (p.type == 'income');
      var nextCat = _category;
      final list0 = isInc ? _incomeCategories : _expenseCategories;
      if (!(nextCat.isNotEmpty && list0.any((c) => c == nextCat))) {
        nextCat = '';
      }
      final suggestedCat = await _resolveSuggestedCategory(
        descricao: (p.descricao ?? '').trim(),
        allowed: list0,
      );
      if (!mounted || gen != _reparseGen) return;

      // Preview e massa na UI (só após «Gerar lançamentos»). Categoria fica à escolha do utilizador no cartão.
      setState(() {
        _reparsing = false;
        _parsed = p;
        _batchCandidateCount = batchCount;
        _parsedSourceText = text;
        _cachedBatchList = batchCount >= 2 ? (batch.isNotEmpty ? batch : null) : null;
        _cachedMultiSummary = batchCount >= 2 ? _batchSummaryLight(p, batchCount) : null;
        if (p.data != null) _paymentDate = p.data!;

        final t = p.type;
        if (_lastParsedTypeForOverride != t) {
          _incomeUserOverride = null;
          _lastParsedTypeForOverride = t;
        }

        if (nextCat.isNotEmpty && list0.any((c) => c == nextCat)) {
          _category = nextCat;
        } else if (_category.isEmpty || !list0.any((c) => c == _category)) {
          _category = suggestedCat;
        }

        _financeAccountId = _pickAccountId(p, isInc);
        if (_shouldDefaultPendingFromParsed(p)) {
          _settlement = 'pending';
        }
      });
    } finally {
      if (mounted && gen == _reparseGen && _reparsing) {
        setState(() => _reparsing = false);
      }
    }
  }

  Future<void> _generateLancamentos() async {
    if (_saving || _importBusy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final t = _textCtrl.text.trim();
    if (t.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite ou cole o texto dos lançamentos. Depois toque em «Gerar lançamentos».')),
      );
      return;
    }
    await _reparse();
    if (!mounted) return;
    final readyNow = _parsed?.hasMinimumForConfirmation ?? false;
    final nBatch = _batchCandidateCount;
    if (!readyNow && nBatch < 2) {
      setState(_clearGeneratedPreview);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível reconhecer valores e descrição neste texto. Ajuste e tente de novo.'),
        ),
      );
      return;
    }
    HapticFeedback.lightImpact();
  }

  void _onUserChangeIncomeType(bool isIncome) {
    HapticFeedback.selectionClick();
    setState(() {
      _incomeUserOverride = isIncome;
      final list = isIncome ? _incomeCategories : _expenseCategories;
      if (!(_category.isNotEmpty && list.any((c) => c == _category))) {
        _category = '';
      }
      if (_parsed != null) {
        _financeAccountId = _pickAccountId(_parsed!, isIncome);
      }
    });
  }

  Future<String> _resolveSuggestedCategory({
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

  Future<void> _criarEUsarNovaCategoria() async {
    final isIncome = _effectiveIsIncome;
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
            decoration: const InputDecoration(
              labelText: 'Nome da categoria',
              hintText: 'Ex.: Farmácia, Bônus, Outros',
            ),
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
    if (c == null || !mounted) return;
    if (c.isEmpty) return;
    try {
      await UserCategoriesService().addCustom(widget.uid, isIncome, c);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível guardar a categoria. Tente de novo.'), backgroundColor: Color(0xFFB00020)),
        );
      }
      return;
    }
    final reloaded = await UserCategoriesService().load(widget.uid);
    if (!mounted) return;
    setState(() {
      _incomeCategories = reloaded.income
          .where((e) => e != UserCategoriesService.kIncluirNova)
          .toList()
        ..sort(UserCategoriesService.compareNamesPt);
      _expenseCategories = reloaded.expense
          .where((e) => e != UserCategoriesService.kIncluirNova)
          .toList()
        ..sort(UserCategoriesService.compareNamesPt);
      _category = c;
    });
  }

  String? _pickAccountId(BankNotificationParseResult p, bool isIncome) {
    if (_accounts.isEmpty) return isIncome ? null : '';
    final sid = p.suggestedPresetId;
    if (sid != null && sid.isNotEmpty) {
      final match = _accounts.where((a) => a.presetId == sid).toList();
      if (match.isNotEmpty) return match.first.id;
    }
    final def = _defaultFinanceAccountId;
    if (def != null && def.isNotEmpty && _accounts.any((a) => a.id == def)) {
      return def;
    }
    if (isIncome) {
      return _financeAccountId;
    }
    final cur = _financeAccountId;
    if (cur != null && cur.isNotEmpty && _accounts.any((a) => a.id == cur)) return cur;
    return _accounts.first.id;
  }

  Future<void> _pasteClipboard() async {
    HapticFeedback.lightImpact();
    setState(() => _modeHighlight = _SmartInputMode.texto);
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text;
    if (t != null && t.isNotEmpty) {
      final norm = _normalizeFieldText(t);
      if (norm.text.isEmpty) {
        if (mounted && norm.strippedPdf) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                kIsWeb
                    ? 'A área de transferência continha só dados PDF bruto. Copie o texto dos lançamentos para o campo.'
                    : 'A área de transferência continha só dados PDF bruto. Importe .txt ou .csv com o texto.',
              ),
            ),
          );
        }
        return;
      }
      _saveUndoSnapshot();
      _suppressTextListener = true;
      _textCtrl.text = norm.text;
      _textCtrl.selection = TextSelection.collapsed(offset: norm.text.length);
      _suppressTextListener = false;
      if (mounted && norm.strippedPdf) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              kIsWeb
                  ? 'PDF bruto na colagem foi ignorado. Cole só o texto dos lançamentos.'
                  : 'PDF bruto na colagem foi ignorado. Use ficheiro .txt ou .csv.',
            ),
          ),
        );
      }
      if (mounted) setState(_clearGeneratedPreview);
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb
                ? 'Sem texto na área de transferência (ou o navegador bloqueou o acesso). Use Ctrl+V no campo ou copie de novo.'
                : 'Área de transferência sem texto. Copie o SMS ou o extrato e toque em «Colar» de novo.',
          ),
        ),
      );
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _paymentDate = picked);
  }

  Future<void> _pushBatch(List<BankNotificationParseResult> raw, {String? importPresetIdHint}) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    if (raw.isEmpty) return;
    final result = await Navigator.of(context).push<SmartInputPopResult?>(
      MaterialPageRoute<SmartInputPopResult?>(
        fullscreenDialog: true,
        builder: (_) => SmartInputBatchPreviewScreen(
          uid: widget.uid,
          profile: widget.profile,
          initialParsed: raw,
          incomeCategories: _incomeCategories,
          expenseCategories: _expenseCategories,
          accounts: _accounts,
          defaultFinanceAccountId: _defaultFinanceAccountId,
          importPresetIdHint: importPresetIdHint,
        ),
      ),
    );
    if (mounted && result != null && result.hasCreated) {
      Navigator.of(context).pop(result);
    }
  }

  Future<void> _openBatchFromField() async {
    if (_parsedSourceText == null || _parsedSourceText != _textCtrl.text) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primeiro toque em «Gerar lançamentos». Depois abra a pré-visualização em massa.')),
      );
      return;
    }
    final raw = _cachedBatchList ?? BankNotificationParser.parseManyForBatch(_textCtrl.text);
    if (raw.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('São necessários pelo menos 2 lançamentos reconhecidos no texto.')),
        );
      }
      return;
    }
    await _pushBatch(raw);
  }

  String _shortErr(Object e) {
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 117)}…' : s;
  }

  void _saveUndoSnapshot() {
    final t = _textCtrl.text;
    if (t.trim().isNotEmpty) _undoFieldSnapshot = t;
  }

  void _undoLastFieldChange() {
    final snap = _undoFieldSnapshot;
    if (snap == null || !mounted) return;
    _suppressTextListener = true;
    _textCtrl.text = snap;
    _textCtrl.selection = TextSelection.collapsed(offset: snap.length);
    _suppressTextListener = false;
    setState(() {
      _undoFieldSnapshot = null;
      _clearGeneratedPreview();
    });
  }

  /// Resumo leve (sem segundo parse) para vários lançamentos no mesmo texto.
  String? _batchSummaryLight(BankNotificationParseResult first, int count) {
    if (count < 2) return null;
    final df = DateFormat('dd/MM/yyyy', 'pt_BR');
    final d0 = first.data;
    final parcela = (first.descricao ?? '').toLowerCase().contains('parcela');
    final parcelaBit = parcela ? ' · parcelas' : '';
    final v0 = first.valor;
    final unitBit = v0 != null && v0 > 0 ? ' · $count× ${CurrencyFormats.formatBRL(v0)}' : '';
    final d0s = d0 != null ? df.format(d0) : '—';
    return '$count lançamentos$unitBit$parcelaBit · 1.º venc. $d0s';
  }

  Future<void> _copyCsvTemplateToClipboard() async {
    await Clipboard.setData(const ClipboardData(text: _kSmartInputCsvTemplateBody));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Modelo CSV copiado. Cole numa folha de cálculo ou guarde como .csv.')),
    );
  }

  Future<void> _onExampleCopied(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Exemplo copiado. Cole no campo acima.')),
    );
  }

  Future<void> _shareCsvTemplate() async {
    final bytes = Uint8List.fromList(utf8.encode(_kSmartInputCsvTemplateBody));
    try {
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            name: 'modelo_controle_total.csv',
            mimeType: 'text/csv',
          ),
        ],
        subject: 'Modelo CSV — WISDOMAPP',
      );
    } catch (_) {
      await _copyCsvTemplateToClipboard();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Partilha indisponível; o modelo foi copiado para a área de transferência.')),
      );
    }
  }

  Future<bool> _showCsvImportPreviewSheet({
    required String fileName,
    required List<BankNotificationParseResult> rows,
    required String headerPreview,
    required bool usedLatin1Fallback,
  }) async {
    if (!mounted) return false;
    final sum = rows.fold<double>(0, (a, p) => a + (p.valor ?? 0));
    final df = DateFormat('dd/MM/yyyy', 'pt_BR');
    DateTime? dMin;
    DateTime? dMax;
    for (final p in rows) {
      final d = p.data;
      if (d == null) continue;
      final curMin = dMin;
      if (curMin == null || d.isBefore(curMin)) dMin = d;
      final curMax = dMax;
      if (curMax == null || d.isAfter(curMax)) dMax = d;
    }
    final r = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 8, bottom: MediaQuery.paddingOf(ctx).bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pré-visualização CSV',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: scheme.onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                fileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
              if (usedLatin1Fallback) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.translate_rounded, size: 20, color: scheme.onSecondaryContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'O ficheiro não estava em UTF-8 perfeito; lemos também em Latin-1 (acentos podem variar).',
                          style: TextStyle(fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600, color: scheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _CsvPreviewStat(icon: Icons.table_rows_rounded, label: 'Linhas com valor', value: '${rows.length}'),
              const SizedBox(height: 8),
              _CsvPreviewStat(icon: Icons.payments_rounded, label: 'Soma dos valores', value: CurrencyFormats.formatBRL(sum)),
              if (dMin != null || dMax != null) ...[
                const SizedBox(height: 8),
                _CsvPreviewStat(
                  icon: Icons.date_range_rounded,
                  label: 'Datas no ficheiro',
                  value: () {
                    final a = dMin;
                    final b = dMax;
                    if (a != null && b != null) {
                      final sameDay = a.year == b.year && a.month == b.month && a.day == b.day;
                      return sameDay ? df.format(a) : '${df.format(a)} — ${df.format(b)}';
                    }
                    if (a != null) return df.format(a);
                    if (b != null) return df.format(b);
                    return '—';
                  }(),
                ),
              ],
              const SizedBox(height: 12),
              Text('Cabeçalho / colunas detetadas', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    headerPreview.length > 280 ? '${headerPreview.substring(0, 277)}…' : headerPreview,
                    style: const TextStyle(fontSize: 11.5, height: 1.35, fontFamily: 'monospace', fontFamilyFallback: ['Consolas', 'monospace']),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Linhas sem valor ou data reconhecível são ignoradas pelo importador.',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Continuar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    return r == true;
  }

  Future<void> _importTextFile() async {
    setState(() {
      _importBusy = true;
      _modeHighlight = _SmartInputMode.csv;
    });
    try {
      final r = await FilePicker.platform.pickFiles(
        dialogTitle: 'Adicionar ficheiro CSV ou TXT',
        type: FileType.custom,
        allowedExtensions: const ['txt', 'csv'],
        withData: true,
      );
      if (r == null || r.files.isEmpty) return;
      final bytes = r.files.first.bytes;
      if (bytes == null || bytes.isEmpty) return;
      final name = r.files.first.name.isEmpty ? 'ficheiro' : r.files.first.name;
      final lowerName = name.toLowerCase();

      if (_bytesLookLikePdf(bytes) || lowerName.endsWith('.pdf')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDF desativado aqui. Exporte o extrato para .csv ou copie o texto para o campo.'),
            ),
          );
        }
        return;
      }

      if (_importBytesLookLikeImage(bytes, name)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Leitura de imagem (OCR) desativada. Importe .csv ou .txt, ou copie o texto para o campo.'),
            ),
          );
        }
        return;
      }

      var usedLatin1Fallback = false;
      final t = utf8.decode(bytes, allowMalformed: true).trim();
      if (t.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ficheiro sem texto legível. Use .txt ou .csv.'),
            ),
          );
        }
        return;
      }
      if (lowerName.endsWith('.csv')) {
        var csvRows = BankNotificationParser.parseFromCsvText(t);
        if (csvRows.isEmpty && bytes.isNotEmpty) {
          final alt = latin1.decode(bytes, allowInvalid: true).trim();
          if (alt.isNotEmpty && alt != t) {
            usedLatin1Fallback = true;
            csvRows = BankNotificationParser.parseFromCsvText(alt);
          }
        }
        if (csvRows.isNotEmpty) {
          final nonEmptyLines = t.split(RegExp(r'\r?\n')).where((e) => e.trim().isNotEmpty).toList();
          final headerLine = nonEmptyLines.isEmpty ? '' : nonEmptyLines.first;
          if (csvRows.length >= 2) {
            final ok = await _showCsvImportPreviewSheet(
              fileName: name,
              rows: csvRows,
              headerPreview: headerLine,
              usedLatin1Fallback: usedLatin1Fallback,
            );
            if (ok && mounted) await _pushBatch(csvRows);
          } else {
            final only = csvRows.first;
            final line = '${only.descricao ?? ''} ${only.valor?.toStringAsFixed(2).replaceAll('.', ',') ?? ''}'.trim();
            if (line.isNotEmpty) {
              final ok = await _showCsvImportPreviewSheet(
                fileName: name,
                rows: csvRows,
                headerPreview: headerLine,
                usedLatin1Fallback: usedLatin1Fallback,
              );
              if (!ok || !mounted) return;
              _saveUndoSnapshot();
              _suppressTextListener = true;
              _textCtrl.text = line;
              _textCtrl.selection = TextSelection.collapsed(offset: _textCtrl.text.length);
              _suppressTextListener = false;
              await _reparse();
            }
          }
          return;
        }
      }
      if (!mounted) return;
      _saveUndoSnapshot();
      setState(() {
        final cur = _textCtrl.text.trim();
        final merged = cur.isEmpty ? t : '$cur\n\n$t';
        final norm = _normalizeFieldText(merged);
        _suppressTextListener = true;
        _textCtrl.text = norm.text;
        _textCtrl.selection = TextSelection.collapsed(offset: _textCtrl.text.length);
        _suppressTextListener = false;
      });
      await _reparse();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ficheiro: ${_shortErr(e)}')));
      }
    } finally {
      if (mounted) setState(() => _importBusy = false);
    }
  }

  Future<void> _confirm() async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    if (_parsedSourceText == null || _parsedSourceText != _textCtrl.text) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Toque em «Gerar lançamentos» para analisar o texto. Se editar o texto, gere de novo antes de confirmar.')),
      );
      return;
    }
    final multi = _cachedBatchList ?? BankNotificationParser.parseManyForBatch(_textCtrl.text.trim());
    if (multi.length > 1) {
      await _confirmParcelBatch(multi);
      return;
    }
    final p = _parsed;
    if (p == null || p.valor == null || p.valor! <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cole um texto com valor em R\$ válido.')));
      return;
    }
    final desc = (p.descricao ?? '').trim();
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível identificar a descrição a partir do texto.')),

      );
      return;
    }
    if (desc.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Histórico muito curto — use pelo menos 3 caracteres ou edite o texto.')),
      );
      return;
    }

    final isIncome = _effectiveIsIncome;
    final aid = (_financeAccountId ?? '').trim();

    if (!isIncome) {
      if (aid.isEmpty || !_accounts.any((a) => a.id == aid)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecione a conta para esta despesa.'), backgroundColor: Color(0xFFB00020)),
        );
        return;
      }
    }

    final cat = _category.trim();
    if (cat.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lançamento sem categoria. Selecione ou crie uma categoria antes de gravar.'),
          backgroundColor: Color(0xFFB00020),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final autoPending = _shouldDefaultPendingFromParsed(p);
      final statusToSave = autoPending ? 'pending' : (_settlement == 'pending' ? 'pending' : 'paid');
      final docId = await FinanceService.saveSmartPasteTransaction(
        uid: widget.uid,
        context: context,
        type: isIncome ? 'income' : 'expense',
        amount: p.valor!,
        category: cat,
        description: desc,
        date: _paymentDate,
        financeAccountId: aid,
        rawSnippet: p.rawSnippet,
        saveLearnedMapping: true,
        status: statusToSave,
      );
      if (docId != null && mounted) {
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(SmartInputPopResult(createdTransactionIds: [docId]));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Várias parcelas detetadas no mesmo texto (ex.: «parcelado em 10 vezes valor total 1.000»).
  Future<void> _confirmParcelBatch(List<BankNotificationParseResult> items) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    for (final p in items) {
      if (!p.hasMinimumForConfirmation) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Um dos lançamentos ficou incompleto. Ajuste o texto ou abra «Massa» para rever.')),
          );
        }
        return;
      }
    }
    final isIncome = _effectiveIsIncome;
    final aid = (_financeAccountId ?? '').trim();
    if (!isIncome) {
      if (aid.isEmpty || !_accounts.any((a) => a.id == aid)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecione a conta para esta despesa.'), backgroundColor: Color(0xFFB00020)),
        );
        return;
      }
    }
    final cat = _category.trim();
    if (cat.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Há lançamento sem categoria. Selecione ou crie uma categoria antes de gravar.'),
          backgroundColor: Color(0xFFB00020),
        ),
      );
      return;
    }

    final nParc = items.length;
    final batchHasInstallmentLike = nParc > 1 || items.any(_shouldDefaultPendingFromParsed);
    setState(() {
      _saving = true;
      if (batchHasInstallmentLike) _settlement = 'pending';
    });
    final batchId = 'smart_${DateTime.now().microsecondsSinceEpoch}';
    final ids = <String>[];
    try {
      for (var i = 0; i < items.length; i++) {
        final p = items[i];
        final desc = (p.descricao ?? '').trim();
        final autoPending = batchHasInstallmentLike || _shouldDefaultPendingFromParsed(p);
        final statusToSave = autoPending ? 'pending' : (_settlement == 'pending' ? 'pending' : 'paid');
        final id = await FinanceService.saveSmartPasteTransaction(
          uid: widget.uid,
          context: context,
          type: isIncome ? 'income' : 'expense',
          amount: p.valor!,
          category: cat,
          description: desc,
          date: p.data ?? _paymentDate,
          financeAccountId: aid,
          rawSnippet: p.rawSnippet,
          saveLearnedMapping: i == 0,
          status: statusToSave,
          showFeedback: false,
          smartPasteBatchId: batchId,
          installmentIndex: nParc > 1 ? i + 1 : null,
          installmentCount: nParc > 1 ? nParc : null,
        );
        if (id != null) ids.add(id);
      }
      if (ids.isNotEmpty && mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${ids.length} lançamento(s) guardado(s).')),
        );
        Navigator.of(context).pop(SmartInputPopResult(createdTransactionIds: ids));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onModeSegmentChanged(Set<_SmartInputMode> sel) async {
    if (sel.isEmpty) return;
    final m = sel.first;
    if (!mounted) return;
    setState(() => _modeHighlight = m);
    if (m == _SmartInputMode.csv) {
      await _importTextFile();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ready = _parsed?.hasMinimumForConfirmation ?? false;
    final multiSummary = _cachedMultiSummary;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _cancelPendingWork();
        }
      },
      child: Scaffold(
      resizeToAvoidBottomInset: scaffoldKeyboardResizeToAvoidBottomInset(),
      backgroundColor: const Color(0xFFF1F5F9),
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Voltar',
          onPressed: () => _leaveScreen(),
          style: IconButton.styleFrom(foregroundColor: Colors.white),
          icon: const Icon(Icons.arrow_back_rounded, size: 24),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.deepBlueDark, AppColors.deepBlue, AppColors.primary],
            ),
            boxShadow: [BoxShadow(color: Color(0x330B1F4B), blurRadius: 20, offset: Offset(0, 6))],
          ),
        ),
        title: const Text('Lançamento inteligente'),
        centerTitle: true,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Center(
              child: _AppBarGradientChip(
                label: 'Colar texto',
                icon: Icons.content_paste_go_rounded,
                onPressed: _pasteClipboard,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Fechar',
            onPressed: () => _leaveScreen(),
            icon: const Icon(Icons.close_rounded, size: 24),
            style: IconButton.styleFrom(foregroundColor: Colors.white),
          ),
        ],
      ),
      body: _loadingLists
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.primary),
                  ),
                  const SizedBox(height: 20),
                  Text('Carregando contas e categorias…', style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                    children: [
                  // Mesmo fio visual do atalho Início (dashboard) e do CTA do Financeiro
                  const _LancExpressoInicioStyleHeader(),
                  SizedBox(height: ready ? 12 : 18),
                  const _PremiumGuideCard(
                    text: _kSmartInputGuideCardText,
                  ),
                  const SizedBox(height: 10),
                  _SmartInputModeChips(
                    mode: _modeHighlight,
                    onSelectionChanged: _saving || _ioBusy
                        ? null
                        : (s) {
                            unawaited(_onModeSegmentChanged(s));
                          },
                  ),
                  if (_undoFieldSnapshot != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _saving || _ioBusy ? null : _undoLastFieldChange,
                        icon: const Icon(Icons.undo_rounded, size: 20),
                        label: const Text('Desfazer colagem ou import'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.deepBlue,
                          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  _SmartInputExamplesPanel(
                    onCopyExample: _onExampleCopied,
                    onCopyCsvTemplate: _copyCsvTemplateToClipboard,
                    onShareCsvTemplate: _shareCsvTemplate,
                  ),
                  SizedBox(height: ready ? 10 : 16),
                  // Borda suave com gradiente (alinhada ao card do início)
                  Container(
                    padding: const EdgeInsets.all(1.2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.primary.withValues(alpha: 0.45),
                          const Color(0xFF0D9488).withValues(alpha: 0.3),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.deepBlue.withValues(alpha: 0.12),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(22.5),
                      ),
                      child: Stack(
                        children: [
                          FastTextField(
                            controller: _textCtrl,
                            focusNode: _fieldFocus,
                            minLines: ready ? 6 : 8,
                            maxLines: 22,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(_maxFieldChars),
                            ],
                            style: const TextStyle(fontSize: 15, height: 1.4),
                            decoration: InputDecoration(
                              alignLabelWithHint: true,
                              hintText:
                                  'Ex.: compra supermercado 100 reais · 6× 250 · 10 parcelas de 250 · 1000 parcelados em 4. Enter = nova linha.',
                              hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.72), fontSize: 13, height: 1.3),
                              filled: true,
                              fillColor: scheme.surface,
                              contentPadding: const EdgeInsets.fromLTRB(18, 20, 18, 58),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(22),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 2,
                            bottom: 2,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Limpar campo',
                                  onPressed: _saving || _importBusy ? null : _clearField,
                                  icon: Icon(Icons.delete_sweep_outlined, size: 22, color: scheme.onSurfaceVariant),
                                ),
                                IconButton(
                                  tooltip: 'Selecionar tudo (depois apague com o teclado)',
                                  onPressed: _saving || _importBusy ? null : _selectAllInField,
                                  icon: Icon(Icons.select_all_rounded, size: 22, color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: _saving ? null : _pasteClipboard,
                                borderRadius: BorderRadius.circular(16),
                                child: Ink(
                                  decoration: const BoxDecoration(
                                    borderRadius: BorderRadius.all(Radius.circular(16)),
                                    gradient: LinearGradient(
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                      colors: [AppColors.deepBlueDark, AppColors.deepBlue, AppColors.primary],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(0x442D5BFF),
                                        blurRadius: 12,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.content_paste_go_rounded, size: 20, color: Colors.white),
                                        SizedBox(width: 6),
                                        Text('Colar texto', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: 0.15)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: (_saving || _ioBusy || _reparsing)
                          ? null
                          : () {
                              unawaited(_generateLancamentos());
                            },
                      icon: const Icon(Icons.auto_fix_high_rounded, size: 22),
                      label: const Text('Gerar lançamentos', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.15)),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  ),
                  if (!_loadingLists) ...[
                    if (_batchCandidateCount >= 2)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: AppColors.primary.withValues(alpha: 0.08),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                Icon(Icons.account_tree_rounded, color: AppColors.deepBlue, size: 22),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Assistente: $_batchCandidateCount lançamento(s) neste texto',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 13,
                                          color: scheme.onSurface,
                                          height: 1.2,
                                        ),
                                      ),
                                      if (multiSummary != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          multiSummary,
                                          style: TextStyle(fontSize: 12, height: 1.3, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (_importBusy || (_reparsing && _textCtrl.text.trim().isNotEmpty)) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                                backgroundColor: AppColors.accent.withValues(alpha: 0.2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _importBusy ? 'A importar ficheiro…' : 'A analisar o texto…',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_importBusy)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 2),
                        child: LinearProgressIndicator(minHeight: 3),
                      ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (_batchCandidateCount >= 2)
                          Semantics(
                            label: 'Abrir pré-visualização em massa, $_batchCandidateCount lançamentos detetados',
                            button: true,
                            child: _ModernActionButton(
                              label: 'Pré-visualizar massa ($_batchCandidateCount)',
                              icon: Icons.grid_view_rounded,
                              emphasize: true,
                              onPressed: _saving || _ioBusy ? null : _openBatchFromField,
                            ),
                          ),
                        Semantics(
                          label: 'Adicionar ficheiro CSV ou TXT ao lançamento',
                          button: true,
                          child: _ModernActionButton(
                            label: 'Adicionar CSV / TXT',
                            icon: Icons.add_chart_rounded,
                            csvAccent: true,
                            onPressed: _saving || _ioBusy ? null : _importTextFile,
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Tríades com | (3, 6, 9… partes) viram linhas. Parcelas: use «em N parcelas» (total) ou «N parcelas de R\$» (cada). Máscaras: supermercado10000, datas dd/mm/aaaa.',
                        style: TextStyle(fontSize: 11, height: 1.35, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                  if (_reparsing && _textCtrl.text.trim().isNotEmpty && !_importBusy) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                  SizedBox(height: ready ? 12 : 20),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: ready
                        ? _ConfirmCard(
                            key: const ValueKey('confirm'),
                            parsed: _parsed!,
                            multiLancSummary: multiSummary,
                            isIncome: _effectiveIsIncome,
                            onIncomeTypeChanged: _onUserChangeIncomeType,
                            category: _category,
                            categories: _catsForType,
                            accounts: _accounts,
                            financeAccountId: _financeAccountId,
                            paymentDate: _paymentDate,
                            settlement: _settlement,
                            onSettlement: (s) {
                              HapticFeedback.selectionClick();
                              setState(() => _settlement = s);
                            },
                            onCategoryChanged: (v) {
                              HapticFeedback.selectionClick();
                              setState(() => _category = v);
                            },
                            onAddNewCategory: _criarEUsarNovaCategoria,
                            onAccountChanged: (v) => setState(() => _financeAccountId = v),
                            onDateTap: _pickDate,
                          )
                        : _HintCard(
                            key: const ValueKey('hint'),
                            scheme: scheme,
                          ),
                  ),
                  ],
                ),
              ),
                if (ready)
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: _PremiumGhostCtaButton(
                              label: 'Cancelar',
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                _leaveScreen();
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _PremiumGradientCtaButton(
                              onPressed: _saving ? null : _confirm,
                              child: _saving
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text(
                                      'Confirmar',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                        color: Colors.white,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    ),
    );
  }
}

class _AppBarGradientChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const _AppBarGradientChip({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: enabled
                ? const LinearGradient(
                    colors: [Color(0xFFF8FAFC), Color(0xFFE2E8F0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: enabled ? null : Colors.white24,
            border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
            boxShadow: enabled
                ? const [
                    BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3)),
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: AppColors.deepBlueDark),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: AppColors.deepBlueDark, letterSpacing: 0.1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SmartInputModeChips extends StatelessWidget {
  final _SmartInputMode mode;
  final void Function(Set<_SmartInputMode>)? onSelectionChanged;

  const _SmartInputModeChips({
    required this.mode,
    required this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chip = SegmentedButton<_SmartInputMode>(
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
      ),
      segments: [
        ButtonSegment<_SmartInputMode>(
          value: _SmartInputMode.texto,
          label: const Text('Texto'),
          icon: Icon(Icons.edit_note_rounded, size: 18, color: scheme.onSurfaceVariant),
        ),
        ButtonSegment<_SmartInputMode>(
          value: _SmartInputMode.csv,
          label: const Text('CSV / TXT'),
          icon: Icon(Icons.table_chart_rounded, size: 18, color: scheme.onSurfaceVariant),
        ),
      ],
      selected: {mode},
      onSelectionChanged: onSelectionChanged,
    );
    if (onSelectionChanged == null) {
      return Opacity(opacity: 0.55, child: IgnorePointer(child: chip));
    }
    return chip;
  }
}

class _SmartInputExamplesPanel extends StatelessWidget {
  final Future<void> Function(String text) onCopyExample;
  final Future<void> Function() onCopyCsvTemplate;
  final Future<void> Function() onShareCsvTemplate;

  const _SmartInputExamplesPanel({
    required this.onCopyExample,
    required this.onCopyCsvTemplate,
    required this.onShareCsvTemplate,
  });

  static const _examples = <(String, String)>[
    ('Supermercado + valor', r'Supermercado r$ 50'),
    ('Data + local', '13/04/2026 farmácia 20,50'),
    ('Total em N parcelas + descrição', r'compra geladeira r$ 1.200 em 6 parcelas começando em 05/05/2026'),
    (r'N parcelas de R$ cada (10×250)', r'10 parcelas de 250,00 sofá novo 05/05/2026'),
    ('Várias linhas: Enter', 'pix enviado 30\ncompra cartao 45,90'),
    ('Múltiplos itens com | (pipe)', r'supermercado R$ 100,00 | açougue R$ 1,50 | padaria 12,00'),
    ('Tríade desc|valor|data (detalhado)', 'mercado|10000|24/04/2026|pao|5000|25/04/2026'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.deepBlue.withValues(alpha: 0.14)),
        color: scheme.surface,
        boxShadow: [
          BoxShadow(color: AppColors.deepBlue.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Exemplos e modelo CSV',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Toque para expandir, copie um exemplo ou o modelo.',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
          ),
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Frases prontas', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            ),
            const SizedBox(height: 6),
            for (final e in _examples)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      unawaited(onCopyExample(e.$2));
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.$1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)),
                                const SizedBox(height: 4),
                                Text(
                                  e.$2,
                                  style: TextStyle(fontSize: 12.5, height: 1.35, color: scheme.onSurface, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          Semantics(
                            label: 'Copiar exemplo ${e.$1}',
                            button: true,
                            child: IconButton(
                              onPressed: () {
                                unawaited(onCopyExample(e.$2));
                              },
                              icon: const Icon(Icons.copy_rounded, size: 20),
                              tooltip: 'Copiar',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Modelo para banco / folha de cálculo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    unawaited(onCopyCsvTemplate());
                  },
                  icon: const Icon(Icons.content_copy_rounded, size: 18),
                  label: const Text('Copiar modelo .csv'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () {
                    unawaited(onShareCsvTemplate());
                  },
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: const Text('Partilhar / guardar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CsvPreviewStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _CsvPreviewStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.deepBlue),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
              Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: scheme.onSurface)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Card título alinhado ao atalho da tela Início (dashboard) e ao CTA do Financeiro.
class _LancExpressoInicioStyleHeader extends StatelessWidget {
  const _LancExpressoInicioStyleHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            AppColors.primary.withValues(alpha: 0.05),
            const Color(0xFF0D9488).withValues(alpha: 0.04),
          ],
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.14), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBlue.withValues(alpha: 0.1),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.78)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Assistente de lançamentos',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: Colors.grey.shade900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Linguagem natural: «compra supermercado 100 reais». Categorias coloridas após gerar. Ajuste conta e confirme.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumGuideCard extends StatelessWidget {
  final String text;
  const _PremiumGuideCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.08),
            const Color(0xFF0D9488).withValues(alpha: 0.05),
            Colors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.16),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(Icons.tips_and_updates_rounded, size: 18, color: AppColors.deepBlue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13.2,
                height: 1.38,
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModernActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool emphasize;
  final bool csvAccent;
  final VoidCallback? onPressed;

  const _ModernActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.emphasize = false,
    this.csvAccent = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = emphasize ? Colors.white : (csvAccent ? const Color(0xFF0D9488) : AppColors.deepBlue);
    final borderColor = emphasize
        ? Colors.transparent
        : (csvAccent ? const Color(0xFF0D9488).withValues(alpha: 0.45) : AppColors.deepBlue.withValues(alpha: 0.25));
    final bg = emphasize ? null : Colors.white;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: emphasize
              ? const LinearGradient(
                  colors: [AppColors.deepBlueDark, AppColors.deepBlue, AppColors.primary],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          borderRadius: BorderRadius.circular(30),
          boxShadow: emphasize
              ? const [
                  BoxShadow(
                    color: Color(0x332D5BFF),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18, color: fg),
          label: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w800)),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            backgroundColor: bg,
            side: BorderSide(color: borderColor),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
        ),
      ),
    );
  }
}

/// Cancelar: estilo ghost premium (branco, borda suave, sombra leve).
class _PremiumGhostCtaButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _PremiumGhostCtaButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.45,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          color: scheme.surface,
          border: Border.all(color: AppColors.deepBlue.withValues(alpha: 0.22)),
          boxShadow: [
            BoxShadow(
              color: AppColors.deepBlue.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(30),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppColors.deepBlue,
                    letterSpacing: 0.15,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Confirmar: gradiente alinhado aos botões de ação premium.
class _PremiumGradientCtaButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;

  const _PremiumGradientCtaButton({required this.onPressed, required this.child});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.55,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            colors: [AppColors.deepBlueDark, AppColors.deepBlue, AppColors.primary],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x332D5BFF),
              blurRadius: 14,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(30),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  final ColorScheme scheme;
  const _HintCard({super.key, required this.scheme});

  @override
  Widget build(BuildContext context) {
    // Mesma linguagem do card do início: branco + borda + sombra leve
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            AppColors.primary.withValues(alpha: 0.04),
            const Color(0xFF0D9488).withValues(alpha: 0.03),
          ],
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12), width: 1.1),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBlue.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  colors: [AppColors.deepBlue, AppColors.primary],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Ex.: «compra supermercado 100 reais» ou «6× 250». Toque em «Gerar lançamentos» — categoria sugerida com cor; depois confirme.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600, height: 1.35, fontSize: 13.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmCard extends StatelessWidget {
  final BankNotificationParseResult parsed;
  /// Quando há vários lançamentos no mesmo texto (ex.: parcelas).
  final String? multiLancSummary;
  final bool isIncome;
  final void Function(bool isIncome) onIncomeTypeChanged;
  final String category;
  final List<String> categories;
  final List<FinanceAccount> accounts;
  final String? financeAccountId;
  final DateTime paymentDate;
  final String settlement;
  final void Function(String) onSettlement;
  final ValueChanged<String> onCategoryChanged;
  final Future<void> Function() onAddNewCategory;
  final ValueChanged<String?> onAccountChanged;
  final VoidCallback onDateTap;

  const _ConfirmCard({
    super.key,
    required this.parsed,
    this.multiLancSummary,
    required this.isIncome,
    required this.onIncomeTypeChanged,
    required this.category,
    required this.categories,
    required this.accounts,
    required this.financeAccountId,
    required this.paymentDate,
    required this.settlement,
    required this.onSettlement,
    required this.onCategoryChanged,
    required this.onAddNewCategory,
    required this.onAccountChanged,
    required this.onDateTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    var sortedCats = List<String>.from(categories)..sort(UserCategoriesService.compareNamesPt);
    if (category.isNotEmpty && !sortedCats.contains(category)) {
      sortedCats = [...sortedCats, category]..sort(UserCategoriesService.compareNamesPt);
    }
    final String? safeCat = category.isNotEmpty && sortedCats.contains(category) ? category : (sortedCats.isNotEmpty ? sortedCats.first : null);
    final displayDesc =
        BankNotificationParser.polishSmartPasteDescription(parsed.descricao) ?? parsed.descricao ?? '';

    String? dropdownValue = financeAccountId;
    if (isIncome) {
      if (financeAccountId == null || financeAccountId!.isEmpty) {
        dropdownValue = null;
      } else if (!accounts.any((a) => a.id == financeAccountId)) {
        dropdownValue = null;
      }
    } else {
      if (accounts.isEmpty) {
        dropdownValue = null;
      } else if (financeAccountId == null || !accounts.any((a) => a.id == financeAccountId)) {
        dropdownValue = accounts.first.id;
      }
    }

    final isPending = settlement == 'pending';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: (isIncome ? AppColors.success : AppColors.error).withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topLeft,
                    child: Text(
                      CurrencyFormats.formatBRL(parsed.valor),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: isIncome ? AppColors.success : AppColors.error,
                        height: 1.05,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      displayDesc,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.25, color: scheme.onSurface),
                    ),
                  ),
                ],
              ),
              if (multiLancSummary != null && multiLancSummary!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: AppColors.primary.withValues(alpha: 0.1),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.28)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.stacked_line_chart_rounded, size: 20, color: AppColors.deepBlue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          multiLancSummary!,
                          style: TextStyle(fontSize: 12, height: 1.35, fontWeight: FontWeight.w700, color: scheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SegmentedButton<bool>(
                      style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      ),
                      segments: const [
                        ButtonSegment<bool>(value: true, label: Text('Receita'), icon: Icon(Icons.south_west_rounded, size: 14)),
                        ButtonSegment<bool>(value: false, label: Text('Despesa'), icon: Icon(Icons.north_east_rounded, size: 14)),
                      ],
                      showSelectedIcon: false,
                      selected: {isIncome},
                      onSelectionChanged: (s) {
                        if (s.isEmpty) return;
                        onIncomeTypeChanged(s.first);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _SettlementPills(
                isIncome: isIncome,
                isPending: isPending,
                dense: true,
                onSelectpaid: () => onSettlement('paid'),
                onSelectPending: () => onSettlement('pending'),
              ),
              if (safeCat != null && safeCat.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    financeCategoryLeadingTile(safeCat, isIncome: isIncome, size: 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        safeCat,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: financeCategoryVisualFor(safeCat, isIncome: isIncome).color,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Categoria',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.deepBlue.withValues(alpha: 0.18)),
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          isDense: true,
                          value: safeCat,
                          hint: Text(
                            sortedCats.isEmpty ? 'Crie a primeira categoria (+)' : 'Categoria',
                            style: const TextStyle(fontSize: 13),
                          ),
                          selectedItemBuilder: (ctx) => [
                            for (final c in sortedCats)
                              financeCategoryDropdownMenuRow(c, isIncome: isIncome, isIncluirNovaOption: false),
                          ],
                          items: [
                            for (final c in sortedCats)
                              DropdownMenuItem(
                                value: c,
                                child: financeCategoryDropdownMenuRow(c, isIncome: isIncome, isIncluirNovaOption: false),
                              ),
                          ],
                          onChanged: sortedCats.isEmpty
                              ? null
                              : (v) {
                                  if (v != null) onCategoryChanged(v);
                                },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    onPressed: () => onAddNewCategory(),
                    tooltip: 'Nova categoria',
                    constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    ),
                    icon: const Icon(Icons.add_rounded, color: AppColors.deepBlue, size: 22),
                  ),
                ],
              ),
              if (!isIncome && accounts.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Cadastre uma conta no Financeiro.', style: TextStyle(color: scheme.error, fontSize: 11.5, fontWeight: FontWeight.w600)),
                ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Conta',
                        isDense: true,
                        prefixIcon: const Icon(Icons.account_balance_wallet_rounded, size: 18, color: AppColors.deepBlue),
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 2),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          isExpanded: true,
                          isDense: true,
                          value: dropdownValue,
                          hint: Text(isIncome ? 'Sem conta' : 'Conta', style: const TextStyle(fontSize: 13)),
                          items: [
                            if (isIncome)
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
                                    Expanded(child: Text(a.displayName, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          onChanged: accounts.isEmpty && !isIncome ? null : onAccountChanged,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: InkWell(
                      onTap: onDateTap,
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Data',
                          isDense: true,
                          filled: true,
                          fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                          ),
                          contentPadding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.event_rounded, color: AppColors.deepBlue, size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${paymentDate.day.toString().padLeft(2, '0')}/${paymentDate.month.toString().padLeft(2, '0')}/${paymentDate.year}',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, size: 18, color: scheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettlementPills extends StatelessWidget {
  final bool isIncome;
  final bool isPending;
  final bool dense;
  final VoidCallback onSelectpaid;
  final VoidCallback onSelectPending;

  const _SettlementPills({
    required this.isIncome,
    required this.isPending,
    this.dense = false,
    required this.onSelectpaid,
    required this.onSelectPending,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Pill(
            label: isIncome ? 'Já cai' : 'Débito no saldo',
            subtitle: isIncome ? 'Saldo hoje' : 'Efetivo',
            active: !isPending,
            primaryColor: isIncome ? AppColors.success : AppColors.deepBlue,
            secondaryColor: isIncome ? const Color(0xFF0D9488) : AppColors.primary,
            dense: dense,
            onTap: onSelectpaid,
          ),
        ),
        SizedBox(width: dense ? 8 : 10),
        Expanded(
          child: _Pill(
            label: isIncome ? 'A receber' : 'Crédito (pend.)',
            subtitle: 'Pendente',
            active: isPending,
            primaryColor: AppColors.financePendente,
            secondaryColor: const Color(0xFFEA580C),
            dense: dense,
            onTap: onSelectPending,
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool active;
  final Color primaryColor;
  final Color secondaryColor;
  final bool dense;
  final VoidCallback onTap;

  const _Pill({
    required this.label,
    required this.subtitle,
    required this.active,
    required this.primaryColor,
    required this.secondaryColor,
    this.dense = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: EdgeInsets.symmetric(vertical: dense ? 9 : 14, horizontal: dense ? 6 : 8),
          constraints: BoxConstraints(minHeight: dense ? 44 : 50),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: active
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [primaryColor, secondaryColor],
                  )
                : null,
            color: active ? null : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: primaryColor.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
            border: Border.all(
              color: active
                  ? Colors.white.withValues(alpha: 0.35)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: dense ? 11 : 12,
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.white : theme.colorScheme.onSurface,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: dense ? 9.5 : 10,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white.withValues(alpha: 0.9) : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
