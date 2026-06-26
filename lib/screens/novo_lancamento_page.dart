import 'dart:async';

import 'package:flutter/material.dart' hide showDatePicker;
import '../widgets/fast_text_field.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../constants/currency_formats.dart';
import '../theme/app_colors.dart';
import '../utils/premium_upgrade.dart';
import '../services/user_categories_service.dart';
import '../services/finance_accounts_service.dart';
import '../services/finance_advanced_settings_service.dart';
import '../models/finance_account.dart';
import '../constants/finance_bank_presets.dart';
import '../constants/finance_account_visuals.dart';
import '../widgets/finance_bank_brand_thumb.dart';
import '../widgets/brl_amount_text_field.dart';
import '../utils/date_picker_a11y.dart';
import '../constants/finance_category_visuals.dart';
import '../widgets/finance_category_picker.dart';
import '../widgets/finance_quick_category_row.dart';
import '../constants/app_business_rules.dart';
import '../utils/keyboard_form_scaffold.dart';
import '../widgets/finance_premium_ui.dart';
import '../widgets/date_time_field.dart';
import '../utils/finance_transaction_datetime.dart';

class NovoLancamentoPage extends StatefulWidget {
  final String uid;
  final String initialType;
  final bool canAttachReceipt;
  /// Se false (licença vencida), bloqueia o salvamento mesmo se a página for aberta por outro caminho.
  final bool hasActiveLicense;

  const NovoLancamentoPage({
    super.key,
    required this.uid,
    required this.initialType,
    this.canAttachReceipt = true,
    this.hasActiveLicense = true,
  });

  @override
  State<NovoLancamentoPage> createState() => _NovoLancamentoPageState();
}

class _NovoLancamentoPageState extends State<NovoLancamentoPage> {
  bool _isIncome = true;
  bool _loadingCategories = true;
  List<String> _incomeCategories = [];
  List<String> _expenseCategories = [];
  bool _hasReceipt = false;
  String _receiptName = '';
  Uint8List? _receiptBytes;
  String? _receiptMime;

  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _amountFocus = FocusNode();
  final _descFocus = FocusNode();
  final _categoryCtrl = TextEditingController();
  final _installmentsCtrl = TextEditingController(text: '1');
  final _installmentStartCtrl = TextEditingController(text: '1');
  /// false = à vista (1 lançamento); true = parcelado (total de parcelas do plano + parcela inicial).
  bool _installmentMode = false;
  /// Com 2+ parcelas: [false] = valor digitado é o **total** do plano (÷ parcelas); [true] = valor de **cada** parcela.
  bool _installmentValueIsPerParcel = false;

  String _selectedCategory = '';
  String _status = 'paid';
  DateTime _date = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.fromDateTime(DateTime.now());
  /// null = saldo geral (sem conta vinculada).
  String? _selectedFinanceAccountId;

  /// Última descrição aplicada automaticamente (categoria + mês/ano). Se o usuário editar o campo, zera e não sobrescreve ao mudar só a data.
  String? _lastAutoDescription;
  bool _settingDescProgrammatically = false;
  Timer? _categoryCustomDebounce;

  static const List<String> _allowedExtensions = ['jpg', 'jpeg', 'png', 'pdf'];

  /// Evita recriar [ThemeData] a cada rebuild (teclado / viewInsets disparam muitos rebuilds).
  Brightness? _cachedThemeBrightness;
  ThemeData? _cachedDarkFormTheme;

  List<String> get _currentCategories =>
      _isIncome ? _incomeCategories : _expenseCategories;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final b = Theme.of(context).brightness;
    if (b != _cachedThemeBrightness) {
      _cachedThemeBrightness = b;
      if (b == Brightness.dark) {
        _cachedDarkFormTheme = ThemeData.light().copyWith(
          colorScheme: ThemeData.light().colorScheme.copyWith(
            primary: Theme.of(context).colorScheme.primary,
            surface: const Color(0xFFFAFAFA),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.grey.shade100,
            labelStyle: TextStyle(color: Colors.grey.shade800),
            hintStyle: TextStyle(color: Colors.grey.shade600),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
          ),
        );
      } else {
        _cachedDarkFormTheme = null;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _isIncome = widget.initialType == 'income';
    _descCtrl.addListener(_onDescriptionFieldChanged);
    _initCategoriesAndDefaultAccount();
    _installmentsCtrl.addListener(_syncPendingIfParcelado);
  }

  void _onDescriptionFieldChanged() {
    if (_settingDescProgrammatically) return;
    if (_descCtrl.text != _lastAutoDescription) {
      _lastAutoDescription = null;
    }
  }

  /// Rótulo do mês do lançamento (data escolhida), ex.: MAIO/2026.
  String _transactionMonthYearLabel(DateTime d) {
    final m = DateFormat('MMMM', 'pt_BR').format(d);
    return '${m.toUpperCase()}/${d.year}';
  }

  String _displayCategoryForDescription() {
    final incluirNova = UserCategoriesService.kIncluirNova;
    if (_selectedCategory == '__outra__') {
      return _categoryCtrl.text.trim();
    }
    if (_selectedCategory.isEmpty || _selectedCategory == incluirNova) {
      return '';
    }
    return _selectedCategory.trim();
  }

  void _setDescriptionProgrammatically(String text) {
    _settingDescProgrammatically = true;
    _descCtrl.text = text;
    _lastAutoDescription = text;
    _settingDescProgrammatically = false;
  }

  /// Descrição sugerida: [categoria ]MÊS/ANO conforme a data do lançamento.
  void _applyAutoDescriptionFromContext() {
    final label = _transactionMonthYearLabel(_date);
    final cat = _displayCategoryForDescription();
    final text = cat.isEmpty ? label : '$cat $label';
    _setDescriptionProgrammatically(text);
  }

  /// Parcelado com 2+ parcelas fica sempre pendente até confirmar no Financeiro.
  void _syncPendingIfParcelado() {
    final n = int.tryParse(_installmentsCtrl.text.trim()) ?? 1;
    if (_installmentMode && n > 1 && _status != 'pending' && mounted) {
      setState(() => _status = 'pending');
    }
  }

  Future<void> _initCategoriesAndDefaultAccount() async {
    final c = await UserCategoriesService().load(widget.uid);
    if (!mounted) return;
    setState(() {
      _incomeCategories = List<String>.from(c.income);
      _expenseCategories = List<String>.from(c.expense);
      final list = _isIncome ? c.income : c.expense;
      final incluirNova = UserCategoriesService.kIncluirNova;
      _selectedCategory = list.length > 1 && list.first == incluirNova
          ? list[1]
          : (list.isNotEmpty ? list.first : '__outra__');
      _categoryCtrl.text =
          _selectedCategory == '__outra__' || _selectedCategory == incluirNova ? '' : _selectedCategory;
      _loadingCategories = false;
    });
    _applyAutoDescriptionFromContext();

    final defId = await FinanceAdvancedSettingsService().getDefaultFinanceAccountId(widget.uid);
    final accounts = await FinanceAccountsService().listOnce(widget.uid);
    if (!mounted) return;

    String? pick;
    if (defId != null && accounts.any((a) => a.id == defId)) {
      pick = defId;
    } else if (!_isIncome && accounts.isNotEmpty) {
      pick = accounts.first.id;
    }

    setState(() {
      _selectedFinanceAccountId = pick;
      _applyStatusDefaultForAccount(accounts);
    });
  }

  /// Cartão de crédito: despesa com pagamento futuro → pendente. Conta/débito → pago.
  void _applyStatusDefaultForAccount(List<FinanceAccount> accounts) {
    if (_isIncome) return;
    final id = _selectedFinanceAccountId;
    if (id == null || id.isEmpty) return;
    FinanceAccount? acc;
    for (final a in accounts) {
      if (a.id == id) {
        acc = a;
        break;
      }
    }
    if (acc == null) return;
    if (acc.expenseDefaultsToPending) {
      _status = 'pending';
    } else if (acc.isDebitBankProduct) {
      _status = 'paid';
    }
  }

  void _onCategoryCustomChanged() {
    _categoryCustomDebounce?.cancel();
    _categoryCustomDebounce = Timer(
      const Duration(milliseconds: AppBusinessRules.searchDebounceMs),
      () {
        if (!mounted) return;
        if (_selectedCategory != '__outra__') return;
        final stillAuto =
            _lastAutoDescription != null && _descCtrl.text == _lastAutoDescription;
        if (stillAuto) _applyAutoDescriptionFromContext();
      },
    );
  }

  @override
  void dispose() {
    _categoryCustomDebounce?.cancel();
    _installmentsCtrl.removeListener(_syncPendingIfParcelado);
    _descCtrl.removeListener(_onDescriptionFieldChanged);
    _amountFocus.dispose();
    _descFocus.dispose();
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _categoryCtrl.dispose();
    _installmentsCtrl.dispose();
    _installmentStartCtrl.dispose();
    super.dispose();
  }

  String _amountFieldLabel() {
    if (!_installmentMode) return 'Valor do lançamento';
    final n = int.tryParse(_installmentsCtrl.text.trim()) ?? 1;
    if (n <= 1) return 'Valor do lançamento';
    return _installmentValueIsPerParcel ? 'Valor de cada parcela' : 'Valor total do plano (÷ $n parcelas)';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      final keepSync =
          _lastAutoDescription != null && _descCtrl.text == _lastAutoDescription;
      setState(() {
        _date = DateTime(picked.year, picked.month, picked.day);
      });
      if (keepSync) {
        _applyAutoDescriptionFromContext();
      }
    }
  }

  /// Seleção de comprovante: apenas JPEG, PNG e PDF. Retém bytes para envio ao Firebase.
  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedExtensions,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final f = result.files.single;
      final ext = (f.extension ?? '').toLowerCase().replaceAll('jpeg', 'jpg');
      final extOk = ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'pdf';
      if (!extOk) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Arquivo inválido. Use apenas JPEG, PNG ou PDF.')),
          );
        }
        return;
      }

      Uint8List? bytes = f.bytes;
      if (bytes == null || bytes.lengthInBytes == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Não foi possível ler o arquivo. Tente outro ou um tamanho menor.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }
      if (bytes.lengthInBytes > 5 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Arquivo grande demais. Limite: 5 MB.')),
          );
        }
        return;
      }

      final mime = ext == 'pdf' ? 'application/pdf' : (ext == 'png' ? 'image/png' : 'image/jpeg');
      setState(() {
        _hasReceipt = true;
        _receiptName = f.name;
        _receiptBytes = bytes;
        _receiptMime = mime;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Arquivo anexado: ${f.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao selecionar arquivo: ${e.toString().split('\n').first}')),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (!widget.hasActiveLicense) {
      mostrarAvisoLicencaVencida(context);
      return;
    }
    final amount = CurrencyFormats.parseBRLInput(_amountCtrl.text) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe um valor válido.')));
      return;
    }

    final incluirNova = UserCategoriesService.kIncluirNova;
    String categoryFinal = (_selectedCategory == '__outra__' || _selectedCategory == incluirNova)
        ? _categoryCtrl.text.trim()
        : _selectedCategory;
    if (categoryFinal.isEmpty) categoryFinal = _isIncome ? 'Receita' : 'Despesa';
    final installmentsTotal = _installmentMode
        ? (int.tryParse(_installmentsCtrl.text.trim()) ?? 12).clamp(1, 999)
        : 1;
    final startIdx = _installmentMode
        ? (int.tryParse(_installmentStartCtrl.text.trim()) ?? 1).clamp(1, installmentsTotal)
        : 1;

    // Só envia comprovante se tiver bytes válidos (evita erro no upload).
    final bool hasValidReceipt = _hasReceipt &&
        _receiptBytes != null &&
        _receiptBytes!.lengthInBytes > 0 &&
        _receiptName.isNotEmpty &&
        _receiptMime != null;

    var financeAid = (_selectedFinanceAccountId ?? '').trim();
    if (!_isIncome) {
      if (financeAid.isEmpty) {
        final list = await FinanceAccountsService().listOnce(widget.uid);
        if (list.isNotEmpty) financeAid = list.first.id;
      }
      if (financeAid.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cadastre uma conta em Financeiro → Bancos e cartões. Despesas exigem conta.')),
          );
        }
        return;
      }
    }

    final parceladoReal = _installmentMode && installmentsTotal > 1;
    final effectiveDate =
        FinanceTransactionDatetime.mergeCalendarDayWithTime(_date, _selectedTime);
    final Map<String, dynamic> result = {
      'type': _isIncome ? 'income' : 'expense',
      'amount': amount,
      'category': categoryFinal,
      'description': _descCtrl.text.trim(),
      'status': parceladoReal ? 'pending' : _status,
      'date': effectiveDate,
      'useExplicitTime': true,
      'recurrence': 'none',
      'installments': installmentsTotal,
      if (parceladoReal) 'installmentStartIndex': startIdx,
      if (parceladoReal && _installmentValueIsPerParcel) 'installmentValueIsPerParcel': true,
      if (_isIncome && financeAid.isNotEmpty) 'financeAccountId': financeAid,
      if (!_isIncome) 'financeAccountId': financeAid,
    };
    if (hasValidReceipt) {
      result['receipt'] = {
        'bytes': _receiptBytes,
        'name': _receiptName,
        'mime': _receiptMime,
      };
    }

    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveTheme = isDark ? _cachedDarkFormTheme : null;

    final mq = MediaQuery.of(context);
    final padBottom = KeyboardFormInsets.scrollBottomExtra(
      context,
      extra: 16,
      standaloneFullPageForm: true,
    );
    final fieldScrollPad = KeyboardFormInsets.fieldScrollPadding(
      context,
      standaloneFullPageForm: true,
    );
    final narrow = mq.size.width < 420;
    final amountFont = narrow ? 30.0 : 34.0;

    final scaffold = Scaffold(
      resizeToAvoidBottomInset:
          scaffoldKeyboardResizeToAvoidBottomInset(standaloneFullPageForm: true),
      backgroundColor: const Color(0xFFF1F5F9),
      extendBodyBehindAppBar: true,
      appBar: financePremiumGradientAppBar(
        title: 'Novo Lançamento',
        onBack: () => Navigator.maybePop(context),
        gradientColors: _isIncome
            ? const [Color(0xFF14532D), Color(0xFF15803D), Color(0xFF22C55E), AppColors.accent]
            : const [Color(0xFF7F1D1D), Color(0xFFB91C1C), Color(0xFFEF4444), AppColors.logoOrange],
        actions: [
          TextButton(
            onPressed: () => Navigator.maybePop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      bottomNavigationBar: _loadingCategories
          ? null
          : KeyboardAwareFormBar(
              standaloneFullPageForm: true,
              backgroundColor: isDark ? const Color(0xFFF5F5F5) : const Color(0xFFF8F9FA),
              child: FinancePremiumFormFooterActions(
                onCancel: () => Navigator.maybePop(context),
                onSave: _submit,
                saveLabel: 'Confirmar lançamento',
                saveIcon: Icons.check_rounded,
                accent: _isIncome ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
              ),
            ),
      body: keyboardScaffoldBody(
        standaloneFullPageForm: true,
        SafeArea(
        bottom: false,
        child: _loadingCategories
            ? const Center(child: CircularProgressIndicator())
            : RepaintBoundary(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16, 72, 16, padBottom),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
            _buildTypeToggle(),
            const SizedBox(height: 12),
            FinanceQuickCategoryRow(
              isIncome: _isIncome,
              currentCategory: _selectedCategory == '__outra__' ? '' : _selectedCategory,
              onPick: (preset) {
                final cur = _selectedCategory == '__outra__' ? '' : _selectedCategory;
                final same = cur.trim().toLowerCase() == preset.categoryName.trim().toLowerCase() &&
                    cur.isNotEmpty;
                if (same) {
                  _openFinanceCategoryPicker();
                  return;
                }
                setState(() {
                  _selectedCategory = preset.categoryName;
                  _categoryCtrl.text = preset.categoryName;
                });
                _applyAutoDescriptionFromContext();
              },
            ),
            const SizedBox(height: 12),
            ListenableBuilder(
              listenable: Listenable.merge([_installmentsCtrl, _installmentStartCtrl]),
              builder: (_, __) => Text(
                _amountFieldLabel(),
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 6),
            RepaintBoundary(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _isIncome
                        ? [
                            const Color(0xFFE8F5E9),
                            const Color(0xFFF1F8E9),
                          ]
                        : [
                            const Color(0xFFFFEBEE),
                            const Color(0xFFFFF3E0),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: (_isIncome ? const Color(0xFF2E7D32) : const Color(0xFFC62828))
                        .withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (_isIncome ? Colors.green : Colors.red).withValues(alpha: 0.12),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: BrlAmountTextField(
                  controller: _amountCtrl,
                  focusNode: _amountFocus,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _descFocus.requestFocus(),
                  scrollPadding: fieldScrollPad,
                  style: TextStyle(
                    fontSize: amountFont,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                    color: _isIncome ? const Color(0xFF1B5E20) : const Color(0xFFB71C1C),
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    prefixText: 'R\$ ',
                    prefixStyle: TextStyle(
                      fontSize: amountFont,
                      fontWeight: FontWeight.w900,
                      color: _isIncome ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F),
                    ),
                    border: InputBorder.none,
                    hintText: '0,00',
                    hintStyle: TextStyle(
                      fontSize: amountFont,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 16, thickness: 1),
            const SizedBox(height: 6),
            _buildPremiumCategorySelector(),
            const SizedBox(height: 10),
            _buildPremiumDescField(),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF1A237E).withValues(alpha: 0.12),
                        const Color(0xFF3949AB).withValues(alpha: 0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.account_balance_rounded, color: Color(0xFF1A237E), size: 22),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Conta',
                    style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1A237E), fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<FinanceAccount>>(
              stream: FinanceAccountsService().streamAccounts(widget.uid),
              builder: (context, snap) {
                final accounts = snap.data ?? [];
                if (accounts.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Text(
                      _isIncome
                          ? 'Cadastre uma conta em Financeiro (Bancos e cartões) para vincular. Receitas podem ser salvas sem conta; despesas exigem conta.'
                          : 'Cadastre ao menos uma conta corrente, poupança ou cartão em Financeiro → Bancos e cartões. Despesas exigem conta.',
                      style: const TextStyle(fontSize: 13, height: 1.35),
                    ),
                  );
                }
                final String? resolvedId = () {
                  if (_isIncome) {
                    final v = _selectedFinanceAccountId;
                    if (v == null || v.isEmpty) return null;
                    return accounts.any((a) => a.id == v) ? v : null;
                  }
                  final v = _selectedFinanceAccountId;
                  if (v != null && v.isNotEmpty && accounts.any((a) => a.id == v)) return v;
                  return accounts.first.id;
                }();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String?>(
                  key: ValueKey<String?>(resolvedId),
                  isExpanded: true,
                  initialValue: resolvedId,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(Icons.wallet_rounded, color: const Color(0xFF1A237E).withValues(alpha: 0.9), size: 26),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: const Color(0xFF1A237E).withValues(alpha: 0.2)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: const Color(0xFF1A237E).withValues(alpha: 0.18)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFF1A237E), width: 1.8),
                    ),
                    labelText: _isIncome ? 'Conta (opcional)' : 'Conta da despesa *',
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade800,
                      fontSize: 14,
                    ),
                  ),
                  items: [
                    if (_isIncome)
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Sem conta vinculada'),
                      ),
                    ...accounts.map((a) {
                      final vis = financeAccountVisualFor(a);
                      return DropdownMenuItem<String?>(
                        value: a.id,
                        child: Row(
                          children: [
                            _NovoLancamentoAccountBadge(account: a),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    a.displayName,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  Text(
                                    vis.badgeLabel,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: vis.isCreditCardStyle
                                          ? const Color(0xFF4F46E5)
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  onChanged: (v) => setState(() {
                    _selectedFinanceAccountId = v;
                    _applyStatusDefaultForAccount(accounts);
                  }),
                    ),
                    if (!_isIncome && resolvedId != null)
                      Builder(
                        builder: (context) {
                          FinanceAccount? acc;
                          for (final a in accounts) {
                            if (a.id == resolvedId) {
                              acc = a;
                              break;
                            }
                          }
                          if (acc == null || !acc.expenseDefaultsToPending) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline_rounded, size: 16, color: Colors.indigo.shade400),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Cartão de crédito: pagamento futuro — status Pendente aplicado automaticamente.',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      height: 1.35,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.indigo.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            ListenableBuilder(
              listenable: Listenable.merge([_installmentsCtrl, _installmentStartCtrl]),
              builder: (_, __) => _buildDateField(),
            ),
            const SizedBox(height: 10),
            _buildTimeField(),
            const SizedBox(height: 12),
            _buildStatusRecurrenceRow(),
            const SizedBox(height: 10),
            ListenableBuilder(
              listenable: Listenable.merge([_installmentsCtrl, _installmentStartCtrl]),
              builder: (_, __) => _buildInstallmentsField(),
            ),
            if (widget.canAttachReceipt) ...[
              const SizedBox(height: 18),
              const Text(
                'Comprovante (JPEG, PNG ou PDF)',
                style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A237E), fontSize: 14),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.canAttachReceipt
                    ? _pickFile
                    : () => mostrarAvisoUpgrade(context),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: !widget.canAttachReceipt
                          ? Colors.grey.shade300
                          : (_hasReceipt ? Colors.blue : Colors.blue.shade100),
                      width: 2,
                    ),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)],
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _hasReceipt ? Icons.check_circle_rounded : Icons.cloud_upload_outlined,
                        size: 40,
                        color: !widget.canAttachReceipt
                            ? Colors.grey
                            : (_hasReceipt ? Colors.green : Colors.blue.shade400),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _hasReceipt ? _receiptName : 'Clique para anexar comprovante',
                        style: TextStyle(
                          color: !widget.canAttachReceipt
                              ? Colors.grey
                              : (_hasReceipt ? Colors.blue.shade700 : Colors.grey),
                          fontWeight: _hasReceipt ? FontWeight.w600 : FontWeight.normal,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      ),
      ),
      ),
    );
    if (effectiveTheme != null) {
      return Theme(data: effectiveTheme, child: scaffold);
    }
    return scaffold;
  }

  Widget _buildTypeToggle() {
    return FinancePremiumTypeToggle(
      isIncome: _isIncome,
      onChanged: (income) {
        setState(() {
          _isIncome = income;
          final list = _currentCategories;
          final incluirNova = UserCategoriesService.kIncluirNova;
          _selectedCategory = list.length > 1 && list.first == incluirNova
              ? list[1]
              : (list.isNotEmpty ? list.first : '__outra__');
          _categoryCtrl.text =
              _selectedCategory == '__outra__' || _selectedCategory == incluirNova ? '' : _selectedCategory;
        });
        _applyAutoDescriptionFromContext();
      },
    );
  }

  Widget _buildCustomField(
    String label,
    IconData icon,
    TextEditingController? controller, {
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.sentences,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)],
      ),
      child: FastTextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        enableSuggestions: false,
        autocorrect: false,
        textCapitalization: textCapitalization,
        onChanged: onChanged,
        decoration: InputDecoration(
          icon: Icon(icon, color: AppColors.deepBlueDark, size: 22),
          labelText: label,
          hintText: hint,
          border: InputBorder.none,
          labelStyle: TextStyle(color: Colors.grey.shade600),
          hintStyle: TextStyle(color: Colors.grey.shade400),
        ),
      ),
    );
  }

  Widget _buildPremiumDescField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Descrição',
          style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey.shade800, fontSize: 12.5),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFFE3F2FD),
                Colors.white,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1565C0).withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1565C0).withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 10, bottom: 8),
                child: Tooltip(
                  message: 'Abrir lista de categorias',
                  child: FilledButton.tonal(
                    onPressed: _openFinanceCategoryPicker,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      foregroundColor: const Color(0xFF0D47A1),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.list_alt_rounded, size: 20),
                        SizedBox(width: 6),
                        Text('LISTA', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.3)),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 14),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF1565C0).withValues(alpha: 0.18),
                        const Color(0xFF1976D2).withValues(alpha: 0.12),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.edit_note_rounded, color: Color(0xFF0D47A1), size: 24),
                ),
              ),
              Expanded(
                child: FastTextField(
                  controller: _descCtrl,
                  focusNode: _descFocus,
                  scrollPadding: KeyboardFormInsets.fieldScrollPadding(
                    context,
                    standaloneFullPageForm: true,
                  ),
                  textInputAction: TextInputAction.done,
                  keyboardType: TextInputType.text,
                  enableSuggestions: false,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Detalhe do lançamento',
                    hintText: 'Padrão: categoria + mês do lançamento (ex.: Supermercado MAIO/2026). Edite se quiser.',
                    border: InputBorder.none,
                    labelStyle: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    contentPadding: const EdgeInsets.fromLTRB(8, 14, 14, 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openFinanceCategoryPicker() async {
    final picked = await showFinanceCategoryPicker(
      context: context,
      uid: widget.uid,
      isIncome: _isIncome,
      initialQuery: _selectedCategory == '__outra__'
          ? _categoryCtrl.text.trim()
          : (_selectedCategory.isEmpty ? '' : _selectedCategory),
    );
    if (picked == null || !mounted) return;
    if (picked != '__outra__') {
      final c = await UserCategoriesService().load(widget.uid);
      if (!mounted) return;
      setState(() {
        _incomeCategories = List<String>.from(c.income);
        _expenseCategories = List<String>.from(c.expense);
        _selectedCategory = picked;
        _categoryCtrl.text = picked;
      });
      _applyAutoDescriptionFromContext();
      return;
    }
    setState(() {
      _selectedCategory = '__outra__';
    });
    _applyAutoDescriptionFromContext();
  }

  Widget _buildPremiumCategorySelector() {
    final incluirNova = UserCategoriesService.kIncluirNova;
    final label = _selectedCategory == '__outra__'
        ? (_categoryCtrl.text.trim().isEmpty ? 'Outra — digite o nome abaixo' : _categoryCtrl.text.trim())
        : (_selectedCategory.isEmpty || _selectedCategory == incluirNova
            ? 'Escolher categoria'
            : _selectedCategory);
    final vis = (_selectedCategory.isNotEmpty &&
            _selectedCategory != '__outra__' &&
            _selectedCategory != incluirNova)
        ? financeCategoryVisualFor(_selectedCategory, isIncome: _isIncome)
        : financeCategoryVisualFor(
            _categoryCtrl.text.trim().isEmpty ? 'Outros' : _categoryCtrl.text.trim(),
            isIncome: _isIncome,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Categoria',
          style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey.shade800, fontSize: 12.5),
        ),
        const SizedBox(height: 5),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          elevation: 0,
          shadowColor: Colors.black26,
          child: InkWell(
            onTap: _openFinanceCategoryPicker,
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1A237E).withValues(alpha: 0.18)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3)),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: vis.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(vis.icon, color: vis.color, size: 21),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: Color(0xFF0F172A),
                          height: 1.2,
                        ),
                      ),
                    ),
                    if (_selectedCategory.isNotEmpty &&
                        _selectedCategory != '__outra__' &&
                        _selectedCategory != incluirNova)
                      IconButton(
                        tooltip: 'Limpar categoria',
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          foregroundColor: Colors.grey.shade600,
                          minimumSize: const Size(40, 40),
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedCategory = '';
                            _categoryCtrl.clear();
                          });
                          _applyAutoDescriptionFromContext();
                        },
                        icon: const Icon(Icons.backspace_outlined, size: 22),
                      ),
                    const Icon(Icons.unfold_more_rounded, color: Color(0xFF1A237E)),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_selectedCategory == '__outra__') ...[
          const SizedBox(height: 12),
          _buildCustomField(
            'Nome da categoria',
            Icons.category_outlined,
            _categoryCtrl,
            hint: 'Ex: Freelance',
            onChanged: (_) => _onCategoryCustomChanged(),
          ),
        ],
      ],
    );
  }

  Widget _buildDateField() {
    final installmentsTotal = (int.tryParse(_installmentsCtrl.text.trim()) ?? 1).clamp(1, 999);
    final isParcelado = _installmentMode && installmentsTotal > 1;
    final isToday = _date.year == DateTime.now().year &&
        _date.month == DateTime.now().month &&
        _date.day == DateTime.now().day;
    final dateLabel = isToday
        ? 'Hoje, ${DateFormat('d \'de\' MMM', 'pt_BR').format(_date)}'
        : DateFormat('d \'de\' MMM yyyy', 'pt_BR').format(_date);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isParcelado)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Data da 1ª parcela — o sistema calcula as demais (15/04, 15/05...). Retroativos e futuros ok.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Toque para escolher o dia (retroativo ou futuro).',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Informe também a hora abaixo (formato 24h).',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500, height: 1.35),
                ),
              ],
            ),
          ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _pickDate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFE0F2F1),
                  const Color(0xFFF1F8E9).withValues(alpha: 0.85),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF00897B).withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00897B).withValues(alpha: 0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF00897B).withValues(alpha: 0.9),
                        const Color(0xFF00695C),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00897B).withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Data do lançamento',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateLabel,
                        style: const TextStyle(
                          color: Color(0xFF004D40),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade500, size: 28),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE8EAF6).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3949AB).withValues(alpha: 0.25)),
      ),
      child: TimeFieldWithClockOrManual(
        label: 'Horário do lançamento',
        value: _selectedTime,
        onChanged: (t) => setState(() => _selectedTime = t),
      ),
    );
  }

  /// Dropdown de status: apenas Pendente ou Pago. Parcelado (2+ parcelas) fica **sempre pendente**.
  Widget _buildStatusRecurrenceRow() {
    return ListenableBuilder(
      listenable: _installmentsCtrl,
      builder: (context, _) {
        final n = (int.tryParse(_installmentsCtrl.text.trim()) ?? 1).clamp(1, 999);
        final parceladoPendente = _installmentMode && n > 1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF7E57C2).withValues(alpha: 0.15),
                        const Color(0xFFFFB74D).withValues(alpha: 0.12),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.flag_circle_rounded, color: Colors.deepPurple.shade700, size: 22),
                ),
                const SizedBox(width: 10),
                Text(
                  'Status do lançamento',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade800, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFFF8E1),
                    Colors.white,
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF9A825).withValues(alpha: 0.35)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: parceladoPendente
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.hourglass_top_rounded, color: Colors.orange.shade900, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Pendente (automático em parcelado)',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.grey.shade900),
                            ),
                          ),
                        ],
                      ),
                    )
                  : DropdownButtonFormField<String>(
                      key: ValueKey<String>(_status),
                      initialValue: _status,
                      decoration: InputDecoration(
                        filled: false,
                        border: InputBorder.none,
                        prefixIcon: Icon(
                          _status == 'paid' ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
                          color: _status == 'paid' ? Colors.green.shade700 : Colors.orange.shade800,
                          size: 28,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      ),
                      isExpanded: true,
                      items: [
                        DropdownMenuItem<String>(
                          value: 'paid',
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_rounded, color: Colors.green.shade700, size: 22),
                              const SizedBox(width: 10),
                              const Text('Pago', style: TextStyle(fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                        DropdownMenuItem<String>(
                          value: 'pending',
                          child: Row(
                            children: [
                              Icon(Icons.schedule_rounded, color: Colors.orange.shade800, size: 22),
                              const SizedBox(width: 10),
                              const Text('Pendente', style: TextStyle(fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _status = v ?? 'paid'),
                    ),
            ),
            if (parceladoPendente)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 2),
                child: Text(
                  'As parcelas aparecem nas listas de pendentes até você confirmar o pagamento/recebimento.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.35),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildInstallmentsField() {
    final n = (int.tryParse(_installmentsCtrl.text.trim()) ?? 1).clamp(1, 999);
    final start = (int.tryParse(_installmentStartCtrl.text.trim()) ?? 1).clamp(1, n);
    final geradas = _installmentMode && n > 1 ? (n - start + 1) : 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.payments_rounded, color: const Color(0xFF1A237E).withValues(alpha: 0.85), size: 22),
            const SizedBox(width: 8),
            Text(
              'À vista ou parcelado',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade800, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment<bool>(
              value: false,
              label: Text('À vista', style: TextStyle(fontWeight: FontWeight.w800)),
              icon: Icon(Icons.flash_on_rounded, size: 20),
            ),
            ButtonSegment<bool>(
              value: true,
              label: Text('Parcelado', style: TextStyle(fontWeight: FontWeight.w800)),
              icon: Icon(Icons.calendar_view_month_rounded, size: 20),
            ),
          ],
          selected: {_installmentMode},
          onSelectionChanged: (Set<bool> sel) {
            setState(() {
              _installmentMode = sel.first;
              if (_installmentMode) {
                if (_installmentsCtrl.text.trim() == '1' || _installmentsCtrl.text.trim().isEmpty) {
                  _installmentsCtrl.text = '12';
                }
                if (_installmentStartCtrl.text.trim().isEmpty) _installmentStartCtrl.text = '1';
                final nPar = int.tryParse(_installmentsCtrl.text.trim()) ?? 1;
                if (nPar > 1) _status = 'pending';
              } else {
                _installmentsCtrl.text = '1';
                _installmentStartCtrl.text = '1';
                _installmentValueIsPerParcel = false;
              }
            });
          },
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: const Color(0xFF1A237E),
            selectedForegroundColor: Colors.white,
            foregroundColor: const Color(0xFF1A237E),
            backgroundColor: Colors.white,
            side: BorderSide(color: const Color(0xFF1A237E).withValues(alpha: 0.35), width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
            textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
        ),
        if (_installmentMode) ...[
          const SizedBox(height: 16),
          _buildCustomField(
            'Total de parcelas (plano)',
            Icons.numbers_rounded,
            _installmentsCtrl,
            hint: '12',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textCapitalization: TextCapitalization.none,
          ),
          const SizedBox(height: 12),
          _buildCustomField(
            'Começar na parcela nº',
            Icons.play_arrow_rounded,
            _installmentStartCtrl,
            hint: '1',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textCapitalization: TextCapitalization.none,
          ),
          if (n > 1) ...[
            const SizedBox(height: 16),
            Text('O valor no topo é:', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  label: Text('Total a dividir'),
                  icon: Icon(Icons.pie_chart_outline_rounded, size: 16),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text('Cada parcela'),
                  icon: Icon(Icons.view_week_rounded, size: 16),
                ),
              ],
              selected: {_installmentValueIsPerParcel},
              onSelectionChanged: (Set<bool> s) => setState(() => _installmentValueIsPerParcel = s.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 10, horizontal: 6)),
              ),
            ),
          ],
        ],
        if (_installmentMode && n > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _installmentValueIsPerParcel
                  ? 'Cada lançamento usa o valor acima. Serão criados $geradas lançamento(s) (parcelas $start a $n). A data acima é a da parcela $start.'
                  : 'O total acima é dividido por $n; cada lançamento fica com a quota mensal. Serão criados $geradas lançamento(s) (parcelas $start a $n). A data acima é a da parcela $start.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.35),
            ),
          ),
      ],
    );
  }
}

class _NovoLancamentoAccountBadge extends StatelessWidget {
  final FinanceAccount account;

  const _NovoLancamentoAccountBadge({required this.account});

  @override
  Widget build(BuildContext context) {
    final vis = financeAccountVisualFor(account);
    final p = account.preset;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        gradient: LinearGradient(
          colors: vis.gradient.length >= 2 ? vis.gradient.sublist(0, 2) : vis.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: vis.isCreditCardStyle
              ? const Color(0xFFFBBF24).withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.35),
          width: vis.isCreditCardStyle ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: vis.gradient.first.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (vis.isCreditCardStyle) const FinanceCreditCardPattern(stripeColor: Color(0xFFFBBF24)),
          Center(
            child: p != null
                ? FinanceBankBrandThumb(
                    preset: p,
                    size: 28,
                    onBrandGradient: true,
                    fallbackIcon: vis.icon,
                  )
                : Icon(vis.icon, color: Colors.white, size: 20),
          ),
        ],
      ),
    );
  }
}
