import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide showDatePicker;
import 'package:flutter/services.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';
import 'package:intl/intl.dart';

import '../constants/commitment_presets.dart';
import '../constants/compromisso_despertador.dart';
import '../models/despertar_item.dart';
import '../models/user_profile.dart';
import '../services/agenda_scale_mirror_service.dart';
import '../theme/app_colors.dart';
import '../theme/gemini_theme.dart';
import '../theme/theme_context.dart';
import '../widgets/despertar_item_card.dart';
import '../services/google_calendar_sync_service.dart';
import '../services/yearly_commitment_repeat_service.dart';
import '../widgets/agenda_form_footer_actions.dart';
import '../widgets/fast_text_field.dart';
import '../utils/keyboard_form_scaffold.dart';
import '../widgets/agenda_form_validation_alert.dart';
import '../widgets/color_palette_tabs_dialog.dart';
import '../widgets/commitment_description_picker.dart';
import '../widgets/compromisso_schedule_personalize_sheet.dart';
import '../widgets/multi_date_month_picker_dialog.dart';
import '../utils/compromisso_schedule_dates.dart';
import '../utils/premium_upgrade.dart';
import '../constants/commitment_symbols.dart';
import '../utils/compromisso_share.dart';
import '../widgets/commitment_symbol_picker.dart';

/// Resultado ao salvar compromisso (novo ou edição).
class CompromissoFormResult {
  CompromissoFormResult({
    required this.title,
    required this.notes,
    String linkLocalizacao = '',
    String contatoWhatsApp = '',
    required this.date,
    required this.time,
    required this.endTime,
    required this.colorHex,
    this.reminderLeads,
    this.notificationSoundId,
    this.notificationDeliveryMode,
    this.repeatYearly = false,
    this.yearlyRepeatWeekdays,
    List<DateTime>? targetDates,
    bool despertador = false,
    this.despertar = DespertarItem.desligado,
    this.commitmentSymbol,
  })  : linkLocalizacao = linkLocalizacao.trim(),
        contatoWhatsApp = contatoWhatsApp.trim(),
        // Série anual não tem «Despertar no horário».
        despertador = despertador && !repeatYearly,
        targetDates = CompromissoScheduleDates.uniqueSorted(
          targetDates ?? [date],
        );

  /// «⏰ Despertar no horário»: toca como despertador NA HORA (campos em
  /// `compromisso_despertador.dart`). Não vale para a série anual.
  final bool despertador;

  /// «Despertar» POR ITEM (liga/desliga + som ou só vibrar) — gravado em
  /// `despertar` no reminder. Nasce desligado. Vale também para a série
  /// anual (todas as ocorrências). Ver [DespertarItem].
  final DespertarItem despertar;

  /// Emoji ou ícone escolhido (`emoji:🎂` / `icon:cake`); null = automático
  /// pelo título. Gravado em `commitmentSymbol` no reminder E no espelho
  /// `scales/agenda_*` (igual ao Controle Total). Ver [CommitmentSymbol].
  final String? commitmentSymbol;

  /// Doc NOVO: só grava quando o usuário escolheu.
  Map<String, dynamic> get camposSimboloNovo {
    final s = (commitmentSymbol ?? '').trim();
    return {if (s.isNotEmpty) kCommitmentSymbolField: s};
  }

  /// Edição (update/merge): grava ou apaga (volta ao automático pelo título).
  Map<String, dynamic> get camposSimboloEdicao {
    final s = (commitmentSymbol ?? '').trim();
    return {kCommitmentSymbolField: s.isEmpty ? FieldValue.delete() : s};
  }

  final String title;
  final String notes;

  /// Link de localização (Maps, endereço ou texto livre).
  final String linkLocalizacao;

  /// Contato WhatsApp (número, wa.me link, etc.).
  final String contatoWhatsApp;

  /// Primeiro dia da seleção (compatibilidade / exibição).
  final DateTime date;
  final TimeOfDay time;
  final TimeOfDay endTime;
  final String colorHex;

  /// Todos os dias onde o compromisso será gravado (1 = único).
  final List<DateTime> targetDates;

  /// Aniversário, casamento, etc. — relança automaticamente todo ano em Escalas.
  final bool repeatYearly;

  /// Ex.: [DateTime.wednesday, DateTime.thursday] — todas as quas/quis do ano.
  final List<int>? yearlyRepeatWeekdays;

  /// Antecedências em minutos só para este item; null = usa Configurações → Notificações.
  final List<int>? reminderLeads;

  /// `id` do banco offline de sons (`notification_sound_catalog.dart`) — só
  /// para este compromisso. `null` = usa o som padrão da categoria
  /// «Compromisso» definido em *Preferências → Sons das notificações*.
  final String? notificationSoundId;

  /// Modo de entrega só para este compromisso (`audio`/`vibrate`/`push`).
  /// `null` = herda o padrão da categoria.
  final String? notificationDeliveryMode;
}

/// Cadastro / edição de compromisso em tela cheia — mesmo padrão premium do
/// **Compromisso particular** (sheet de Lançamento expresso). Inclui:
///
/// - linha de 6 ícones rápidos coloridos (REUNIÃO, MÉDICO, DENTISTA, IGREJA,
///   ANIVERSÁRIO, CASAMENTO) que preenchem descrição + cor sugerida;
/// - sufixo "lista" no campo título que abre o picker fullscreen com a lista
///   alfabética completa (~39 compromissos) + opção de incluir personalizado;
/// - escolha de cor do calendário (mesma paleta de 72 cores do pré-cadastro);
/// - hora de fim sugerida automaticamente (+1h) ao escolher hora de início.
class CompromissoFormPage extends StatefulWidget {
  const CompromissoFormPage({
    super.key,
    required this.profile,
    required this.hasActiveLicense,
    this.existingDoc,
    this.initialDate,
    this.googleEventSeed,
  });

  final UserProfile profile;
  final bool hasActiveLicense;
  final QueryDocumentSnapshot<Map<String, dynamic>>? existingDoc;

  /// Dia pré-selecionado ao abrir pelo calendário da Agenda.
  final DateTime? initialDate;

  /// Pré-preenche formulário ao editar evento que veio só do Google Calendar.
  final GoogleCalendarEventItem? googleEventSeed;

  bool get isEdit => existingDoc != null || googleEventSeed != null;

  @override
  State<CompromissoFormPage> createState() => _CompromissoFormPageState();
}

class _CompromissoFormPageState extends State<CompromissoFormPage> {
  final FlutterNativeContactPicker _contactPicker =
      FlutterNativeContactPicker();
  late TextEditingController _titleCtrl;
  late TextEditingController _linkLocalizacaoCtrl;
  late TextEditingController _whatsAppCtrl;
  late TextEditingController _notesCtrl;
  late DateTime _date;
  late TimeOfDay _time;
  late TimeOfDay _endTime;
  late String _colorHex;
  bool _repeatYearly = false;
  late List<DateTime> _selectedDates;

  /// «⏰ Despertar no horário» (toca como despertador na hora).
  bool _despertador = false;

  /// «Despertar» por item — nasce desligado no cadastro novo.
  DespertarItem _despertar = DespertarItem.desligado;

  /// Emoji/ícone do compromisso (null = automático pelo título).
  CommitmentSymbol? _symbol;

  static TimeOfDay _addOneHour(TimeOfDay t) {
    final m = t.hour * 60 + t.minute + 60;
    final h = (m ~/ 60) % 24;
    return TimeOfDay(hour: h, minute: m % 60);
  }

  static int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  static TimeOfDay _parseHHmm(String s, TimeOfDay fallback) {
    final parts = s.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '');
    final m = int.tryParse(parts.length > 1 ? parts[1] : '');
    if (h == null) return fallback;
    return TimeOfDay(hour: h, minute: m ?? 0);
  }

  @override
  void initState() {
    super.initState();
    final doc = widget.existingDoc;
    if (doc != null) {
      final data = doc.data();
      _titleCtrl =
          TextEditingController(text: (data['title'] ?? '').toString());
      _linkLocalizacaoCtrl = TextEditingController(
          text: (data['linkLocalizacao'] ?? '').toString());
      _whatsAppCtrl = TextEditingController(
          text: (data['contatoWhatsApp'] ?? '').toString());
      _notesCtrl =
          TextEditingController(text: (data['notes'] ?? '').toString());
      _date = (data['date'] as Timestamp?)?.toDate() ??
          DateTime.now().add(const Duration(days: 1));
      _time = _parseHHmm((data['time'] ?? '09:00').toString(),
          const TimeOfDay(hour: 9, minute: 0));
      _endTime =
          _parseHHmm((data['endTime'] ?? '').toString(), _addOneHour(_time));
      final corSalva = (data['colorHex'] ?? '').toString().trim();
      _colorHex = corSalva.isNotEmpty
          ? _normalizeHex(corSalva)
          : kAgendaCompromissoDefaultColor;
      _repeatYearly = data['repeatYearly'] == true ||
          data['isYearlyRepeatTemplate'] == true ||
          (data['yearlyRepeatTemplateId'] ?? '').toString().trim().isNotEmpty;
      _despertador = compromissoTemDespertador(data);
      _despertar = DespertarItem.doDocumento(data);
      _symbol = CommitmentSymbol.fromData(data);
      _selectedDates = [
        DateTime(_date.year, _date.month, _date.day),
      ];
    } else if (widget.googleEventSeed != null) {
      final g = widget.googleEventSeed!;
      _titleCtrl = TextEditingController(text: g.title);
      _notesCtrl = TextEditingController(text: g.notes);
      _date = g.day;
      _time = g.timeStart.isEmpty
          ? const TimeOfDay(hour: 9, minute: 0)
          : _parseHHmm(g.timeStart, const TimeOfDay(hour: 9, minute: 0));
      _endTime = g.timeEnd.isEmpty
          ? _addOneHour(_time)
          : _parseHHmm(g.timeEnd, _addOneHour(_time));
      _colorHex = '#4285F4';
      _selectedDates = [
        DateTime(_date.year, _date.month, _date.day),
      ];
    } else {
      _titleCtrl = TextEditingController();
      _linkLocalizacaoCtrl = TextEditingController();
      _whatsAppCtrl = TextEditingController();
      _notesCtrl = TextEditingController();
      final seed = widget.initialDate;
      _date = seed != null
          ? DateTime(seed.year, seed.month, seed.day)
          : DateTime.now().add(const Duration(days: 1));
      _time = const TimeOfDay(hour: 9, minute: 0);
      _endTime = const TimeOfDay(hour: 10, minute: 0);
      _colorHex = kAgendaCompromissoDefaultColor;
      _selectedDates = [
        DateTime(_date.year, _date.month, _date.day),
      ];
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _linkLocalizacaoCtrl.dispose();
    _whatsAppCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  static String _normalizeHex(String hex) {
    var h = hex
        .replaceFirst('#', '')
        .replaceFirst(RegExp(r'^0x', caseSensitive: false), '');
    if (h.length > 6) h = h.substring(h.length - 6);
    if (h.length < 6) return kAgendaCompromissoDefaultColor;
    return '#${h.toUpperCase()}';
  }

  Color _colorFromHex(String hex) {
    var h = hex
        .replaceFirst('#', '')
        .replaceFirst(RegExp(r'^0x', caseSensitive: false), '');
    if (h.length > 6) h = h.substring(h.length - 6);
    if (h.length < 6) return AppColors.primary;
    return Color(int.parse('FF$h', radix: 16));
  }

  static Future<void> _pasteInto(
      TextEditingController ctrl, VoidCallback onChanged) async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text == null) return;
      final sel = ctrl.selection;
      final start = sel.start.clamp(0, ctrl.text.length);
      final end = sel.end.clamp(0, ctrl.text.length);
      ctrl.text = ctrl.text.replaceRange(start, end, data!.text!);
      ctrl.selection =
          TextSelection.collapsed(offset: start + data.text!.length);
      onChanged();
    } catch (_) {}
  }

  Future<void> _pickWhatsAppContact() async {
    final isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (!isMobile) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A agenda de contatos está disponível no celular.'),
        ),
      );
      return;
    }

    try {
      final contact = await _contactPicker.selectPhoneNumber();
      if (!mounted || contact == null) return;

      final phone = (contact.selectedPhoneNumber ??
              (contact.phoneNumbers?.isNotEmpty == true
                  ? contact.phoneNumbers!.first
                  : null))
          ?.trim();
      if (phone == null || phone.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('O contato selecionado não possui telefone.'),
          ),
        );
        return;
      }

      setState(() {
        _whatsAppCtrl.value = TextEditingValue(
          text: phone,
          selection: TextSelection.collapsed(offset: phone.length),
        );
      });
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir a agenda de contatos.'),
        ),
      );
    }
  }

  InputDecoration _inputDecoration(String label, String hint,
          {Widget? suffixIcon, Widget? prefixIcon}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true,
        fillColor: context.appInputFill,
        suffixIcon: suffixIcon,
        prefixIcon: prefixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GeminiTheme.inputRadius),
          borderSide: BorderSide.none,
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    Widget? suffixIcon,
    Widget? prefixIcon,
    TextInputType? keyboardType,
  }) {
    final isMultiline = maxLines != 1;
    return FastTextField(
      controller: controller,
      decoration: _inputDecoration(label, hint,
          suffixIcon: suffixIcon, prefixIcon: prefixIcon),
      kind: isMultiline ? FastTextFieldKind.prose : FastTextFieldKind.standard,
      keyboardType: keyboardType,
      maxLines: maxLines,
      minLines: isMultiline ? 1 : null,
      scrollPadding: KeyboardFormInsets.fieldScrollPadding(
        context,
        standaloneFullPageForm: true,
      ),
      textInputAction:
          isMultiline ? TextInputAction.newline : TextInputAction.next,
      onSubmitted:
          isMultiline ? null : (_) => FocusScope.of(context).nextFocus(),
    );
  }

  /// Tile compacto reutilizável — usado nos pickers (Data | Início | Fim).
  /// Toque no card inteiro abre o seletor (sem botão "Alterar" extra,
  /// economizando largura para caber lado a lado em iPhone estreito).
  Widget _compactPickerTile({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: context.appInputFill,
      borderRadius: BorderRadius.circular(GeminiTheme.inputRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GeminiTheme.inputRadius),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          child: Row(
            children: [
              Icon(icon, size: 17, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: context.isDarkMode
                              ? context.appTextSecondary
                              : Colors.grey.shade700,
                          letterSpacing: 0.2,
                        )),
                    const SizedBox(height: 2),
                    Text(value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: context.appTextPrimary,
                          height: 1.1,
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _multiDateMode => !widget.isEdit;

  String get _dateFieldLabel {
    if (!_multiDateMode || _selectedDates.length <= 1) {
      return DateFormat("dd/MM (EEE)", 'pt_BR').format(_date);
    }
    return '${_selectedDates.length} dias';
  }

  Future<void> _pickDate() async {
    if (!_multiDateMode) {
      final picked = await pickSingleDateWithHolidayCalendar(
        context: context,
        initialDate: _date,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (picked != null) {
        setState(() {
          _date = picked;
          _selectedDates = [DateTime(picked.year, picked.month, picked.day)];
          if (_repeatYearly) _applyYearlyNotesLine();
        });
      }
      return;
    }

    final picked = await showMultiDateMonthPickerDialog(
      context: context,
      month: _date,
      initialSelected: _selectedDates,
    );
    if (picked != null && picked.isNotEmpty) {
      setState(() {
        _selectedDates = CompromissoScheduleDates.uniqueSorted(picked);
        _date = _selectedDates.first;
        if (_repeatYearly) _applyYearlyNotesLine();
      });
    }
  }

  Future<void> _openPersonalizeDates() async {
    final merged = await showCompromissoSchedulePersonalizeSheet(
      context: context,
      referenceMonth: _date,
      initialSelected: _selectedDates,
    );
    if (merged == null || merged.isEmpty || !mounted) return;
    setState(() {
      _selectedDates = CompromissoScheduleDates.uniqueSorted(merged);
      _date = _selectedDates.first;
      if (_repeatYearly) _applyYearlyNotesLine();
    });
  }

  void _applyYearlyNotesLine() {
    final merged = YearlyCommitmentRepeatService.mergeUserNotesWithYearlyLine(
      userNotes: _notesCtrl.text,
      month: _date.month,
      day: _date.day,
    );
    _notesCtrl.text = merged;
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _time = picked;
      // Auto-fim: sugere início + 1h se o fim atual ficar inválido (anterior
      // ou igual ao novo início). Mantém o fim atual quando ainda faz sentido.
      if (_toMinutes(_endTime) <= _toMinutes(_time)) {
        _endTime = _addOneHour(_time);
      }
    });
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _endTime = picked);
  }

  void _aplicarPreset(CommitmentPreset p) {
    setState(() {
      _titleCtrl.text = p.name.toUpperCase();
      _colorHex = hexFromCommitmentColor(p.color);
    });
  }

  Future<void> _abrirPickerDescricao() async {
    final selected = await showCommitmentDescriptionPicker(
      context: context,
      uid: widget.profile.uid,
      initialQuery: _titleCtrl.text.trim(),
    );
    if (selected == null || !mounted) return;
    final preset = kCommitmentPresetByName[selected.toLowerCase().trim()];
    setState(() {
      _titleCtrl.text = selected.toUpperCase();
      if (preset != null) _colorHex = hexFromCommitmentColor(preset.color);
    });
  }

  Future<void> _abrirSeletorCor() async {
    final escolhida = await mostrarSeletorDeCores(
      context,
      titulo: 'Cor no calendário',
      selecionadaHex: _colorHex,
    );
    if (escolhida == null || !mounted) return;
    setState(() => _colorHex = _normalizeHex(escolhida));
  }

  Future<void> _submit() async {
    if (!widget.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final title = _titleCtrl.text.trim();
    final canSave = await validateCompromissoFormOrShowAlert(
      context,
      title: title,
      repeatYearlyConflict: _repeatYearly && _selectedDates.length > 1,
    );
    if (!canSave || !mounted) return;
    Navigator.of(context).pop(
      CompromissoFormResult(
        title: title,
        notes: _notesCtrl.text.trim(),
        linkLocalizacao: _linkLocalizacaoCtrl.text.trim(),
        contatoWhatsApp: _whatsAppCtrl.text.trim(),
        date: _date,
        time: _time,
        endTime: _endTime,
        colorHex: _colorHex,
        reminderLeads: null,
        notificationSoundId: null,
        notificationDeliveryMode: null,
        repeatYearly: _repeatYearly,
        yearlyRepeatWeekdays: null,
        targetDates: _selectedDates,
        despertador: _despertador,
        despertar: _despertar,
        commitmentSymbol: _symbol?.raw,
      ),
    );
  }

  /// Compartilhar (detalhe/edição): usa o que está na tela agora.
  Future<void> _compartilhar(BuildContext ctx) async {
    final data = <String, dynamic>{
      'title': _titleCtrl.text.trim(),
      'date': _date,
      'time': _fmtHHmm(_time),
      'endTime': _fmtHHmm(_endTime),
      'linkLocalizacao': _linkLocalizacaoCtrl.text.trim(),
      'notes': _notesCtrl.text.trim(),
      if (_symbol != null) kCommitmentSymbolField: _symbol!.raw,
    };
    await shareCompromisso(ctx, data);
  }

  static String _fmtHHmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _abrirSeletorSimbolo() async {
    final pick = await showCommitmentSymbolPicker(
      context,
      atual: _symbol,
      title: _titleCtrl.text,
      cor: _colorFromHex(_colorHex),
    );
    if (pick == null || !mounted) return;
    setState(() => _symbol = pick.symbol);
  }

  /// Emoji ou ícone moderno do compromisso — aparece no card do resumo do dia,
  /// no espelho de Escalas e no texto compartilhado. Vazio = pelo título.
  Widget _buildSymbolCard(Color pickedFill) {
    return Container(
      decoration: context.appPanelDecoration(radius: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: pickedFill.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: pickedFill.withValues(alpha: 0.45)),
              ),
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _titleCtrl,
                builder: (_, v, __) => commitmentSymbolWidget(
                  symbol: _symbol,
                  title: v.text,
                  size: 22,
                  color: pickedFill,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Emoji ou ícone',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: context.appTextPrimary,
                    ),
                  ),
                  Text(
                    _symbol == null
                        ? 'Automático pelo título'
                        : 'Escolhido por você',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: context.appTextSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _abrirSeletorSimbolo,
              icon: const Icon(Icons.emoji_emotions_rounded, size: 16),
              label: const Text('Escolher'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Interruptor «⏰ Despertar no horário» — some na série anual.
  Widget _despertadorTile() {
    return Material(
      color: context.appInputFill,
      borderRadius: BorderRadius.circular(GeminiTheme.inputRadius),
      child: SwitchListTile.adaptive(
        value: _despertador,
        onChanged: (v) => setState(() => _despertador = v),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GeminiTheme.inputRadius),
        ),
        secondary: Icon(Icons.alarm_rounded,
            color: _despertador ? AppColors.primary : context.appTextSecondary),
        title: Text(
          '⏰ Despertar no horário',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: context.appTextPrimary,
          ),
        ),
        subtitle: Text(
          'Toca como despertador na hora (Adiar / Encerrar). '
          'Encerrar marca como concluído; passou o horário, desliga sozinho.',
          style: TextStyle(fontSize: 11.5, color: context.appTextSecondary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isEdit ? 'Editar compromisso' : 'Novo compromisso';
    final pickedFill = _colorFromHex(_colorHex);
    final onPicked = pickedFill.computeLuminance() > 0.55
        ? const Color(0xFF0F172A)
        : Colors.white;

    return Scaffold(
      backgroundColor: context.isDarkMode
          ? context.appScaffold
          : const Color(0xFFF1F5F9),
      resizeToAvoidBottomInset: scaffoldKeyboardResizeToAvoidBottomInset(
          standaloneFullPageForm: true),
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
          title,
          style:
              const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2),
        ),
        leading: IconButton(
          tooltip: 'Fechar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
          style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
        actions: [
          if (widget.isEdit)
            Builder(
              builder: (ctx) => IconButton(
                tooltip: 'Compartilhar',
                icon: const Icon(Icons.share_rounded),
                onPressed: () => _compartilhar(ctx),
              ),
            ),
        ],
      ),
      bottomNavigationBar: KeyboardAwareFormBar(
        standaloneFullPageForm: true,
        child: AgendaFormFooterActions(
          onCancel: () => Navigator.of(context).maybePop(),
          onSave: _submit,
          saveLabel: widget.isEdit ? 'Salvar alterações' : 'Salvar cadastro',
        ),
      ),
      // ListView com padding bottom dinâmico (viewInsets) — garante que o
      // último campo focado nunca fique escondido pelo teclado no iOS,
      // independente do dispositivo.
      body: keyboardScaffoldBody(
        standaloneFullPageForm: true,
        SafeArea(
          bottom: false,
          child: Builder(builder: (ctx) {
            final kb = KeyboardFormInsets.scrollBottomExtra(
              ctx,
              extra: 0,
              standaloneFullPageForm: true,
            );
            return ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + kb),
              children: [
                _buildHeader(title),
                const SizedBox(height: 10),
                // Ícones rápidos coloridos: REUNIÃO, MÉDICO, DENTISTA, IGREJA,
                // ANIVERSÁRIO, CASAMENTO. 1 toque preenche descrição + cor.
                CommitmentQuickIconsRow(
                  currentName: _titleCtrl.text,
                  enabled: true,
                  onPick: _aplicarPreset,
                ),
                const SizedBox(height: 10),
                // Título com sufixo "abrir lista" — abre picker fullscreen com
                // a lista alfabética completa + opção de incluir personalizado.
                _field(
                  controller: _titleCtrl,
                  label: 'Título *',
                  hint: 'Ex: Reunião, Consulta',
                  suffixIcon: IconButton(
                    tooltip: 'Lista de compromissos',
                    icon: const Icon(Icons.list_alt_rounded, size: 20),
                    color: AppColors.primary,
                    onPressed: _abrirPickerDescricao,
                    splashRadius: 22,
                  ),
                ),
                const SizedBox(height: 10),
                // Link de localização
                _field(
                  controller: _linkLocalizacaoCtrl,
                  label: 'Link de localização',
                  hint: 'Digite ou cole o link (opcional)',
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(left: 12, right: 8),
                    child: Icon(
                      Icons.location_on_rounded,
                      size: 18,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                  suffixIcon: IconButton(
                    tooltip: 'Colar',
                    icon: const Icon(Icons.content_paste_rounded, size: 18),
                    color: AppColors.primary,
                    splashRadius: 22,
                    onPressed: () =>
                        _pasteInto(_linkLocalizacaoCtrl, () => setState(() {})),
                  ),
                ),
                const SizedBox(height: 10),
                // Contato WhatsApp
                _field(
                  controller: _whatsAppCtrl,
                  label: 'Contato WhatsApp',
                  hint: 'Digite ou escolha da agenda',
                  keyboardType: TextInputType.phone,
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(left: 12, right: 8),
                    child: Icon(
                      Icons.chat_rounded,
                      size: 18,
                      color: Color(0xFF25D366),
                    ),
                  ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Seletor de contatos do sistema (Android ACTION_PICK /
                      // iOS CNContactPicker): não pede READ_CONTACTS. Fora do
                      // celular (web/desktop) o botão some — digita ou cola.
                      if (!kIsWeb &&
                          (defaultTargetPlatform == TargetPlatform.android ||
                              defaultTargetPlatform == TargetPlatform.iOS))
                        IconButton(
                          tooltip: 'Escolher da agenda',
                          icon: const Icon(Icons.contacts_rounded, size: 19),
                          color: AppColors.primary,
                          splashRadius: 22,
                          onPressed: _pickWhatsAppContact,
                        ),
                      IconButton(
                        tooltip: 'Colar',
                        icon: const Icon(Icons.content_paste_rounded, size: 18),
                        color: AppColors.primary,
                        splashRadius: 22,
                        onPressed: () =>
                            _pasteInto(_whatsAppCtrl, () => setState(() {})),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // Data + Início + Fim em 3 colunas para iPhone estreito.
                Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: _compactPickerTile(
                        icon: Icons.calendar_today_rounded,
                        label: 'DATA',
                        value: _dateFieldLabel,
                        onTap: _pickDate,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: _compactPickerTile(
                        icon: Icons.schedule_rounded,
                        label: 'INÍCIO',
                        value: _time.format(context),
                        onTap: _pickStartTime,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: _compactPickerTile(
                        icon: Icons.schedule_rounded,
                        label: 'FIM',
                        value: _endTime.format(context),
                        onTap: _pickEndTime,
                      ),
                    ),
                  ],
                ),
                if (_multiDateMode) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openPersonalizeDates,
                          icon: const Icon(Icons.tune_rounded, size: 18),
                          label: const Text(
                            'Personalizar',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      if (_selectedDates.length > 1) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => setState(() {
                            final d = _selectedDates.first;
                            _selectedDates = [DateTime(d.year, d.month, d.day)];
                            _date = _selectedDates.first;
                          }),
                          child: const Text('1 dia'),
                        ),
                      ],
                    ],
                  ),
                  if (_selectedDates.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _selectedDatesSummary(),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: context.isDarkMode ? context.appTextSecondary : Colors.grey.shade700,
                          height: 1.25,
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 10),
                DespertarItemCard(
                  value: _despertar,
                  descricaoItem: 'este compromisso',
                  onChanged: (v) => setState(() => _despertar = v),
                ),
                if (!_repeatYearly) ...[
                  const SizedBox(height: 10),
                  _despertadorTile(),
                ],
                const SizedBox(height: 10),
                _buildSymbolCard(pickedFill),
                const SizedBox(height: 10),
                _buildColorCard(pickedFill, onPicked),
                const SizedBox(height: 10),
                _field(
                  controller: _notesCtrl,
                  label: 'Observações',
                  hint: _repeatYearly
                      ? 'Inclui aviso de repetição anual (editável)'
                      : 'Detalhes opcionais',
                  maxLines: 4,
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.content_paste_rounded, size: 16),
                    label: const Text('Colar nas observações'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minimumSize: const Size(0, 36),
                      textStyle: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                    onPressed: () =>
                        _pasteInto(_notesCtrl, () => setState(() {})),
                  ),
                ),
                const SizedBox(height: 10),
                _buildRepeatYearlyCard(),
                const SizedBox(height: 6),
                _buildIntegracaoEscalaInfo(),
              ],
            );
          }),
        ),
      ),
    );
  }

  String _selectedDatesSummary() {
    if (_selectedDates.length <= 1) return '';
    final fmt = DateFormat('dd/MM');
    final shown = _selectedDates.take(8).map(fmt.format).join(', ');
    if (_selectedDates.length > 8) {
      return '$shown … (+${_selectedDates.length - 8})';
    }
    return shown;
  }

  Widget _buildHeader(String title) {
    return Material(
      color: context.isDarkMode
          ? context.appSurface
          : Colors.white.withValues(alpha: 0.98),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Padding(
                padding: EdgeInsets.all(7),
                child: Icon(Icons.event_available_rounded,
                    color: AppColors.primary, size: 20),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: context.appTextPrimary,
                        height: 1.1),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Compromisso particular · aparece no calendário de Escalas',
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.15,
                        color: context.isDarkMode ? context.appTextSecondary : Colors.grey.shade700,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorCard(Color pickedFill, Color onPicked) {
    return Material(
      color: context.isDarkMode ? context.appSurface : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Icon(Icons.palette_rounded, size: 18, color: AppColors.primary),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'Cor no calendário',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: context.appTextPrimary,
                ),
              ),
            ),
            Material(
              color: pickedFill,
              borderRadius: BorderRadius.circular(12),
              elevation: 2,
              shadowColor: pickedFill.withValues(alpha: 0.45),
              child: InkWell(
                onTap: _abrirSeletorCor,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.colorize_rounded, color: onPicked, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Trocar',
                        style: TextStyle(
                          color: onPicked,
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRepeatYearlyCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: context.isDarkMode ? context.appSurface : Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: _repeatYearly
                  ? const Color(0xFF2E7D32).withValues(alpha: 0.45)
                  : (context.isDarkMode
                      ? context.appChipIdleBorder
                      : Colors.grey.shade300),
              width: _repeatYearly ? 2 : 1,
            ),
          ),
          child: SwitchListTile(
            value: _repeatYearly,
            onChanged: _selectedDates.length > 1
                ? null
                : (v) {
                    setState(() {
                      _repeatYearly = v;
                      if (v) {
                        _applyYearlyNotesLine();
                      } else {
                        _notesCtrl.text = YearlyCommitmentRepeatService
                            .stripYearlyRepeatLines(
                          _notesCtrl.text,
                        );
                      }
                    });
                  },
            activeThumbColor: const Color(0xFF2E7D32),
            title: const Text(
              'Repetir todo ano',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            subtitle: Text(
              'Repete todo ano exatamente o título, horário e cor que você '
              'escreveu — sem criar outro compromisso similar.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.3,
                color: context.isDarkMode ? context.appTextSecondary : Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
            secondary: Icon(
              Icons.event_repeat_rounded,
              color:
                  _repeatYearly ? const Color(0xFF2E7D32) : AppColors.primary,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
        ),
      ],
    );
  }

  Widget _buildIntegracaoEscalaInfo() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.event_note_rounded, size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Este compromisso aparece no calendário da Agenda, com a cor escolhida. Se a integração Google Calendar estiver ativa, também será sincronizado lá.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: context.isDarkMode
                      ? context.appTextSecondary
                      : Colors.grey.shade800,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
