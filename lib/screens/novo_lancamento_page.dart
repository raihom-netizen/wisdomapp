import 'dart:async';

import 'package:flutter/material.dart' hide showDatePicker;
import '../theme/theme_context.dart';
import '../widgets/despertar_item_card.dart';
import '../widgets/fast_text_field.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/currency_formats.dart';
import '../theme/app_colors.dart';
import '../utils/premium_upgrade.dart';
import '../services/user_categories_service.dart';
import '../services/finance_accounts_service.dart';
import '../services/finance_advanced_settings_service.dart';
import '../services/finance_month_cache.dart';
import '../services/finance_receipt_upload_service.dart';
import '../services/goal_deposit_service.dart';
import '../services/logs_service.dart';
import '../utils/finance_goal_tx_delete.dart';
import '../utils/finance_line_opening.dart';
import '../utils/finance_transaction_status_resolver.dart';
import '../utils/finance_transactions_hub.dart';
import '../utils/firestore_user_doc_id.dart';
import '../models/despertar_item.dart';
import '../models/finance_account.dart';
import '../widgets/fixed_flow_finance_account_field.dart';
import '../widgets/brl_amount_text_field.dart';
import '../utils/date_picker_a11y.dart';
import '../constants/finance_category_visuals.dart';
import '../widgets/finance_category_picker.dart';
import '../widgets/finance_quick_category_row.dart';
import '../constants/app_business_rules.dart';
import '../utils/keyboard_form_scaffold.dart';
import '../utils/finance_transaction_datetime.dart';
import '../widgets/modern_module_ui.dart';
import '../widgets/finance_premium_ui.dart';
import '../widgets/color_palette_tabs_dialog.dart';
import '../widgets/finance_calendar_color_picker.dart';
import '../services/transaction_save_service.dart';
import '../utils/receipt_attachment_utils.dart';

class NovoLancamentoPage extends StatefulWidget {
  final String uid;
  final String initialType;
  final bool canAttachReceipt;

  /// Se false (licença vencida), bloqueia o salvamento mesmo se a página for aberta por outro caminho.
  final bool hasActiveLicense;

  /// Se preenchido, a página entra em modo edição de um lançamento existente.
  final String? editingTransactionId;
  final Map<String, dynamic>? editingData;

  /// Botão "Duplicar": mesmos campos de um lançamento existente, mas a
  /// página continua em modo "novo" (cria um documento novo, sem botão
  /// excluir). Mesmo formato de [editingData]. Ignorado se
  /// [editingTransactionId] for informado.
  final Map<String, dynamic>? duplicateFromData;

  const NovoLancamentoPage({
    super.key,
    required this.uid,
    required this.initialType,
    this.canAttachReceipt = true,
    this.hasActiveLicense = true,
    this.editingTransactionId,
    this.editingData,
    this.duplicateFromData,
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

  /// No modo edição: indica que havia comprovante no Firestore (para exibir nome).
  bool _hasExistingReceipt = false;
  bool _removeExistingReceipt = false;

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

  /// null = saldo geral (sem conta vinculada).
  String? _selectedFinanceAccountId;

  /// Contas do usuário (cache) — usado para reaplicar o status padrão ao trocar a conta.
  List<FinanceAccount> _accounts = const [];

  /// Cor que o lançamento exibirá no calendário (hex, ex.: '#E53935'). Null = padrão (vermelho/verde).
  String? _calendarColorHex;

  /// Se true e o status for pendente, o lançamento aparece no calendário Agenda/Escala.
  /// Padrão: DESLIGADO (regra do dono 01/10/2026) — a pessoa liga se quiser.
  bool _addToCalendar = false;

  /// «Despertar» da conta PENDENTE (padrão desligado): o aviso de vencimento
  /// chega como despertador. Paga não desperta.
  DespertarItem _despertar = DespertarItem.desligado;

  /// Última descrição aplicada automaticamente (categoria + mês/ano). Se o usuário editar o campo, zera e não sobrescreve ao mudar só a data.
  String? _lastAutoDescription;
  bool _settingDescProgrammatically = false;
  Timer? _categoryCustomDebounce;

  bool get _isEditing =>
      widget.editingTransactionId != null && widget.editingData != null;

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

  void _loadEditingData(Map<String, dynamic> d) {
    _isIncome = (d['type'] ?? 'expense').toString() == 'income';
    final amount = (d['amount'] as num?)?.toDouble() ?? 0;
    _amountCtrl.text = CurrencyFormats.formatBRLInput(amount);
    _descCtrl.text = (d['description'] ?? '').toString();
    _status = (d['status'] ?? 'paid').toString();
    final dateTs = d['date'];
    if (dateTs is Timestamp) {
      _date = dateTs.toDate();
    } else if (dateTs is DateTime) {
      _date = dateTs;
    }
    _selectedFinanceAccountId = (d['financeAccountId'] ?? '').toString().trim();
    if (_selectedFinanceAccountId!.isEmpty) _selectedFinanceAccountId = null;
    _calendarColorHex = d['calendarColorHex']?.toString();
    final st = (d['status'] ?? 'paid').toString();
    // Reflete o gravado: só ligado com opt-in explícito (ausente = desligado).
    _addToCalendar =
        st == 'pending' && FinanceCalendarColorPicker.calendarioLigado(d);
    _despertar = DespertarItem.doDocumento(d);

    final receipt = Map<String, dynamic>.from(d['receipt'] ?? {});
    final receiptName = (receipt['name'] ?? '').toString();
    _hasExistingReceipt = receiptName.isNotEmpty;
    _hasReceipt = _hasExistingReceipt;
    _receiptName = receiptName;
    _receiptBytes = null;
    _receiptMime = null;
    _removeExistingReceipt = false;

    final currentCat = (d['category'] ?? '').toString().trim();
    final list = _isIncome ? _incomeCategories : _expenseCategories;
    final incluirNova = UserCategoriesService.kIncluirNova;
    final match =
        list.where((c) => c.toLowerCase() == currentCat.toLowerCase()).toList();
    if (currentCat.isNotEmpty && match.isNotEmpty) {
      _selectedCategory = match.first;
      _categoryCtrl.text = _selectedCategory;
    } else if (currentCat.isNotEmpty) {
      _selectedCategory = '__outra__';
      _categoryCtrl.text = currentCat;
    } else {
      _selectedCategory = list.length > 1 && list.first == incluirNova
          ? list[1]
          : (list.isNotEmpty ? list.first : '__outra__');
      _categoryCtrl.text =
          _selectedCategory == '__outra__' || _selectedCategory == incluirNova
              ? ''
              : _selectedCategory;
    }

    final installments = (d['installments'] as num?)?.toInt() ?? 1;
    _installmentMode = installments > 1;
    _installmentsCtrl.text = installments.clamp(1, 999).toString();
    final startIdx = (d['installmentStartIndex'] as num?)?.toInt() ?? 1;
    _installmentStartCtrl.text = startIdx.clamp(1, installments).toString();
    _installmentValueIsPerParcel = d['installmentValueIsPerParcel'] == true;
  }

  Future<void> _initCategoriesAndDefaultAccount() async {
    final isEditing =
        widget.editingTransactionId != null && widget.editingData != null;
    final precisaDaLista = isEditing || widget.duplicateFromData != null;
    // Lançamento NOVO não espera as categorias (WISDOMAPP ebf13c4, 02/10/2026):
    // começa em «Escolher categoria» e o seletor relê a lista ao abrir —
    // esperar a leitura deixava a tela em spinner para sempre na Web quando o
    // Firestore demorava. Editar/duplicar precisa da lista para casar a
    // categoria gravada, então espera no máximo 4 s (sem ela, a categoria
    // aparece como «Outra» com o nome gravado — nada se perde).
    final loadFuture = UserCategoriesService().load(widget.uid);
    ({List<String> income, List<String> expense})? c;
    if (precisaDaLista) {
      try {
        final r = await loadFuture.timeout(const Duration(seconds: 4));
        c = (income: List<String>.from(r.income), expense: List<String>.from(r.expense));
      } catch (e) {
        debugPrint('NovoLancamentoPage: categorias não carregaram: $e');
      }
    } else {
      unawaited(loadFuture.then<void>((_) {}, onError: (Object e) {
        debugPrint('NovoLancamentoPage: categorias não carregaram: $e');
      }));
    }
    if (!mounted) return;
    setState(() {
      if (c != null) {
        _incomeCategories = c.income;
        _expenseCategories = c.expense;
      }
      if (isEditing) {
        _loadEditingData(widget.editingData!);
      } else if (widget.duplicateFromData != null) {
        _loadEditingData(widget.duplicateFromData!);
        // Comprovante pertence ao lançamento original — não copia a
        // referência; o usuário anexa de novo se precisar.
        _hasExistingReceipt = false;
        _hasReceipt = false;
        _receiptName = '';
      } else {
        // Lançamento novo começa em «Escolher categoria» (pedido do dono,
        // 30/09/2026): antes vinha a 1ª da lista (Alimentação) e o gasto
        // entrava na categoria errada quando a pessoa não trocava.
        _selectedCategory = '';
        _categoryCtrl.text = '';
        _applyAutoDescriptionFromContext();
      }
      _loadingCategories = false;
    });

    final accounts = await FinanceAccountsService().listOnce(widget.uid);
    if (!mounted) return;
    _accounts = accounts;

    if (isEditing) {
      // Mantém conta carregada; se não existir mais, o dropdown mostrará vínculo antigo.
      setState(() {});
    } else {
      final defId = await FinanceAdvancedSettingsService()
          .getDefaultFinanceAccountId(widget.uid);
      String? pick;
      if (defId != null && accounts.any((a) => a.id == defId)) {
        pick = defId;
      } else if (accounts.isNotEmpty) {
        // Receita também já abre com uma conta — como as fixas fazem. Sem
        // conta, a receita não entra no saldo de banco nenhum e o «Receber
        // via Pix» não sabe de qual chave gerar o QR. O usuário troca se
        // precisar.
        // O cofre (reserva) não é conta de movimento: fica por último.
        final movimento = accounts.where((a) => !a.isVaultProduct).toList();
        pick = (movimento.isNotEmpty ? movimento : accounts).first.id;
      }
      setState(() {
        _selectedFinanceAccountId = pick;
        _applyStatusDefaultForAccount(accounts);
      });
    }
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
        final stillAuto = _lastAutoDescription != null &&
            _descCtrl.text == _lastAutoDescription;
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

  /// Copia o conteúdo inteiro do campo — mesmo botão usado em outros
  /// formulários do app, não depende de selecionar texto na mão (toque e
  /// segure no iPhone).
  Future<void> _copyWholeField(TextEditingController ctrl) async {
    final text = ctrl.text;
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Copiado.'), duration: Duration(seconds: 1)),
      );
    }
  }

  String _amountFieldLabel() {
    if (!_installmentMode) return 'Valor do lançamento';
    final n = int.tryParse(_installmentsCtrl.text.trim()) ?? 1;
    if (n <= 1) return 'Valor do lançamento';
    return _installmentValueIsPerParcel
        ? 'Valor de cada parcela'
        : 'Valor total do plano (÷ $n parcelas)';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      final keepSync = _lastAutoDescription != null &&
          _descCtrl.text == _lastAutoDescription;
      setState(() {
        _date = FinanceTransactionDatetime.mergeCalendarDayWithExistingTime(
          picked,
          _date,
        );
      });
      if (keepSync) {
        _applyAutoDescriptionFromContext();
      }
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _date.hour, minute: _date.minute),
      helpText: 'Horário do lançamento',
      hourLabelText: 'Hora',
      minuteLabelText: 'Minuto',
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked == null) return;
    setState(() {
      _date = FinanceTransactionDatetime.mergeCalendarDayWithTimeOfDay(
        _date,
        picked.hour,
        picked.minute,
      );
    });
  }

  /// Seleção de comprovante: câmera, galeria ou PDF/imagem (JPEG, PNG, PDF;
  /// até 5 MB) — utilitário do WISDOMAPP. Retém bytes para envio ao Firebase.
  Future<void> _pickFile() async {
    final picked = await ReceiptAttachmentUtils.pickValidated(context);
    if (picked == null || !mounted) return;
    setState(() {
      _hasReceipt = true;
      _hasExistingReceipt = false;
      _removeExistingReceipt = false;
      _receiptName = picked.name;
      _receiptBytes = picked.bytes;
      _receiptMime = picked.mime;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Arquivo anexado: ${picked.name}')),
    );
  }

  Future<void> _submit() async {
    if (!widget.hasActiveLicense) {
      mostrarAvisoLicencaVencida(context);
      return;
    }
    final amount = CurrencyFormats.parseBRLInput(_amountCtrl.text) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe um valor válido.')));
      return;
    }

    final incluirNova = UserCategoriesService.kIncluirNova;
    String categoryFinal =
        (_selectedCategory == '__outra__' || _selectedCategory == incluirNova)
            ? _categoryCtrl.text.trim()
            : _selectedCategory;
    // Sem categoria escolhida: pede a escolha (abre a lista) em vez de gravar
    // como «Despesa»/«Receita» genérica. Na edição de um lançamento antigo
    // sem categoria, mantém o comportamento de antes.
    if (categoryFinal.isEmpty && !_isEditing) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Escolha a categoria do lançamento.')));
      await _openFinanceCategoryPicker();
      return;
    }
    if (categoryFinal.isEmpty) {
      categoryFinal = _isIncome ? 'Receita' : 'Despesa';
    }

    var financeAid = (_selectedFinanceAccountId ?? '').trim();
    // Conta não é mais obrigatória — lança sem vínculo se não houver.
    if (financeAid.isEmpty && !_isIncome) {
      final list = await FinanceAccountsService().listOnce(widget.uid);
      if (list.isNotEmpty) financeAid = list.first.id;
    }

    if (_isEditing) {
      await _updateEditingTransaction(
        amount: amount,
        categoryFinal: categoryFinal,
        financeAid: financeAid,
      );
      return;
    }

    final installmentsTotal = _installmentMode
        ? (int.tryParse(_installmentsCtrl.text.trim()) ?? 12).clamp(1, 999)
        : 1;
    final startIdx = _installmentMode
        ? (int.tryParse(_installmentStartCtrl.text.trim()) ?? 1)
            .clamp(1, installmentsTotal)
        : 1;

    // Só envia comprovante se tiver bytes válidos (evita erro no upload).
    final bool hasValidReceipt = _hasReceipt &&
        _receiptBytes != null &&
        _receiptBytes!.lengthInBytes > 0 &&
        _receiptName.isNotEmpty &&
        _receiptMime != null;

    final parceladoReal = _installmentMode && installmentsTotal > 1;
    final Map<String, dynamic> result = {
      'type': _isIncome ? 'income' : 'expense',
      'amount': amount,
      'category': categoryFinal,
      'description': _descCtrl.text.trim(),
      'status': parceladoReal ? 'pending' : _status,
      'date': _date,
      // O horário escolhido na tela vale (sem trocar pelo relógio ao salvar).
      'useExplicitTime': true,
      'recurrence': 'none',
      'installments': installmentsTotal,
      if (parceladoReal) 'installmentStartIndex': startIdx,
      if (parceladoReal && _installmentValueIsPerParcel)
        'installmentValueIsPerParcel': true,
      if (_isIncome && financeAid.isNotEmpty) 'financeAccountId': financeAid,
      if (!_isIncome) 'financeAccountId': financeAid,
      'addToCalendar': _status == 'pending' && _addToCalendar,
      'hideFromCalendar': _status == 'pending' && !_addToCalendar,
      if (_status == 'pending' &&
          _addToCalendar &&
          _calendarColorHex != null &&
          _calendarColorHex!.isNotEmpty)
        'calendarColorHex': _calendarColorHex,
      if (parceladoReal || _status == 'pending') ..._despertar.campos,
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

  /// Atualiza o lançamento existente no Firestore (modo edição full-screen).
  Future<void> _updateEditingTransaction({
    required double amount,
    required String categoryFinal,
    required String financeAid,
  }) async {
    final docId = widget.editingTransactionId!;
    final current = widget.editingData!;

    final dateWithoutSeconds = FinanceTransactionDatetime.withoutSeconds(_date);
    final resolvedStatus = FinanceTransactionStatusResolver.resolveByDateTime(
      dateWithoutSeconds,
      preferredStatus: _status,
      respeitarPendente: true,
    );
    final paidForEffective = resolvedStatus == 'paid'
        ? (current['paidAt'] is Timestamp
            ? current['paidAt'] as Timestamp
            : FinanceTransactionStatusResolver.paidAtForAutoPaid(
                dateWithoutSeconds))
        : null;

    final updateData = <String, dynamic>{
      'amount': amount,
      'category': categoryFinal,
      'description': _descCtrl.text.trim(),
      'status': resolvedStatus,
      'date': Timestamp.fromDate(dateWithoutSeconds),
      'updatedAt': FieldValue.serverTimestamp(),
      'effectiveDate': FinanceLineOpening.effectiveTimestampForWrite(
        date: dateWithoutSeconds,
        paidAt: paidForEffective,
      ),
    };

    if (financeAid.isEmpty) {
      updateData['financeAccountId'] = FieldValue.delete();
    } else {
      updateData['financeAccountId'] = financeAid;
    }


    updateData['addToCalendar'] = _status == 'pending' && _addToCalendar;
    updateData['hideFromCalendar'] = _status == 'pending' && !_addToCalendar;
    if (_status == 'pending') updateData.addAll(_despertar.campos);
    if (_status == 'pending' &&
        _addToCalendar &&
        _calendarColorHex != null &&
        _calendarColorHex!.isNotEmpty) {
      updateData['calendarColorHex'] = _calendarColorHex;
    } else {
      updateData['calendarColorHex'] = FieldValue.delete();
    }

    try {
      if (widget.canAttachReceipt) {
        if (_removeExistingReceipt) {
          updateData['receipt'] = FieldValue.delete();
          updateData['hasReceipt'] = false;
        } else if (_receiptBytes != null &&
            _receiptBytes!.isNotEmpty &&
            _receiptName.isNotEmpty &&
            _receiptMime != null) {
          await FinanceReceiptUploadService.attachToTransaction(
            uid: widget.uid,
            txDocId: docId,
            bytes: _receiptBytes!,
            filename: _receiptName,
            mimeType: _receiptMime!,
            context: context,
          );
          updateData['hasReceipt'] = true;
        }
      }

      // Local primeiro (padrão WISDOMAPP): vale no cache na hora; não espera o
      // servidor confirmar para fechar. Sem Finance Pro: nada de «controle».
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      await TransactionSaveService.writeLocalFirst(
        () => FirebaseFirestore.instance
            .collection('users')
            .doc(firestoreUserDocIdForAppShell(widget.uid))
            .collection('transactions')
            .doc(docId)
            .update(updateData),
        messenger: messenger,
        failureMessage: 'Não foi possível sincronizar a edição',
      );

      final goalId = (current['goalId'] ?? '').toString().trim();
      if (goalId.isNotEmpty && _isIncome) {
        unawaited(
          GoalDepositService.syncFromTransaction(
            uid: widget.uid,
            goalId: goalId,
            txId: docId,
            amount: amount,
            date: dateWithoutSeconds,
            financeAccountId: financeAid.isEmpty ? null : financeAid,
          ).catchError((_) {}),
        );
      }

      unawaited(
        LogsService()
            .saveLog(
              modulo: 'Agenda/Escala',
              acao: _isIncome ? 'Editou receita' : 'Editou despesa',
              detalhes: '$categoryFinal • ${CurrencyFormats.formatBRL(amount)}',
            )
            .catchError((_) {}),
      );

      FinanceMonthCache.clearUid(widget.uid);
      FinanceTransactionsHub.notifyMutated(uid: widget.uid);

      if (mounted) {
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Lançamento atualizado.')));
        Navigator.of(context).pop(true);
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Erro ao atualizar: ${err.toString().split('\n').first}'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  /// Confirma e executa a exclusão do lançamento em edição.
  Future<void> _confirmDeleteEditing() async {
    final current = widget.editingData!;
    final metaInfo = await GoalDepositService.linkedInfoForTransaction(
      uid: widget.uid,
      txId: widget.editingTransactionId!,
      txData: current,
    );
    if (!mounted) return;
    final confirmed = await confirmFinanceTransactionDelete(
      context: context,
      metaInfo: metaInfo,
    );
    if (confirmed != true || !mounted) return;

    try {
      final txCol = FirebaseFirestore.instance
          .collection('users')
          .doc(firestoreUserDocIdForAppShell(widget.uid))
          .collection('transactions');
      await deleteFinanceTransactionRecord(
        uid: widget.uid,
        docId: widget.editingTransactionId!,
        txData: current,
        txCol: txCol,
      );

      final typeLog = (current['type'] ?? 'expense').toString();
      final amountLog = (current['amount'] ?? 0).toDouble();
      final categoryLog = (current['category'] ?? '').toString();

      unawaited(
        LogsService()
            .saveLog(
              modulo: 'Agenda/Escala',
              acao: typeLog == 'income' ? 'Excluiu receita' : 'Excluiu despesa',
              detalhes:
                  '${categoryLog.isEmpty ? 'Categoria' : categoryLog} • ${CurrencyFormats.formatBRL(amountLog)}',
            )
            .catchError((_) {}),
      );

      FinanceMonthCache.clearUid(widget.uid);
      FinanceTransactionsHub.notifyMutated(uid: widget.uid);

      if (mounted) {
        final extra = metaInfo?.hasWeeksImpact == true
            ? ' Semanas da meta atualizadas.'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lançamento excluído.$extra')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao excluir: ${err.toString().split('\n').first}'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
      resizeToAvoidBottomInset: scaffoldKeyboardResizeToAvoidBottomInset(
          standaloneFullPageForm: true),
      backgroundColor: ModernModuleUI.scaffoldBgOf(context),
      extendBodyBehindAppBar: true,
      appBar: financePremiumGradientAppBar(
        title: _isEditing ? 'Editar Lançamento' : 'Novo Lançamento',
        onBack: () => Navigator.maybePop(context),
        gradientColors: _isIncome
            ? const [
                Color(0xFF14532D),
                Color(0xFF15803D),
                Color(0xFF22C55E),
                AppColors.accent
              ]
            : const [
                Color(0xFF7F1D1D),
                Color(0xFFDC2626),
                Color(0xFFEF4444),
                AppColors.logoOrange
              ],
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Excluir lançamento',
              onPressed: _confirmDeleteEditing,
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Colors.white, size: 24),
            ),
          TextButton(
            onPressed: () => Navigator.maybePop(context),
            child: Text('Cancelar',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      bottomNavigationBar: _loadingCategories
          ? null
          : KeyboardAwareFormBar(
              standaloneFullPageForm: true,
              backgroundColor: context.appScaffold,
              child: FinancePremiumFormFooterActions(
                onCancel: () => Navigator.maybePop(context),
                onSave: _submit,
                saveLabel:
                    _isEditing ? 'Salvar alterações' : 'Confirmar lançamento',
                saveIcon: Icons.check_rounded,
                accent: _isIncome
                    ? const Color(0xFF15803D)
                    : const Color(0xFFDC2626),
              ),
            ),
      body: keyboardScaffoldBody(
        standaloneFullPageForm: true,
        SafeArea(
          bottom: false,
          child: _loadingCategories
              ? Center(child: CircularProgressIndicator())
              : RepaintBoundary(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(16, 72, 16, padBottom),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTypeToggle(),
                        SizedBox(height: 12),
                        FinanceQuickCategoryRow(
                          isIncome: _isIncome,
                          currentCategory: _selectedCategory == '__outra__'
                              ? ''
                              : _selectedCategory,
                          onPick: (preset) {
                            final cur = _selectedCategory == '__outra__'
                                ? ''
                                : _selectedCategory;
                            final same = cur.trim().toLowerCase() ==
                                    preset.categoryName.trim().toLowerCase() &&
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
                        SizedBox(height: 12),
                        ListenableBuilder(
                          listenable: Listenable.merge(
                              [_installmentsCtrl, _installmentStartCtrl]),
                          builder: (_, __) => Text(
                            _amountFieldLabel(),
                            style: TextStyle(
                                color: context.appTextSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        SizedBox(height: 6),
                        RepaintBoundary(
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: context.isDarkMode
                                    ? [
                                        (_isIncome
                                                ? const Color(0xFF14532D)
                                                : const Color(0xFF7F1D1D))
                                            .withValues(alpha: 0.55),
                                        context.appSurfaceHigh,
                                      ]
                                    : _isIncome
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
                                color: (_isIncome
                                        ? const Color(0xFF16A34A)
                                        : const Color(0xFFC62828))
                                    .withValues(
                                        alpha:
                                            context.isDarkMode ? 0.72 : 0.35),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (_isIncome ? Colors.green : Colors.red)
                                      .withValues(
                                          alpha:
                                              context.isDarkMode ? 0.22 : 0.12),
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
                                color: _isIncome
                                    ? (context.isDarkMode
                                        ? const Color(0xFF86EFAC)
                                        : const Color(0xFF1B5E20))
                                    : (context.isDarkMode
                                        ? const Color(0xFFFCA5A5)
                                        : const Color(0xFFB71C1C)),
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                prefixText: 'R\$ ',
                                prefixStyle: TextStyle(
                                  fontSize: amountFont,
                                  fontWeight: FontWeight.w900,
                                  color: _isIncome
                                      ? (context.isDarkMode
                                          ? const Color(0xFF4ADE80)
                                          : const Color(0xFF16A34A))
                                      : (context.isDarkMode
                                          ? const Color(0xFFF87171)
                                          : const Color(0xFFD32F2F)),
                                ),
                                border: InputBorder.none,
                                hintText: '0,00',
                                hintStyle: TextStyle(
                                  fontSize: amountFont,
                                  fontWeight: FontWeight.bold,
                                  color: context.appTextMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Divider(height: 16, thickness: 1),
                        SizedBox(height: 6),
                        _buildPremiumCategorySelector(),
                        SizedBox(height: 10),
                        _buildPremiumDescField(),
                        SizedBox(height: 12),
                        Text(
                          'Conta',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: context.appTextPrimary,
                              fontSize: 12.5),
                        ),
                        SizedBox(height: 6),
                        FixedFlowFinanceAccountField(
                          uid: widget.uid,
                          selectedAccountId: _selectedFinanceAccountId,
                          onChanged: (v) => setState(() {
                            _selectedFinanceAccountId = v;
                            _applyStatusDefaultForAccount(_accounts);
                          }),
                        ),
                        SizedBox(height: 10),
                        ListenableBuilder(
                          listenable: Listenable.merge(
                              [_installmentsCtrl, _installmentStartCtrl]),
                          builder: (_, __) => _buildDateField(),
                        ),
                        SizedBox(height: 12),
                        _buildStatusRecurrenceRow(),
                        SizedBox(height: 10),
                        ListenableBuilder(
                          listenable: Listenable.merge(
                              [_installmentsCtrl, _installmentStartCtrl]),
                          builder: (_, __) => _buildInstallmentsField(),
                        ),
                        if (_status == 'pending') ...[
                          SizedBox(height: 14),
                          DespertarItemCard(
                            value: _despertar,
                            descricaoItem: _isIncome
                                ? 'esta conta a receber (enquanto pendente)'
                                : 'esta conta a pagar (enquanto pendente)',
                            onChanged: (v) => setState(() => _despertar = v),
                          ),
                          SizedBox(height: 14),
                          _buildAddToCalendarToggle(),
                          if (_addToCalendar) ...[
                            SizedBox(height: 10),
                            _buildCalendarColorRow(),
                          ],
                        ],
                        if (widget.canAttachReceipt) ...[
                          SizedBox(height: 18),
                          Text(
                            'Comprovante (JPEG, PNG ou PDF)',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: context.appDeepTitle,
                                fontSize: 14),
                          ),
                          SizedBox(height: 8),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.canAttachReceipt
                                ? _pickFile
                                : () => mostrarAvisoUpgrade(context),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              decoration:
                                  context.appPanelDecoration(radius: 16),
                              child: Stack(
                                children: [
                                  Column(
                                    children: [
                                      Icon(
                                        _hasReceipt
                                            ? Icons.check_circle_rounded
                                            : Icons.cloud_upload_outlined,
                                        size: 40,
                                        color: !widget.canAttachReceipt
                                            ? Colors.grey
                                            : (_hasReceipt
                                                ? Colors.green
                                                : Colors.blue.shade400),
                                      ),
                                      SizedBox(height: 10),
                                      Text(
                                        _hasReceipt
                                            ? _receiptName
                                            : 'Clique para anexar comprovante',
                                        style: TextStyle(
                                          color: !widget.canAttachReceipt
                                              ? Colors.grey
                                              : (_hasReceipt
                                                  ? Colors.blue.shade700
                                                  : Colors.grey),
                                          fontWeight: _hasReceipt
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                          fontSize: 14,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                  if (_hasExistingReceipt)
                                    Positioned(
                                      top: 0,
                                      right: 0,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => setState(() {
                                          _removeExistingReceipt = true;
                                          _hasExistingReceipt = false;
                                          _hasReceipt = false;
                                          _receiptName = '';
                                          _receiptBytes = null;
                                          _receiptMime = null;
                                        }),
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFEF4444),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.close_rounded,
                                              color: Colors.white, size: 16),
                                        ),
                                      ),
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
    return scaffold;
  }

  Widget _buildTypeToggle() {
    return FinancePremiumTypeToggle(
      isIncome: _isIncome,
      onChanged: (income) {
        setState(() {
          _isIncome = income;
          // Trocou Receita/Despesa: a categoria volta para «Escolher
          // categoria» (a lista é outra; nada de pré-selecionar a 1ª).
          _selectedCategory = '';
          _categoryCtrl.text = '';
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
    bool showCopyButton = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: context.appPanelDecoration(radius: 14),
      child: FastTextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        enableSuggestions: false,
        autocorrect: false,
        textCapitalization: textCapitalization,
        onChanged: onChanged,
        decoration: InputDecoration(
          icon: Icon(icon,
              color: context.isDarkMode
                  ? context.appTextSecondary
                  : AppColors.deepBlueDark,
              size: 22),
          labelText: label,
          hintText: hint,
          border: InputBorder.none,
          labelStyle: TextStyle(color: context.appTextSecondary),
          hintStyle: TextStyle(color: Colors.grey.shade400),
          suffixIcon: (showCopyButton && controller != null)
              ? IconButton(
                  tooltip: 'Copiar',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  color: AppColors.primary,
                  onPressed: () => _copyWholeField(controller),
                  splashRadius: 22,
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                )
              : null,
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
          style: TextStyle(
              fontWeight: FontWeight.w700,
              color: context.appTextPrimary,
              fontSize: 12.5),
        ),
        SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: context.isDarkMode
                  ? [
                      context.appDarkModuleSurface,
                      context.appSurfaceHigh,
                    ]
                  : [
                      const Color(0xFFE3F2FD),
                      Colors.white,
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: const Color(0xFF2563EB).withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2563EB).withValues(alpha: 0.08),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      foregroundColor: context.isDarkMode
                          ? const Color(0xFF93C5FD)
                          : const Color(0xFF0D47A1),
                      backgroundColor: context.isDarkMode
                          ? const Color(0xFF2563EB).withValues(alpha: 0.22)
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.list_alt_rounded, size: 20),
                        SizedBox(width: 6),
                        Text('LISTA',
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                                letterSpacing: 0.3)),
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
                        const Color(0xFF2563EB).withValues(alpha: 0.18),
                        const Color(0xFF1976D2).withValues(alpha: 0.12),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.edit_note_rounded,
                      color: context.isDarkMode
                          ? const Color(0xFF93C5FD)
                          : const Color(0xFF0D47A1),
                      size: 24),
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
                    hintText:
                        'Padrão: categoria + mês do lançamento (ex.: Supermercado MAIO/2026). Edite se quiser.',
                    border: InputBorder.none,
                    labelStyle: TextStyle(
                        color: context.appTextSecondary,
                        fontWeight: FontWeight.w600),
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    contentPadding: const EdgeInsets.fromLTRB(8, 14, 14, 14),
                    suffixIcon: IconButton(
                      tooltip: 'Copiar',
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      color: AppColors.primary,
                      onPressed: () => _copyWholeField(_descCtrl),
                      splashRadius: 22,
                      constraints:
                          const BoxConstraints(minWidth: 44, minHeight: 44),
                    ),
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
        ? (_categoryCtrl.text.trim().isEmpty
            ? 'Outra — digite o nome abaixo'
            : _categoryCtrl.text.trim())
        : (_selectedCategory.isEmpty || _selectedCategory == incluirNova
            ? 'Escolher categoria'
            : _selectedCategory);
    final vis = (_selectedCategory.isNotEmpty &&
            _selectedCategory != '__outra__' &&
            _selectedCategory != incluirNova)
        ? financeCategoryVisualFor(_selectedCategory, isIncome: _isIncome)
        : financeCategoryVisualFor(
            _categoryCtrl.text.trim().isEmpty
                ? 'Outros'
                : _categoryCtrl.text.trim(),
            isIncome: _isIncome,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Categoria',
          style: TextStyle(
              fontWeight: FontWeight.w700,
              color: context.appTextPrimary,
              fontSize: 12.5),
        ),
        SizedBox(height: 5),
        Material(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(14),
          elevation: 0,
          shadowColor: Colors.black26,
          child: InkWell(
            onTap: _openFinanceCategoryPicker,
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: context.appDeepTitle.withValues(alpha: 0.18)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3)),
                ],
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: context.appTextPrimary,
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
                          foregroundColor: context.isDarkMode
                              ? context.appTextMuted
                              : Colors.grey.shade600,
                          minimumSize: const Size(40, 40),
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedCategory = '';
                            _categoryCtrl.clear();
                          });
                          _applyAutoDescriptionFromContext();
                        },
                        icon: Icon(Icons.backspace_outlined, size: 22),
                      ),
                    Icon(Icons.unfold_more_rounded,
                        color: context.appDeepTitle),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_selectedCategory == '__outra__') ...[
          SizedBox(height: 12),
          _buildCustomField(
            'Nome da categoria',
            Icons.category_outlined,
            _categoryCtrl,
            hint: 'Ex: Freelance',
            onChanged: (_) => _onCategoryCustomChanged(),
            showCopyButton: true,
          ),
        ],
      ],
    );
  }

  Widget _buildDateField() {
    final installmentsTotal =
        (int.tryParse(_installmentsCtrl.text.trim()) ?? 1).clamp(1, 999);
    final isParcelado = _installmentMode && installmentsTotal > 1;
    final isToday = _date.year == DateTime.now().year &&
        _date.month == DateTime.now().month &&
        _date.day == DateTime.now().day;
    final dateLabel = isToday
        ? 'Hoje, ${DateFormat('d \'de\' MMM', 'pt_BR').format(_date)}'
        : DateFormat('d \'de\' MMM yyyy', 'pt_BR').format(_date);
    final timeLabel = DateFormat('HH:mm', 'pt_BR').format(_date);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isParcelado)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Data e horário da 1ª parcela — o sistema calcula as demais mantendo a mesma hora. Retroativos e futuros ok.',
              style: TextStyle(fontSize: 12, color: context.appTextSecondary),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Toque para escolher o dia e o horário (retroativo ou futuro).',
                  style:
                      TextStyle(fontSize: 12, color: context.appTextSecondary),
                ),
                SizedBox(height: 4),
                Text(
                  'O horário já vem com a hora atual e pode ser ajustado em hora/minuto.',
                  style: TextStyle(
                      fontSize: 11, color: context.appTextMuted, height: 1.35),
                ),
              ],
            ),
          ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _pickDate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: context.isDarkMode
                ? context.appPanelDecoration(
                    radius: 16,
                    borderAccent: const Color(0xFF14B8A6),
                  )
                : BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFE0F2F1),
                        const Color(0xFFF1F8E9).withValues(alpha: 0.85),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: const Color(0xFF14B8A6).withValues(alpha: 0.35)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF14B8A6).withValues(alpha: 0.1),
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
                        const Color(0xFF14B8A6).withValues(alpha: 0.9),
                        const Color(0xFF00695C),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF14B8A6).withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(Icons.calendar_month_rounded,
                      color: Colors.white, size: 22),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Data do lançamento',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: context.appTextSecondary,
                          letterSpacing: 0.2,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        dateLabel,
                        style: TextStyle(
                          color: context.isDarkMode
                              ? const Color(0xFF6EE7B7)
                              : const Color(0xFF004D40),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: context.appTextMuted, size: 28),
              ],
            ),
          ),
        ),
        SizedBox(height: 8),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _pickTime,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: context.appPanelDecoration(
              radius: 16,
              borderAccent: const Color(0xFF14B8A6),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14B8A6).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.schedule_rounded,
                      color: context.isDarkMode
                          ? const Color(0xFF6EE7B7)
                          : const Color(0xFF00695C),
                      size: 22),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Horário do lançamento',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: context.appTextSecondary,
                          letterSpacing: 0.2,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        timeLabel,
                        style: TextStyle(
                          color: context.isDarkMode
                              ? const Color(0xFF6EE7B7)
                              : const Color(0xFF004D40),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _pickTime,
                  child: Text('Alterar'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Dropdown de status: apenas Pendente ou Pago. Parcelado (2+ parcelas) fica **sempre pendente**.
  Widget _buildStatusRecurrenceRow() {
    return ListenableBuilder(
      listenable: _installmentsCtrl,
      builder: (context, _) {
        final n =
            (int.tryParse(_installmentsCtrl.text.trim()) ?? 1).clamp(1, 999);
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
                        const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                        const Color(0xFFFFB74D).withValues(alpha: 0.12),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.flag_circle_rounded,
                      color: Colors.deepPurple.shade700, size: 22),
                ),
                SizedBox(width: 10),
                Text(
                  'Status do lançamento',
                  style: TextStyle(
                      fontSize: 13,
                      color: context.appTextPrimary,
                      fontWeight: FontWeight.w800),
                ),
              ],
            ),
            SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: context.isDarkMode
                  ? context.appPanelDecoration(
                      radius: 16,
                      borderAccent: const Color(0xFFEAB308),
                    )
                  : BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFFFF8E1),
                          Colors.white,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color:
                              const Color(0xFFEAB308).withValues(alpha: 0.35)),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.hourglass_top_rounded,
                                color: Colors.orange.shade900, size: 24),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Pendente (automático em parcelado)',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: context.appTextPrimary),
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
                          _status == 'paid'
                              ? Icons.check_circle_rounded
                              : Icons.pending_actions_rounded,
                          color: _status == 'paid'
                              ? Colors.green.shade700
                              : Colors.orange.shade800,
                          size: 28,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 12),
                      ),
                      isExpanded: true,
                      items: [
                        DropdownMenuItem<String>(
                          value: 'paid',
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_rounded,
                                  color: Colors.green.shade700, size: 22),
                              SizedBox(width: 10),
                              Text('Pago',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                        DropdownMenuItem<String>(
                          value: 'pending',
                          child: Row(
                            children: [
                              Icon(Icons.schedule_rounded,
                                  color: Colors.orange.shade800, size: 22),
                              SizedBox(width: 10),
                              Text('Pendente',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() {
                        _status = v ?? 'paid';
                        // Calendário NÃO liga sozinho (regra 01/10/2026):
                        // a pessoa ativa no switch se quiser.
                      }),
                    ),
            ),
            if (parceladoPendente)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 2),
                child: Text(
                  'As parcelas aparecem nas listas de pendentes até você confirmar o pagamento/recebimento.',
                  style: TextStyle(
                      fontSize: 11,
                      color: context.appTextSecondary,
                      height: 1.35),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Toggle para incluir/excluir o lançamento pendente do calendário Agenda/Escala.
  Widget _buildAddToCalendarToggle() {
    final accent =
        _isIncome ? const Color(0xFF16A34A) : const Color(0xFFEF4444);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.isDarkMode
            ? accent.withValues(alpha: 0.12)
            : accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent.withValues(alpha: 0.28),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _addToCalendar
                ? Icons.event_available_rounded
                : Icons.event_busy_rounded,
            size: 20,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mostrar no calendário',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: context.appTextPrimary,
                  ),
                ),
                Text(
                  'Agenda/Escala',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.appTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _addToCalendar,
            activeThumbColor: accent,
            activeTrackColor: accent.withValues(alpha: 0.5),
            onChanged: (v) async {
              setState(() => _addToCalendar = v);
              if (!v) return;
              // Ao ativar: paleta padrão já com a cor sugerida/atual.
              final hex = await FinanceCalendarColorPicker.escolherAoAtivar(
                context,
                isIncome: _isIncome,
                currentHex: _calendarColorHex,
              );
              if (!mounted) return;
              setState(() => _calendarColorHex = hex);
            },
          ),
        ],
      ),
    );
  }

  /// Linha de seleção de cor para exibição no calendário (Agenda/Escala).
  /// Padrão: vermelho para despesas, verde para receitas. Usuário pode trocar.
  /// Usa a mesma paleta de 72 cores do módulo Escalas.
  Widget _buildCalendarColorRow() {
    final defaultHex = _isIncome ? '#2E7D32' : '#E53935';
    final current = _calendarColorHex ?? defaultHex;
    final currentClean = current.replaceFirst('#', '').toUpperCase();
    final currentColor = Color(0xFF000000 +
        int.parse(
            currentClean.length > 6
                ? currentClean.substring(currentClean.length - 6)
                : currentClean,
            radix: 16));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.palette_rounded,
                size: 18, color: context.appTextSecondary),
            SizedBox(width: 8),
            Text(
              'Cor no calendário',
              style: TextStyle(
                  fontSize: 13,
                  color: context.appTextPrimary,
                  fontWeight: FontWeight.w700),
            ),
          ],
        ),
        SizedBox(height: 8),
        Material(
          color: currentColor,
          borderRadius: BorderRadius.circular(14),
          elevation: 2,
          shadowColor: currentColor.withValues(alpha: 0.45),
          child: InkWell(
            onTap: _abrirSeletorCorFinancas,
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 44,
              width: double.infinity,
              child: Center(
                child: Text(
                  'Toque para escolher a cor',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.25,
                      fontSize: 13.5),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Seletor padrao do app: paleta completa em abas (Paleta 01/02/03).
  Future<void> _abrirSeletorCorFinancas() async {
    // Cor atual (ou o padrao do tipo) ja pre-selecionada no dialogo.
    final defaultHex = _isIncome ? '#16A34A' : '#EF4444';
    final current = (_calendarColorHex ?? defaultHex);
    final escolhida = await mostrarSeletorDeCores(
      context,
      titulo: 'Cor no calendário',
      selecionadaHex: current,
    );
    if (escolhida != null) {
      setState(() => _calendarColorHex = escolhida);
    }
  }

  Widget _buildInstallmentsField() {
    final n = (int.tryParse(_installmentsCtrl.text.trim()) ?? 1).clamp(1, 999);
    final start =
        (int.tryParse(_installmentStartCtrl.text.trim()) ?? 1).clamp(1, n);
    final geradas = _installmentMode && n > 1 ? (n - start + 1) : 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.payments_rounded,
                color: context.appDeepTitle.withValues(alpha: 0.85), size: 22),
            SizedBox(width: 8),
            Text(
              'À vista ou parcelado',
              style: TextStyle(
                  fontSize: 13,
                  color: context.appTextPrimary,
                  fontWeight: FontWeight.w800),
            ),
          ],
        ),
        SizedBox(height: 10),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment<bool>(
              value: false,
              label: Text('À vista',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              icon: Icon(Icons.flash_on_rounded, size: 20),
            ),
            ButtonSegment<bool>(
              value: true,
              label: Text('Parcelado',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              icon: Icon(Icons.calendar_view_month_rounded, size: 20),
            ),
          ],
          selected: {_installmentMode},
          onSelectionChanged: (Set<bool> sel) {
            setState(() {
              _installmentMode = sel.first;
              if (_installmentMode) {
                if (_installmentsCtrl.text.trim() == '1' ||
                    _installmentsCtrl.text.trim().isEmpty) {
                  _installmentsCtrl.text = '12';
                }
                if (_installmentStartCtrl.text.trim().isEmpty) {
                  _installmentStartCtrl.text = '1';
                }
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
            selectedBackgroundColor: const Color(0xFF3730A3),
            selectedForegroundColor: Colors.white,
            foregroundColor: context.isDarkMode
                ? context.appTextPrimary
                : const Color(0xFF3730A3),
            backgroundColor: context.appSurface,
            side: BorderSide(
                color: context.appDeepTitle.withValues(alpha: 0.35),
                width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
            textStyle:
                const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
        ),
        if (_installmentMode) ...[
          SizedBox(height: 16),
          _buildCustomField(
            'Total de parcelas (plano)',
            Icons.numbers_rounded,
            _installmentsCtrl,
            hint: '12',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textCapitalization: TextCapitalization.none,
          ),
          SizedBox(height: 12),
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
            SizedBox(height: 16),
            Text('O valor no topo é:',
                style: TextStyle(
                    fontSize: 12,
                    color: context.appTextSecondary,
                    fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
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
              onSelectionChanged: (Set<bool> s) =>
                  setState(() => _installmentValueIsPerParcel = s.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 6)),
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
              style: TextStyle(
                  fontSize: 12, color: context.appTextSecondary, height: 1.35),
            ),
          ),
      ],
    );
  }
}

