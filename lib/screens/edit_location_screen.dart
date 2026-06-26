import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/color_palette.dart';
import '../models/shift_location.dart';
import '../constants/currency_formats.dart';
import '../theme/app_colors.dart';
import 'locations_screen.dart';
import '../utils/uppercase_text_input_formatter.dart';
import '../utils/firestore_user_doc_id.dart';
import '../widgets/agenda_form_footer_actions.dart';
import '../widgets/brl_amount_text_field.dart';
import '../utils/keyboard_form_scaffold.dart';

class EditLocationScreen extends StatefulWidget {
  final String uid;
  final ShiftLocation? location;

  const EditLocationScreen({super.key, required this.uid, this.location});

  @override
  State<EditLocationScreen> createState() => _EditLocationScreenState();
}

class _EditLocationScreenState extends State<EditLocationScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _abbrevCtrl;
  late TextEditingController _startCtrl;
  late TextEditingController _endCtrl;
  late TextEditingController _baseValueCtrl;
  late TextEditingController _bonusCtrl;
  late TextEditingController _discountCtrl;

  late bool _notifyEnabled;
  late bool _financialEnabled;
  late PaymentType _paymentType;
  late EmployerType _employerType;
  late bool _nightDifferentialEnabled;
  late Color _pickedColor;
  bool _saving = false;
  bool _abbrevManual = false;
  bool _abbrevProgrammatic = false;

  String get _userDocId => firestoreUserDocIdForAppShell(widget.uid);

  CollectionReference<Map<String, dynamic>> get _ref => FirebaseFirestore.instance
      .collection('users')
      .doc(_userDocId)
      .collection('locations');

  @override
  void initState() {
    super.initState();
    final loc = widget.location;
    final nameBase = (loc?.name ?? '').trim().toUpperCase();
    final start = loc?.startTime ?? '08:00';
    final end = loc?.endTime ?? '18:00';
    final nameCompleto = ShiftLocation.fullNameWithSchedule(nameBase, start, end);
    _nameCtrl = TextEditingController(text: nameCompleto);
    final abbr = (loc?.abbreviation ?? '').trim().toUpperCase();
    _abbrevCtrl = TextEditingController(text: abbr.length > 6 ? abbr.substring(0, 6) : abbr);
    _abbrevManual = abbr.isNotEmpty;
    _startCtrl = TextEditingController(text: loc?.startTime ?? '08:00');
    _endCtrl = TextEditingController(text: loc?.endTime ?? '18:00');
    _baseValueCtrl = TextEditingController(text: (loc?.baseValue ?? 0).toStringAsFixed(2));
    _bonusCtrl = TextEditingController(text: (loc?.bonus ?? 0).toStringAsFixed(2));
    _discountCtrl = TextEditingController(text: (loc?.discount ?? 0).toStringAsFixed(2));
    _notifyEnabled = loc?.notifyEnabled ?? true;
    // Novo pré-cadastro: plantão pago / financeiro ativo por defeito (Estado já é o vínculo padrão).
    _financialEnabled = widget.location?.financialEnabled ?? true;
    _paymentType = loc?.paymentType ?? PaymentType.perHour;
    _employerType = loc?.employerType ?? EmployerType.state;
    _nightDifferentialEnabled = loc?.nightDifferentialEnabled ?? false;
    _pickedColor = loc?.color ?? AppColors.primary;
    _nameCtrl.addListener(_onNameForAbbrev);
    _abbrevCtrl.addListener(_onAbbrevUserEdit);
  }

  void _onNameForAbbrev() {
    if (_abbrevManual) return;
    final base = ShiftLocation.baseNameFromFull(_nameCtrl.text);
    final auto = ShiftLocation.abbreviationFromName(base);
    if (auto.isEmpty) return;
    final clipped = auto.length > 6 ? auto.substring(0, 6) : auto;
    _abbrevProgrammatic = true;
    if (_abbrevCtrl.text != clipped) {
      _abbrevCtrl.value = TextEditingValue(
        text: clipped,
        selection: TextSelection.collapsed(offset: clipped.length),
      );
    }
    _abbrevProgrammatic = false;
  }

  void _onAbbrevUserEdit() {
    if (_abbrevProgrammatic) return;
    if (_abbrevCtrl.text.trim().isEmpty) {
      _abbrevManual = false;
      _onNameForAbbrev();
      return;
    }
    _abbrevManual = true;
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_onNameForAbbrev);
    _abbrevCtrl.removeListener(_onAbbrevUserEdit);
    _nameCtrl.dispose();
    _abbrevCtrl.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    _baseValueCtrl.dispose();
    _bonusCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  String _colorToHex(Color c) {
    return '0xFF${c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  /// Formato da escala: #RRGGBB (6 hex).
  String _colorToHexForScale(Color c) {
    final hex = c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
    return '#${hex.length > 6 ? hex.substring(hex.length - 6) : hex}';
  }

  /// Converte "HH:mm" em TimeOfDay.
  TimeOfDay _parseTime(String s) {
    final parts = s.trim().split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
  }

  /// Formata TimeOfDay em "HH:mm" (24h).
  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Abre o seletor de horário 24h e atualiza o controller ao confirmar.
  /// Também auto-completa o nome do plantão com "BASE HH:MM ÀS HH:MM" para facilitar relatórios.
  Future<void> _pickTime(bool isStart) async {
    final ctrl = isStart ? _startCtrl : _endCtrl;
    final initial = _parseTime(ctrl.text);
    final t = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (t != null && mounted) {
      ctrl.text = _formatTime(t);
      _nameCtrl.text = ShiftLocation.fullNameWithSchedule(_nameCtrl.text, _startCtrl.text, _endCtrl.text);
      setState(() {});
    }
  }

  /// Atualiza colorHex em todas as entradas da coleção scales cujo label é o nome do plantão/compromisso.
  Future<void> _atualizarCorEmTodasEscalas(String nomePlantao, String novaCorHex) async {
    if (nomePlantao.isEmpty) return;
    final scalesRef = FirebaseFirestore.instance
        .collection('users')
        .doc(_userDocId)
        .collection('scales');
    final snap = await scalesRef.where('label', isEqualTo: nomePlantao).get();
    if (snap.docs.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'colorHex': novaCorHex});
    }
    await batch.commit();
  }

  Future<void> _save() async {
    final typedName = _nameCtrl.text.trim().toUpperCase();
    final start = _startCtrl.text.trim().isNotEmpty ? _startCtrl.text.trim() : '08:00';
    final end = _endCtrl.text.trim().isNotEmpty ? _endCtrl.text.trim() : '18:00';
    final baseName = ShiftLocation.baseNameFromFull(typedName);
    final name = ShiftLocation.fullNameWithSchedule(baseName, start, end);
    final abbrev = _abbrevCtrl.text.trim().toUpperCase();
    final faltando = <String>[];
    if (name.isEmpty) faltando.add('Nome do local');
    if (faltando.isNotEmpty) {
      final texto = faltando.length == 1
          ? 'Não foi possível salvar. Preencha: ${faltando.single} (obrigatório).'
          : 'Não foi possível salvar. Campos obrigatórios: ${faltando.join(' e ')}.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
      return;
    }
    setState(() => _saving = true);
    try {
      final isParticular = _employerType == EmployerType.private;
      final abbrevFinal = abbrev.isNotEmpty
          ? (abbrev.length > 6 ? abbrev.substring(0, 6) : abbrev)
          : ShiftLocation.abbreviationFromName(name);
      final loc = ShiftLocation(
        id: widget.location?.id,
        name: name,
        abbreviation: abbrevFinal,
        colorHex: _colorToHex(_pickedColor),
        startTime: start,
        endTime: end,
        notifyEnabled: _notifyEnabled,
        financialEnabled: _financialEnabled,
        paymentType: isParticular ? _paymentType : PaymentType.perHour,
        employerType: _employerType,
        baseValue: isParticular ? (CurrencyFormats.parseBRLInput(_baseValueCtrl.text) ?? 0) : 0,
        bonus: isParticular ? (CurrencyFormats.parseBRLInput(_bonusCtrl.text) ?? 0) : 0,
        discount: isParticular ? (CurrencyFormats.parseBRLInput(_discountCtrl.text) ?? 0) : 0,
        nightDifferentialEnabled: isParticular ? _nightDifferentialEnabled : false,
        nightDifferentialPercent: 20,
        nightStart: '22:00',
        nightEnd: '05:00',
      );
      if (widget.location?.id != null) {
        final patch = Map<String, dynamic>.from(loc.toMap());
        patch['reminderLeads'] = FieldValue.delete();
        patch['notificationSoundId'] = FieldValue.delete();
        patch['notificationDeliveryMode'] = FieldValue.delete();
        await _ref.doc(widget.location!.id).update(patch);
        // Atualizar a cor em todas as entradas da escala (passadas e futuras) com o mesmo nome do plantão/compromisso.
        await _atualizarCorEmTodasEscalas(widget.location!.name, _colorToHexForScale(_pickedColor));
      } else {
        await _ref.add(loc.toMap());
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Local salvo.')));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _inputDecoration(
    BuildContext context, {
    required String labelText,
    String? hintText,
    String? counterText,
    Widget? suffixIcon,
    String? prefixText,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      counterText: counterText,
      suffixIcon: suffixIcon,
      prefixText: prefixText,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      labelStyle: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.deepBlue.withValues(alpha: 0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset:
          scaffoldKeyboardResizeToAvoidBottomInset(standaloneFullPageForm: true),
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: AppColors.logoGradient,
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        title: Text(
          widget.location != null ? 'Editar Local' : 'Novo Local',
          style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => LocationsScreen(uid: _userDocId)),
              );
            },
            icon: const Icon(Icons.list_rounded, size: 20, color: Colors.white),
            label: const Text('Ver existentes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      bottomNavigationBar: KeyboardAwareFormBar(
        standaloneFullPageForm: true,
        backgroundColor: const Color(0xFFF1F5F9),
        child: AgendaFormFooterActions(
          onCancel: () => Navigator.of(context).maybePop(),
          onSave: _save,
          saveLabel: 'Salvar Local',
          isBusy: _saving,
          saveIcon: Icons.check_rounded,
        ),
      ),
      body: keyboardScaffoldBody(
        standaloneFullPageForm: true,
        SafeArea(
        bottom: false,
        child: Builder(
          builder: (scrollCtx) {
            final bottomPad = KeyboardFormInsets.scrollBottomExtra(
              scrollCtx,
              extra: 16,
              standaloneFullPageForm: true,
            );
            return ListView(
              physics: const BouncingScrollPhysics(),
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(14, 10, 14, bottomPad),
              children: [
          _section(
            icon: Icons.work_rounded,
            title: 'Identificação',
            subtitle: 'Super premium · pré-cadastro para o calendário',
            children: [
              FastTextField(
                controller: _nameCtrl,
                decoration: _inputDecoration(
                  context,
                  labelText: 'Nome do local *',
                  hintText: 'Ex: REFORÇO CAMPO LIMPO (maiúsculas)',
                ),
                scrollPadding: KeyboardFormInsets.fieldScrollPadding(
                  context,
                  standaloneFullPageForm: true,
                ),
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [UpperCaseTextFormatter()],
              ),
              // Campo de sigla removido da UI para deixar o pré-cadastro mais enxuto.
            ],
          ),
          const SizedBox(height: 10),
          _section(
            icon: Icons.schedule_rounded,
            title: 'Horário',
            children: [
              SwitchListTile(
                value: _notifyEnabled,
                onChanged: (v) => setState(() => _notifyEnabled = v),
                title: const Text('Notificar', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Lembrete antes do plantão'),
                activeTrackColor: AppColors.primary.withValues(alpha: 0.45),
                activeThumbColor: Colors.white,
                inactiveTrackColor: AppColors.textMuted.withValues(alpha: 0.25),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickTime(true),
                      borderRadius: BorderRadius.circular(16),
                      child: InputDecorator(
                        decoration: _inputDecoration(
                          context,
                          labelText: 'Início',
                          suffixIcon: const Icon(Icons.schedule_rounded, color: AppColors.primary),
                        ),
                        child: Text(
                          _startCtrl.text.isEmpty ? '08:00' : _startCtrl.text,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickTime(false),
                      borderRadius: BorderRadius.circular(16),
                      child: InputDecorator(
                        decoration: _inputDecoration(
                          context,
                          labelText: 'Fim',
                          suffixIcon: const Icon(Icons.schedule_rounded, color: AppColors.primary),
                        ),
                        child: Text(
                          _endCtrl.text.isEmpty ? '18:00' : _endCtrl.text,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Toque no campo para abrir o relógio 24h e escolher hora inicial e final.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w500, height: 1.3),
              ),
              if (_notifyEnabled) ...[
                const SizedBox(height: 14),
                Text(
                  'Lembretes usam o padrão de Configurações → Notificações.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          _section(
            icon: Icons.attach_money_rounded,
            title: 'Financeiro',
            children: [
              SwitchListTile(
                value: _financialEnabled,
                onChanged: (v) => setState(() => _financialEnabled = v),
                title: const Text('Ativado', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Plantão pago (calendário e resumos)'),
                activeTrackColor: AppColors.primary.withValues(alpha: 0.45),
                activeThumbColor: Colors.white,
                inactiveTrackColor: AppColors.textMuted.withValues(alpha: 0.25),
              ),
              if (_financialEnabled) ...[
                const SizedBox(height: 12),
                const Text('Vínculo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text(
                  'Padrão: Estado. Estado e Município usam valores padrão GO. Particular: informe valor/hora, diária, bônus etc.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _vinculoButton(EmployerType.state)),
                    const SizedBox(width: 8),
                    Expanded(child: _vinculoButton(EmployerType.municipality)),
                    const SizedBox(width: 8),
                    Expanded(child: _vinculoButton(EmployerType.private)),
                  ],
                ),
                if (_employerType == EmployerType.private) ...[
                  const SizedBox(height: 16),
                  const Text('Tipo de pagamento', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<PaymentType>(
                          segments: const [
                            ButtonSegment(value: PaymentType.perHour, label: Text('Por Hora'), icon: Icon(Icons.schedule_rounded, size: 18)),
                            ButtonSegment(value: PaymentType.fixed, label: Text('Fixo'), icon: Icon(Icons.payments_rounded, size: 18)),
                          ],
                          selected: {_paymentType},
                          onSelectionChanged: (s) => setState(() => _paymentType = s.first),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  BrlAmountTextField(
                    controller: _baseValueCtrl,
                    scrollPadding: KeyboardFormInsets.fieldScrollPadding(
                      context,
                      standaloneFullPageForm: true,
                    ),
                    decoration: _inputDecoration(
                      context,
                      labelText: _paymentType == PaymentType.perHour ? 'Valor por hora (R\$)' : 'Valor total / diária (R\$)',
                      prefixText: 'R\$ ',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: BrlAmountTextField(
                          controller: _bonusCtrl,
                          scrollPadding: KeyboardFormInsets.fieldScrollPadding(
                            context,
                            standaloneFullPageForm: true,
                          ),
                          decoration: _inputDecoration(context, labelText: 'Bônus (+)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: BrlAmountTextField(
                          controller: _discountCtrl,
                          scrollPadding: KeyboardFormInsets.fieldScrollPadding(
                            context,
                            standaloneFullPageForm: true,
                          ),
                          decoration: _inputDecoration(context, labelText: 'Descontos (-)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: _nightDifferentialEnabled,
                    onChanged: (v) => setState(() => _nightDifferentialEnabled = v),
                    title: const Text('Adicional noturno (20%)', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Automático entre 22h e 05h'),
                    secondary: Icon(Icons.nightlight_round, color: AppColors.amber),
                    activeTrackColor: AppColors.primary.withValues(alpha: 0.45),
                    activeThumbColor: Colors.white,
                    inactiveTrackColor: AppColors.textMuted.withValues(alpha: 0.25),
                  ),
                ],
              ],
            ],
          ),
          const SizedBox(height: 10),
          _section(
            icon: Icons.palette_rounded,
            title: 'Identificação visual',
            subtitle: 'Cor exibida no calendário e gráficos',
            children: [
              Material(
                color: AppColors.vividShift(_pickedColor),
                borderRadius: BorderRadius.circular(16),
                elevation: 4,
                shadowColor: AppColors.vividShift(_pickedColor).withValues(alpha: 0.45),
                child: InkWell(
                  onTap: () async {
                    final colors = kColorPaletteHex.take(72).map((hex) {
                      final h = hex.replaceFirst('#', '').replaceFirst('0x', '');
                      return Color(0xFF000000 + int.parse(h.length <= 6 ? h : h.substring(0, 6), radix: 16));
                    }).toList();
                    final chosen = await showDialog<Color>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        titlePadding: const EdgeInsets.fromLTRB(18, 12, 8, 2),
                        title: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Cor da frente de serviço',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.close_rounded, size: 18),
                              label: const Text('Cancelar'),
                            ),
                          ],
                        ),
                        content: SingleChildScrollView(
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: colors.map((c) => InkWell(
                              onTap: () => Navigator.pop(ctx, c),
                              borderRadius: BorderRadius.circular(12),
                                child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 6, offset: const Offset(0, 2))],
                                ),
                              ),
                            )).toList(),
                          ),
                        ),
                      ),
                    );
                    if (chosen != null) setState(() => _pickedColor = chosen);
                  },
                  borderRadius: BorderRadius.circular(14),
                    child: const SizedBox(
                    height: 44,
                    width: double.infinity,
                    child: Center(
                      child: Text('Selecionar cor', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 0.3, fontSize: 13.5)),
                    ),
                  ),
                ),
              ),
            ],
          ),
                ],
            );
          },
        ),
      ),
      ),
    );
  }

  /// Mesmo padrão do lançamento expresso ([lancamento_expresso_plantao_sheet] `_buildVinculoChips`).
  Color _vinculoAccent(EmployerType e) {
    switch (e) {
      case EmployerType.state:
        return AppColors.vinculoEstado;
      case EmployerType.municipality:
        return AppColors.vinculoMunicipio;
      case EmployerType.private:
        return AppColors.vinculoParticular;
    }
  }

  IconData _vinculoIcon(EmployerType e) {
    switch (e) {
      case EmployerType.state:
        return Icons.account_balance_rounded;
      case EmployerType.municipality:
        return Icons.location_city_rounded;
      case EmployerType.private:
        return Icons.person_rounded;
    }
  }

  Widget _vinculoButton(EmployerType type) {
    final sel = _employerType == type;
    final accent = _vinculoAccent(type);
    final dark = accent.computeLuminance() > 0.55;
    final fg = sel ? (dark ? const Color(0xFF37474F) : Colors.white) : accent;
    final bg = sel ? accent : accent.withValues(alpha: 0.12);
    final border = sel ? accent : accent.withValues(alpha: 0.4);
    final icon = _vinculoIcon(type);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _employerType = type),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: sel ? 2.2 : 1),
            boxShadow: sel
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.38),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: fg),
              const SizedBox(height: 4),
              Text(
                ShiftLocation.employerTypeLabel(type),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg, letterSpacing: 0.1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Card premium ultra-compacto — ajustado para o pré-cadastro caber sem
  /// rolagem em iPhone com teclado aberto: padding 14/12 (em vez de 18/18),
  /// título 14.5 (em vez de 17), ícone 18 (em vez de 22).
  Widget _section({
    required IconData icon,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.deepBlue.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBlueDark.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 3,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: AppColors.logoGradient,
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: AppColors.deepBlue, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                      height: 1.3,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                ...children,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

