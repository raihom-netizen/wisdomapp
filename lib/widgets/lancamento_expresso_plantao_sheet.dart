import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'fast_text_field.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../constants/color_palette.dart';
import '../constants/commitment_presets.dart';
import '../constants/reminder_lead_chip_presets.dart';
import '../constants/currency_formats.dart';
import '../constants/field_text_limits.dart';
import '../models/scale_entry.dart';
import '../models/scale_rates.dart';
import '../models/shift_location.dart';
import '../services/scale_rates_service.dart';
import '../theme/app_colors.dart';
import '../widgets/shell_keyboard_bottom_pad.dart';
import '../utils/uppercase_text_input_formatter.dart';
import 'commitment_description_picker.dart';
import 'employer_vinculo_chips.dart';
import 'brl_amount_text_field.dart';
import 'multi_date_month_picker_dialog.dart';
import '../services/express_compromisso_agenda_sync.dart';
import '../utils/agenda_reminder_module_scope.dart';
import '../services/yearly_commitment_repeat_service.dart';
import '../utils/firestore_user_doc_id.dart';
import 'agenda_form_footer_actions.dart';

/// Lançamento rápido na escala sem exigir plantão pré-cadastrado.
///
/// **Nunca** grava em [users/uid/locations] (pré-cadastro).
/// Plantão: [users/uid/scales]. Compromisso particular: [users/uid/reminders] + espelho
/// em Escalas (`agenda_{id}`) — painel «em aberto», Agenda e calendário integrados.
Future<void> showLancamentoExpressoPlantaoSheet({
  required BuildContext context,
  required String uid,
  required DateTime day,

  /// Se não for null, permite vários dias no **mesmo mês** (lançamento em lote).
  List<DateTime>? days,
  required VoidCallback onSalvar,
  bool lockDate = false,

  /// Abre com financeiro ligado por padrão (Estado / Município / Particular); use [initialFinanceiro]: false para compromisso.
  bool initialFinanceiro = true,
  EmployerType initialEmployer = EmployerType.state,
  ScaleEntry? editingEntry,
}) {
  final initialDays = days ?? [day];
  final isEditing = editingEntry?.id != null;
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (sheetCtx) => Scaffold(
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
            // Padronização (rules: "Compromisso particular" no app inteiro).
            // Plantão usa "Lançamento expresso"; compromisso vira
            // "Compromisso particular" — mesmo nome do dashboard, do menu do
            // dia, da geração automática e do switch de edição rápida.
            initialFinanceiro
                ? (isEditing
                    ? 'Editar lançamento expresso'
                    : 'Lançamento expresso')
                : (isEditing
                    ? 'Editar compromisso particular'
                    : 'Compromisso particular'),
            style: const TextStyle(
                fontWeight: FontWeight.w900, letterSpacing: 0.2),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Fechar',
            onPressed: () => Navigator.of(sheetCtx).pop(),
          ),
        ),
        body: _LancamentoExpressoBody(
          uid: uid,
          day: day,
          initialDays: initialDays,
          lockDate: lockDate,
          onSalvar: onSalvar,
          initialFinanceiro: initialFinanceiro,
          initialEmployer: initialEmployer,
          editingEntry: editingEntry,
        ),
      ),
    ),
  );
}

class _LancamentoExpressoBody extends StatefulWidget {
  final String uid;
  final DateTime day;
  final List<DateTime> initialDays;
  final bool lockDate;
  final VoidCallback onSalvar;
  final bool initialFinanceiro;
  final EmployerType initialEmployer;
  final ScaleEntry? editingEntry;

  const _LancamentoExpressoBody({
    required this.uid,
    required this.day,
    required this.initialDays,
    this.lockDate = false,
    required this.onSalvar,
    this.initialFinanceiro = true,
    this.initialEmployer = EmployerType.state,
    this.editingEntry,
  });

  @override
  State<_LancamentoExpressoBody> createState() =>
      _LancamentoExpressoBodyState();
}

class _LancamentoExpressoBodyState extends State<_LancamentoExpressoBody> {
  late List<DateTime> _days;
  late TextEditingController _nomeCtrl;
  late TextEditingController _startCtrl;
  late TextEditingController _endCtrl;
  late TextEditingController _scaleNumberCtrl;
  late TextEditingController _notesCtrl;

  bool _financeiro = true;
  EmployerType _employer = EmployerType.state;
  bool _loading = false;
  Map<String, double>? _valorCalculado;
  ScaleRates? _ratesCache;
  Future<ScaleRates>? _ratesFuture;
  Timer? _valorRecalcDebounce;
  int _valorRecalcIndex = 0;
  late String _colorHexPicked;

  /// Primeiro plantão Particular com financeiro (Configurações → Plantões), p/ valores padrão no expresso.
  ShiftLocation? _privateTemplate;
  bool _privateOverride = false;

  /// true = valor fixo por plantão (diária); false = valor por hora (neste lançamento).
  bool _privateOverrideFixed = false;
  late TextEditingController _particularValorOverrideCtrl;

  /// Repetir todo ano (aniversário, casamento) — só com um único dia selecionado.
  bool _repeatYearly = false;

  String get _userDocId => firestoreUserDocIdForAppShell(widget.uid);
  bool get _isEditing => widget.editingEntry?.id != null;

  /// Modo "compromisso simples" (sem financeiro).
  ///
  /// Quando true, a tela esconde: switch de financeiro, chips de vínculo,
  /// número da escala e a mensagem "Avulso e seguro…"; e renomeia
  /// "Nome da escala / plantão" para "Descrição". Plantão (financeiro) segue
  /// idêntico. Definido pela origem do fluxo (initialFinanceiro=false ou
  /// edição de um item gravado como compromisso) — não muda durante a edição.
  ///
  /// Para edição: usa a mesma regra da chamada do sheet pelo módulo
  /// Escalas (scales_screen.dart): é compromisso quando `isCompromisso`
  /// estiver marcado **ou** quando o item não tem valor financeiro
  /// (`totalValue <= 0`). Assim, ao clicar "Editar" num compromisso (ou
  /// num plantão zerado), o usuário vê a versão simplificada que ele
  /// criou — só os campos essenciais.
  bool get _isCompromissoMode {
    final editing = widget.editingEntry;
    if (editing != null) {
      return editing.isCompromisso || editing.totalValue <= 0;
    }
    return !widget.initialFinanceiro;
  }

  CollectionReference<Map<String, dynamic>> get _scalesRef =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_userDocId)
          .collection('scales');

  static DateTime _normDay(DateTime d) => DateTime(d.year, d.month, d.day);

  List<DateTime> get _daysSorted =>
      _days.map(_normDay).toSet().toList()..sort((a, b) => a.compareTo(b));

  Future<void> _loadRepeatYearlyFromReminder(String reminderId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_userDocId)
          .collection('reminders')
          .doc(reminderId)
          .get();
      final d = snap.data();
      if (!mounted || d == null) return;
      final yearly = d['repeatYearly'] == true ||
          d['isYearlyRepeatTemplate'] == true ||
          (d['yearlyRepeatTemplateId'] ?? '').toString().trim().isNotEmpty;
      if (yearly) setState(() => _repeatYearly = true);
    } catch (_) {}
  }

  /// Dia usado no cálculo de preview e horários.
  DateTime get _day =>
      _daysSorted.isNotEmpty ? _daysSorted.first : _normDay(widget.day);

  @override
  void initState() {
    super.initState();
    final editing = widget.editingEntry;
    _days = editing != null
        ? [_normDay(editing.date)]
        : widget.initialDays.map(_normDay).toList();
    _financeiro = editing != null
        ? (!editing.isCompromisso && editing.totalValue > 0)
        : widget.initialFinanceiro;
    _employer = _employerFromEntry(editing) ?? widget.initialEmployer;
    _nomeCtrl = TextEditingController(
      text: editing == null
          ? ''
          : ShiftLocation.baseNameFromFull((editing.label ?? '').trim()),
    );
    _startCtrl = TextEditingController(text: editing?.start ?? '08:00');
    _endCtrl = TextEditingController(text: editing?.end ?? '18:00');
    _scaleNumberCtrl =
        TextEditingController(text: (editing?.scaleNumber ?? '').trim());
    _notesCtrl = TextEditingController(text: (editing?.notes ?? '').trim());
    _particularValorOverrideCtrl = TextEditingController();
    _startCtrl.addListener(_onFormChanged);
    _endCtrl.addListener(_onFormChanged);
    _particularValorOverrideCtrl.addListener(_onFormChanged);
    if (editing != null && (editing.isCompromisso || editing.totalValue <= 0)) {
      final rid = ExpressCompromissoAgendaSync.reminderIdFromScaleDocId(editing.id);
      if (rid != null) {
        unawaited(_loadRepeatYearlyFromReminder(rid));
      }
    }
    _colorHexPicked = editing?.colorHex?.trim().isNotEmpty == true
        ? _canonicalHex(editing!.colorHex!)
        : (kColorPaletteHex.isNotEmpty ? kColorPaletteHex[5] : '#5C6BC0');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadPrivateTemplate();
      if (_financeiro) _recalcularValor(immediate: true);
    });
  }

  Future<void> _loadPrivateTemplate() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_userDocId)
          .collection('locations')
          .get();
      ShiftLocation? best;
      var bestOrder = 1 << 30;
      for (final d in snap.docs) {
        final loc = ShiftLocation.fromMap(d.id, d.data());
        if (!loc.financialEnabled || loc.employerType != EmployerType.private) {
          continue;
        }
        if (loc.sortOrder < bestOrder) {
          bestOrder = loc.sortOrder;
          best = loc;
        }
      }
      if (!mounted) return;
      setState(() {
        _privateTemplate = best;
        if (best != null && best.baseValue > 0) {
          _particularValorOverrideCtrl.text =
              CurrencyFormats.formatBRLInput(best.baseValue);
        }
      });
      if (_financeiro && _employer == EmployerType.private) {
        _recalcularValor(immediate: true);
      }
    } catch (_) {}
  }

  /// Mesma regra do pré-cadastro em [scales_screen]: particular com valor fixo quando `fixed` ou [baseValue] > 0.
  bool _isPrivateFixedFromTemplate(ShiftLocation loc) =>
      loc.paymentType == PaymentType.fixed || loc.baseValue > 0;

  void _onFormChanged() {
    if (_financeiro) {
      _recalcularValor();
    }
  }

  @override
  void dispose() {
    _valorRecalcDebounce?.cancel();
    _particularValorOverrideCtrl.dispose();
    _scaleNumberCtrl.dispose();
    _notesCtrl.dispose();
    _nomeCtrl.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  String _normalizeColorHexForScale() {
    var hex = _colorHexPicked
        .replaceFirst(RegExp(r'^#'), '')
        .replaceFirst(RegExp(r'^0x', caseSensitive: false), '');
    if (hex.length > 6) hex = hex.substring(hex.length - 6);
    if (hex.length < 6) return '#5C6BC0';
    return '#${hex.toUpperCase()}';
  }

  Color _colorFromHex6(String hex) {
    var h = hex
        .replaceFirst('#', '')
        .replaceFirst(RegExp(r'^0x', caseSensitive: false), '');
    if (h.length > 6) h = h.substring(h.length - 6);
    return Color(int.parse('FF$h', radix: 16));
  }

  String _canonicalHex(String hex) {
    var h = hex
        .replaceFirst('#', '')
        .replaceFirst(RegExp(r'^0x', caseSensitive: false), '');
    if (h.length > 6) h = h.substring(h.length - 6);
    return '#${h.toUpperCase()}';
  }

  EmployerType? _employerFromEntry(ScaleEntry? entry) {
    switch ((entry?.employerType ?? '').trim().toLowerCase()) {
      case 'state':
        return EmployerType.state;
      case 'municipality':
        return EmployerType.municipality;
      case 'private':
        return EmployerType.private;
    }
    return null;
  }

  TimeOfDay _parseTime(String s) {
    final parts = s.trim().split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime(bool isStart) async {
    final ctrl = isStart ? _startCtrl : _endCtrl;
    final t = await showTimePicker(
      context: context,
      initialTime: _parseTime(ctrl.text),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (t != null && mounted) {
      ctrl.text = _formatTime(t);
      // No fluxo COMPROMISSO, ao definir o Início, auto-sugere o Fim
      // como Início + 1h se o Fim atual estiver vazio, igual ou antes do
      // novo Início — assim o usuário só configura uma vez. (No fluxo de
      // plantão preserva a lógica financeira existente.)
      if (isStart && _isCompromissoMode) {
        final start = t;
        final end = _parseTime(_endCtrl.text);
        final startMin = start.hour * 60 + start.minute;
        final endMin = end.hour * 60 + end.minute;
        final endIsEmpty = _endCtrl.text.trim().isEmpty;
        if (endIsEmpty || endMin <= startMin) {
          var sugMin = (startMin + 60) % (24 * 60);
          _endCtrl.text = _formatTime(
            TimeOfDay(hour: sugMin ~/ 60, minute: sugMin % 60),
          );
        }
      }
      setState(() {});
    }
  }

  InputDecoration _fieldDeco({required String labelText, String? hintText}) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            BorderSide(color: AppColors.deepBlue.withValues(alpha: 0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  // ----- Compromisso: atalhos rápidos + picker de descrição --------------

  /// Linha com os 6 ícones modernos coloridos dos compromissos mais comuns.
  /// Toque preenche descrição e sugere cor base. Reaproveita o widget
  /// reutilizável (mesma UX usada na "Geração automática").
  Widget _quickPresetIconsRow() {
    return CommitmentQuickIconsRow(
      currentName: _nomeCtrl.text,
      enabled: !_loading,
      onPick: _aplicarPresetCompromisso,
    );
  }

  /// Aplica preset: descrição em UPPER + cor sugerida.
  void _aplicarPresetCompromisso(CommitmentPreset p) {
    setState(() {
      _nomeCtrl.text = p.name.toUpperCase();
      _colorHexPicked = hexFromCommitmentColor(p.color);
    });
  }

  Future<void> _abrirPickerDescricao() async {
    final selected = await showCommitmentDescriptionPicker(
      context: context,
      uid: widget.uid,
      initialQuery: _nomeCtrl.text.trim(),
    );
    if (selected == null || !mounted) return;
    final preset = kCommitmentPresetByName[selected.toLowerCase().trim()];
    setState(() {
      _nomeCtrl.text = selected.toUpperCase();
      if (preset != null) {
        _colorHexPicked = hexFromCommitmentColor(preset.color);
      }
    });
  }

  // ----- Compartilhar (WhatsApp / e-mail) e Duplicar ---------------------

  /// Monta o texto pronto para compartilhar via WhatsApp, e-mail, etc.
  /// Usa os valores **atuais do formulário** (ainda não salvos), assim funciona
  /// também enquanto o usuário ajusta detalhes antes de gravar.
  String _buildShareText() {
    final tipoLabel = _isCompromissoMode ? 'Compromisso' : 'Plantão';
    final emoji = _isCompromissoMode ? '📅' : '⏰';
    final nomeBase = _nomeCtrl.text.trim();
    final titulo = nomeBase.isNotEmpty ? nomeBase.toUpperCase() : tipoLabel;
    final dia = _day;
    final dataLong =
        DateFormat("EEEE, d 'de' MMMM 'de' y", 'pt_BR').format(dia);
    final dataLongCap =
        dataLong.isNotEmpty ? dataLong[0].toUpperCase() + dataLong.substring(1) : dataLong;
    final start =
        _startCtrl.text.trim().isNotEmpty ? _startCtrl.text.trim() : '08:00';
    final end =
        _endCtrl.text.trim().isNotEmpty ? _endCtrl.text.trim() : '18:00';
    final notes = _notesCtrl.text.trim();

    final buffer = StringBuffer()
      ..writeln('$emoji *$titulo*')
      ..writeln('📆 $dataLongCap')
      ..writeln('🕒 $start às $end');
    if (notes.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('📝 $notes');
    }
    buffer
      ..writeln()
      ..write('— via WISDOMAPP');
    return buffer.toString();
  }

  Future<void> _compartilhar() async {
    final texto = _buildShareText();
    final subject = _nomeCtrl.text.trim().isNotEmpty
        ? _nomeCtrl.text.trim().toUpperCase()
        : (_isCompromissoMode ? 'Compromisso' : 'Plantão');
    try {
      await Share.share(texto, subject: subject);
    } catch (e) {
      // Fallback: copiar para a área de transferência se share falhar
      // (alguns ambientes web/PWA podem não suportar o nativo).
      try {
        await Clipboard.setData(ClipboardData(text: texto));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Compartilhamento indisponível — texto copiado para colar.'),
          duration: Duration(seconds: 3),
        ));
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não foi possível compartilhar agora.'),
        ));
      }
    }
  }

  /// Duplica o lançamento atual em edição, criando uma nova entrada **+7 dias**
  /// (mesma reunião na próxima semana). Mantém todos os campos (nome, cor,
  /// horário, lembrete personalizado, vínculo, valor). Marca como **não pago**
  /// (não foi de fato realizado). Após salvar, fecha o sheet, atualiza a tela
  /// e mostra um snackbar com a nova data.
  Future<void> _duplicar() async {
    final entry = widget.editingEntry;
    if (entry == null || entry.id == null) return;
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final novaData = entry.date.add(const Duration(days: 7));
      final newDoc = _scalesRef.doc();
      final base = entry.toMap();
      base['date'] = Timestamp.fromDate(
          DateTime.utc(novaData.year, novaData.month, novaData.day, 12, 0, 0));
      base['paid'] = false;
      base.remove('autoViradaMes');
      base.remove('autoViradaSourceId');
      await newDoc.set(base);
      if (!mounted) return;
      widget.onSalvar();
      Navigator.of(context).maybePop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Duplicado para ${DateFormat("EEEE, d/MM", 'pt_BR').format(novaData)}.'),
        duration: const Duration(seconds: 4),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Não foi possível duplicar: $e'),
      ));
    }
  }

  // ----- UI: barra de ações (em edição) e card de lembretes ----------------

  /// Barra com "Duplicar" e "Compartilhar" — só em edição. Botões grandes,
  /// modernos, com ícones; tom claro (não competem com o "Salvar" do rodapé).
  Widget _acoesEdicaoBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.deepBlue.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBlueDark.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: [
          Expanded(
            child: _acaoEdicaoChip(
              icon: Icons.copy_all_rounded,
              label: 'Duplicar +7 dias',
              color: const Color(0xFF1E88E5),
              onTap: _loading ? null : _duplicar,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _acaoEdicaoChip(
              icon: Icons.ios_share_rounded,
              label: 'Compartilhar',
              color: const Color(0xFF25D366),
              onTap: _loading ? null : _compartilhar,
            ),
          ),
        ],
      ),
    );
  }

  Widget _acaoEdicaoChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Card premium ultra-compacto. Ajustado para que TODOS os campos do
  /// lançamento caibam sem rolagem em iPhone com teclado aberto: header de
  /// 32px (em vez de ~46px), padding interno 10/12 (em vez de 14/14), título
  /// 13.5 (em vez de 15), subtítulo 11.5 (em vez de 12).
  Widget _expressoCard({
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
            color: AppColors.deepBlueDark.withValues(alpha: 0.07),
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
            padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.08),
                  AppColors.accent.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: AppColors.primary, size: 18),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.1,
                          height: 1.15,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                              height: 1.25,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirSeletorCor() async {
    final palette = kColorPaletteHex.take(72).toList();
    final colors = palette.map((hex) {
      var h = hex
          .replaceFirst('#', '')
          .replaceFirst(RegExp(r'^0x', caseSensitive: false), '');
      if (h.length > 6) h = h.substring(h.length - 6);
      return Color(int.parse('FF$h', radix: 16));
    }).toList();
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
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary),
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
                          offset: const Offset(0, 2)),
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
      setState(() => _colorHexPicked = _canonicalHex(palette[idx]));
    }
  }

  Future<Map<String, double>?> _valorMapForDay(
    DateTime forDay, {
    ScaleRates? cachedRates,
  }) async {
    if (!_financeiro) return null;
    final partsStart = _startCtrl.text.split(':');
    final partsEnd = _endCtrl.text.split(':');
    final startH =
        int.tryParse(partsStart.isNotEmpty ? partsStart[0] : '') ?? 8;
    final startM = partsStart.length > 1 ? int.tryParse(partsStart[1]) ?? 0 : 0;
    final endH = int.tryParse(partsEnd.isNotEmpty ? partsEnd[0] : '') ?? 18;
    final endM = partsEnd.length > 1 ? int.tryParse(partsEnd[1]) ?? 0 : 0;
    var startDt =
        DateTime(forDay.year, forDay.month, forDay.day, startH, startM);
    var endDt = DateTime(forDay.year, forDay.month, forDay.day, endH, endM);
    if (endDt.isBefore(startDt) || endDt.isAtSameMomentAs(startDt)) {
      endDt = endDt.add(const Duration(days: 1));
    }

    if (_employer == EmployerType.private) {
      final vManual =
          CurrencyFormats.parseBRLInput(_particularValorOverrideCtrl.text) ?? 0;

      if (_privateOverride) {
        if (_privateOverrideFixed) {
          return {
            'total': vManual,
            'hoursDay': 0,
            'hoursNight': 0,
            'dayRate': 0,
            'nightRate': 0,
          };
        }
        if (vManual <= 0) {
          return {
            'total': 0,
            'hoursDay': 0,
            'hoursNight': 0,
            'dayRate': 0,
            'nightRate': 0
          };
        }
        final durH = endDt.difference(startDt).inMinutes / 60.0;
        return {
          'total': durH * vManual,
          'hoursDay': durH,
          'hoursNight': 0,
          'dayRate': vManual,
          'nightRate': 0,
        };
      }

      final tpl = _privateTemplate;
      if (tpl != null &&
          _isPrivateFixedFromTemplate(tpl) &&
          tpl.baseValue > 0) {
        return {
          'total': tpl.baseValue,
          'hoursDay': 0,
          'hoursNight': 0,
          'dayRate': 0,
          'nightRate': 0,
        };
      }
    }

    final res = await ScaleRatesService().computeShiftForUid(
      uid: _userDocId,
      start: startDt,
      end: endDt,
      entryDate: forDay,
    );
    return res;
  }

  Future<ScaleRates> _getRatesCached() {
    final cached = _ratesCache;
    if (cached != null) return Future.value(cached);
    final existing = _ratesFuture;
    if (existing != null) return existing;
    final future =
        ScaleRatesService().getEffectiveRates(_userDocId).then((rates) {
      _ratesCache = rates;
      return rates;
    });
    _ratesFuture = future;
    return future;
  }

  void _recalcularValor({bool immediate = false}) {
    _valorRecalcDebounce?.cancel();
    final index = ++_valorRecalcIndex;
    if (!_financeiro) {
      if (_valorCalculado != null && mounted) {
        setState(() => _valorCalculado = null);
      }
      return;
    }

    Future<void> run() async {
      final res = await _valorMapForDay(_day, cachedRates: _ratesCache);
      if (!mounted || index != _valorRecalcIndex) return;
      setState(() => _valorCalculado = res);
    }

    if (immediate) {
      unawaited(run());
    } else {
      _valorRecalcDebounce = Timer(const Duration(milliseconds: 120), () {
        unawaited(run());
      });
    }
  }

  String _labelBotaoDatasExpresso() {
    final ds = _daysSorted;
    if (ds.isEmpty) {
      return DateFormat('EEEE, d \'de\' MMMM', 'pt_BR').format(widget.day);
    }
    if (widget.lockDate || ds.length == 1) {
      return DateFormat('EEEE, d \'de\' MMMM', 'pt_BR').format(ds.first);
    }
    final mes = DateFormat('MMMM yyyy', 'pt_BR').format(ds.first);
    final nums = ds.map((d) => '${d.day}').join(', ');
    return '${ds.length} dias em $mes ($nums)';
  }

  String _autoViradaMarker(String sourceId) => '[AUTO_VIRADA_MES:$sourceId]';
  String _autoViradaNote(String sourceId) =>
      'Lançamento automático (virada de mês) ${_autoViradaMarker(sourceId)}';

  bool _isLastDayOfMonth(DateTime d) => ScaleRates.isLastDayOfMonth(d);

  Future<void> _removeAutoLancamentoBySourceId(String sourceId) async {
    final bySource =
        await _scalesRef.where('autoViradaSourceId', isEqualTo: sourceId).get();
    for (final doc in bySource.docs) {
      await _scalesRef.doc(doc.id).delete();
    }
    final note = _autoViradaNote(sourceId);
    final legacy = await _scalesRef.where('notes', isEqualTo: note).get();
    for (final doc in legacy.docs) {
      await _scalesRef.doc(doc.id).delete();
    }
  }

  Future<void> _syncAutoViradaMes({
    required String sourceId,
    required bool financialEnabled,
    required String employerTypeName,
    required String start,
    required String end,
    required String labelComHorario,
    required String abbreviation,
    required String colorHex,
    required DateTime entryDate,
  }) async {
    await _removeAutoLancamentoBySourceId(sourceId);
    if (!financialEnabled) return;
    if (!_isLastDayOfMonth(entryDate)) return;

    final partsStart = start.split(':');
    final partsEnd = end.split(':');
    final startH = int.tryParse(partsStart.first) ?? 8;
    final startM = partsStart.length > 1 ? int.tryParse(partsStart[1]) ?? 0 : 0;
    final endH = int.tryParse(partsEnd.first) ?? 18;
    final endM = partsEnd.length > 1 ? int.tryParse(partsEnd[1]) ?? 0 : 0;
    final startDt = DateTime(
        entryDate.year, entryDate.month, entryDate.day, startH, startM);
    var endDt =
        DateTime(entryDate.year, entryDate.month, entryDate.day, endH, endM);
    if (endDt.isBefore(startDt) || endDt.isAtSameMomentAs(startDt)) {
      endDt = endDt.add(const Duration(days: 1));
    }
    if (endDt.day == entryDate.day &&
        endDt.month == entryDate.month &&
        endDt.year == entryDate.year) {
      return;
    }

    final carryDate = DateTime(entryDate.year, entryDate.month, entryDate.day)
        .add(const Duration(days: 1));
    final nextStart = DateTime(carryDate.year, carryDate.month, carryDate.day);
    final res = await ScaleRatesService().computeShiftForUid(
      uid: _userDocId,
      start: nextStart,
      end: endDt,
      entryDate: carryDate,
    );
    final total = (res['total'] ?? 0).toDouble();
    if (total <= 0) return;

    final ratesCarry =
        await ScaleRatesService().getRatesForServiceDay(_userDocId, carryDate);
    final ratesSource =
        await ScaleRatesService().getRatesForServiceDay(_userDocId, entryDate);

    final hoje =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final autoEntry = ScaleEntry(
      date: carryDate,
      start: '00:00',
      end:
          '${endDt.hour.toString().padLeft(2, '0')}:${endDt.minute.toString().padLeft(2, '0')}',
      dayRate:
          ratesCarry.diurnoForWeekday(ScaleRates.weekdayToIndex(carryDate.weekday)),
      nightRate:
          ratesSource.noturnoForWeekday(ScaleRates.weekdayToIndex(entryDate.weekday)),
      hoursDay: (res['hoursDay'] ?? 0).toDouble(),
      hoursNight: (res['hoursNight'] ?? 0).toDouble(),
      totalValue: total,
      label: labelComHorario,
      abbreviation: abbreviation,
      colorHex: colorHex,
      paid: carryDate.isBefore(hoje),
      isCompromisso: false,
      employerType: employerTypeName,
      notes: _autoViradaNote(sourceId),
    );
    final autoMap = autoEntry.toMap();
    autoMap['autoViradaMes'] = true;
    autoMap['autoViradaSourceId'] = sourceId;
    await _scalesRef.add(autoMap);
  }

  Future<void> _salvar() async {
    final rawName = _nomeCtrl.text.trim().toUpperCase();
    final baseName = ShiftLocation.baseNameFromFull(rawName);
    final faltando = <String>[];
    if (baseName.isEmpty) {
      faltando.add(_isCompromissoMode ? 'Descrição' : 'Nome da escala/plantão');
    }
    if (faltando.isNotEmpty) {
      final texto = faltando.length == 1
          ? 'Não foi possível gravar. Preencha: ${faltando.single} (obrigatório).'
          : 'Não foi possível gravar. Campos obrigatórios: ${faltando.join(' e ')}.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(texto)));
      return;
    }

    if (_financeiro && _employer == EmployerType.private && _privateOverride) {
      final v =
          CurrencyFormats.parseBRLInput(_particularValorOverrideCtrl.text) ?? 0;
      if (v <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _privateOverrideFixed
                  ? 'Particular: informe o valor fixo (diária) em reais.'
                  : 'Particular: informe o valor da hora em reais.',
            ),
          ),
        );
        return;
      }
    }

    final start =
        _startCtrl.text.trim().isNotEmpty ? _startCtrl.text.trim() : '08:00';
    final end =
        _endCtrl.text.trim().isNotEmpty ? _endCtrl.text.trim() : '18:00';
    final autoAbbrev = ShiftLocation.abbreviationFromName(baseName);
    final abbrev = autoAbbrev.isNotEmpty
        ? autoAbbrev.substring(0, autoAbbrev.length.clamp(1, 6))
        : '';
    final colorHex = _normalizeColorHexForScale();
    final labelComHorario =
        ShiftLocation.fullNameWithSchedule(baseName, start, end);

    setState(() => _loading = true);
    try {
      final hoje = DateTime(
          DateTime.now().year, DateTime.now().month, DateTime.now().day);
      final dias = _daysSorted;
      if (dias.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final bool isCompromisso = !_financeiro;
      final bool compromissoParticularNaAgenda = isCompromisso &&
          !expressTitleLooksLikePlantaoEscala(baseName);
      final String employerTypeName =
          _financeiro ? _employer.name : EmployerType.private.name;
      final ScaleRates? cachedRates = _financeiro
          ? await ScaleRatesService().getEffectiveRates(_userDocId)
          : null;

      var gravados = 0;
      final pendingMainEntries = <({
        DocumentReference<Map<String, dynamic>> ref,
        Map<String, dynamic> data,
        DateTime dayNorm,
      })>[];

      if (compromissoParticularNaAgenda) {
        final existingScaleId =
            _isEditing ? widget.editingEntry?.id?.trim() : null;

        final useYearlyRepeat = _repeatYearly && dias.length == 1;

        if (useYearlyRepeat) {
          final dayNorm = dias.first;
          if (_isEditing && existingScaleId != null) {
            final rid =
                ExpressCompromissoAgendaSync.reminderIdFromScaleDocId(
                        existingScaleId) ??
                    existingScaleId;
            final snap = await FirebaseFirestore.instance
                .collection('users')
                .doc(_userDocId)
                .collection('reminders')
                .doc(rid)
                .get();
            final tid = YearlyCommitmentRepeatService.templateIdFromReminderData(
                  snap.data() ?? {},
                  rid,
                ) ??
                rid;
            await YearlyCommitmentRepeatService.updateYearlySeries(
              userDocId: _userDocId,
              templateId: tid,
              title: baseName,
              notes: normalizeScaleNotesForSave(_notesCtrl.text),
              anchorCalendarDay: dayNorm,
              startHHmm: start,
              endHHmm: end,
              colorHex: colorHex,
              reminderLeads: null,
              notificationSoundId: null,
              notificationDeliveryMode: null,
            );
            gravados = 1;
          } else {
            await YearlyCommitmentRepeatService.createWithYearlyRepeat(
              userDocId: _userDocId,
              title: baseName,
              notes: normalizeScaleNotesForSave(_notesCtrl.text),
              anchorCalendarDay: dayNorm,
              startHHmm: start,
              endHHmm: end,
              colorHex: colorHex,
              reminderLeads: null,
              notificationSoundId: null,
              notificationDeliveryMode: null,
            );
            gravados = 1;
          }
        } else {
          for (final dayNorm in dias) {
            await ExpressCompromissoAgendaSync.upsertFromExpress(
              userDocId: _userDocId,
              title: baseName,
              date: dayNorm,
              startHHmm: start,
              endHHmm: end,
              colorHex: colorHex,
              notes: normalizeScaleNotesForSave(_notesCtrl.text),
              existingScaleDocId:
                  dias.length == 1 ? existingScaleId : null,
              reminderLeads: null,
              notificationSoundId: null,
              notificationDeliveryMode: null,
            );
            gravados++;
          }
        }
        ExpressCompromissoAgendaSync.refreshNotifications(_userDocId);

        if (!mounted) return;
        Navigator.pop(context);
        final msg = useYearlyRepeat
            ? (_isEditing
                ? '$baseName atualizado — repete todo ano em Escalas.'
                : '$baseName salvo — repete automaticamente todo ano.')
            : (_isEditing
                ? '$baseName atualizado na Agenda e no calendário.'
                : (gravados == 1
                    ? '$baseName gravado — aparece no painel, Agenda e Escalas.'
                    : '$gravados compromissos gravados — painel, Agenda e Escalas.'));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
        widget.onSalvar();
        return;
      }

      for (final dayNorm in dias) {
        final isRetroativo = dayNorm.isBefore(hoje);

        double totalValue = 0;
        double hoursDay = 0;
        double hoursNight = 0;
        double dayRate = 0;
        double nightRate = 0;

        if (_financeiro && cachedRates != null) {
          final valorLocal = await _valorMapForDay(
            dayNorm,
            cachedRates: cachedRates,
          );
          if (valorLocal != null) {
            totalValue = valorLocal['total'] ?? 0;
            hoursDay = valorLocal['hoursDay'] ?? 0;
            hoursNight = valorLocal['hoursNight'] ?? 0;
            if (valorLocal.containsKey('dayRate') &&
                valorLocal.containsKey('nightRate')) {
              dayRate = valorLocal['dayRate'] ?? 0;
              nightRate = valorLocal['nightRate'] ?? 0;
            } else {
              dayRate = cachedRates
                  .diurnoForWeekday(ScaleRates.weekdayToIndex(dayNorm.weekday));
              nightRate = cachedRates.noturnoForWeekday(
                  ScaleRates.weekdayToIndex(dayNorm.weekday));
            }
          }
        }

        final entry = ScaleEntry(
          date: dayNorm,
          start: start,
          end: end,
          dayRate: dayRate,
          nightRate: nightRate,
          hoursDay: hoursDay,
          hoursNight: hoursNight,
          totalValue: totalValue,
          label: labelComHorario,
          abbreviation: abbrev,
          colorHex: colorHex,
          paid: _isEditing ? widget.editingEntry!.paid : isRetroativo,
          isCompromisso: isCompromisso,
          employerType: employerTypeName,
          notes: normalizeScaleNotesForSave(_notesCtrl.text),
          scaleNumber: _scaleNumberCtrl.text.trim().toUpperCase(),
          source: 'lancamento_expresso',
          lancamentoOrigem: 'lancamento_expresso',
          createdByLancamentoExpresso: true,
          reminderLeads: null,
          notificationSoundId: null,
          notificationDeliveryMode: null,
        );

        final ref = _isEditing
            ? _scalesRef.doc(widget.editingEntry!.id)
            : _scalesRef.doc();
        pendingMainEntries.add((
          ref: ref,
          data: entry.toMap(),
          dayNorm: dayNorm,
        ));
      }

      const batchLimit = 450;
      for (var i = 0; i < pendingMainEntries.length; i += batchLimit) {
        final batch = FirebaseFirestore.instance.batch();
        final slice = pendingMainEntries.skip(i).take(batchLimit);
        for (final item in slice) {
          if (_isEditing) {
            batch.update(item.ref, item.data);
          } else {
            batch.set(item.ref, item.data);
          }
        }
        await batch.commit();
      }

      gravados = pendingMainEntries.length;

      // Pequeno intervalo antes de escritas/leituras extras (virada de mês): reduz corrida no listener na web.
      await Future.delayed(const Duration(milliseconds: 120));

      for (final item in pendingMainEntries) {
        await _syncAutoViradaMes(
          sourceId: item.ref.id,
          financialEnabled: _financeiro,
          employerTypeName: employerTypeName,
          start: start,
          end: end,
          labelComHorario: labelComHorario,
          abbreviation: abbrev,
          colorHex: colorHex,
          entryDate: item.dayNorm,
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
      final msg = _isEditing
          ? '$labelComHorario atualizado.'
          : (gravados == 1
              ? '$labelComHorario gravado na escala.'
              : '$gravados lançamentos de "$baseName" gravados na escala.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      widget.onSalvar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: ${e.toString().split('\n').first}')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final padBottom = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final pickedFill = _colorFromHex6(_colorHexPicked);
    final onPicked = pickedFill.computeLuminance() > 0.55
        ? AppColors.textPrimary
        : Colors.white;

    // Altura aproximada do footer (Cancelar + Gravar) — usada como padding
    // bottom do ListView para que, ao focar um campo, o Flutter role o
    // suficiente e o campo focado fique visível ACIMA do footer (não atrás
    // dele). O footer fica sticky e não duplica o viewInsets — o Scaffold
    // já encolhe o body quando o teclado abre.
    const footerApproxHeight = 84.0;
    return Column(
      children: [
        Expanded(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, footerApproxHeight),
            children: [
              // Em edição, exibimos uma barra de ações rápidas com Duplicar
              // e Compartilhar (WhatsApp / e-mail). Não aparece em criação
              // para não poluir a primeira impressão visual do cadastro.
              if (_isEditing) ...[
                _acoesEdicaoBar(),
                const SizedBox(height: 10),
              ],
              // Card de cabeçalho — só aparece para PLANTÃO (com financeiro).
              // Compromisso fica direto na Data, sem essa explicação extra
              // (tela mais compacta, conforme pedido do usuário).
              if (!_isCompromissoMode) ...[
                _expressoCard(
                  icon: Icons.flash_on_rounded,
                  title: 'Lançamento expresso',
                  subtitle: _isEditing
                      ? 'Edite aqui o item criado pelo lançamento expresso.'
                      : 'Plantão com financeiro ou compromisso sem valor — mesmo fluxo visual do pré-cadastro.',
                  children: [
                    Text(
                      'Avulso e seguro: fica só no calendário e nos relatórios (coleção da escala). Não é gravado no pré-cadastro de Plantões. Para reutilizar um nome, cadastre depois em Configurações → Plantões.',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                          height: 1.35,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              // Card único "Quando" (Data + Horário). Antes eram dois cards
              // separados; unificados aqui para a tela caber sem rolagem em
              // iPhone — mesmo com teclado aberto, fica todos os campos
              // visíveis. Mantém UX premium e visual.
              _expressoCard(
                icon: Icons.event_available_rounded,
                title: _isCompromissoMode ? 'Quando' : 'Data e horário',
                children: [
                  if (_isEditing)
                    FilledButton.tonalIcon(
                      onPressed: _loading
                          ? null
                          : () async {
                              final picked =
                                  await pickSingleDateWithHolidayCalendar(
                                context: context,
                                initialDate: _day,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030, 12, 31),
                              );
                              if (picked != null && mounted) {
                                setState(() => _days = [_normDay(picked)]);
                                if (_financeiro) _recalcularValor();
                              }
                            },
                      icon: const Icon(Icons.calendar_today_rounded, size: 18),
                      label: Text(
                        DateFormat('EEEE, d \'de\' MMMM', 'pt_BR').format(_day),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: FilledButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(
                            vertical: 11, horizontal: 12),
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.1),
                        foregroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    )
                  else if (widget.lockDate)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.18)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.event_available_rounded,
                              size: 19, color: AppColors.primary),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              DateFormat('EEEE, d \'de\' MMMM', 'pt_BR')
                                  .format(_day),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                  color: AppColors.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    FilledButton.tonalIcon(
                      onPressed: _loading
                          ? null
                          : () async {
                              final res = await showMultiDateMonthPickerDialog(
                                context: context,
                                month: DateTime(_day.year, _day.month, 1),
                                initialSelected: _days,
                              );
                              if (res != null && res.isNotEmpty && mounted) {
                                setState(() {
                                  _days = res.map(_normDay).toList();
                                  if (_days.length >= 3) {
                                    _repeatYearly = false;
                                  }
                                });
                                if (_financeiro) _recalcularValor();
                              }
                            },
                      icon: const Icon(Icons.calendar_today_rounded, size: 18),
                      label: Text(_labelBotaoDatasExpresso(),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      style: FilledButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(
                            vertical: 11, horizontal: 12),
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.1),
                        foregroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  const SizedBox(height: 10),
                  // Horário (Início + Fim) — agora dentro do MESMO card
                  // "Quando", evitando o gap/header de um card separado.
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _loading ? null : () => _pickTime(true),
                          borderRadius: BorderRadius.circular(14),
                          child: InputDecorator(
                            decoration: _fieldDeco(labelText: 'Início').copyWith(
                              suffixIcon: const Icon(Icons.schedule_rounded,
                                  color: AppColors.primary, size: 20),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            child: Text(
                              _startCtrl.text.isEmpty ? '08:00' : _startCtrl.text,
                              style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: _loading ? null : () => _pickTime(false),
                          borderRadius: BorderRadius.circular(14),
                          child: InputDecorator(
                            decoration: _fieldDeco(labelText: 'Fim').copyWith(
                              suffixIcon: const Icon(Icons.schedule_rounded,
                                  color: AppColors.primary, size: 20),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            child: Text(
                              _endCtrl.text.isEmpty ? '18:00' : _endCtrl.text,
                              style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Card "Opções" (switch financeiro + vínculo + override Particular)
              // só aparece para PLANTÃO. Compromisso é sempre sem financeiro,
              // então não há nada para configurar — fluxo fica mais compacto.
              if (!_isCompromissoMode) ...[
              const SizedBox(height: 10),
              _expressoCard(
                icon: Icons.tune_rounded,
                title: 'Opções',
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _financeiro,
                    title: const Text('Habilitar financeiro',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14)),
                    subtitle: const Text(
                      'Calcula valor (Estado, Município ou Particular). Desligado = compromisso sem valor.',
                      style: TextStyle(fontSize: 12.5, height: 1.35),
                    ),
                    activeTrackColor: AppColors.primary.withValues(alpha: 0.45),
                    activeThumbColor: Colors.white,
                    inactiveTrackColor:
                        AppColors.textMuted.withValues(alpha: 0.25),
                    onChanged: _loading
                        ? null
                        : (v) {
                            setState(() {
                              _financeiro = v;
                              if (v) {
                                _recalcularValor();
                              } else {
                                _valorCalculado = null;
                              }
                            });
                          },
                  ),
                  if (_financeiro) ...[
                    const SizedBox(height: 6),
                    const Text('Vínculo',
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 8),
                    EmployerVinculoChips.selectionRow(
                      dense: true,
                      selected: _employer,
                      onChanged: (t) {
                        setState(() => _employer = t);
                        _recalcularValor();
                      },
                    ),
                    if (_employer == EmployerType.private) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        decoration: BoxDecoration(
                          color: AppColors.vinculoParticular
                              .withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: AppColors.vinculoParticular
                                  .withValues(alpha: 0.22)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_privateTemplate != null && !_privateOverride)
                              Text(
                                _isPrivateFixedFromTemplate(_privateTemplate!)
                                    ? 'Valor fixo do plantão «${_privateTemplate!.name}» (Configurações → Plantões).'
                                    : 'Por hora conforme tabela da escala e o plantão «${_privateTemplate!.name}» (Configurações → Plantões).',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textSecondary,
                                    height: 1.35),
                              )
                            else if (_privateTemplate == null &&
                                !_privateOverride)
                              Text(
                                'Nenhum plantão Particular com financeiro no pré-cadastro. Usando a tabela de horas da escala (Configurações → Escala). Use a opção abaixo para informar valor por hora ou fixo.',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textSecondary,
                                    height: 1.35),
                              ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                  'Definir valor só neste lançamento',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: const Text(
                                  'Valor da hora ou valor fixo (diária), sem alterar o pré-cadastro.'),
                              value: _privateOverride,
                              activeTrackColor:
                                  AppColors.primary.withValues(alpha: 0.45),
                              activeThumbColor: Colors.white,
                              inactiveTrackColor:
                                  AppColors.textMuted.withValues(alpha: 0.25),
                              onChanged: (v) {
                                setState(() {
                                  _privateOverride = v;
                                  if (v &&
                                      _privateTemplate != null &&
                                      _privateTemplate!.baseValue > 0) {
                                    _particularValorOverrideCtrl.text =
                                        CurrencyFormats.formatBRLInput(
                                            _privateTemplate!.baseValue);
                                    _privateOverrideFixed =
                                        _isPrivateFixedFromTemplate(
                                            _privateTemplate!);
                                  }
                                });
                                _recalcularValor();
                              },
                            ),
                            if (_privateOverride) ...[
                              SegmentedButton<bool>(
                                segments: const [
                                  ButtonSegment<bool>(
                                      value: false,
                                      label: Text('Por hora'),
                                      icon: Icon(Icons.schedule_rounded,
                                          size: 18)),
                                  ButtonSegment<bool>(
                                      value: true,
                                      label: Text('Valor fixo'),
                                      icon: Icon(Icons.payments_rounded,
                                          size: 18)),
                                ],
                                selected: {_privateOverrideFixed},
                                onSelectionChanged: (s) {
                                  setState(
                                      () => _privateOverrideFixed = s.first);
                                  _recalcularValor();
                                },
                              ),
                              const SizedBox(height: 10),
                              BrlAmountTextField(
                                controller: _particularValorOverrideCtrl,
                                decoration: _fieldDeco(
                                  labelText: _privateOverrideFixed
                                      ? 'Valor fixo do plantão (R\$)'
                                      : 'Valor da hora (R\$)',
                                  hintText: '0,00',
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
              ],
              const SizedBox(height: 10),
              _expressoCard(
                icon: Icons.badge_rounded,
                title: 'Identificação',
                subtitle: _isCompromissoMode
                    ? 'Toque num ícone para preencher rápido — ou abra a lista.'
                    : null,
                children: [
                  // Atalhos visuais (6 ícones modernos coloridos) só no fluxo
                  // de compromisso simples. Toque preenche descrição + cor.
                  if (_isCompromissoMode) ...[
                    _quickPresetIconsRow(),
                    const SizedBox(height: 10),
                  ],
                  // Em compromisso o campo vira TextField + sufixo "abrir
                  // lista" (40 sugestões + customizadas) — usuário digita ou
                  // escolhe da lista, igual despesas/receitas.
                  FastTextField(
                    controller: _nomeCtrl,
                    decoration: _fieldDeco(
                        labelText: _isCompromissoMode
                            ? 'Descrição *'
                            : 'Nome da escala / plantão *',
                        hintText: _isCompromissoMode
                            ? 'EX.: REUNIÃO COM EQUIPE'
                            : 'EX.: UPA NORTE').copyWith(
                      suffixIcon: _isCompromissoMode
                          ? IconButton(
                              tooltip: 'Escolher da lista',
                              icon: const Icon(
                                Icons.arrow_drop_down_circle_rounded,
                                color: AppColors.primary,
                              ),
                              onPressed:
                                  _loading ? null : _abrirPickerDescricao,
                            )
                          : null,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [UpperCaseTextFormatter()],
                  ),
                  if (!_isCompromissoMode) ...[
                    const SizedBox(height: 8),
                    FastTextField(
                      controller: _scaleNumberCtrl,
                      decoration: _fieldDeco(
                          labelText: 'Número da escala',
                          hintText: 'EX.: RAI 123'),
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [UpperCaseTextFormatter()],
                    ),
                  ],
                  const SizedBox(height: 8),
                  FastTextField(
                    controller: _notesCtrl,
                    minLines: _isCompromissoMode ? 2 : 3,
                    maxLines: _isCompromissoMode ? 6 : 8,
                    maxLength: kScaleNotesMaxLength,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    decoration: _fieldDeco(
                        labelText: 'Observações',
                        hintText: _isCompromissoMode
                            ? 'Detalhes do compromisso (até $kScaleNotesMaxLength caracteres)'
                            : 'Detalhes do plantão (até $kScaleNotesMaxLength caracteres)'),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [UpperCaseTextFormatter()],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _expressoCard(
                icon: Icons.palette_rounded,
                title: 'Cor no calendário',
                subtitle: _isCompromissoMode
                    ? 'Como o compromisso aparece no calendário.'
                    : 'Mesmas 72 cores do pré-cadastro (Configurações → Plantões).',
                children: [
                  Material(
                    color: pickedFill,
                    borderRadius: BorderRadius.circular(14),
                    elevation: 2,
                    shadowColor: pickedFill.withValues(alpha: 0.45),
                    child: InkWell(
                      onTap: _loading ? null : _abrirSeletorCor,
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        height: 44,
                        width: double.infinity,
                        child: Center(
                          child: Text(
                            'Toque para escolher a cor',
                            style: TextStyle(
                                color: onPicked,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.25,
                                fontSize: 13.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_isCompromissoMode && _daysSorted.length == 1) ...[
                const SizedBox(height: 10),
                _expressoCard(
                  icon: Icons.event_repeat_rounded,
                  title: 'Repetir todo ano',
                  subtitle:
                      'Repete exatamente o que você escreveu — 1 vez por ano, sem criar outro similar. Para 3+ dias, use o calendário sem esta opção.',
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: _repeatYearly,
                      onChanged: _loading
                          ? null
                          : (v) => setState(() => _repeatYearly = v),
                      title: const Text(
                        'Ativar repetição anual',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13.5),
                      ),
                      activeTrackColor:
                          const Color(0xFF2E7D32).withValues(alpha: 0.45),
                      activeThumbColor: Colors.white,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              if (_financeiro && _valorCalculado != null) ...[
                const SizedBox(height: 10),
                _expressoCard(
                  icon: Icons.payments_rounded,
                  title: 'Valor estimado',
                  children: [
                    if (_daysSorted.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          'Valor estimado para o 1º dia (${DateFormat('dd/MM').format(_daysSorted.first)}); nos demais dias o total segue o dia da semana.',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textMuted,
                              height: 1.35),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Diurnas',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        Text(
                            '${(_valorCalculado!['hoursDay'] ?? 0).toStringAsFixed(1)} h',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Noturnas',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        Text(
                            '${(_valorCalculado!['hoursNight'] ?? 0).toStringAsFixed(1)} h',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const Divider(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total',
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                color: AppColors.deepBlue)),
                        Text(
                          CurrencyFormats.formatBRL(
                              (_valorCalculado!['total'] ?? 0) as num),
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                              color: AppColors.deepBlue),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        // Footer sticky. Quando o teclado abre, o Scaffold já encolhe o
        // body — NÃO somamos `padBottom` aqui (isso duplicava o ajuste e
        // empurrava o footer para fora da tela em iPhone). Apenas a área
        // segura do dispositivo é considerada.
        Container(
          padding: EdgeInsets.fromLTRB(
              14, 8, 14, 8 + (padBottom > 0 ? 0 : safeBottom)),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 10,
                  offset: const Offset(0, -2)),
            ],
          ),
          child: AgendaFormFooterActions(
            onCancel: () => Navigator.of(context).maybePop(),
            onSave: _salvar,
            saveLabel: _isEditing
                ? 'Salvar alterações'
                : (_daysSorted.length > 1
                    ? 'Gravar em ${_daysSorted.length} dias'
                    : 'Gravar'),
            isBusy: _loading,
            busyLabel: 'Salvando…',
            saveIcon: _isEditing ? Icons.save_rounded : Icons.add_task_rounded,
          ),
        ),
      ],
    );
  }
}
