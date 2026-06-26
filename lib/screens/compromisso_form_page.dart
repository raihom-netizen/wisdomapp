import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide showDatePicker;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../constants/color_palette.dart';
import '../constants/commitment_presets.dart';
import '../models/user_profile.dart';
import '../services/agenda_scale_mirror_service.dart';
import '../theme/app_colors.dart';
import '../theme/gemini_theme.dart';
import '../services/yearly_commitment_repeat_service.dart';
import '../widgets/agenda_form_footer_actions.dart';
import '../widgets/fast_text_field.dart';
import '../utils/keyboard_form_scaffold.dart';
import '../widgets/commitment_description_picker.dart';
import '../widgets/multi_date_month_picker_dialog.dart';
import '../utils/premium_upgrade.dart';

/// Resultado ao salvar compromisso (novo ou edição).
class CompromissoFormResult {
  CompromissoFormResult({
    required this.title,
    required this.notes,
    required this.date,
    required this.time,
    required this.endTime,
    required this.colorHex,
    this.reminderLeads,
    this.notificationSoundId,
    this.notificationDeliveryMode,
    this.repeatYearly = false,
    this.yearlyRepeatWeekdays,
  });

  final String title;
  final String notes;
  final DateTime date;
  final TimeOfDay time;
  final TimeOfDay endTime;
  final String colorHex;
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
  });

  final UserProfile profile;
  final bool hasActiveLicense;
  final QueryDocumentSnapshot<Map<String, dynamic>>? existingDoc;
  /// Dia pré-selecionado ao abrir pelo calendário da Agenda.
  final DateTime? initialDate;

  bool get isEdit => existingDoc != null;

  @override
  State<CompromissoFormPage> createState() => _CompromissoFormPageState();
}

class _CompromissoFormPageState extends State<CompromissoFormPage> {
  late TextEditingController _titleCtrl;
  late TextEditingController _notesCtrl;
  late DateTime _date;
  late TimeOfDay _time;
  late TimeOfDay _endTime;
  late String _colorHex;
  bool _repeatYearly = false;

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
      _titleCtrl = TextEditingController(text: (data['title'] ?? '').toString());
      _notesCtrl = TextEditingController(text: (data['notes'] ?? '').toString());
      _date = (data['date'] as Timestamp?)?.toDate() ?? DateTime.now().add(const Duration(days: 1));
      _time = _parseHHmm((data['time'] ?? '09:00').toString(),
          const TimeOfDay(hour: 9, minute: 0));
      _endTime = _parseHHmm((data['endTime'] ?? '').toString(), _addOneHour(_time));
      final corSalva = (data['colorHex'] ?? '').toString().trim();
      _colorHex = corSalva.isNotEmpty ? _normalizeHex(corSalva) : kAgendaCompromissoDefaultColor;
      _repeatYearly = data['repeatYearly'] == true ||
          data['isYearlyRepeatTemplate'] == true ||
          (data['yearlyRepeatTemplateId'] ?? '').toString().trim().isNotEmpty;
    } else {
      _titleCtrl = TextEditingController();
      _notesCtrl = TextEditingController();
      final seed = widget.initialDate;
      _date = seed != null
          ? DateTime(seed.year, seed.month, seed.day)
          : DateTime.now().add(const Duration(days: 1));
      _time = const TimeOfDay(hour: 9, minute: 0);
      _endTime = const TimeOfDay(hour: 10, minute: 0);
      _colorHex = kAgendaCompromissoDefaultColor;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
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

  static Future<void> _pasteInto(TextEditingController ctrl, VoidCallback onChanged) async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text == null) return;
      final sel = ctrl.selection;
      final start = sel.start.clamp(0, ctrl.text.length);
      final end = sel.end.clamp(0, ctrl.text.length);
      ctrl.text = ctrl.text.replaceRange(start, end, data!.text!);
      ctrl.selection = TextSelection.collapsed(offset: start + data.text!.length);
      onChanged();
    } catch (_) {}
  }

  InputDecoration _inputDecoration(String label, String hint, {Widget? suffixIcon}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        suffixIcon: suffixIcon,
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
  }) {
    final isMultiline = maxLines != 1;
    return FastTextField(
      controller: controller,
      decoration: _inputDecoration(label, hint, suffixIcon: suffixIcon),
      kind: isMultiline ? FastTextFieldKind.prose : FastTextFieldKind.standard,
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
      color: const Color(0xFFF1F5F9),
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
                          color: Colors.grey.shade700,
                          letterSpacing: 0.2,
                        )),
                    const SizedBox(height: 2),
                    Text(value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
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

  Future<void> _pickDate() async {
    final picked = await pickSingleDateWithHolidayCalendar(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _date = picked;
        if (_repeatYearly) _applyYearlyNotesLine();
      });
    }
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
    final palette = kColorPaletteHex.take(72).toList();
    final colors = palette.map(_colorFromHex).toList();
    final idx = await showDialog<int>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(18, 12, 8, 2),
        title: Row(
          children: [
            const Expanded(
              child: Text(
                'Cor no calendário',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            TextButton.icon(
              onPressed: () => Navigator.pop(dlgCtx),
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Cancelar'),
              style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List.generate(colors.length, (i) {
              final c = colors[i];
              return InkWell(
                onTap: () => Navigator.pop(dlgCtx, i),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: c.withValues(alpha: 0.5),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
    if (idx == null || !mounted) return;
    if (idx >= 0 && idx < palette.length) {
      setState(() => _colorHex = _normalizeHex(palette[idx]));
    }
  }

  void _submit() {
    if (!widget.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o título do compromisso.')),
      );
      return;
    }
    Navigator.of(context).pop(
      CompromissoFormResult(
        title: title,
        notes: _notesCtrl.text.trim(),
        date: _date,
        time: _time,
        endTime: _endTime,
        colorHex: _colorHex,
        reminderLeads: null,
        notificationSoundId: null,
        notificationDeliveryMode: null,
        repeatYearly: _repeatYearly,
        yearlyRepeatWeekdays: null,
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
      backgroundColor: const Color(0xFFF1F5F9),
      resizeToAvoidBottomInset:
          scaffoldKeyboardResizeToAvoidBottomInset(standaloneFullPageForm: true),
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
          style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2),
        ),
        leading: IconButton(
          tooltip: 'Fechar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
          style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
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
              // Data + Início + Fim em 3 colunas para iPhone estreito.
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: _compactPickerTile(
                      icon: Icons.calendar_today_rounded,
                      label: 'DATA',
                      value: DateFormat("dd/MM (EEE)", 'pt_BR').format(_date),
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: const Size(0, 36),
                    textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () => _pasteInto(_notesCtrl, () => setState(() {})),
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

  Widget _buildHeader(String title) {
    return Material(
      color: Colors.white.withValues(alpha: 0.98),
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
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        height: 1.1),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Compromisso particular · aparece no calendário de Escalas',
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.15,
                        color: Colors.grey.shade700,
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
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Icon(Icons.palette_rounded, size: 18, color: AppColors.primary),
            const SizedBox(width: 9),
            const Expanded(
              child: Text(
                'Cor no calendário',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: _repeatYearly
              ? const Color(0xFF2E7D32).withValues(alpha: 0.45)
              : Colors.grey.shade300,
          width: _repeatYearly ? 2 : 1,
        ),
      ),
      child: SwitchListTile(
        value: _repeatYearly,
        onChanged: (v) {
          setState(() {
            _repeatYearly = v;
            if (v) {
              _applyYearlyNotesLine();
            } else {
              _notesCtrl.text = YearlyCommitmentRepeatService.stripYearlyRepeatLines(
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
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w500,
          ),
        ),
        secondary: Icon(
          Icons.event_repeat_rounded,
          color: _repeatYearly ? const Color(0xFF2E7D32) : AppColors.primary,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            Icon(Icons.event_note_rounded,
                size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Este compromisso aparece no calendário da Agenda, com a cor escolhida. Se a integração Google Calendar estiver ativa, também será sincronizado lá.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.grey.shade800,
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
