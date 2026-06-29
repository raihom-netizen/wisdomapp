import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:table_calendar/table_calendar.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../models/user_profile.dart';
import '../models/scale_rates.dart';
import '../models/scale_entry.dart';
import '../utils/scale_entry_sei_ocorrencia.dart';
import '../widgets/scale_plantao_edit_dialog.dart';
import '../widgets/scale_entry_notes_grid.dart';
import '../constants/color_palette.dart';
import '../constants/currency_formats.dart';
import '../theme/app_colors.dart';
import '../theme/gemini_theme.dart';
import '../services/scale_rates_period_service.dart';
import '../services/goias_scale_rates_recalc_service.dart';
import '../services/scale_rates_service.dart';
import '../services/functions_service.dart';
import '../services/relatorio_service.dart';
import '../services/pdf_launcher.dart';
import 'report_preview_screen.dart';
import '../services/agenda_notification_reschedule_helper.dart';
import '../utils/agenda_delivery_reset.dart';
import '../services/scale_notifications_service.dart';
import '../utils/premium_upgrade.dart';
import '../widgets/selecao_plantao_sheet.dart';
import '../widgets/lancamento_expresso_plantao_sheet.dart';
import '../widgets/month_year_resumo_header.dart';
import '../widgets/commitment_description_picker.dart';
import '../constants/commitment_presets.dart';
import '../models/shift_location.dart';
import '../models/controle_total_config.dart';
import '../services/controle_total_config_service.dart';
import 'locations_screen.dart';
import 'edit_location_screen.dart';
import '../widgets/multi_date_month_picker_dialog.dart';
import '../widgets/scale_month_closure_sheet.dart';
import '../widgets/scales/scale_bulk_clear_sheet.dart';
import '../utils/uppercase_text_input_formatter.dart';
import '../shared/utils/holiday_helper.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/keyboard_form_scaffold.dart';
import '../utils/home_shell_layout.dart';
import '../widgets/shell_keyboard_bottom_pad.dart';
import '../widgets/brl_amount_text_field.dart';
import '../services/agenda_reminder_delete_helper.dart';
import '../services/scale_entry_agenda_edit.dart';
import '../services/express_compromisso_agenda_sync.dart';
import '../services/produtividade_scale_mirror_service.dart';
import '../services/yearly_commitment_repeat_service.dart';

bool _isSameDay(DateTime? a, DateTime b) =>
    a != null && a.year == b.year && a.month == b.month && a.day == b.day;

/// Tipografia coerente em mobile (Android/iPhone/Web estreito) vs desktop.
double _scalesScreenFontSize(BuildContext context, double desktop) {
  final w = MediaQuery.sizeOf(context).width;
  if (w >= 720) return desktop;
  if (w < 390) return math.max(10.0, desktop * 0.87);
  return math.max(11.0, desktop * 0.92);
}

// Cores por tipo (CalendÃ¡rio e cards): Noturno=Ãndigo, Diurno/Extra=Laranja, Compromisso=Teal
const Color _corNoturno = Color(0xFF3F51B5);
const Color _corDiurno = Color(0xFFFF9800);
const Color _corCompromisso = Color(0xFF12B5A5);
const String _hexNoturno = '3F51B5';
const String _hexDiurno = 'FF9800';
const String _hexCompromisso = '12B5A5';

/// CTA para ConfiguraÃ§Ãµes â†’ PlantÃµes (plantÃµes recorrentes). Mesmo fluxo que o antigo Â«prÃ©-cadastroÂ».
const String _kListaPlantoesRecorrentesCta =
    'Lista de plantÃµes recorrentes â€“ cadastre aquiâ€¦';

/// Entra no resumo Estado/MunicÃ­pio/Particular: financeiro via lista de plantÃµes recorrentes **ou** vÃ­nculo salvo na escala
/// (ex.: lanÃ§amento expresso sem plantÃ£o em ConfiguraÃ§Ãµes â†’ PlantÃµes).
bool _entryInResumoFinanceiro(ScaleEntry e, List<ShiftLocation> locations) {
  if (e.isCompromisso) return false;
  if (e.temFinanceiroHabilitadoNoPainel) return true;
  final loc = matchShiftLocationForScaleEntry(e, locations);
  return loc != null && loc.financialEnabled;
}

Color _corPorTipo(ScaleEntry e) {
  if (e.isCompromisso) return _corCompromisso;
  return e.hoursNight >= e.hoursDay ? _corNoturno : _corDiurno;
}

/// Resolve employerType para um plantÃ£o: usa campo salvo ou match por label/abbreviation com locations (igual ao painel).
String _employerTypeForEntry(ScaleEntry e, List<ShiftLocation> locations) {
  if (e.employerType != null && e.employerType!.isNotEmpty)
    return e.employerType!;
  final labelBase = (e.label ?? '').trim().toUpperCase();
  final abbr = (e.abbreviation ?? '').trim().toUpperCase();
  if (labelBase.isEmpty && abbr.isEmpty) return 'private';
  for (final loc in locations) {
    final nameBase = ShiftLocation.baseNameFromFull(loc.name).toUpperCase();
    final locAbbr = loc.abbreviation.trim().toUpperCase();
    if (nameBase.isNotEmpty &&
        (labelBase.contains(nameBase) || nameBase.contains(labelBase)))
      return loc.employerType.name;
    if (locAbbr.isNotEmpty && (abbr == locAbbr || labelBase.contains(locAbbr)))
      return loc.employerType.name;
  }
  return 'private';
}

/// Mesmo padrÃ£o visual do lanÃ§amento expresso ([lancamento_expresso_plantao_sheet] `_buildVinculoChips`).
Widget _buildVinculoChip(
    BuildContext ctx,
    void Function(VoidCallback) setModalState,
    String value,
    String label,
    Color accent,
    IconData icon,
    String current,
    VoidCallback onSelect) {
  final sel = current == value;
  final dark = accent.computeLuminance() > 0.55;
  final fg = sel ? (dark ? const Color(0xFF37474F) : Colors.white) : accent;
  final bg = sel ? accent : accent.withValues(alpha: 0.12);
  final border = sel ? accent : accent.withValues(alpha: 0.4);
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () => setModalState(onSelect),
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
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
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: fg,
                  letterSpacing: 0.1),
            ),
          ],
        ),
      ),
    ),
  );
}

List<Color> _magicRegimeGradient(String r) {
  switch (r) {
    case '16x56':
      return const [Color(0xFF0E7490), Color(0xFF22D3EE)];
    case '12x36':
      return const [Color(0xFF4F46E5), Color(0xFF7C3AED)];
    case '24x48':
      return const [Color(0xFF0369A1), Color(0xFF0EA5E9)];
    case '24x72':
      return const [Color(0xFF0F766E), Color(0xFF14B8A6)];
    case '24x96':
      return const [Color(0xFFC2410C), Color(0xFFF97316)];
    case '24x144':
      return const [Color(0xFFBE123C), Color(0xFFEC4899)];
    case '24x192':
      return const [Color(0xFF7C2D12), Color(0xFFEA580C)];
    case '12x24x72':
      return const [Color(0xFF6D28D9), Color(0xFFA855F7)];
    case 'Expediente':
      return const [Color(0xFF1D4ED8), Color(0xFF60A5FA)];
    default:
      return [AppColors.primary, AppColors.accent];
  }
}

/// Tipo de geraÃ§Ã£o / CTAs do â€œbotÃ£o mÃ¡gicoâ€ â€” gradiente + Ã­cone em cÃ¡psula.
Widget _magicGradientChoice({
  required bool selected,
  required String label,
  required IconData icon,
  required VoidCallback onTap,
  required List<Color> selectedGradient,
  required Color idleAccent,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: selectedGradient,
                )
              : null,
          color: selected ? null : const Color(0xFFF8FAFC),
          border: Border.all(
            color: selected
                ? Colors.white.withValues(alpha: 0.45)
                : idleAccent.withValues(alpha: 0.45),
            width: selected ? 1.5 : 1.4,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: selectedGradient.last.withValues(alpha: 0.42),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.22)
                    : idleAccent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 20,
                color: selected ? Colors.white : idleAccent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.15,
                  color: selected ? Colors.white : AppColors.textPrimary,
                  height: 1.25,
                ),
              ),
            ),
            if (selected)
              Icon(
                Icons.check_circle_rounded,
                color: Colors.white.withValues(alpha: 0.95),
                size: 22,
              ),
          ],
        ),
      ),
    ),
  );
}

Widget _magicRegimePill({
  required String label,
  required bool selected,
  required VoidCallback onTap,
}) {
  final g = _magicRegimeGradient(label);
  return Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: g,
                  )
                : null,
            color: selected ? null : const Color(0xFFF1F5F9),
            border: Border.all(
              color: selected
                  ? Colors.white.withValues(alpha: 0.4)
                  : const Color(0xFFCBD5E1),
              width: selected ? 1.3 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: g.last.withValues(alpha: 0.38),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  color: selected ? Colors.white : AppColors.textPrimary,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.check_rounded,
                  size: 17,
                  color: Colors.white.withValues(alpha: 0.95),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// CTA largura total â€” gradiente (lista de plantÃµes recorrentes / aÃ§Ãµes principais).
Widget _magicFullWidthCta({
  required VoidCallback? onPressed,
  required IconData icon,
  required String label,
  required List<Color> gradient,
  bool enabled = true,
}) {
  final op = (onPressed != null && enabled) ? onPressed : null;
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: op,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: op != null
                ? gradient
                : [
                    Colors.grey.shade400,
                    Colors.grey.shade500,
                  ],
          ),
          boxShadow: op != null
              ? [
                  BoxShadow(
                    color: gradient.last.withValues(alpha: 0.4),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  letterSpacing: 0.2,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// SecundÃ¡rio premium (personalizado / expediente) â€” contorno colorido + preenchimento suave.
Widget _magicSecondaryCta({
  required VoidCallback? onPressed,
  required IconData icon,
  required String label,
  required List<Color> accentGradient,
  bool selected = false,
}) {
  final a = accentGradient.first;
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: selected
                ? [
                    a.withValues(alpha: 0.14),
                    accentGradient.last.withValues(alpha: 0.1),
                  ]
                : [
                    Colors.white,
                    const Color(0xFFF8FAFC),
                  ],
          ),
          border: Border.all(
            color:
                selected ? a.withValues(alpha: 0.75) : a.withValues(alpha: 0.4),
            width: selected ? 2 : 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: a.withValues(alpha: selected ? 0.22 : 0.1),
              blurRadius: selected ? 12 : 6,
              offset: Offset(0, selected ? 4 : 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: a, size: 22),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? AppColors.textPrimary : a,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  letterSpacing: 0.15,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ScalesScreen extends StatefulWidget {
  final String uid;
  final UserProfile profile;

  /// Quando a Calculadora pede "Configurar plantÃ£o", o shell passa a data inicial aqui para abrir o formulÃ¡rio ao exibir Escalas.
  final DateTime? initialOpenConfigurarPlantao;

  /// Chamado apÃ³s abrir o formulÃ¡rio para o shell limpar o pending.
  final VoidCallback? onConsumedConfigurarPlantao;

  /// Chamado ao tocar em "Voltar" na pÃ¡gina principal do mÃ³dulo (volta para a tela inicial / painel principal).
  final void Function(int index)? onNavigateTo;

  /// Quando dentro do [HomeShell]: scroll volta ao topo ao mudar de mÃ³dulo.
  final ScrollController? shellScrollController;

  /// No [HomeShell]: false quando outro mÃ³dulo estÃ¡ ativo â€” pausa listener Firestore.
  final bool isShellVisible;

  const ScalesScreen({
    super.key,
    required this.uid,
    required this.profile,
    this.initialOpenConfigurarPlantao,
    this.onConsumedConfigurarPlantao,
    this.onNavigateTo,
    this.shellScrollController,
    this.isShellVisible = true,
  });

  @override
  State<ScalesScreen> createState() => _ScalesScreenState();
}

class _ScalesScreenState extends State<ScalesScreen> {
  Widget _ptBrContextMenuBuilder(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    String? mapLabel(ContextMenuButtonType type) {
      switch (type) {
        case ContextMenuButtonType.cut:
          return 'Recortar';
        case ContextMenuButtonType.copy:
          return 'Copiar';
        case ContextMenuButtonType.paste:
          return 'Colar';
        case ContextMenuButtonType.selectAll:
          return 'Selecionar tudo';
        case ContextMenuButtonType.lookUp:
          return 'Consultar';
        case ContextMenuButtonType.searchWeb:
          return 'Pesquisar na web';
        case ContextMenuButtonType.share:
          return 'Compartilhar';
        case ContextMenuButtonType.liveTextInput:
          return 'Escanear texto';
        default:
          return null;
      }
    }

    final mappedItems = editableTextState.contextMenuButtonItems
        .map((item) => item.copyWith(label: mapLabel(item.type) ?? item.label))
        .toList();

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: mappedItems,
    );
  }

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  DateTime? _lastHandledConfigurarPlantaoDate;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _scalesSub;
  String? _boundScalesMonthKey;
  String? _lastEntriesFingerprint;
  bool _yearlyTemplatesSyncStarted = false;
  bool _goiasRecalcStarted = false;

  final _scalesRef = FirebaseFirestore.instance;
  List<ScaleEntry> _allEntries = [];
  List<FrenteServico> _frentes = [];
  List<ShiftLocation> _locations = [];
  StreamSubscription<fa.User?>? _authStateSub;

  String get _userDocId => firestoreUserDocIdForAppShell(widget.uid);

  CollectionReference<Map<String, dynamic>> get _scales =>
      _scalesRef.collection('users').doc(_userDocId).collection('scales');

  CollectionReference<Map<String, dynamic>> get _locationsRef =>
      _scalesRef.collection('users').doc(_userDocId).collection('locations');

  /// Igual ao painel inicial: ordinÃ¡rios viram "jÃ¡ tirado" apÃ³s o dia civil; com financeiro ativo usa sÃ³ [paid].
  bool _jaTiradoOrdinarioDisplay(ScaleEntry e) =>
      e.effectiveJaTiradoParaExibicao(DateTime.now());

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('pt_BR', null);
    _selectedDay = _focusedDay;
    _authStateSub = fa.FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted && widget.isShellVisible) {
        _loadFrentes();
        _loadLocations();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScalesShellVisibility();
    });
  }

  @override
  void didUpdateWidget(ScalesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isShellVisible != widget.isShellVisible ||
        oldWidget.uid != widget.uid) {
      _syncScalesShellVisibility();
    }
  }

  void _syncScalesShellVisibility() {
    if (!mounted) return;
    if (!widget.isShellVisible) {
      _cancelScalesStream();
      return;
    }
    unawaited(ScaleRatesPeriodService().ensureLoaded());
    _loadFrentes();
    _loadLocations();
    _ensureScalesStreamBound();
    if (!_goiasRecalcStarted && _userDocId.isNotEmpty) {
      _goiasRecalcStarted = true;
      unawaited(GoiasScaleRatesRecalcService().runIfNeeded(_userDocId));
    }
  }

  @override
  void dispose() {
    _authStateSub?.cancel();
    _cancelScalesStream();
    super.dispose();
  }

  void _cancelScalesStream() {
    unawaited(_scalesSub?.cancel());
    _scalesSub = null;
    _boundScalesMonthKey = null;
  }

  String _scalesMonthKey(DateTime day) => '${day.year}-${day.month}';

  bool _scaleEntryInMonth(ScaleEntry e, DateTime monthStart, DateTime monthEnd) {
    final d = DateTime(e.date.year, e.date.month, e.date.day);
    final start = DateTime(monthStart.year, monthStart.month, monthStart.day);
    final end = DateTime(monthEnd.year, monthEnd.month, monthEnd.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  String _entriesFingerprint(List<ScaleEntry> entries) {
    if (entries.isEmpty) return 'empty';
    final b = StringBuffer();
    for (final e in entries) {
      b.write(
        '${e.id}|${e.paid}|${e.date.millisecondsSinceEpoch}|${e.totalValue}|${e.hoursDay}|${e.hoursNight};',
      );
    }
    return b.toString();
  }

  void _ensureScalesStreamBound() {
    if (!mounted) return;
    if (!widget.isShellVisible) {
      _cancelScalesStream();
      return;
    }
    if (_userDocId.isEmpty) return;

    if (!_yearlyTemplatesSyncStarted) {
      _yearlyTemplatesSyncStarted = true;
      unawaited(
        YearlyCommitmentRepeatService.ensureAllTemplatesSynced(_userDocId),
      );
    }

    final monthKey = _scalesMonthKey(_focusedDay);
    if (_scalesSub != null && _boundScalesMonthKey == monthKey) return;

    _cancelScalesStream();
    _boundScalesMonthKey = monthKey;

    final monthStart = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final monthEnd =
        DateTime(_focusedDay.year, _focusedDay.month + 1, 0, 23, 59, 59);

    _scalesSub = _scales
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(monthEnd))
        .orderBy('date')
        .snapshots()
        .listen(
      _onScalesSnapshot,
      onError: (Object e) => debugPrint('scales: snapshots: $e'),
    );
  }

  void _onScalesSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    if (!mounted) return;
    List<ScaleEntry> next = [];
    if (snap.docs.isNotEmpty) {
      try {
        next = snap.docs.map((d) => ScaleEntry.fromDoc(d)).toList();
      } catch (_) {
        return;
      }
    }
    final fp = _entriesFingerprint(next);
    _lastEntriesFingerprint = fp;
    _allEntries = next;
    if (widget.isShellVisible && mounted) setState(() {});
    // NotificaÃ§Ãµes locais: sÃ³ ao criar/editar data-hora (AgendaNotificationRescheduleHelper),
    // nunca a cada snapshot do calendÃ¡rio (paid/valor/etc. disparava GET pesado e travava).
  }

  Future<void> _loadLocations() async {
    final uid = _userDocId;
    if (uid.isEmpty) return;
    try {
      final snap = await _locationsRef.get();
      if (!mounted) return;
      final list = snap.docs
          .map((d) => ShiftLocation.fromMap(d.id, d.data()))
          .where((l) => l.name.isNotEmpty || l.abbreviation.isNotEmpty)
          .toList();
      list.sort((a, b) => a.name.compareTo(b.name));
      setState(() => _locations = list);
    } catch (e) {
      debugPrint('scales: _loadLocations: $e');
    }
  }

  Future<void> _loadFrentes() async {
    final uid = _userDocId;
    if (uid.isEmpty) return;
    try {
      final snap = await _scalesRef
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('frentes')
          .get();
      if (!mounted) return;
      if (snap.exists && snap.data() != null) {
        final list = snap.data()!['list'] as List<dynamic>?;
        if (list != null) {
          setState(() {
            _frentes = list.asMap().entries.map((e) {
              final m = e.value as Map<String, dynamic>? ?? {};
              return FrenteServico(
                id: e.key.toString(),
                name: (m['name'] ?? 'Frente ${e.key + 1}').toString(),
                colorHex: (m['colorHex'] ?? '#2D5BFF').toString(),
              );
            }).toList();
          });
        }
      }
      if (_frentes.isEmpty) {
        setState(() {
          _frentes = [
            const FrenteServico(
                id: '0', name: 'OrdinÃ¡rio', colorHex: '#2D5BFF'),
            const FrenteServico(id: '1', name: 'ReforÃ§o', colorHex: '#12B5A5'),
            const FrenteServico(id: '2', name: 'Extra', colorHex: '#FFB648'),
          ];
        });
      }
    } catch (e) {
      debugPrint('scales: _loadFrentes: $e');
    }
  }

  int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  TimeOfDay _parseTime(String value) {
    final parts = value.split(':');
    final h = int.tryParse(parts.first) ?? 0;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
  }

  /// Retorna o [DateTime] em que o turno termina (fim do plantÃ£o ou dia seguinte se noturno).
  DateTime _fimDoTurno(ScaleEntry e) {
    final startT = _parseTime(e.start);
    final endT = _parseTime(e.end);
    var endDt =
        DateTime(e.date.year, e.date.month, e.date.day, endT.hour, endT.minute);
    final startDt = DateTime(
        e.date.year, e.date.month, e.date.day, startT.hour, startT.minute);
    if (endDt.isBefore(startDt) || endDt.isAtSameMomentAs(startDt)) {
      endDt = endDt.add(const Duration(days: 1));
    }
    return endDt;
  }

  /// True se o turno jÃ¡ terminou (ou jÃ¡ passou para o dia seguinte), permitindo confirmar conclusÃ£o.
  bool _turnoJaTerminou(ScaleEntry e) {
    return DateTime.now().isAfter(_fimDoTurno(e)) ||
        DateTime.now().isAtSameMomentAs(_fimDoTurno(e));
  }

  Map<String, double> _calc(
      TimeOfDay start, TimeOfDay end, double dayRate, double nightRate) {
    final s = _toMinutes(start);
    var e = _toMinutes(end);
    if (e <= s) e += 24 * 60;
    double dayMin = 0, nightMin = 0;
    const nightStart = TimeOfDay(hour: 22, minute: 0);
    const nightEnd = TimeOfDay(hour: 5, minute: 0);
    for (int m = s; m < e; m++) {
      final mod = m % (24 * 60);
      final isNight =
          (mod >= _toMinutes(nightStart)) || (mod < _toMinutes(nightEnd));
      if (isNight)
        nightMin++;
      else
        dayMin++;
    }
    return {
      'hoursDay': dayMin / 60,
      'hoursNight': nightMin / 60,
      'total': (dayMin / 60) * dayRate + (nightMin / 60) * nightRate,
    };
  }

  // MÃ©todos de AÃ§Ã£o (Add, Edit, Move, Duplicate, Clean)
  // ... (Mantendo a lÃ³gica interna para focar no visual)

  @override
  Widget build(BuildContext context) {
    if (!widget.isShellVisible) {
      return const ColoredBox(color: Color(0xFFF4F7FA));
    }
    // Quando o atalho "Incluir plantÃ£o" (ou Calculadora) pede, abre o formulÃ¡rio Configurar PlantÃ£o
    final dateToOpen = widget.initialOpenConfigurarPlantao;
    if (dateToOpen != null && _lastHandledConfigurarPlantaoDate != dateToOpen) {
      _lastHandledConfigurarPlantaoDate = dateToOpen;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onConsumedConfigurarPlantao?.call();
        _abrirFormularioEscala(context, initialDate: dateToOpen);
      });
    }
    if (dateToOpen == null) _lastHandledConfigurarPlantaoDate = null;

    final screenSize = MediaQuery.sizeOf(context);
    final isNarrow = screenSize.width < 720;
    final isVeryNarrow = screenSize.width < 390;
    final padding = MediaQuery.paddingOf(context);
    final embeddedInShell = widget.shellScrollController != null;
    final bottomPad = padding.bottom;
    final horizontalPad = isVeryNarrow ? 10.0 : (isNarrow ? 12.0 : 20.0);
    final leftPad =
        padding.left > horizontalPad ? padding.left : horizontalPad;
    final rightPad =
        padding.right > horizontalPad ? padding.right : horizontalPad;
    final sectionGap = isNarrow ? 16.0 : 24.0;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      resizeToAvoidBottomInset: scaffoldKeyboardResizeToAvoidBottomInset(
        embeddedInHomeShell: widget.shellScrollController != null,
      ),
      floatingActionButton: isNarrow
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _preCadastrarPlantao(context),
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.playlist_add_check_rounded),
                  label: Text(
                    _kListaPlantoesRecorrentesCta,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      letterSpacing: 0.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
          // Android e iPhone: SafeArea + padding com insets para boa visibilidade (notch, home indicator, bordas)
          body: SafeArea(
            top: true,
            bottom: homeShellSafeAreaBottom(embeddedInHomeShell: embeddedInShell),
            left: true,
            right: true,
            child: RefreshIndicator(
              onRefresh: () async {
                _lastEntriesFingerprint = null;
                _ensureScalesStreamBound();
                await Future<void>.delayed(
                  const Duration(milliseconds: 350),
                );
              },
              child: SingleChildScrollView(
                controller: widget.shellScrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  leftPad,
                  isNarrow ? 4 : 6,
                  rightPad,
                  embeddedInShell
                      ? homeShellScrollBottomPadding(
                          context,
                          embeddedInHomeShell: true,
                          tail: 8,
                        )
                      : (isNarrow ? 44 : 100) + bottomPad,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: 1100, minWidth: isNarrow ? 0 : 400),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTopBar(context,
                            isNarrow: isNarrow, isVeryNarrow: isVeryNarrow),
                        SizedBox(height: isNarrow ? (isVeryNarrow ? 4 : 6) : 12),
                        _buildCtaListaPlantoesRecorrentes(
                          isNarrow: isNarrow,
                          isVeryNarrow: isVeryNarrow,
                        ),
                        SizedBox(height: isNarrow ? (isVeryNarrow ? 5 : 7) : 12),
                        // CalendÃ¡rio: altura mÃ­nima alta no mobile para a grade ficar bem visÃ­vel ao abrir o mÃ³dulo
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: isNarrow
                                ? screenSize.height *
                                    (isVeryNarrow ? 0.72 : 0.76)
                                : 520,
                          ),
                          child: _buildCalendarSection(
                            isNarrow: isNarrow,
                            isVeryNarrow: isVeryNarrow,
                          ),
                        ),
                        SizedBox(height: sectionGap),
                        // Â«Resumo de horas no mÃªsÂ» (JÃ¡ tirou / PrevisÃ£o / Teto): pedido do
                        // usuÃ¡rio â€” fica logo apÃ³s o card do calendÃ¡rio + resumo feriados, e
                        // antes do Controle Estado Â· MunicÃ­pio Â· Particular (nÃ£o no rodapÃ© do
                        // grÃ¡fico Diurno x Noturno).
                        _buildAlertaTeto192Rodape(),
                        SizedBox(height: sectionGap),
                        _buildResumoPorVinculo(isNarrow: isNarrow),
                        SizedBox(height: sectionGap),
                        ScaleMonthClosureInviteCard(
                          uid: _userDocId,
                          profile: widget.profile,
                          entriesSource: _allEntries,
                          locations: _locations,
                          periodStart:
                              DateTime(_focusedDay.year, _focusedDay.month, 1),
                          periodEnd: DateTime(
                              _focusedDay.year, _focusedDay.month + 1, 0),
                          periodLabel:
                              'MÃªs do calendÃ¡rio: ${DateFormat('MM/yyyy').format(_focusedDay)}',
                          allowEditPeriodFromSource: true,
                        ),
                        SizedBox(height: sectionGap),
                        _buildPieChartDiurnoNoturno(isNarrow: isNarrow),
                        SizedBox(height: sectionGap),
                        _buildResumoMesDetalhado(isNarrow: isNarrow),
                        SizedBox(height: sectionGap),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
  }

  Widget _buildTopBar(BuildContext context,
      {bool isNarrow = false, bool isVeryNarrow = false}) {
    // PadrÃ£o Clean Premium: faixa com aÃ§Ãµes; voltar e tÃ­tulo do mÃ³dulo ficam na barra do [HomeShell].
    final embeddedInShell = widget.onNavigateTo != null;
    final title = Text(
      'Escalas â€¢ Compromissos â€¢ ServiÃ§os',
      style: TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: isNarrow ? (isVeryNarrow ? 14.5 : 16) : 19,
        color: Colors.white,
        letterSpacing: 0.2,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );

    final backButton = embeddedInShell
        ? const SizedBox.shrink()
        : IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: Colors.white, size: 24),
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Voltar',
            style: IconButton.styleFrom(
                minimumSize: const Size(44, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: isVeryNarrow ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: isNarrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!embeddedInShell) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      backButton,
                      Expanded(
                          child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: title)),
                    ],
                  ),
                  SizedBox(height: isVeryNarrow ? 6 : 8),
                ],
                // Em telas muito estreitas (ex.: iPhone) os Ã­cones podem rolar horizontalmente
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _topIconButton(
                          Icons.print_outlined,
                          Colors.white70,
                          () => widget.profile.hasActiveLicense
                              ? _gerarPdfEscalas()
                              : mostrarAvisoSeLicencaInativa(
                                  context, widget.profile),
                          tooltip: 'Exportar mÃªs em PDF'),
                      const SizedBox(width: 6),
                      _topIconButton(
                          Icons.auto_awesome_rounded,
                          AppColors.amber,
                          () => widget.profile.hasActiveLicense
                              ? _gerarEscalaAutomatica(context)
                              : mostrarAvisoSeLicencaInativa(
                                  context, widget.profile),
                          tooltip: 'Criar escalas automÃ¡ticas'),
                      _topIconButton(Icons.calendar_month_rounded, Colors.white,
                          _irParaDataEspecifica,
                          tooltip: 'Ir para data'),
                      _topIconButton(
                          Icons.delete_sweep_rounded,
                          Colors.white70,
                          () => widget.profile.hasActiveLicense
                              ? _showLimpezaDialog()
                              : mostrarAvisoSeLicencaInativa(
                                  context, widget.profile),
                          tooltip: 'Limpar escalas'),
                    ],
                  ),
                ),
              ],
            )
          : Row(
              children: [
                backButton,
                if (!embeddedInShell) ...[
                  const SizedBox(width: 4),
                  Expanded(child: title),
                ],
                if (embeddedInShell) const Spacer(),
                _topIconButton(
                    Icons.print_outlined,
                    Colors.white70,
                    () => widget.profile.hasActiveLicense
                        ? _gerarPdfEscalas()
                        : mostrarAvisoSeLicencaInativa(context, widget.profile),
                    tooltip: 'Exportar mÃªs em PDF'),
                const SizedBox(width: 8),
                _topIconButton(
                    Icons.auto_awesome_rounded,
                    AppColors.amber,
                    () => widget.profile.hasActiveLicense
                        ? _gerarEscalaAutomatica(context)
                        : mostrarAvisoSeLicencaInativa(context, widget.profile),
                    tooltip: 'Criar escalas automÃ¡ticas'),
                _topIconButton(Icons.calendar_month_rounded, Colors.white,
                    _irParaDataEspecifica,
                    tooltip: 'Ir para data'),
                _topIconButton(
                    Icons.delete_sweep_rounded,
                    Colors.white70,
                    () => widget.profile.hasActiveLicense
                        ? _showLimpezaDialog()
                        : mostrarAvisoSeLicencaInativa(context, widget.profile),
                    tooltip: 'Limpar escalas'),
              ],
            ),
    );
  }

  Widget _topIconButton(IconData icon, Color color, VoidCallback onTap,
      {String? tooltip}) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: 22),
        onPressed: onTap,
        tooltip: tooltip,
        style: IconButton.styleFrom(
            minimumSize: const Size(48, 48),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      ),
    );
  }

  Widget _buildHeaderDashboard({bool isNarrow = false}) {
    // Valores do mÃªs no calendÃ¡rio (inclui hoje e futuros com `paid` false); `paid` sÃ³ controla â€œjÃ¡ recebidoâ€ na UI.
    final entriesMes = _allEntries.where((e) => !e.isCompromisso).toList();
    final totalMonth = entriesMes.fold<double>(0, (s, e) => s + e.totalValue);
    final totalCount = entriesMes.length;

    if (isNarrow) {
      return Column(
        children: [
          _dashboardCard(
            'GANHOS DO MÃŠS',
            CurrencyFormats.formatBRL(totalMonth),
            Icons.account_balance_wallet_rounded,
            Colors.green,
          ),
          const SizedBox(height: 16),
          _dashboardCard(
            'PLANTÃ•ES',
            '$totalCount no mÃªs',
            Icons.event_available_rounded,
            AppColors.primary,
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: _dashboardCard(
            'GANHOS DO MÃŠS',
            CurrencyFormats.formatBRL(totalMonth),
            Icons.account_balance_wallet_rounded,
            Colors.green,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _dashboardCard(
            'PLANTÃ•ES',
            '$totalCount no mÃªs',
            Icons.event_available_rounded,
            AppColors.primary,
          ),
        ),
      ],
    );
  }

  Widget _dashboardCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: GeminiTheme.cardDecoration(color: Colors.white).copyWith(
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10)),
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: GeminiTheme.textMuted,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: GeminiTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// GrÃ¡fico de barras: ganhos por semana do mÃªs (padrÃ£o Gemini).
  Widget _buildWeeklyChart({bool isNarrow = false}) {
    final monthStart = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final monthEnd = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);
    final weeks = <int, double>{};
    for (int w = 1; w <= 5; w++) weeks[w] = 0;
    for (final e in _allEntries) {
      if (e.isCompromisso) continue;
      final day = e.date.day;
      final weekIndex = ((day - 1) / 7).floor() + 1;
      weeks[weekIndex] = (weeks[weekIndex] ?? 0) + e.totalValue;
    }
    final maxY = (weeks.values.isEmpty
            ? 1.0
            : weeks.values.reduce((a, b) => a > b ? a : b) * 1.2)
        .clamp(100.0, double.infinity);
    final spots = weeks.entries
        .map((e) => BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: (e.value).clamp(0.0, maxY),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: GeminiTheme.gradientChart,
                  ),
                  width: isNarrow ? 20 : 28,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(10)),
                  backDrawRodData: BackgroundBarChartRodData(
                      show: true,
                      toY: maxY,
                      color: GeminiTheme.textMuted.withOpacity(0.08)),
                ),
              ],
              showingTooltipIndicators: [0],
            ))
        .toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: GeminiTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded,
                  color: GeminiTheme.primary, size: 24),
              const SizedBox(width: 10),
              const Text(
                'Ganhos por semana',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: GeminiTheme.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: isNarrow ? 180 : 220,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                        BarTooltipItem(
                      'Sem ${group.x}\n${CurrencyFormats.formatBRL(rod.toY)}',
                      const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12),
                    ),
                    tooltipRoundedRadius: 12,
                    tooltipPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    getTooltipColor: (_) => GeminiTheme.primary,
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, meta) => Text(
                        'Sem ${v.toInt()}',
                        style: const TextStyle(
                            color: GeminiTheme.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                      reservedSize: 32,
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, meta) => Text(
                        v >= 1000
                            ? '${(v / 1000).toStringAsFixed(1)}k'
                            : v.toInt().toString(),
                        style: const TextStyle(
                            color: GeminiTheme.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w500),
                      ),
                      reservedSize: 36,
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (v) => FlLine(
                        color: GeminiTheme.textMuted.withOpacity(0.12),
                        strokeWidth: 1)),
                borderData: FlBorderData(show: false),
                barGroups: spots,
              ),
              duration: const Duration(milliseconds: 300),
            ),
          ),
        ],
      ),
    );
  }

  /// CTA lista de plantÃµes recorrentes (substitui o banner Â«1 toqueÂ»); abre ConfiguraÃ§Ãµes â†’ PlantÃµes.
  /// Mesmo padrÃ£o visual dos CTAs premium da folha Â«Incluir plantÃ£oÂ» (gradiente roxo + tipografia maior).
  Widget _buildCtaListaPlantoesRecorrentes({
    bool isNarrow = false,
    bool isVeryNarrow = false,
  }) {
    // **Destaque maior** a pedido do usuÃ¡rio: tÃ­tulo do CTA Â«Lista de plantÃµes
    // recorrentesÂ» com fonte +2 pt em relaÃ§Ã£o ao padrÃ£o anterior, peso mÃ¡ximo
    // (w900) e mais letter-spacing, para diferenciar visualmente do restante.
    //
    // **Sem comprometer o calendÃ¡rio inicial**: o `vPad` foi reduzido em ~2 px
    // (12â†’10 / 13â†’11 / 15â†’13) para compensar exatamente o ganho de altura da
    // tipografia. Assim o calendÃ¡rio continua aparecendo na mesma posiÃ§Ã£o em
    // iPhone SE / Android pequenos, com o mÃ³dulo Escalas idÃªntico ao anterior.
    final titleFs = _scalesScreenFontSize(
      context,
      isVeryNarrow ? 16.5 : (isNarrow ? 17.5 : 18.0),
    );
    final subtitleFs = _scalesScreenFontSize(context, 12.75);
    const gradient = [
      Color(0xFF5B21B6),
      Color(0xFF7C3AED),
      Color(0xFF9333EA),
    ];
    final vPad = isVeryNarrow ? 10.0 : (isNarrow ? 11.0 : 13.0);
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.42),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: InkWell(
            onTap: () => _preCadastrarPlantao(context),
            borderRadius: BorderRadius.circular(16),
            splashColor: Colors.white.withValues(alpha: 0.18),
            highlightColor: Colors.white.withValues(alpha: 0.08),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: vPad),
              child: Row(
                children: [
                  Container(
                    width: isVeryNarrow ? 36 : 40,
                    height: isVeryNarrow ? 36 : 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      Icons.playlist_add_check_rounded,
                      color: Colors.white,
                      size: isVeryNarrow ? 20 : 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Lista de plantÃµes recorrentes',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: titleFs,
                            letterSpacing: 0.3,
                            height: 1.18,
                            shadows: const [
                              Shadow(
                                color: Color(0x66000000),
                                blurRadius: 3,
                                offset: Offset(0, 1.5),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Cadastre aquiâ€¦',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontWeight: FontWeight.w600,
                            fontSize: subtitleFs,
                            height: 1.2,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white.withValues(alpha: 0.95),
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// GrÃ¡fico pizza: valores diurnos realizados, noturnos realizados, previsÃ£o diurno/noturno a tirar.
  Widget _buildPieChartDiurnoNoturno({bool isNarrow = false}) {
    double diurnoReal = 0, noturnoReal = 0, diurnoPrev = 0, noturnoPrev = 0;
    for (final e in _allEntries) {
      final val = e.totalValue;
      final isDiurno = e.hoursDay >= e.hoursNight;
      if (e.paid) {
        if (isDiurno)
          diurnoReal += val;
        else
          noturnoReal += val;
      } else {
        if (isDiurno)
          diurnoPrev += val;
        else
          noturnoPrev += val;
      }
    }
    final total = diurnoReal + noturnoReal + diurnoPrev + noturnoPrev;
    final fsTitulo = _scalesScreenFontSize(context, 18);
    final fsCorpo = _scalesScreenFontSize(context, 14);
    final fsInfo = _scalesScreenFontSize(context, 11);
    if (total <= 0) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: GeminiTheme.cardDecoration(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pie_chart_outline_rounded,
                color: GeminiTheme.textMuted, size: 32),
            const SizedBox(width: 12),
            Text('Sem dados para o grÃ¡fico',
                style:
                    TextStyle(color: GeminiTheme.textMuted, fontSize: fsCorpo)),
          ],
        ),
      );
    }
    final sections = <PieChartSectionData>[
      if (diurnoReal > 0)
        PieChartSectionData(
          value: diurnoReal,
          title: '${(diurnoReal / total * 100).toStringAsFixed(0)}%',
          color: _corDiurno,
          radius: 60,
          titleStyle: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
        ),
      if (noturnoReal > 0)
        PieChartSectionData(
          value: noturnoReal,
          title: '${(noturnoReal / total * 100).toStringAsFixed(0)}%',
          color: _corNoturno,
          radius: 60,
          titleStyle: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
        ),
      if (diurnoPrev > 0)
        PieChartSectionData(
          value: diurnoPrev,
          title: '${(diurnoPrev / total * 100).toStringAsFixed(0)}%',
          color: Colors.orange.shade200,
          radius: 60,
          titleStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1C1E)),
        ),
      if (noturnoPrev > 0)
        PieChartSectionData(
          value: noturnoPrev,
          title: '${(noturnoPrev / total * 100).toStringAsFixed(0)}%',
          color: Colors.indigo.shade200,
          radius: 60,
          titleStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1C1E)),
        ),
    ];
    if (sections.isEmpty) {
      return const SizedBox.shrink();
    }
    // Com zoom/texto grande, legenda ao lado do grÃ¡fico ficava estreita e quebrava valores.
    final textScaleFactor = MediaQuery.textScalerOf(context).scale(14) / 14.0;
    final stackChartLegend = isNarrow || textScaleFactor > 1.06;
    final legendColumn = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (diurnoReal > 0)
          _pieLegenda(_corDiurno, 'Diurno realizados',
              CurrencyFormats.formatBRLTight(diurnoReal)),
        if (noturnoReal > 0)
          _pieLegenda(_corNoturno, 'Noturno realizados',
              CurrencyFormats.formatBRLTight(noturnoReal)),
        if (diurnoPrev > 0)
          _pieLegenda(Colors.orange.shade200, 'Diurno a tirar',
              CurrencyFormats.formatBRLTight(diurnoPrev)),
        if (noturnoPrev > 0)
          _pieLegenda(Colors.indigo.shade200, 'Noturno a tirar',
              CurrencyFormats.formatBRLTight(noturnoPrev)),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: GeminiTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pie_chart_rounded,
                  color: GeminiTheme.primary, size: 24),
              const SizedBox(width: 10),
              Text(
                'Diurno x Noturno',
                style: TextStyle(
                    fontSize: fsTitulo,
                    fontWeight: FontWeight.w800,
                    color: GeminiTheme.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (stackChartLegend)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: isNarrow ? 200 : 220,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 40,
                      sections: sections,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                legendColumn,
              ],
            )
          else
            SizedBox(
              height: isNarrow ? 200 : 240,
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                        sections: sections,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: textScaleFactor > 1.03 ? 3 : 1,
                    child: legendColumn,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: Colors.amber.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Banco de Horas: 05h Ã s 22h (diurno); 22h01 Ã s 05h (noturno). PadrÃ£o GO: o dia civil encerra Ã  meia-noite; atÃ© 23:59 no calendÃ¡rio; apÃ³s 00:00 do dia seguinte (e na virada do mÃªs, apÃ³s 00:00 do dia 1Âº) no mÃªs seguinte.',
                    style: TextStyle(
                        fontSize: fsInfo, color: Colors.amber.shade900),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatHorasTetoDelta(double horas) {
    final arred = (horas * 10).round() / 10;
    if ((arred - arred.roundToDouble()).abs() < 0.05) {
      return '${arred.round()} h';
    }
    return '${arred.toStringAsFixed(1)} h';
  }

  /// Quadro destacado: diferenÃ§a entre teto e previsÃ£o (verde = margem; vermelho = excedeu).
  ({String title, String value, Color bg, Color fg}) _scaleTetoMargemMetric(
    double tetoHoras,
    double horasPrevisao,
  ) {
    final diff = tetoHoras - horasPrevisao;
    if (horasPrevisao > tetoHoras) {
      final excedeu = horasPrevisao - tetoHoras;
      return (
        title: 'Acima do teto',
        value: 'Passou ${_formatHorasTetoDelta(excedeu)}',
        bg: const Color(0xFFFFEBEE),
        fg: const Color(0xFFC62828),
      );
    }
    if (diff <= 0.05) {
      return (
        title: 'Margem',
        value: 'No teto',
        bg: const Color(0xFFE8F5E9),
        fg: const Color(0xFF2E7D32),
      );
    }
    final h = _formatHorasTetoDelta(diff);
    final faltaLabel =
        diff >= 0.95 && diff < 1.05 ? 'Falta $h' : 'Faltam $h';
    return (
      title: 'Margem',
      value: faltaLabel,
      bg: const Color(0xFFE8F5E9),
      fg: const Color(0xFF1B5E20),
    );
  }

  /// PÃ­lula premium para mÃ©tricas do teto (JÃ¡ tirou / PrevisÃ£o / Teto / Margem).
  Widget _scaleTetoMetricPill(
    BuildContext context, {
    required String title,
    required String value,
    required Color background,
    required Color foreground,
    bool ring = false,
    bool emphasized = false,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 108),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: emphasized
              ? foreground.withValues(alpha: 0.75)
              : ring
                  ? foreground.withValues(alpha: 0.55)
                  : foreground.withValues(alpha: 0.22),
          width: emphasized ? 2.5 : (ring ? 2 : 1),
        ),
        boxShadow: [
          BoxShadow(
            color: foreground.withValues(alpha: emphasized ? 0.22 : 0.08),
            blurRadius: emphasized ? 12 : 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: _scalesScreenFontSize(context, 11),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
              color: foreground.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: _scalesScreenFontSize(context, 21),
              fontWeight: FontWeight.w900,
              height: 1.05,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }

  /// Alerta no rodapÃ© do grÃ¡fico Diurno x Noturno: horas jÃ¡ feitas e previsÃ£o no mÃªs do calendÃ¡rio (sÃ³ com valor financeiro; teto configurÃ¡vel).
  /// Usa o mÃªs exibido no calendÃ¡rio (_focusedDay) para contabilizar e exibir o nome do mÃªs na observaÃ§Ã£o.
  Widget _buildAlertaTeto192Rodape() {
    final hoje = DateTime.now();
    // MÃªs do calendÃ¡rio em cima: quando o usuÃ¡rio estÃ¡ em marÃ§o, contabiliza marÃ§o
    final monthStart = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final monthEnd =
        DateTime(_focusedDay.year, _focusedDay.month + 1, 0, 23, 59, 59);
    final nomeMes = DateFormat('MMMM', 'pt_BR').format(monthStart);
    return StreamBuilder<ControleTotalConfig>(
      stream: ControleTotalConfigService().watchConfig(_userDocId),
      builder: (context, configSnap) {
        final config = configSnap.data ?? const ControleTotalConfig();
        final tetoHoras = config.tetoHorasMensal > 0
            ? config.tetoHorasMensal
            : ControleTotalConfig.tetoHorasMensalPadrao;
        final fsMsg = _scalesScreenFontSize(context, 11);
        final entries = _allEntries
            .where((e) => _scaleEntryInMonth(e, monthStart, monthEnd))
            .toList();
        final comValor = entries.where((e) => e.totalValue > 0).toList();
        if (comValor.isEmpty) return const SizedBox.shrink();
        double horasJa = 0;
        double horasPrevisao = 0;
        final hojeNorm = DateTime(hoje.year, hoje.month, hoje.day);
        for (final e in comValor) {
          final h = e.hoursDay + e.hoursNight;
          horasPrevisao += h;
          final d = DateTime(e.date.year, e.date.month, e.date.day);
          if (d.isBefore(hojeNorm) || d.isAtSameMomentAs(hojeNorm)) {
            horasJa += h;
          }
        }
        final passouTeto = horasPrevisao > tetoHoras;
        final tetoInt = tetoHoras.round();
        final margem = _scaleTetoMargemMetric(tetoHoras, horasPrevisao);
        final jaStr = '${horasJa.toStringAsFixed(1)} h';
        final prevStr = '${horasPrevisao.toStringAsFixed(1)} h';
        final tetoStr = '$tetoInt h';
        final tituloAlerta = passouTeto
            ? 'AtenÃ§Ã£o: previsÃ£o acima do teto'
            : 'Resumo de horas no mÃªs';
        final rodapeAlerta = passouTeto
            ? 'Revise escalas ou ajuste o teto em ConfiguraÃ§Ãµes > Horas extras.'
            : 'PlantÃµes com valor no mÃªs de $nomeMes (sÃ³ entram horas com valor financeiro).';
        final fsTitulo = _scalesScreenFontSize(context, 15);
        return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: passouTeto
                      ? [
                          Colors.orange.shade50,
                          Colors.orange.shade100.withValues(alpha: 0.45),
                        ]
                      : [
                          GeminiTheme.primary.withValues(alpha: 0.10),
                          Colors.white,
                        ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  width: 1.5,
                  color: passouTeto
                      ? Colors.orange.shade400
                      : GeminiTheme.primary.withValues(alpha: 0.35),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        passouTeto
                            ? Icons.warning_amber_rounded
                            : Icons.schedule_rounded,
                        size: 28,
                        color: passouTeto
                            ? Colors.orange.shade900
                            : GeminiTheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tituloAlerta,
                              style: TextStyle(
                                fontSize: fsTitulo,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.2,
                                color: passouTeto
                                    ? Colors.orange.shade900
                                    : const Color(0xFF1A237E),
                              ),
                            ),
                            const SizedBox(height: 6),
                            MonthYearResumoHeader(
                              monthStart: monthStart,
                              compact: MediaQuery.sizeOf(context).width < 400,
                              accentWhenCurrent: passouTeto
                                  ? Colors.orange.shade900
                                  : GeminiTheme.primary,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _scaleTetoMetricPill(
                        context,
                        title: 'JÃ¡ tirou',
                        value: jaStr,
                        background: passouTeto
                            ? Colors.white.withValues(alpha: 0.92)
                            : const Color(0xFFE8EAF6),
                        foreground: const Color(0xFF1A237E),
                      ),
                      _scaleTetoMetricPill(
                        context,
                        title: 'PrevisÃ£o no mÃªs',
                        value: prevStr,
                        background: passouTeto
                            ? Colors.deepOrange.shade50
                            : const Color(0xFFFFF3E0),
                        foreground: const Color(0xFFE65100),
                      ),
                      _scaleTetoMetricPill(
                        context,
                        title: 'Teto',
                        value: tetoStr,
                        background: passouTeto
                            ? Colors.red.shade50
                            : const Color(0xFFE3F2FD),
                        foreground: const Color(0xFF0D47A1),
                        ring: true,
                      ),
                      _scaleTetoMetricPill(
                        context,
                        title: margem.title,
                        value: margem.value,
                        background: margem.bg,
                        foreground: margem.fg,
                        emphasized: true,
                        ring: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    rodapeAlerta,
                    style: TextStyle(
                      fontSize: fsMsg,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                      color: passouTeto
                          ? Colors.orange.shade900
                          : GeminiTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            );
      },
    );
  }

  Widget _pieLegenda(Color cor, String label, String valor) {
    final fsLbl = _scalesScreenFontSize(context, 13);
    final fsVal = _scalesScreenFontSize(context, 16);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: cor, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: fsLbl,
                        color: GeminiTheme.textMuted,
                        fontWeight: FontWeight.w600),
                    softWrap: true),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    valor,
                    maxLines: 1,
                    style: TextStyle(
                        fontSize: fsVal,
                        fontWeight: FontWeight.w800,
                        color: GeminiTheme.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Resumo por vÃ­nculo (Estado / MunicÃ­pio / Particular); apÃ³s o Â«Resumo de horas no mÃªsÂ» e antes do Resumo do mÃªs detalhado.
  /// PrÃ©-cadastro com financeiro **ou** entrada com vÃ­nculo + valor na escala (ex.: lanÃ§amento expresso).
  /// Particular: apenas serviÃ§os explicitamente marcados como Particular (employerType == 'private').
  Widget _buildResumoPorVinculo({bool isNarrow = false}) {
    const types = ['state', 'municipality', 'private'];
    const labels = {
      'state': 'Estado',
      'municipality': 'MunicÃ­pio',
      'private': 'Particular'
    };
    final fsSec = _scalesScreenFontSize(context, 16);
    final fsCardTitle = _scalesScreenFontSize(context, 17);
    final fsRow = _scalesScreenFontSize(context, 15);
    final fsCap = _scalesScreenFontSize(context, 12);
    final fsTotBig = _scalesScreenFontSize(context, 18);
    final fsSub = _scalesScreenFontSize(context, 13);
    final fsTiny = _scalesScreenFontSize(context, 10);
    final fsHint = _scalesScreenFontSize(context, 11);
    final byType = <String, List<ScaleEntry>>{};
    for (final t in types) byType[t] = [];
    for (final e in _allEntries) {
      if (!_entryInResumoFinanceiro(e, _locations)) continue;
      // Particular: sÃ³ entra se estiver explicitamente marcado como particular (nÃ£o por inferÃªncia).
      if (e.employerType != null && e.employerType! == 'private') {
        byType['private']!.add(e);
        continue;
      }
      final t = _employerTypeForEntry(e, _locations);
      if (t == 'state' || t == 'municipality') {
        byType[t]!.add(e);
      }
      // Entradas inferidas como 'private' (sem tipo salvo, sem match) nÃ£o entram em nenhum card.
    }
    final hojeResumoVinculo = DateTime.now();
    Widget cardVinculo(String typeKey, String label, List<ScaleEntry> entries,
        {VoidCallback? onTap}) {
      final realizados = entries
          .where((e) => e.effectiveJaTiradoParaExibicaoComLocais(
              hojeResumoVinculo, _locations))
          .toList();
      final pendentes = entries
          .where((e) => !e.effectiveJaTiradoParaExibicaoComLocais(
              hojeResumoVinculo, _locations))
          .toList();
      final valReal = realizados.fold<double>(0, (s, e) => s + e.totalValue);
      final valPend = pendentes.fold<double>(0, (s, e) => s + e.totalValue);
      final valTotal = valReal + valPend;
      final color = typeKey == 'state'
          ? const Color(0xFF1A237E)
          : typeKey == 'municipality'
              ? const Color(0xFF0D9488)
              : const Color(0xFF7C3AED);
      final content = Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.deepBlue.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: AppColors.deepBlueDark.withValues(alpha: 0.11),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: color.withValues(alpha: 0.07),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.deepBlueDark,
                    color,
                    AppColors.accent,
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child:
                            Icon(Icons.badge_rounded, color: color, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: fsCardTitle,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textPrimary,
                                letterSpacing: 0.2,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Super premium Â· financeiro ativo',
                              style: TextStyle(
                                fontSize: fsTiny,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(Icons.check_circle_rounded,
                          size: 22, color: Colors.green.shade700),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${realizados.length} real. Â· ${CurrencyFormats.formatBRL(valReal)}',
                          style: TextStyle(
                              fontSize: fsRow,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                              height: 1.25),
                          maxLines: 2,
                          softWrap: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded,
                          size: 22, color: Colors.orange.shade800),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${pendentes.length} pend. Â· ${CurrencyFormats.formatBRL(valPend)}',
                          style: TextStyle(
                              fontSize: fsRow,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                              height: 1.25),
                          maxLines: 2,
                          softWrap: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          color.withValues(alpha: 0.1),
                          AppColors.primary.withValues(alpha: 0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: color.withValues(alpha: 0.22)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'VALOR TOTAL',
                                style: TextStyle(
                                  fontSize: fsTiny,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.65,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Realizados + pendentes',
                                style: TextStyle(
                                  fontSize: fsHint,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              CurrencyFormats.formatBRL(valTotal),
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: fsTotBig,
                                fontWeight: FontWeight.w900,
                                color: color,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: onTap != null
            ? Material(
                color: Colors.transparent,
                child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: onTap,
                    child: content))
            : content,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.account_balance_rounded,
                color: GeminiTheme.primary, size: 22),
            const SizedBox(width: 8),
            Text(
              'Controle Estado Â· MunicÃ­pio Â· Particular',
              style: TextStyle(
                  fontSize: fsSec,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1A1C1E)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Apenas plantÃµes ligados Ã  lista de plantÃµes recorrentes com financeiro ativo Â· mÃªs do calendÃ¡rio: ${DateFormat('MM/yyyy').format(_focusedDay)}',
          style: TextStyle(
              fontSize: fsCap, color: Colors.grey.shade700, height: 1.25),
        ),
        const SizedBox(height: 12),
        cardVinculo('state', labels['state']!, byType['state']!,
            onTap: () => _abrirListaServicos(
                context, byType['state']!, 'Estado (financeiro ativo)')),
        cardVinculo(
            'municipality', labels['municipality']!, byType['municipality']!,
            onTap: () => _abrirListaServicos(context, byType['municipality']!,
                'MunicÃ­pio (financeiro ativo)')),
        cardVinculo('private', labels['private']!, byType['private']!,
            onTap: () => _abrirListaServicos(
                context, byType['private']!, 'Particular (financeiro ativo)')),
        const SizedBox(height: 4),
        Builder(
          builder: (context) {
            final allFin = <ScaleEntry>[
              ...byType['state']!,
              ...byType['municipality']!,
              ...byType['private']!,
            ];
            final totReal = allFin
                .where((e) => e.effectiveJaTiradoParaExibicaoComLocais(
                    hojeResumoVinculo, _locations))
                .toList();
            final totPend = allFin
                .where((e) => !e.effectiveJaTiradoParaExibicaoComLocais(
                    hojeResumoVinculo, _locations))
                .toList();
            final vReal = totReal.fold<double>(0, (s, e) => s + e.totalValue);
            final vPend = totPend.fold<double>(0, (s, e) => s + e.totalValue);
            final vMes = vReal + vPend;
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                    color: AppColors.deepBlue.withValues(alpha: 0.12)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.deepBlueDark.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 4,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: AppColors.logoGradient,
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.summarize_rounded,
                                  size: 22, color: AppColors.deepBlue),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Totalizador',
                                    style: TextStyle(
                                      fontSize: fsTiny,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.55,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Estado + MunicÃ­pio + Particular',
                                    style: TextStyle(
                                      fontSize: fsRow,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.textPrimary,
                                      height: 1.2,
                                    ),
                                    softWrap: true,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Soma sÃ³ dos vÃ­nculos com financeiro ativo no mÃªs visÃ­vel acima.',
                          style: TextStyle(
                              fontSize: fsHint,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              height: 1.3),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.deepBlue.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color:
                                    AppColors.deepBlue.withValues(alpha: 0.1)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => _abrirListaServicos(
                                        context,
                                        totReal,
                                        'Total realizados (todos os vÃ­nculos)'),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 6, horizontal: 4),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('Realizados',
                                              style: TextStyle(
                                                  fontSize: fsCap,
                                                  fontWeight: FontWeight.w800,
                                                  color:
                                                      AppColors.textSecondary)),
                                          const SizedBox(height: 4),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              CurrencyFormats.formatBRLTight(
                                                  vReal),
                                              maxLines: 1,
                                              style: TextStyle(
                                                  fontSize: fsCardTitle,
                                                  fontWeight: FontWeight.w900,
                                                  color: Colors.green.shade700),
                                            ),
                                          ),
                                          Text(
                                              '${totReal.length} plantÃ£o(Ãµes) Â· toque p/ ver',
                                              style: TextStyle(
                                                  fontSize: fsTiny,
                                                  color: AppColors.textMuted)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                  width: 1,
                                  height: 56,
                                  color: AppColors.logoSilver
                                      .withValues(alpha: 0.5)),
                              Expanded(
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => _abrirListaServicos(
                                        context,
                                        totPend,
                                        'Total pendentes (todos os vÃ­nculos)'),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 6, horizontal: 4),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('Pendentes',
                                              style: TextStyle(
                                                  fontSize: fsCap,
                                                  fontWeight: FontWeight.w800,
                                                  color:
                                                      AppColors.textSecondary)),
                                          const SizedBox(height: 4),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              CurrencyFormats.formatBRLTight(
                                                  vPend),
                                              maxLines: 1,
                                              style: TextStyle(
                                                  fontSize: fsCardTitle,
                                                  fontWeight: FontWeight.w900,
                                                  color:
                                                      Colors.orange.shade800),
                                            ),
                                          ),
                                          Text(
                                              '${totPend.length} plantÃ£o(Ãµes) Â· toque p/ ver',
                                              style: TextStyle(
                                                  fontSize: fsTiny,
                                                  color: AppColors.textMuted)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.deepBlue.withValues(alpha: 0.12),
                                AppColors.accent.withValues(alpha: 0.08),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color:
                                    AppColors.deepBlue.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'VALOR TOTAL DO MÃŠS',
                                style: TextStyle(
                                  fontSize: fsTiny,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.65,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'ProjeÃ§Ã£o (realizados + pendentes)',
                                style: TextStyle(
                                    fontSize: fsSub,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textSecondary),
                                softWrap: true,
                              ),
                              const SizedBox(height: 8),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  CurrencyFormats.formatBRLTight(vMes),
                                  maxLines: 1,
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                      fontSize: fsTotBig + 1,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.deepBlue),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCalendarSection({
    bool isNarrow = false,
    bool isVeryNarrow = false,
  }) {
    final cardPad = isNarrow
        ? (isVeryNarrow ? 12.0 : 14.0)
        : 26.0;
    // Topo mais justo: mÃªs/ano do calendÃ¡rio encosta melhor na borda superior do card branco.
    final cardTopPad = isNarrow
        ? (isVeryNarrow ? 5.0 : 6.0)
        : 18.0;
    final gapRodape = isNarrow ? 8.0 : 16.0;
    final gapSel = isNarrow ? 8.0 : 12.0;
    return RepaintBoundary(
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: isNarrow ? 0 : 15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(isNarrow ? 22 : 28),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 20,
                offset: const Offset(0, 8)),
            BoxShadow(
                color: AppColors.primary.withOpacity(0.04),
                blurRadius: 24,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(cardPad, cardTopPad, cardPad, cardPad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            // Em mobile, centraliza o bloco do calendÃ¡rio no card ampliado (estilo full screen)
            mainAxisAlignment:
                isNarrow ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              _buildCalendar(isNarrow: isNarrow),
              if (_selectedDay != null) ...[
                SizedBox(height: gapSel),
                _buildRodapeTotalDia(),
              ],
              SizedBox(height: gapRodape),
              _buildRodapeFeriadosMes(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRodapeFeriadosMes() {
    final feriados = HolidayHelper.getFeriadosDoMes(_focusedDay);
    final tituloMes = DateFormat("MMMM 'de' y", 'pt_BR').format(_focusedDay);
    final fsTitulo = _scalesScreenFontSize(context, 12.5);
    final fsCorpo = _scalesScreenFontSize(context, 12);

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.deepBlue.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBlueDark.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 4,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: AppColors.logoGradient,
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.event_available_rounded,
                        size: 18,
                        color: AppColors.deepBlue,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Resumo feriados',
                            style: TextStyle(
                              fontSize: _scalesScreenFontSize(context, 10.5),
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.55,
                              color: AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Feriados de $tituloMes',
                            style: TextStyle(
                              fontSize: fsTitulo,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (feriados.isEmpty)
                  Text(
                    'Sem feriados nacionais neste mÃªs.',
                    style: TextStyle(
                      fontSize: fsCorpo,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: feriados.map((f) {
                      final data = DateFormat('dd/MM', 'pt_BR').format(f.date);
                      final extra = f.isOptional ? ' (facultativo)' : '';
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary.withValues(alpha: 0.09),
                              AppColors.accent.withValues(alpha: 0.06),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.deepBlue.withValues(alpha: 0.14),
                          ),
                        ),
                        child: Text(
                          '$data Â· ${f.name}$extra',
                          style: TextStyle(
                            fontSize: fsCorpo,
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (DateTime, DateTime) _actualStartEndEntry(ScaleEntry e) {
    final partsStart = e.start.split(':');
    final partsEnd = e.end.split(':');
    final sh = int.tryParse(partsStart.first) ?? 0;
    final sm = partsStart.length > 1 ? (int.tryParse(partsStart[1]) ?? 0) : 0;
    final eh = int.tryParse(partsEnd.first) ?? 0;
    final em = partsEnd.length > 1 ? (int.tryParse(partsEnd[1]) ?? 0) : 0;
    final actualStart =
        DateTime(e.date.year, e.date.month, e.date.day, sh, sm, 0);
    final actualEnd = (eh * 60 + em) <= (sh * 60 + sm)
        ? DateTime(e.date.year, e.date.month, e.date.day + 1, eh, em, 0)
        : DateTime(e.date.year, e.date.month, e.date.day, eh, em, 0);
    return (actualStart, actualEnd);
  }

  String _autoViradaMarker(String sourceId) => '[AUTO_VIRADA_MES:$sourceId]';
  String _autoViradaNote(String sourceId) =>
      'LanÃ§amento automÃ¡tico (virada de mÃªs) ${_autoViradaMarker(sourceId)}';

  String _timeToHHmm(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  bool _isCrossingToNextDay(DateTime startDt, DateTime endDt) {
    return startDt.year != endDt.year ||
        startDt.month != endDt.month ||
        startDt.day != endDt.day;
  }

  Future<void> _syncAutoLancamentoViradaMes({
    required String sourceId,
    required DateTime sourceDate,
    required DateTime startDt,
    required DateTime endDt,
    required bool financeiroAtivo,
    required bool isCompromisso,
    required String nome,
    required String? abbreviation,
    required String colorHex,
    required String employerType,
  }) async {
    final marker = _autoViradaMarker(sourceId);
    final note = _autoViradaNote(sourceId);
    final carryDate =
        DateTime(sourceDate.year, sourceDate.month, sourceDate.day + 1);
    final carryDateTs = Timestamp.fromDate(
      DateTime.utc(carryDate.year, carryDate.month, carryDate.day, 12, 0, 0),
    );

    // Remove qualquer lanÃ§amento automÃ¡tico antigo desse plantÃ£o-fonte (query indexada por sourceId).
    await _removeAutoLancamentoBySourceId(sourceId);

    // SÃ³ cria lanÃ§amento automÃ¡tico quando hÃ¡ financeiro ativo + virada de mÃªs.
    if (!financeiroAtivo ||
        isCompromisso ||
        !_isLastDayOfMonth(sourceDate) ||
        !_isCrossingToNextDay(startDt, endDt)) {
      return;
    }

    final nextDayStart =
        DateTime(carryDate.year, carryDate.month, carryDate.day, 0, 0, 0);
    final carryRes = await ScaleRatesService().computeShiftForUid(
      uid: _userDocId,
      start: nextDayStart,
      end: endDt,
      entryDate: carryDate,
    );
    final carryTotal = (carryRes['total'] ?? 0).toDouble();
    if (carryTotal <= 0) return;

    final hoursDay = (carryRes['hoursDay'] ?? 0).toDouble();
    final hoursNight = (carryRes['hoursNight'] ?? 0).toDouble();
    final ratesCarry =
        await ScaleRatesService().getRatesForServiceDay(_userDocId, carryDate);
    final ratesSource =
        await ScaleRatesService().getRatesForServiceDay(_userDocId, sourceDate);
    final hoje =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final isRetroativo = carryDate.isBefore(hoje);

    final autoEntry = ScaleEntry(
      date: carryDate,
      start: '00:00',
      end: _timeToHHmm(endDt),
      dayRate: ratesCarry
          .diurnoForWeekday(ScaleRates.weekdayToIndex(carryDate.weekday)),
      nightRate: ratesSource
          .noturnoForWeekday(ScaleRates.weekdayToIndex(sourceDate.weekday)),
      hoursDay: hoursDay,
      hoursNight: hoursNight,
      totalValue: carryTotal,
      label: nome,
      abbreviation: abbreviation,
      colorHex: colorHex,
      paid: isRetroativo,
      isCompromisso: false,
      employerType: employerType,
      notes: note,
      reminderLeads: null,
    );

    final autoMap = autoEntry.toMap();
    autoMap['autoViradaMes'] = true;
    autoMap['autoViradaSourceId'] = sourceId;
    await _scales.add(autoMap);
  }

  Future<void> _removeAutoLancamentoBySourceId(String sourceId) async {
    final bySource =
        await _scales.where('autoViradaSourceId', isEqualTo: sourceId).get();
    for (final doc in bySource.docs) {
      await _scales.doc(doc.id).delete();
    }
    // Compatibilidade com lanÃ§amentos antigos (antes do campo indexado).
    final note = _autoViradaNote(sourceId);
    final legacy = await _scales.where('notes', isEqualTo: note).get();
    for (final doc in legacy.docs) {
      await _scales.doc(doc.id).delete();
    }
  }

  Future<void> _removeAutoLancamentosBySourceIds(
      Iterable<String> sourceIds) async {
    for (final id in sourceIds) {
      await _removeAutoLancamentoBySourceId(id);
    }
  }

  bool _isLastDayOfMonth(DateTime d) => ScaleRates.isLastDayOfMonth(d);

  Future<({double ate2359, double de0007, bool temSplit})> _computeSplitDia(
      DateTime day, List<ScaleEntry> entries) async {
    final dayEnd = DateTime(day.year, day.month, day.day, 23, 59, 59);
    final nextDayStart = DateTime(day.year, day.month, day.day + 1, 0, 0, 0);
    double ate2359 = 0, de0007 = 0;
    bool temSplit = false;
    if (entries.isEmpty) return (ate2359: 0.0, de0007: 0.0, temSplit: false);
    for (final e in entries) {
      if (e.isCompromisso) continue;
      final (actualStart, actualEnd) = _actualStartEndEntry(e);
      if (actualEnd.isAfter(dayEnd)) {
        temSplit = true;
        final res1 = await ScaleRatesService().computeShiftForUid(
          uid: _userDocId,
          start: actualStart,
          end: dayEnd,
          entryDate: e.date,
        );
        final res2 = await ScaleRatesService().computeShiftForUid(
          uid: _userDocId,
          start: nextDayStart,
          end: actualEnd,
          entryDate: e.date.add(const Duration(days: 1)),
        );
        ate2359 += res1['total'] ?? 0;
        de0007 += res2['total'] ?? 0;
      } else {
        ate2359 += e.totalValue;
      }
    }
    return (ate2359: ate2359, de0007: de0007, temSplit: temSplit);
  }

  /// RodapÃ© do calendÃ¡rio: total do dia selecionado + **resumo do dia** com data, horÃ¡rio,
  /// SEI/processos (espelho da Agenda) e observaÃ§Ãµes, para 1 ou mais lanÃ§amentos.
  Widget _buildRodapeTotalDia() {
    final day = _selectedDay!;
    final dayStart = DateTime(day.year, day.month, day.day);
    final entries = _allEntries
        .where(
            (e) => DateTime(e.date.year, e.date.month, e.date.day) == dayStart)
        .toList();
    final totalDia = entries.fold<double>(0, (s, e) => s + (e.totalValue));
    return FutureBuilder<({double ate2359, double de0007, bool temSplit})>(
      future: _computeSplitDia(day, entries),
      builder: (context, snap) {
        final split = snap.data;
        final temSplit = split?.temSplit ?? false;
        final fs11 = _scalesScreenFontSize(context, 11);
        final fs12 = _scalesScreenFontSize(context, 12);
        final fs13 = _scalesScreenFontSize(context, 13);
        final fs14 = _scalesScreenFontSize(context, 14);
        final fs18 = _scalesScreenFontSize(context, 18);
        final fsResumoDiaHeader = _scalesScreenFontSize(context, 15);
        final fsResumoItemTitulo = _scalesScreenFontSize(context, 16.5);
        final pillColor = (ScaleEntry e) =>
            (e.colorHex != null && e.colorHex!.isNotEmpty)
                ? e.color
                : _corPorTipo(e);
        Widget linhaResumoPremium(ScaleEntry e) {
          final valorStr = e.isCompromisso
              ? 'Compromisso'
              : CurrencyFormats.formatBRL(e.totalValue);
          final metaLinha = scaleEntryDiaSemanaDataHorario(e);
          final resumoLinhas = scaleEntryResumoNumberLines(e);
          final notes = (e.notes ?? '').trim();
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    width: 5,
                    height: 42,
                    decoration: BoxDecoration(
                      color: pillColor(e),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: pillColor(e).withValues(alpha: 0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      scaleEntryResumoTitleText(
                        e,
                        fontSize: fsResumoItemTitulo,
                        color: const Color(0xFF1A237E),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        metaLinha,
                        style: scaleEntryResumoMetaTextStyle(
                          fontSize: fs13,
                          color: AppColors.primary,
                        ),
                      ),
                      for (final linha in resumoLinhas) ...[
                        const SizedBox(height: 2),
                        Text(
                          linha,
                          style: TextStyle(
                            fontSize: fs12,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                            color: const Color(0xFF1A237E),
                          ),
                        ),
                      ],
                      if (notes.isNotEmpty)
                        _scaleNotesGridBlock(e, fontSize: fs11),
                      const SizedBox(height: 4),
                      Text(
                        valorStr,
                        style: TextStyle(
                          fontSize: fs12,
                          fontWeight: FontWeight.w800,
                          color: e.isCompromisso
                              ? AppColors.textMuted
                              : Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: Colors.white,
            border: Border.all(
              color: AppColors.deepBlue.withValues(alpha: 0.12),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.deepBlueDark.withValues(alpha: 0.12),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 4,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: AppColors.logoGradient,
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (entries.isNotEmpty) ...[
                      Text(
                        'Resumo do dia',
                        style: TextStyle(
                          fontSize: fsResumoDiaHeader,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.35,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat("EEEE, dd/MM/yyyy", 'pt_BR').format(day),
                        style: TextStyle(
                          fontSize: fs12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...entries.map(linhaResumoPremium),
                      const SizedBox(height: 4),
                    ],
                    if (temSplit && split != null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text('AtÃ© 23:59 (padrÃ£o GO)',
                                style: TextStyle(
                                    fontSize: fs12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade700),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 8),
                          Text(CurrencyFormats.formatBRL(split.ate2359),
                              style: TextStyle(
                                  fontSize: fs14,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF1A237E))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text('00h Ã s 07h (prÃ³x. dia)',
                                style: TextStyle(
                                    fontSize: fs12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade700),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 8),
                          Text(CurrencyFormats.formatBRL(split.de0007),
                              style: TextStyle(
                                  fontSize: fs14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.indigo.shade700)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 6, horizontal: 8),
                        decoration: BoxDecoration(
                          color: _isLastDayOfMonth(day) && split.de0007 > 0
                              ? Colors.indigo.shade50
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _isLastDayOfMonth(day) && split.de0007 > 0
                                  ? Colors.indigo.shade200
                                  : Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 14,
                                color:
                                    _isLastDayOfMonth(day) && split.de0007 > 0
                                        ? Colors.indigo.shade700
                                        : Colors.grey.shade600),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _isLastDayOfMonth(day) && split.de0007 > 0
                                    ? 'O valor referente ao horÃ¡rio 00h00 Ã s 07h ficarÃ¡ para o prÃ³ximo mÃªs.'
                                    : 'Banco de Horas: 05h Ã s 22h (diurno); 22h01 Ã s 05h (noturno).',
                                style: TextStyle(
                                    fontSize: fs11,
                                    color: _isLastDayOfMonth(day) &&
                                            split.de0007 > 0
                                        ? Colors.indigo.shade800
                                        : Colors.grey.shade700),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            'Total do dia ${DateFormat('dd/MM').format(day)}',
                            style: TextStyle(
                                fontSize: fs13,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                                color: AppColors.textSecondary),
                            softWrap: true,
                            maxLines: 2,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          CurrencyFormats.formatBRL(totalDia),
                          style: TextStyle(
                              fontSize: fs18,
                              fontWeight: FontWeight.w900,
                              color: AppColors.deepBlue),
                          overflow: TextOverflow.visible,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// NÃºmero do dia nas cÃ©lulas do calendÃ¡rio: permanece dentro do quadrado (cÃ©lulas estreitas / fonte maior).
  Widget _dialNumberInCell({
    required String text,
    required TextStyle style,
    BoxDecoration? badgeDecoration,
    EdgeInsets badgePadding =
        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const pad = 4.0;
        final maxW = math.max(0.0, constraints.maxWidth - pad);
        final maxH = math.max(0.0, constraints.maxHeight - pad);
        Widget inner = Text(
          text,
          maxLines: 1,
          softWrap: false,
          textAlign: TextAlign.center,
          style: style,
        );
        if (badgeDecoration != null) {
          inner = Container(
            padding: badgePadding,
            decoration: badgeDecoration,
            child: inner,
          );
        }
        return Center(
          child: SizedBox(
            width: maxW,
            height: maxH,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: inner,
            ),
          ),
        );
      },
    );
  }

  Widget _buildCalendar({bool isNarrow = false}) {
    final rawScale = MediaQuery.textScalerOf(context).scale(1.0);
    // Acessibilidade: acompanha fonte maior sem quebrar cabeÃ§alho/grade em Android e iPhone.
    final calendarScale = rawScale.clamp(1.0, 1.30);
    // Evita MediaQuery.of: animaÃ§Ã£o do teclado (viewInsets) nÃ£o deve rebuildar o calendÃ¡rio inteiro.
    final view = View.maybeOf(context);
    final media = view != null
        ? MediaQueryData.fromView(view)
            .copyWith(textScaler: TextScaler.linear(calendarScale))
        : MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(calendarScale));
    final eventLoader = <DateTime, List<ScaleEntry>>{};
    final datesWithShifts = <DateTime>{};
    final holidayKeys = HolidayHelper.getFeriados(_focusedDay.year)
        .map((h) => '${h.date.year}-${h.date.month}-${h.date.day}')
        .toSet();
    bool isHolidayDay(DateTime day) =>
        holidayKeys.contains('${day.year}-${day.month}-${day.day}');

    Color vividFromEntry(ScaleEntry e) {
      final raw = (e.colorHex != null && e.colorHex!.isNotEmpty)
          ? e.color
          : _corPorTipo(e);
      return AppColors.vividShift(raw);
    }

    /// Realce 3D premium do "hoje": halo colorido + sombra de elevaÃ§Ã£o + brilho interno.
    /// VisÃ­vel mesmo quando o dia tem plantÃ£o (borda + sombra nas 4 direÃ§Ãµes).
    List<BoxShadow> todaySoftLift(Color accent) {
      return [
        // Halo externo grande (anel colorido difuso ao redor do dia)
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.55),
          blurRadius: 14,
          offset: const Offset(0, 0),
          spreadRadius: 1.5,
        ),
        // ReforÃ§o do halo na cor do plantÃ£o (segunda camada)
        BoxShadow(
          color: accent.withValues(alpha: 0.55),
          blurRadius: 18,
          offset: const Offset(0, 6),
          spreadRadius: 1,
        ),
        // Sombra de profundidade (efeito 3D)
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.22),
          blurRadius: 10,
          offset: const Offset(0, 5),
        ),
        // Brilho interno superior (fica acima como um destaque metÃ¡lico)
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.6),
          blurRadius: 4,
          offset: const Offset(0, -1),
          spreadRadius: -1,
        ),
      ];
    }

    /// Pequeno selo "HOJE" sobre o dia atual para garantir destaque mesmo com plantÃ£o colorido.
    Widget todayBadge() {
      return Positioned(
        top: -4,
        right: -2,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white, width: 1.4),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.55),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Text(
            'HOJE',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 8.5,
              letterSpacing: 0.6,
              height: 1.0,
            ),
          ),
        ),
      );
    }

    for (final e in _allEntries) {
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      eventLoader.putIfAbsent(d, () => []).add(e);
      datesWithShifts.add(d);
    }

    /// CÃ©lula "hoje sem plantÃ£o" (e/ou feriado): aparÃªncia consistente independente
    /// de estar selecionado ou nÃ£o. Evita o bug em que ao clicar em outro dia o "hoje"
    /// caÃ­a em decoraÃ§Ã£o genÃ©rica e perdia a forma (mobile/web/iOS).
    ///
    /// **PadrÃ£o visual a pedido do usuÃ¡rio**: fundo **branco**, borda **azul** e
    /// texto Â«HojeÂ» dentro da cÃ©lula (em vez do badge externo Â«HOJEÂ»). MantÃ©m o
    /// destaque do dia atual sem o gradiente colorido pesado.
    ///
    /// **Importante (responsividade iOS/Android/Web):** quando o usuÃ¡rio adiciona
    /// um plantÃ£o neste dia, o `todayBuilder` automaticamente troca para
    /// [calendarShiftDayCell] (com a cor do plantÃ£o), preservando a forma â€” esta
    /// cÃ©lula sÃ³ aparece em dias **sem plantÃ£o**. As fontes ficam dimensionadas
    /// para caber no slot do `table_calendar` (rowHeight padrÃ£o 52 px âˆ’
    /// `cellMargin` vertical 12 px em narrow) e usam `FittedBox.scaleDown` como
    /// rede de seguranÃ§a em iPhones pequenos / Android com fonte grande.
    Widget todayCellNoShifts(BuildContext context, DateTime day,
        {required bool isHol}) {
      final fsNumber = (isNarrow ? 16.0 : 15.0);
      return AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.18),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      color: isHol
                          ? const Color(0xFFE53935)
                          : AppColors.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: fsNumber,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 1),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Hoje',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 9,
                      letterSpacing: 0.3,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    /// CÃ©lula com plantÃ£o(Ãµes): usada no [defaultBuilder] e no [todayBuilder].
    ///
    /// **Importante (table_calendar):** quando "hoje" nÃ£o estÃ¡ selecionado, o pacote
    /// usa [todayBuilder] *antes* de [defaultBuilder]. Se [todayBuilder] devolver
    /// `null` em um dia com plantÃµes, cai no `todayDecoration` genÃ©rico e some a cor
    /// do usuÃ¡rio â€” por isso reutilizamos o mesmo desenho aqui e em [todayBuilder].
    Widget calendarShiftDayCell(BuildContext context, DateTime day) {
      final d = DateTime(day.year, day.month, day.day);
      final events = eventLoader[d] ?? [];
      final orderedColors = <Color>[];
      for (final e in events) {
        final c = vividFromEntry(e);
        if (!orderedColors.any((x) => x.value == c.value)) orderedColors.add(c);
      }
      final list = orderedColors.toList();
      final isSelected = _isSameDay(_selectedDay, d);
      final isToday = _isSameDay(DateTime.now(), d);
      final isHol = isHolidayDay(day);
      Color borderColor = list.isNotEmpty ? list.first : AppColors.primary;
      if (isToday && list.isEmpty) {
        borderColor = AppColors.primary;
      } else if (list.isNotEmpty) {
        borderColor = Color.lerp(list.first, Colors.black, 0.22) ?? list.first;
      }
      final borderWidth = isToday ? 3.0 : (isSelected ? 2.5 : 2.0);
      final baseShadow = isSelected && list.isNotEmpty
          ? [
              BoxShadow(
                  color: list.first.withOpacity(0.45),
                  blurRadius: 10,
                  offset: const Offset(0, 2))
            ]
          : [
              BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 5,
                  offset: const Offset(0, 1))
            ];
      final accentLift = list.isNotEmpty ? list.first : AppColors.primary;
      final List<BoxShadow> boxShadow = [
        if (isToday) ...todaySoftLift(accentLift),
        ...baseShadow,
      ];
      if (list.length == 1) {
        final fillColor = isToday && list.isEmpty
            ? AppColors.primary.withOpacity(0.42)
            : list.first.withOpacity(isSelected ? 1.0 : 0.93);
        final fg = isHol
            ? const Color(0xFFE53935)
            : AppColors.onVividFill(fillColor);
        final shadows = isHol
            ? AppColors.calendarDialLegibilityShadows(darkInk: false)
            : (fg == Colors.white
                ? AppColors.calendarDialLegibilityShadows(darkInk: false)
                : AppColors.calendarDialLegibilityShadows(darkInk: true));
        final cell = Container(
          margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: borderWidth),
            boxShadow: boxShadow,
          ),
          child: _dialNumberInCell(
            text: '${day.day}',
            style: TextStyle(
                color: fg,
                shadows: shadows,
                fontWeight: FontWeight.w900,
                fontSize: 18 + (isToday ? 2 : 0)),
          ),
        );
        if (!isToday) return cell;
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [cell, todayBadge()],
        );
      }
      final cellMulti = Container(
        margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: boxShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _CalendarDayNPartsPainter(
                    colors: list.map((c) => c.withOpacity(1.0)).toList(),
                  ),
                ),
              ),
              _dialNumberInCell(
                text: '${day.day}',
                style: TextStyle(
                    color: isHol
                        ? const Color(0xFFE53935)
                        : AppColors.textPrimary,
                    shadows: isHol
                        ? AppColors.calendarDialLegibilityShadows(darkInk: false)
                        : AppColors.calendarDialLegibilityShadows(darkInk: true),
                    fontWeight: FontWeight.w900,
                    fontSize:
                        (list.length > 3 ? 15 : 17) + (isToday ? 2 : 0)),
              ),
            ],
          ),
        ),
      );
      if (!isToday) return cellMulti;
      return Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [cellMulti, todayBadge()],
      );
    }

    return MediaQuery(
      data: media,
      child: TableCalendar<ScaleEntry>(
        locale: 'pt_BR',
        firstDay: DateTime(2020, 1, 1),
        lastDay: DateTime(2030, 12, 31),
        focusedDay: _focusedDay,
        calendarFormat: CalendarFormat.month,
        availableCalendarFormats: const {
          CalendarFormat.month: 'MÃªs',
        },
        daysOfWeekHeight: isNarrow ? 30 : 28,
        daysOfWeekStyle: DaysOfWeekStyle(
          weekdayStyle: TextStyle(
            fontSize: isNarrow ? 11 : 10.5,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF455A64),
          ),
          weekendStyle: TextStyle(
            fontSize: isNarrow ? 11 : 10.5,
            fontWeight: FontWeight.w800,
            color: Colors.red.shade700,
          ),
        ),
        // SÃ³ gestos horizontais (trocar mÃªs); scroll vertical fica com o SingleChildScrollView da tela â€” evita travar ao rolar atÃ© o calendÃ¡rio
        availableGestures: AvailableGestures.horizontalSwipe,
        selectedDayPredicate: (day) => _isSameDay(_selectedDay, day),

        /// Feriados nacionais: mesma cor dos fins de semana (vermelho). SÃ³ quando o dia
        /// nÃ£o tem plantÃ£o â€” se tiver, o `defaultBuilder` colorido tem prioridade visual.
        holidayPredicate: (day) {
          final d = DateTime(day.year, day.month, day.day);
          return isHolidayDay(day) && !datesWithShifts.contains(d);
        },
        headerStyle: HeaderStyle(
          titleCentered: true,
          formatButtonVisible: false,
          formatButtonDecoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          formatButtonTextStyle: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
              fontSize: isNarrow ? 13 : 14),
          titleTextStyle: TextStyle(
            fontSize: (_focusedDay.year == DateTime.now().year &&
                    _focusedDay.month == DateTime.now().month)
                ? (isNarrow ? 26 : 24)
                : (isNarrow ? 22 : 21),
            fontWeight: FontWeight.w900,
            color: const Color(0xFF1A237E),
            letterSpacing: -0.35,
          ),
          leftChevronIcon: Container(
            padding: EdgeInsets.all(isNarrow ? 7 : 6),
            decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle),
            child: Icon(Icons.chevron_left_rounded,
                color: AppColors.primary, size: isNarrow ? 28 : 26),
          ),
          rightChevronIcon: Container(
            padding: EdgeInsets.all(isNarrow ? 7 : 6),
            decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle),
            child: Icon(Icons.chevron_right_rounded,
                color: AppColors.primary, size: isNarrow ? 28 : 26),
          ),
          headerMargin: EdgeInsets.zero,
          headerPadding: EdgeInsets.only(bottom: isNarrow ? 10 : 12),
        ),
        calendarStyle: CalendarStyle(
          todayDecoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.32),
                AppColors.primary.withValues(alpha: 0.18),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: AppColors.primary, width: 3),
            boxShadow: todaySoftLift(AppColors.primary),
          ),
          todayTextStyle: TextStyle(
              color: const Color(0xFF0B1F4B),
              fontWeight: FontWeight.w900,
              fontSize: isNarrow ? 26 : 24),
          // SeleÃ§Ã£o: sÃ³ indicador discreto (ponto), sem preencher a cÃ©lula de azul â€” evita confundir com plantÃµes coloridos
          selectedDecoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          selectedTextStyle: TextStyle(
              color: const Color(0xFF1A1C1E),
              fontWeight: FontWeight.w600,
              fontSize: isNarrow ? 21 : 19),
          markerDecoration: BoxDecoration(
              color: AppColors.accent, borderRadius: BorderRadius.circular(4)),
          outsideDaysVisible: false,
          defaultTextStyle: TextStyle(
              color: const Color(0xFF1A1C1E),
              fontWeight: FontWeight.w600,
              fontSize: isNarrow ? 21 : 19),
          weekendTextStyle: TextStyle(
              color: const Color(0xFFE53935),
              fontWeight: FontWeight.w600,
              fontSize: isNarrow ? 21 : 19),
          weekendDecoration: const BoxDecoration(shape: BoxShape.circle),
          holidayTextStyle: TextStyle(
              color: const Color(0xFFE53935),
              fontWeight: FontWeight.w600,
              fontSize: isNarrow ? 21 : 19),
          holidayDecoration: const BoxDecoration(shape: BoxShape.circle),
          cellMargin: EdgeInsets.symmetric(
              horizontal: isNarrow ? 5 : 5, vertical: isNarrow ? 12 : 8),
        ),
        onDaySelected: (selected, focused) {
          setState(() {
            _selectedDay = selected;
            _focusedDay = focused;
          });
          final dayStart =
              DateTime(selected.year, selected.month, selected.day);
          final entries = _allEntries
              .where((e) =>
                  DateTime(e.date.year, e.date.month, e.date.day) == dayStart)
              .toList();

          if (!widget.profile.hasActiveLicense) {
            mostrarAvisoSeLicencaInativa(context, widget.profile);
            setState(() => _selectedDay = null);
            return;
          }
          // Dia limpo: tela de inclusÃ£o (prÃ©-cadastro + expressos + botÃ£o mÃ¡gico).
          if (entries.isEmpty) {
            _abrirSelecaoPlantao(
              context,
              selected,
              trocar: false,
              limparSelecaoSeDiaVazioAoFechar: true,
            );
            return;
          }
          // Dia jÃ¡ preenchido: menu editar / trocar / limpar + botÃ£o mÃ¡gico.
          _mostrarMenuDiaCalendario(context, selected);
        },
        eventLoader: (day) =>
            eventLoader[DateTime(day.year, day.month, day.day)] ?? [],
        calendarBuilders: CalendarBuilders(
          /// "Hoje" sempre tem o MESMO desenho â€” selecionado ou nÃ£o.
          /// - Com plantÃµes: usa [calendarShiftDayCell] (mantÃ©m a cor do usuÃ¡rio).
          /// - Sem plantÃµes: usa [todayCellNoShifts] (forte, gradiente + halo + selo HOJE).
          /// Nunca retornar `null` aqui: evita cair no `todayDecoration` genÃ©rico e
          /// "desconfigurar" o dia de hoje ao tocar em outra data (iOS/Android/Web).
          todayBuilder: (context, day, focusedDay) {
            final d = DateTime(day.year, day.month, day.day);
            if (datesWithShifts.contains(d)) {
              return calendarShiftDayCell(context, day);
            }
            return todayCellNoShifts(context, day, isHol: isHolidayDay(day));
          },
          dowBuilder: (context, day) {
            const names = ['SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SAB', 'DOM'];
            final idx = day.weekday - 1;
            final isWeekend = day.weekday == DateTime.saturday ||
                day.weekday == DateTime.sunday;
            return Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  names[idx],
                  style: TextStyle(
                    fontSize: isNarrow ? 11 : 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                    color: isWeekend
                        ? Colors.red.shade700
                        : const Color(0xFF455A64),
                  ),
                ),
              ),
            );
          },
          // Dia selecionado: apenas um ponto indicador (nÃ£o preenche de azul); cÃ©lula colorida sÃ³ quando tem plantÃ£o/compromisso
          // SÃ³ desenha seleÃ§Ã£o no dia realmente selecionado â€” evita marcaÃ§Ã£o fantasma em outro dia (ex.: 25 ao clicar em 26)
          selectedBuilder: (context, day, focusedDay) {
            final d = DateTime(day.year, day.month, day.day);
            if (!_isSameDay(_selectedDay, d)) return null;
            final hasShifts = datesWithShifts.contains(d);
            // Com plantÃµes: usa o mesmo visual do defaultBuilder (cÃ©lula colorida), sem azul de seleÃ§Ã£o
            if (hasShifts) {
              final isTodayCell = _isSameDay(DateTime.now(), d);
              final isHol = isHolidayDay(day);
              final events = eventLoader[d] ?? [];
              final orderedColors = <Color>[];
              for (final e in events) {
                final c = vividFromEntry(e);
                if (!orderedColors.any((x) => x.value == c.value))
                  orderedColors.add(c);
              }
              final list = orderedColors.toList();
              Color borderColor =
                  list.isNotEmpty ? list.first : AppColors.primary;
              if (list.isNotEmpty)
                borderColor =
                    Color.lerp(list.first, Colors.black, 0.22) ?? list.first;
              final borderW = isTodayCell ? 3.0 : 2.5;
              final boxShadow = <BoxShadow>[
                if (isTodayCell) ...todaySoftLift(list.first),
                BoxShadow(
                    color: list.first.withOpacity(0.45),
                    blurRadius: 10,
                    offset: const Offset(0, 2))
              ];
              if (list.length == 1) {
                final fillColor = list.first.withOpacity(1.0);
                final fg = isHol
                    ? const Color(0xFFE53935)
                    : AppColors.onVividFill(fillColor);
                final shadows = isHol
                    ? AppColors.calendarDialLegibilityShadows(darkInk: false)
                    : (fg == Colors.white
                        ? AppColors.calendarDialLegibilityShadows(
                            darkInk: false)
                        : AppColors.calendarDialLegibilityShadows(
                            darkInk: true));
                return Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 1, vertical: 2),
                      decoration: BoxDecoration(
                        color: fillColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor, width: borderW),
                        boxShadow: boxShadow,
                      ),
                      child: _dialNumberInCell(
                        text: '${day.day}',
                        style: TextStyle(
                            color: fg,
                            shadows: shadows,
                            fontWeight: FontWeight.w900,
                            fontSize: 18 + (isTodayCell ? 2 : 0)),
                      ),
                    ),
                    Positioned(
                        top: 5,
                        right: 5,
                        child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black26, blurRadius: 2)
                                ]))),
                    if (isTodayCell) todayBadge(),
                  ],
                );
              }
              return Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor, width: borderW),
                      boxShadow: boxShadow,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _CalendarDayNPartsPainter(
                                colors: list
                                    .map((c) => c.withOpacity(1.0))
                                    .toList(),
                              ),
                            ),
                          ),
                          _dialNumberInCell(
                            text: '${day.day}',
                            style: TextStyle(
                                color: isHol
                                    ? const Color(0xFFE53935)
                                    : AppColors.textPrimary,
                                shadows: isHol
                                    ? AppColors.calendarDialLegibilityShadows(
                                        darkInk: false)
                                    : AppColors.calendarDialLegibilityShadows(
                                        darkInk: true),
                                fontWeight: FontWeight.w900,
                                fontSize: (list.length > 3 ? 15 : 17) +
                                    (isTodayCell ? 2 : 0)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                      top: 5,
                      right: 5,
                      child: Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: Colors.black26, blurRadius: 2)
                              ]))),
                  if (isTodayCell) todayBadge(),
                ],
              );
            }
            // Sem plantÃµes: sÃ³ nÃºmero do dia + ponto indicador de seleÃ§Ã£o (nunca azul)
            final isToday = _isSameDay(DateTime.now(), d);
            final isHol = isHolidayDay(day);
            // Hoje selecionado e sem plantÃ£o: usa exatamente a mesma cÃ©lula do
            // [todayBuilder]. Assim hoje fica IDÃŠNTICO selecionado ou nÃ£o â€” nÃ£o
            // "desconfigura" ao tocar em outra data.
            if (isToday) {
              return todayCellNoShifts(context, day, isHol: isHol);
            }
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
              decoration: null,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          color: isHol
                              ? const Color(0xFFE53935)
                              : const Color(0xFF1A1C1E),
                          fontWeight:
                              isHol ? FontWeight.w900 : FontWeight.w600,
                          fontSize: isNarrow ? 17 : 15,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: AppColors.primary.withOpacity(0.45),
                              blurRadius: 4)
                        ],
                      ),
                    ),
                  ),
                  if (isToday) todayBadge(),
                ],
              ),
            );
          },
          defaultBuilder: (context, day, focusedDay) {
            final d = DateTime(day.year, day.month, day.day);
            if (!datesWithShifts.contains(d)) return null;
            return calendarShiftDayCell(context, day);
          },
        ),
        onPageChanged: (focused) {
          // Atualiza apÃ³s o frame para nÃ£o travar durante a animaÃ§Ã£o do calendÃ¡rio
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _focusedDay = focused);
            _ensureScalesStreamBound();
          });
        },
      ),
    );
  }

  /// Bloco "Resumo do dia" (dia selecionado + lista + botÃ£o Adicionar). NÃ£o usado na Ã¡rvore atual:
  /// o resumo do dia ficou apenas no segundo toque no calendÃ¡rio (menu do dia). BotÃµes de aÃ§Ã£o
  /// estÃ£o na CTA Â«lista de plantÃµes recorrentesÂ», acima do calendÃ¡rio; abaixo do calendÃ¡rio
  /// (e feriados) vem o Â«Resumo de horas no mÃªsÂ», depois Controle Estado Â· MunicÃ­pio Â· Particular.
  Widget _buildDailyShifts() {
    final day = _selectedDay ?? DateTime.now();
    final dayStart = DateTime(day.year, day.month, day.day);
    final entries = _allEntries
        .where(
            (e) => DateTime(e.date.year, e.date.month, e.date.day) == dayStart)
        .toList();
    final totalDia =
        entries.fold<double>(0, (s, e) => s + (e.paid ? e.totalValue : 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              DateFormat("EEEE, d 'de' MMMM", 'pt_BR')
                  .format(day)
                  .toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Colors.grey.shade600,
                letterSpacing: 1.2,
              ),
            ),
            if (entries.isNotEmpty)
              Text(
                CurrencyFormats.formatBRL(totalDia),
                style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.green,
                    fontSize: 16),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (entries.isEmpty)
          _emptyState()
        else
          ...entries.map((e) => _buildShiftCardPremium(e)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _addScale(context, initialDate: day),
            icon: const Icon(Icons.add_rounded),
            label: const Text('ADICIONAR PLANTÃƒO',
                style:
                    TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 20),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              elevation: 4,
              shadowColor: AppColors.primary.withOpacity(0.4),
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.event_busy_rounded,
                size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Nenhum plantÃ£o agendado',
              style: TextStyle(
                  color: Colors.grey.shade500, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  /// MÃªs/ano iguais ao mÃªs do calendÃ¡rio (ex.: MARÃ‡O/2026).
  String _mesAnoResumoCalendario() {
    final m = DateFormat('MMMM', 'pt_BR').format(_focusedDay).trim();
    return '${m.toUpperCase()}/${_focusedDay.year}';
  }

  /// Contagens sÃ³ em quantidade (valores ficam no resumo Estado/MunicÃ­pio/Particular acima).
  ({
    int plantoesEscalasCompromissos,
    int extrasEstado,
    int extrasMunicipio,
    int particulares,
    int total
  }) _contagensResumoMesDetalhado(List<ScaleEntry> entries) {
    int plantoesEscalasCompromissos = 0;
    int extrasEstado = 0;
    int extrasMunicipio = 0;
    int particulares = 0;
    for (final e in entries) {
      if (!_entryInResumoFinanceiro(e, _locations)) {
        plantoesEscalasCompromissos++;
        continue;
      }
      if (e.employerType != null && e.employerType! == 'private') {
        particulares++;
        continue;
      }
      final t = _employerTypeForEntry(e, _locations);
      if (t == 'state') {
        extrasEstado++;
      } else if (t == 'municipality') {
        extrasMunicipio++;
      } else {
        particulares++;
      }
    }
    return (
      plantoesEscalasCompromissos: plantoesEscalasCompromissos,
      extrasEstado: extrasEstado,
      extrasMunicipio: extrasMunicipio,
      particulares: particulares,
      total: entries.length,
    );
  }

  Widget _linhaResumoMesSoQuantidade(String label, int valor) {
    final fsLbl = _scalesScreenFontSize(context, 13);
    final fsVal = _scalesScreenFontSize(context, 16);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: fsLbl,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800,
                height: 1.3,
              ),
            ),
          ),
          Text(
            '$valor',
            style: TextStyle(
              fontSize: fsVal,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF1A237E),
            ),
          ),
        ],
      ),
    );
  }

  /// Resumo do mÃªs detalhado: acompanha a navegaÃ§Ã£o do calendÃ¡rio. Lista todos os serviÃ§os (com e sem valor).
  /// Permite remover um serviÃ§o diretamente da lista. Ãšltimo campo da tela (abaixo de ADICIONAR e lista de plantÃµes recorrentes).
  Widget _buildResumoMesDetalhado({bool isNarrow = false}) {
    final monthName = DateFormat('MMMM yyyy', 'pt_BR').format(_focusedDay);
    final mesAnoCal = _mesAnoResumoCalendario();
    final fs18 = _scalesScreenFontSize(context, 18);
    final fs17 = _scalesScreenFontSize(context, 17);
    final fs15 = _scalesScreenFontSize(context, 15);
    final fs14 = _scalesScreenFontSize(context, 14);
    final fs12 = _scalesScreenFontSize(context, 12);
    final entries = List<ScaleEntry>.from(_allEntries)
      ..sort((a, b) => a.date.compareTo(b.date));
    if (entries.isEmpty) {
      final z = _contagensResumoMesDetalhado(entries);
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.list_alt_rounded,
                    color: AppColors.primary, size: 24),
                const SizedBox(width: 10),
                Text(
                  'Resumo do mÃªs detalhado',
                  style: TextStyle(
                      fontSize: fs18,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade800),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              mesAnoCal,
              style: TextStyle(
                  fontSize: fs17,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF1A237E),
                  letterSpacing: 0.5),
            ),
            const SizedBox(height: 14),
            _linhaResumoMesSoQuantidade('PLANTÃ•ES ESCALAS / COMPROMISSOS',
                z.plantoesEscalasCompromissos),
            _linhaResumoMesSoQuantidade('EXTRAS ESTADO', z.extrasEstado),
            _linhaResumoMesSoQuantidade('EXTRAS MUNICÃPIO', z.extrasMunicipio),
            _linhaResumoMesSoQuantidade('PARTICULARES', z.particulares),
            const Divider(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'TOTAL SERVIÃ‡OS NO MÃŠS:',
                    style: TextStyle(
                        fontSize: fs14,
                        fontWeight: FontWeight.w900,
                        color: Colors.grey.shade900),
                  ),
                ),
                Text(
                  '${z.total} SERVIÃ‡OS',
                  style: TextStyle(
                      fontSize: fs15,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF1A237E)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: Column(
                children: [
                  Icon(Icons.inbox_rounded,
                      size: 40, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text('Nenhum serviÃ§o em $mesAnoCal',
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: fs14)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final counts = _contagensResumoMesDetalhado(entries);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 520;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.list_alt_rounded,
                          color: AppColors.primary, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Resumo do mÃªs detalhado',
                          style: TextStyle(
                              fontSize: fs18,
                              fontWeight: FontWeight.w800,
                              color: Colors.grey.shade800),
                        ),
                      ),
                      if (!narrow)
                        FilledButton.icon(
                          onPressed: () => _exportarResumoMesPdf(
                              context, entries, monthName),
                          icon: const Icon(Icons.picture_as_pdf_rounded,
                              size: 18),
                          label: const Text('Exportar PDF'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            minimumSize: const Size(0, 40),
                          ),
                        ),
                    ],
                  ),
                  if (narrow) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () =>
                          _exportarResumoMesPdf(context, entries, monthName),
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                      label: const Text('Exportar PDF'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        minimumSize: const Size(0, 40),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            mesAnoCal,
            style: TextStyle(
                fontSize: fs17,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF1A237E),
                letterSpacing: 0.5),
          ),
          const SizedBox(height: 14),
          Text(
            'Somente quantidades (valores em Estado / MunicÃ­pio / Particular acima).',
            style: TextStyle(
                fontSize: fs12, color: Colors.grey.shade700, height: 1.35),
          ),
          const SizedBox(height: 12),
          _linhaResumoMesSoQuantidade('PLANTÃ•ES ESCALAS / COMPROMISSOS',
              counts.plantoesEscalasCompromissos),
          _linhaResumoMesSoQuantidade('EXTRAS ESTADO', counts.extrasEstado),
          _linhaResumoMesSoQuantidade(
              'EXTRAS MUNICÃPIO', counts.extrasMunicipio),
          _linhaResumoMesSoQuantidade('PARTICULARES', counts.particulares),
          const Divider(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'TOTAL SERVIÃ‡OS NO MÃŠS:',
                  style: TextStyle(
                      fontSize: fs14,
                      fontWeight: FontWeight.w900,
                      color: Colors.grey.shade900),
                ),
              ),
              Text(
                '${counts.total} SERVIÃ‡OS',
                style: TextStyle(
                    fontSize: fs15,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF1A237E)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Lista do mÃªs: editar (nÂº escala e observaÃ§Ãµes), remover.',
            style: TextStyle(
                fontSize: 12, color: Colors.grey.shade600, height: 1.3),
          ),
          const SizedBox(height: 12),
          ...entries.map((e) => _buildResumoMesDetalhadoItem(e)),
        ],
      ),
    );
  }

  /// Converte entradas do resumo do mÃªs para o formato do relatÃ³rio PDF (horas antes do valor).
  List<Map<String, dynamic>> _resumoMesToEscalasMap(
      List<ScaleEntry> entries, ScaleRates rates, DateTime hojeRef,
      {bool goiasPerServiceDay = false}) {
    return entries.map((e) {
      // Escalas sem valor (compromisso ou totalValue 0): exibir R$ 0,00 em vez de sÃ­mbolo no PDF.
      final valorStr = (e.isCompromisso || e.totalValue == 0)
          ? 'R\$ 0,00'
          : CurrencyFormats.formatBRL(e.totalValue);
      final dataPlantao = DateTime(e.date.year, e.date.month, e.date.day);
      final statusStr = dataPlantao.isAfter(hojeRef)
          ? 'A confirmar'
          : (e.effectiveJaTiradoParaExibicao(hojeRef)
              ? 'JÃ¡ tirado'
              : 'A tirar');
      final (hd, hn) = _hoursDayNightForPdfEntry(e, rates,
          goiasPerServiceDay: goiasPerServiceDay);
      return {
        'data': DateFormat('dd/MM/yyyy', 'pt_BR').format(e.date),
        'numeroEscala': e.scaleNumber ?? '',
        'compromisso': e.label ?? 'PlantÃ£o',
        'valor': valorStr,
        'status': statusStr,
        'observacao': e.notes ?? '',
        'horasLinha': RelatorioService.formatHorasLinhaPdf(hd, hn),
        'horasCompacta': RelatorioService.formatHorasLinhaPdfCompact(hd, hn),
      };
    }).toList();
  }

  Future<void> _exportarResumoMesPdf(
      BuildContext context, List<ScaleEntry> entries, String monthName) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 28, vertical: 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text('A gerar o PDFâ€¦'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    try {
      final results = await Future.wait([
        ScaleRatesService().usesGlobalGoiasRates(_userDocId),
        ScaleRatesService().getRates(uid: _userDocId),
      ]);
      final usesGlobal = results[0] as bool;
      final rates = results[1] as ScaleRates;
      final hoje =
          DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      final escalas = _resumoMesToEscalasMap(entries, rates, hoje,
          goiasPerServiceDay: usesGlobal);
      double totalRecebido = 0, totalPendente = 0;
      for (final e in entries) {
        if (e.isCompromisso) continue;
        if (e.paid)
          totalRecebido += e.totalValue;
        else
          totalPendente += e.totalValue;
      }
      final resumoPdf = _resumoBancoHorasFromEntries(entries, hoje, rates,
          goiasPerServiceDay: usesGlobal);
      final mesAno =
          '${_focusedDay.month.toString().padLeft(2, '0')}-${_focusedDay.year}';
      final filename = 'resumo mes detalhado $mesAno';
      final (bytes, _) = await RelatorioService.buildRelatorioEscalasBytes(
        periodo: monthName,
        escalas: escalas,
        totalRecebido: totalRecebido,
        totalPendente: totalPendente,
        reportTitle: 'Resumo do mÃªs detalhado â€” Banco de horas',
        suggestedFilename: filename,
        resumoBancoHoras: resumoPdf,
      );
      if (!context.mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ReportPreviewScreen(bytes: bytes, filename: filename),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Erro ao gerar PDF: ${e.toString().split('\n').first}'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  /// RÃ³tulo para badge na listagem detalhada: Compromisso, vÃ­nculo com financeiro ou plantÃ£o geral.
  String _badgeCategoriaResumoMes(ScaleEntry e) {
    if (e.isCompromisso && !scaleEntryIsPlantaoParaEdicaoRapida(e)) {
      return 'Compromisso';
    }
    if (e.isCompromisso && scaleEntryIsPlantaoParaEdicaoRapida(e)) {
      return 'PlantÃ£o';
    }
    if (_entryInResumoFinanceiro(e, _locations)) {
      final t = _employerTypeForEntry(e, _locations);
      switch (t) {
        case 'state':
          return 'Estado';
        case 'municipality':
          return 'MunicÃ­pio';
        case 'private':
          return 'Particular';
        default:
          return 'Financeiro';
      }
    }
    return 'PlantÃ£o';
  }

  ({Color bg, Color fg}) _badgeCoresCategoria(String cat) {
    switch (cat) {
      case 'Compromisso':
        return (
          bg: const Color(0xFF00796B).withOpacity(0.12),
          fg: const Color(0xFF00695C)
        );
      case 'Estado':
        return (
          bg: const Color(0xFF1A237E).withOpacity(0.12),
          fg: const Color(0xFF1A237E)
        );
      case 'MunicÃ­pio':
        return (
          bg: const Color(0xFF0D9488).withOpacity(0.14),
          fg: const Color(0xFF0F766E)
        );
      case 'Particular':
        return (
          bg: const Color(0xFF7C3AED).withOpacity(0.12),
          fg: const Color(0xFF6D28D9)
        );
      default:
        return (bg: Colors.grey.shade200, fg: Colors.grey.shade800);
    }
  }

  /// Linha de Editar/Excluir: Ã­cones (telas muito estreitas) ou botÃµes com rÃ³tulo.
  Widget _buildResumoItemEditDeleteRow(ScaleEntry e,
      {required bool soIconesBotoes}) {
    if (soIconesBotoes) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filledTonal(
            onPressed: () => _editarItemNaEscalas(context, e),
            icon: const Icon(Icons.edit_rounded, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primary.withValues(alpha: 0.14),
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.all(10),
              minimumSize: const Size(48, 48),
            ),
            tooltip: 'Editar',
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => _confirmarRemoverServicoResumo(context, e),
            icon: Icon(Icons.delete_outline_rounded, color: AppColors.error),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.error.withValues(alpha: 0.1),
              padding: const EdgeInsets.all(10),
              minimumSize: const Size(48, 48),
            ),
            tooltip: 'Excluir',
          ),
        ],
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.end,
      children: [
        FilledButton.icon(
          onPressed: () => _editarItemNaEscalas(context, e),
          icon: const Icon(Icons.edit_rounded, size: 18),
          label: const Text(
            'Editar',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: FilledButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            minimumSize: const Size(44, 44),
            tapTargetSize: MaterialTapTargetSize.padded,
            backgroundColor: AppColors.primary.withValues(alpha: 0.14),
            foregroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _confirmarRemoverServicoResumo(context, e),
          icon: const Icon(Icons.delete_outline_rounded, size: 16),
          label: const Text(
            'Excluir',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            minimumSize: const Size(44, 44),
            tapTargetSize: MaterialTapTargetSize.padded,
            foregroundColor: AppColors.error,
            side: BorderSide(
              color: AppColors.error.withValues(alpha: 0.5),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  /// ObservaÃ§Ãµes na grid: Â«Veja maisÂ» (200 chars) + olho (preview editÃ¡vel).
  Widget _scaleNotesGridBlock(
    ScaleEntry e, {
    double fontSize = 13,
    bool showObsPrefix = false,
  }) {
    final notes = (e.notes ?? '').trim();
    if (notes.isEmpty) return const SizedBox.shrink();
    return ScaleEntryNotesGridBlock(
      notes: notes,
      entryTitle: scaleEntryResumoDisplayTitle(e),
      fontSize: fontSize,
      showObsPrefix: showObsPrefix,
      onSaveNotes: (text) => _salvarObservacaoGrid(e, text),
    );
  }

  Future<bool> _salvarObservacaoGrid(ScaleEntry e, String rawNotes) async {
    if (e.id == null) return false;
    if (!widget.profile.hasActiveLicense) {
      if (mounted) mostrarAvisoSeLicencaInativa(context, widget.profile);
      return false;
    }
    try {
      final notes = normalizeScaleNotesForSave(rawNotes);
      if (e.isAgendaMirror) {
        await _scales.doc(e.id).update({
          'notes': notes.isEmpty ? FieldValue.delete() : notes,
        });
      } else {
        await _scales.doc(e.id).update(
              scalePlantaoFirestorePatch(
                ScalePlantaoEditValues(
                  scaleNumber: scalePlantaoNumberFromEntry(e),
                  notes: rawNotes,
                ),
              ),
            );
      }
      if (mounted) {
        _allEntries = _allEntries
            .map(
              (entry) => entry.id == e.id
                  ? entry.copyWith(notes: notes.isEmpty ? null : notes)
                  : entry,
            )
            .toList();
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ObservaÃ§Ãµes atualizadas.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return true;
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao salvar: ${err.toString().split('\n').first}',
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  /// CartÃ£o "Resumo do mÃªs" â€” evita flex 50/50 + horiz. scroll a cortar aÃ§Ãµes (web / Android / iOS estreito).
  Widget _buildResumoMesDetalhadoItem(ScaleEntry e) {
    final jaOrd = _jaTiradoOrdinarioDisplay(e);
    final statusStr = jaOrd ? 'JÃ¡ tirado' : 'A tirar';
    final statusColor = jaOrd ? AppColors.success : AppColors.financePendente;
    final cat = _badgeCategoriaResumoMes(e);
    final catColors = _badgeCoresCategoria(cat);
    final accent = (e.colorHex != null && e.colorHex!.isNotEmpty)
        ? e.color
        : _corPorTipo(e);
    final title = (e.label ?? 'PlantÃ£o').trim();
    // Data do serviÃ§o no rodapÃ© do card: mesmo peso/tamanho do nome da frente (tÃ­tulo).
    final resumoDataServicoStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w800,
      color: AppColors.textPrimary,
      height: 1.25,
    );
    final dia = DateFormat('dd', 'pt_BR').format(e.date);
    final mesCurto = DateFormat('MMM', 'pt_BR').format(e.date).toUpperCase();
    final resumoLinhas = scaleEntryResumoNumberLines(e);

    // PÃ­lula Â«ValorÂ» (Super Premium) â€” sempre presente; quando o plantÃ£o
    // nÃ£o tem financeiro, mostra **R$ 0,00** em cinza neutro para deixar
    // claro ao usuÃ¡rio. Responsiva: usa `FittedBox` para nÃ£o estourar em
    // telemÃ³veis estreitos (iPhone SE/Android pequeno) e na web reduzida.
    final temValor = e.totalValue > 0;
    final valorBgColor = temValor
        ? AppColors.success.withValues(alpha: 0.10)
        : AppColors.textMuted.withValues(alpha: 0.10);
    final valorFgColor =
        temValor ? AppColors.success : AppColors.textSecondary;
    Widget valorPill() {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: valorBgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: valorFgColor.withValues(alpha: 0.28),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              temValor
                  ? Icons.payments_rounded
                  : Icons.payments_outlined,
              size: 14,
              color: valorFgColor,
            ),
            const SizedBox(width: 6),
            Text(
              'VALOR',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
                color: valorFgColor.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  CurrencyFormats.formatBRL(e.totalValue),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: valorFgColor,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget colPrincipal({bool mostrarDataEBotoesAbaixo = false}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: catColors.bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  cat,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: catColors.fg,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  jaOrd ? 'JÃ¡ tirado' : 'A tirar',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            title.isEmpty ? 'PlantÃ£o' : title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: AppColors.textPrimary,
              height: 1.25,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          if (resumoLinhas.isEmpty)
            Row(
              children: [
                Icon(Icons.tag_rounded, size: 14, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    scaleEntryResumoNumberEmptyLabel(e),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            )
          else
            ...resumoLinhas.map(
              (line) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  line,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          _scaleNotesGridBlock(e),
          // Linha do Â«ValorÂ» â€” aparece em ambos os layouts (empilhado e wide),
          // garantindo paridade total entre iOS / Android / Web.
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: valorPill(),
          ),
          if (!mostrarDataEBotoesAbaixo) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusStr,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  DateFormat('dd/MM/yyyy', 'pt_BR').format(e.date),
                  style: resumoDataServicoStyle,
                ),
              ],
            ),
          ],
        ],
      );
    }

    Widget colunaDiaBotoes({required bool compacta}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                dia,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: accent,
                  height: 1,
                ),
              ),
              Text(
                mesCurto,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: accent.withValues(alpha: 0.85),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildResumoItemEditDeleteRow(e, soIconesBotoes: compacta),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, cardConstraints) {
        final w = cardConstraints.maxWidth;
        // Empilhar data/aÃ§Ãµes: web mobile e telemÃ³veis; Ã­cones sÃ³ se for muito estreito
        final empilhado = w < 520;
        final soIconesBotoes = w < 380;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border(left: BorderSide(color: accent, width: 4)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.07),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _editarItemNaEscalas(context, e),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    empilhado ? 10 : 14, 12, empilhado ? 10 : 14, 12),
                child: empilhado
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  jaOrd
                                      ? Icons.check_circle_rounded
                                      : Icons.event_available_rounded,
                                  color: accent,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: colPrincipal(
                                      mostrarDataEBotoesAbaixo: true)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color:
                                            statusColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        statusStr,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: statusColor,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      DateFormat('dd/MM/yyyy', 'pt_BR')
                                          .format(e.date),
                                      style: resumoDataServicoStyle,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              _buildResumoItemEditDeleteRow(e,
                                  soIconesBotoes: soIconesBotoes),
                            ],
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              jaOrd
                                  ? Icons.check_circle_rounded
                                  : Icons.event_available_rounded,
                              color: accent,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child:
                                colPrincipal(mostrarDataEBotoesAbaixo: false),
                          ),
                          const SizedBox(width: 8),
                          colunaDiaBotoes(compacta: soIconesBotoes),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Editar no resumo/lista: audiÃªncia/compromisso Agenda â†’ formulÃ¡rio completo; plantÃ£o â†’ nÂº escala.
  Future<void> _editarItemNaEscalas(BuildContext context, ScaleEntry e) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    await ScaleEntryAgendaEdit.editScaleEntry(
      context: context,
      entry: e,
      userDocId: _userDocId,
      profile: widget.profile,
      onPlantaoQuickEdit: () =>
          _showEditarNumeroEscalaObservacoesResumo(context, e),
      onSaved: () {
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _showEditarNumeroEscalaObservacoesResumo(
      BuildContext context, ScaleEntry e) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final edited = await ScalePlantaoEditDialog.show(context, entry: e);
    if (edited == null || e.id == null || !mounted) return;
    try {
      final scaleRef = _scales.doc(e.id);
      await scaleRef.update(scalePlantaoFirestorePatch(edited));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('NÂº escala e observaÃ§Ãµes atualizados.'),
          ),
        );
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Erro ao salvar: ${err.toString().split('\n').first}'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  /// Remove da Escalas e sincroniza mÃ³dulos ligados (Agenda ou Produtividade).
  Future<void> _syncDeleteScaleEntry(
    ScaleEntry e, {
    BuildContext? dialogContext,
  }) async {
    if (e.id == null || e.id!.isEmpty) return;

    if (ProdutividadeScaleMirrorService.isProdutividadeFolgaEntry(e)) {
      await ProdutividadeScaleMirrorService.removeFromCalendarAndClearOcorrencias(
        userDocId: _userDocId,
        folgaDay: e.date,
      );
      return;
    }

    final scaleId = e.id!;
    if (scaleId.startsWith('agenda_') &&
        dialogContext != null &&
        dialogContext.mounted) {
      final agendaId = scaleId.substring('agenda_'.length);
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(_userDocId)
            .collection('reminders')
            .doc(agendaId)
            .get();
        if (snap.exists) {
          final data = snap.data() ?? {};
          final isAud = (data['type'] ?? 'compromisso').toString() == 'audiencia';
          await deleteAgendaReminder(
            context: dialogContext,
            userDocId: _userDocId,
            reminderDocId: agendaId,
            isAudiencia: isAud,
            reminderData: data,
          );
          return;
        }
      } catch (_) {}
    }
    await ExpressCompromissoAgendaSync.deleteScaleWithAgendaSync(
      userDocId: _userDocId,
      entry: e,
    );
  }

  Future<bool> _confirmarRemoverServicoResumo(
      BuildContext context, ScaleEntry e) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return false;
    }
    final isFolgaProd =
        ProdutividadeScaleMirrorService.isProdutividadeFolgaEntry(e);
    final label = isFolgaProd
        ? 'Folga Â· Produtividade'
        : (e.label ?? 'PlantÃ£o');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isFolgaProd ? 'Remover folga?' : 'Remover serviÃ§o?'),
        content: Text(
          isFolgaProd
              ? 'Remover a folga de Produtividade do dia ${DateFormat('dd/MM/yyyy', 'pt_BR').format(e.date)}? '
                  'As ocorrÃªncias voltam a ficar disponÃ­veis para marcar outra data.'
              : 'Remover "$label" do dia ${DateFormat('dd/MM/yyyy', 'pt_BR').format(e.date)}? Esta aÃ§Ã£o nÃ£o pode ser desfeita.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok == true && e.id != null && mounted) {
      await _removeAutoLancamentoBySourceId(e.id!);
      await _syncDeleteScaleEntry(e, dialogContext: context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${e.label ?? "ServiÃ§o"} removido.'),
              backgroundColor: Colors.green),
        );
        return true;
      }
    }
    return false;
  }

  /// Abre sheet com lista de serviÃ§os (realizados ou pendentes) com ediÃ§Ã£o e remoÃ§Ã£o, igual ao painel.
  /// Barra superior padrÃ£o dos previews/sheets do mÃ³dulo Escalas â€” pedido
  /// do usuÃ¡rio: cada preview tem **Â«VoltarÂ»** Ã  esquerda (paridade total
  /// iPhone / iOS / Android / Web) + atalho **Â«XÂ»** Ã  direita.
  /// Mesmo visual usado nos previews do Painel Inicial e nos demais
  /// mÃ³dulos (AudiÃªncias, Compromissos, Produtividade).
  Widget _scalesPreviewTopBar(BuildContext ctx) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Row(
        children: [
          Material(
            color: AppColors.primary.withValues(alpha: 0.08),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(ctx).pop(),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: AppColors.primary,
                  size: 22,
                  semanticLabel: 'Voltar',
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              foregroundColor: AppColors.primary,
            ),
            child: const Text(
              'Voltar',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const Spacer(),
          Material(
            color: Colors.grey.shade100,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(ctx).pop(),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  Icons.close_rounded,
                  size: 22,
                  color: Color(0xFF1A237E),
                  semanticLabel: 'Fechar',
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Future<void> _abrirListaServicos(
      BuildContext context, List<ScaleEntry> entries, String titulo) async {
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Nenhum serviÃ§o em $titulo.'),
            behavior: SnackBarBehavior.floating),
      );
      return;
    }
    final sorted = List<ScaleEntry>.from(entries)
      ..sort((a, b) => a.date.compareTo(b.date));
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final sheetBottomPad = MediaQuery.paddingOf(ctx).bottom;
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Topo: Â«VoltarÂ» (esquerda) + atalho Â«FecharÂ» (direita).
              // Mesmo padrÃ£o dos previews do Painel Inicial e dos demais
              // mÃ³dulos â€” mantÃ©m paridade total iPhone / Android / Web.
              _scalesPreviewTopBar(ctx),
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  titulo,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1C1E)),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  cacheExtent: 400,
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + sheetBottomPad),
                  itemCount: sorted.length,
                  itemBuilder: (_, i) {
                    final e = sorted[i];
                    return _buildResumoMesDetalhadoItemComRemoverCallback(
                      e,
                      onRemoved: () => Navigator.pop(ctx),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildResumoMesDetalhadoItemComRemoverCallback(ScaleEntry e,
      {VoidCallback? onRemoved}) {
    final valorStr =
        e.isCompromisso ? 'â€”' : CurrencyFormats.formatBRL(e.totalValue);
    final jaOrd = _jaTiradoOrdinarioDisplay(e);
    final statusStr = jaOrd ? 'JÃ¡ tirado' : 'A tirar';
    final statusColor = jaOrd ? Colors.green : Colors.orange.shade700;
    final cat = _badgeCategoriaResumoMes(e);
    final catColors = _badgeCoresCategoria(cat);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: (e.colorHex != null && e.colorHex!.isNotEmpty)
                    ? e.color
                    : _corPorTipo(e),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.label ?? 'PlantÃ£o',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Color(0xFF1A237E)),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: catColors.bg,
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(cat,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: catColors.fg)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(jaOrd ? 'JÃ¡ tirado' : 'A tirar',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: statusColor)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${DateFormat('dd/MM/yyyy', 'pt_BR').format(e.date)} Â· das ${e.start} Ã s ${e.end}',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(statusStr,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusColor)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'NÂº escala: ${(e.scaleNumber ?? '').trim().isEmpty ? '' : e.scaleNumber!.trim()}',
                    style: TextStyle(
                        fontSize: 12,
                        color: (e.scaleNumber ?? '').trim().isEmpty
                            ? Colors.grey.shade500
                            : Colors.grey.shade700),
                  ),
                  _scaleNotesGridBlock(e, showObsPrefix: true),
                ],
              ),
            ),
            Text(
              valorStr,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: e.isCompromisso
                    ? Colors.grey
                    : (jaOrd ? Colors.green : Colors.orange.shade800),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon:
                  Icon(Icons.edit_outlined, color: AppColors.primary, size: 22),
              onPressed: () => _editarItemNaEscalas(context, e),
              tooltip: 'Editar',
              style: IconButton.styleFrom(
                backgroundColor: AppColors.primary.withOpacity(0.1),
                minimumSize: const Size(40, 40),
                padding: EdgeInsets.zero,
              ),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline_rounded,
                  color: Colors.red.shade400, size: 22),
              onPressed: () async {
                final deleted =
                    await _confirmarRemoverServicoResumo(context, e);
                if (deleted && context.mounted) onRemoved?.call();
              },
              tooltip: 'Remover serviÃ§o',
              style: IconButton.styleFrom(
                backgroundColor: Colors.red.shade50,
                minimumSize: const Size(40, 40),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Card colorido no estilo Premium: borda esquerda pela cor do tipo, valor e status jÃ¡ tirado/nÃ£o tirado.
  Widget _buildShiftCardPremium(ScaleEntry e) {
    final jaOrd = _jaTiradoOrdinarioDisplay(e);
    final horas = e.hoursDay + e.hoursNight;
    final valorStr =
        e.isCompromisso ? '-' : CurrencyFormats.formatBRL(e.totalValue);
    final fsTitle = _scalesScreenFontSize(context, 17);
    final fsHora = _scalesScreenFontSize(context, 18);
    final fsAux = _scalesScreenFontSize(context, 14);
    final fsBadge = _scalesScreenFontSize(context, 14);
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
        border: Border(
            left: BorderSide(
                color: (e.colorHex != null && e.colorHex!.isNotEmpty)
                    ? e.color
                    : _corPorTipo(e),
                width: 8)),
      ),
      child: InkWell(
        onTap: () => _showOpcoesPlantao(e),
        borderRadius: BorderRadius.circular(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.label ?? 'PlantÃ£o',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: fsTitle,
                        color: const Color(0xFF1A237E)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (e.isCompromisso)
                        Text(
                          'Folga programada',
                          style: TextStyle(
                            fontSize: fsAux,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF00695C),
                          ),
                        )
                      else if (horas > 0) ...[
                        Text(
                          '${horas.toStringAsFixed(1)} h',
                          style: TextStyle(
                            fontSize: fsHora,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF1A237E),
                            height: 1.1,
                          ),
                        ),
                        Text(
                          'trabalhadas',
                          style: TextStyle(
                            fontSize: fsAux,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ] else
                        Text(
                          'Valor fixo',
                          style: TextStyle(
                            fontSize: fsAux,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      if (!e.isCompromisso)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: jaOrd
                                  ? [
                                      Colors.green.shade100,
                                      Colors.green.shade50,
                                    ]
                                  : [
                                      Colors.orange.shade100,
                                      Colors.orange.shade50,
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: jaOrd
                                  ? Colors.green.shade600
                                  : Colors.orange.shade600,
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            jaOrd ? 'JÃ¡ tirado' : 'A tirar',
                            style: TextStyle(
                              fontSize: fsBadge,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.2,
                              color: jaOrd
                                  ? Colors.green.shade900
                                  : Colors.orange.shade900,
                            ),
                          ),
                        ),
                    ],
                  ),
                  _scaleNotesGridBlock(
                    e,
                    fontSize: _scalesScreenFontSize(context, 13),
                    showObsPrefix: true,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  valorStr,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: _scalesScreenFontSize(context, 18),
                    color: e.isCompromisso
                        ? Colors.grey
                        : (jaOrd ? Colors.green : Colors.red),
                  ),
                ),
                const SizedBox(height: 4),
                Icon(
                  jaOrd ? Icons.check_circle_rounded : Icons.schedule_rounded,
                  size: 24,
                  color: jaOrd ? Colors.green : Colors.orange,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Menu ao clicar no dia: botÃ£o mÃ¡gico (perÃ­odo), expresso, incluir, trocar, limpar + resumo.
  /// Quando hÃ¡ mais de um plantÃ£o/compromisso, o usuÃ¡rio pode selecionar um para Limpar ou Trocar apenas esse.
  void _mostrarMenuDiaCalendario(BuildContext context, DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final entries = _allEntries
        .where(
            (e) => DateTime(e.date.year, e.date.month, e.date.day) == dayStart)
        .toList();
    final totalDia = entries.fold<double>(0, (s, e) => s + e.totalValue);
    final selectedIdNotifier = ValueNotifier<String?>(null);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => ValueListenableBuilder<String?>(
        valueListenable: selectedIdNotifier,
        builder: (ctx, selectedId, _) {
          ScaleEntry? selectedEntry;
          if (selectedId != null) {
            for (final e in entries) {
              if (e.id == selectedId) {
                selectedEntry = e;
                break;
              }
            }
          }
          final safeBottom = math.max(MediaQuery.viewPaddingOf(ctx).bottom,
              MediaQuery.paddingOf(ctx).bottom);
          final sheetMaxH = MediaQuery.sizeOf(ctx).height;
          return SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 16 + safeBottom),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: sheetMaxH * 0.9),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: () => Navigator.pop(ctx),
                            icon: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 17,
                              color: AppColors.textSecondary,
                            ),
                            label: Text(
                              'Voltar',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: _scalesScreenFontSize(ctx, 14),
                                color: AppColors.textSecondary,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              foregroundColor: AppColors.textSecondary,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            child: Text(
                              'Cancelar',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: _scalesScreenFontSize(ctx, 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Divider(
                          height: 14,
                          thickness: 1,
                          color: AppColors.logoSilver.withValues(alpha: 0.35)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary.withValues(alpha: 0.07),
                                AppColors.accent.withValues(alpha: 0.05),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.14),
                            ),
                          ),
                          child: Text(
                            DateFormat("EEEE, d 'de' MMMM 'de' yyyy", 'pt_BR')
                                .format(day),
                            style: TextStyle(
                              fontSize: _scalesScreenFontSize(ctx, 15),
                              fontWeight: FontWeight.w900,
                              color: AppColors.deepBlue,
                              letterSpacing: -0.2,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (ctx, constraints) {
                          // Largura real do corpo do sheet (Windows/desktop: MediaQuery.width aqui pode falhar; stretch no Row + scroll gerava altura 0).
                          var sheetW = constraints.maxWidth;
                          if (!sheetW.isFinite || sheetW <= 0) {
                            sheetW = MediaQuery.sizeOf(ctx).width;
                          }
                          if (!sheetW.isFinite || sheetW <= 0) {
                            sheetW = 400;
                          }
                          final panelW = math.max(280.0, sheetW);
                          final textScale =
                              MediaQuery.textScalerOf(ctx).scale(1.0);
                          final isUltraCompact =
                              panelW <= 360 || textScale >= 1.15;
                          final isCompact = panelW < 420;
                          final fsResumoSecTitulo =
                              _scalesScreenFontSize(ctx, isUltraCompact ? 15 : 17.5);
                          final fsResumoItemTitulo = _scalesScreenFontSize(
                              ctx, isUltraCompact ? 14.75 : 17);
                          final fsResumoValor = _scalesScreenFontSize(
                              ctx, isUltraCompact ? 13.5 : 15.5);
                          final fsResumoHint =
                              _scalesScreenFontSize(ctx, isUltraCompact ? 11 : 12);
                          final spacing =
                              isUltraCompact ? 6.0 : (isCompact ? 7.0 : 8.0);
                          Widget rowPair(Widget a, Widget b) {
                            return Padding(
                              padding: EdgeInsets.only(bottom: spacing),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: a),
                                  SizedBox(width: spacing),
                                  Expanded(child: b),
                                ],
                              ),
                            );
                          }

                          final btnEditar = _menuActionButton(
                            ctx,
                            ultraCompact: isUltraCompact,
                            compact: isCompact,
                            icon: Icons.edit_note_rounded,
                            label: 'Editar compromisso/plantÃ£o',
                            color: const Color(0xFF6366F1),
                            iconGradient: const [
                              Color(0xFF6366F1),
                              Color(0xFF8B5CF6),
                            ],
                            onTap: () async {
                              if (!widget.profile.hasActiveLicense) {
                                mostrarAvisoSeLicencaInativa(
                                    context, widget.profile);
                                return;
                              }
                              final alvo = await _selecionarItemParaEditarDia(
                                ctx,
                                entries: entries,
                                selectedEntry: selectedEntry,
                                day: dayStart,
                              );
                              if (alvo == null) return;
                              if (ctx.mounted) Navigator.pop(ctx);
                              await _abrirEdicaoCompletaCompromissoPlantao(
                                context,
                                alvo,
                              );
                            },
                          );

                          final btnIncluir = _menuActionButton(
                            ctx,
                            ultraCompact: isUltraCompact,
                            compact: isCompact,
                            icon: Icons.add_circle_rounded,
                            label: 'Incluir plantÃ£o',
                            color: const Color(0xFF10B981),
                            iconGradient: const [
                              Color(0xFF10B981),
                              Color(0xFF059669),
                            ],
                            onTap: () {
                              Navigator.pop(ctx);
                              if (!widget.profile.hasActiveLicense) {
                                mostrarAvisoSeLicencaInativa(
                                    context, widget.profile);
                                return;
                              }
                              _abrirSelecaoPlantao(context, day, trocar: false);
                            },
                          );

                          final btnTrocar = _menuActionButton(
                            ctx,
                            ultraCompact: isUltraCompact,
                            compact: isCompact,
                            icon: Icons.compare_arrows_rounded,
                            label: 'Trocar plantÃ£o',
                            color: const Color(0xFF0EA5E9),
                            iconGradient: const [
                              Color(0xFF0EA5E9),
                              Color(0xFF2563EB),
                            ],
                            onTap: () {
                              Navigator.pop(ctx);
                              if (!widget.profile.hasActiveLicense) {
                                mostrarAvisoSeLicencaInativa(
                                    context, widget.profile);
                                return;
                              }
                              if (entries.isEmpty) {
                                _abrirSelecaoPlantao(context, day,
                                    trocar: false);
                              } else {
                                _abrirSelecaoPlantao(context, day,
                                    trocar: true,
                                    entriesExistentes: selectedEntry != null
                                        ? [selectedEntry]
                                        : entries);
                              }
                            },
                          );

                          final btnMagicPeriodo = _menuMagicCalendarioCta(
                            ctx,
                            panelWidth: panelW,
                            ultraCompact: isUltraCompact,
                            compact: isCompact,
                            onTap: () {
                              if (!widget.profile.hasActiveLicense) {
                                mostrarAvisoSeLicencaInativa(
                                    context, widget.profile);
                                return;
                              }
                              // NÃ£o fecha o menu do dia: Â«VoltarÂ» no mÃ¡gico volta aos botÃµes.
                              unawaited(_gerarEscalaAutomatica(
                                ctx,
                                initialDay: dayStart,
                              ));
                            },
                          );

                          final btnPlantaoExpresso = _menuActionButton(
                            ctx,
                            ultraCompact: isUltraCompact,
                            compact: isCompact,
                            icon: Icons.bolt_rounded,
                            label: 'PlantÃ£o expresso',
                            color: const Color(0xFFF97316),
                            iconGradient: const [
                              Color(0xFFFB923C),
                              Color(0xFFF97316),
                            ],
                            onTap: () {
                              Navigator.pop(ctx);
                              if (!widget.profile.hasActiveLicense) {
                                mostrarAvisoSeLicencaInativa(
                                    context, widget.profile);
                                return;
                              }
                              showLancamentoExpressoPlantaoSheet(
                                context: context,
                                uid: _userDocId,
                                day: dayStart,
                                lockDate: true,
                                initialFinanceiro: true,
                                initialEmployer: EmployerType.state,
                                onSalvar: () {
                                  if (mounted) {
                                    _loadLocations();
                                    setState(() {});
                                  }
                                },
                              );
                            },
                          );

                          final btnCompromissoExpresso = _menuActionButton(
                            ctx,
                            ultraCompact: isUltraCompact,
                            compact: isCompact,
                            icon: Icons.event_available_rounded,
                            label: 'Compromisso particular',
                            color: const Color(0xFF14B8A6),
                            iconGradient: const [
                              Color(0xFF14B8A6),
                              Color(0xFF0D9488),
                            ],
                            onTap: () {
                              Navigator.pop(ctx);
                              if (!widget.profile.hasActiveLicense) {
                                mostrarAvisoSeLicencaInativa(
                                    context, widget.profile);
                                return;
                              }
                              showLancamentoExpressoPlantaoSheet(
                                context: context,
                                uid: _userDocId,
                                day: dayStart,
                                lockDate: true,
                                initialFinanceiro: false,
                                initialEmployer: EmployerType.state,
                                onSalvar: () {
                                  if (mounted) {
                                    _loadLocations();
                                    setState(() {});
                                  }
                                },
                              );
                            },
                          );

                          final btnLimpar = ValueListenableBuilder<String?>(
                            valueListenable: selectedIdNotifier,
                            builder: (ctx2, sid, __) {
                              ScaleEntry? sel;
                              if (sid != null) {
                                for (final e in entries) {
                                  if (e.id == sid) {
                                    sel = e;
                                    break;
                                  }
                                }
                              }
                              final lbl = sel != null
                                  ? 'Limpar plantÃ£o selecionado'
                                  : 'Limpar dia';
                              return _menuActionButton(
                                ctx2,
                                ultraCompact: isUltraCompact,
                                compact: isCompact,
                                icon: Icons.delete_sweep_rounded,
                                label: lbl,
                                color: const Color(0xFFEF4444),
                                iconGradient: const [
                                  Color(0xFFF43F5E),
                                  Color(0xFFDC2626),
                                ],
                                onTap: () {
                                  Navigator.pop(ctx2);
                                  if (!widget.profile.hasActiveLicense) {
                                    mostrarAvisoSeLicencaInativa(
                                        context, widget.profile);
                                    return;
                                  }
                                  if (sel != null) {
                                    _limparPlantao(context, sel);
                                  } else {
                                    _limparDia(context, day);
                                  }
                                },
                              );
                            },
                          );

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              RepaintBoundary(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    btnMagicPeriodo,
                                    SizedBox(height: spacing),
                                    rowPair(btnEditar, btnPlantaoExpresso),
                                    rowPair(btnIncluir, btnCompromissoExpresso),
                                    rowPair(btnTrocar, btnLimpar),
                                  ],
                                ),
                              ),
                      // Resumo do dia (cores por frente + valores); toque para selecionar quando hÃ¡ mais de um
                      if (entries.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Divider(height: 1),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.primary.withValues(alpha: 0.12),
                                    AppColors.accent.withValues(alpha: 0.08),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.18),
                                ),
                              ),
                              child: Icon(Icons.summarize_rounded,
                                  size: isUltraCompact ? 19 : 22,
                                  color: AppColors.primary
                                      .withValues(alpha: 0.95)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Resumo do dia',
                                style: TextStyle(
                                    fontSize: fsResumoSecTitulo,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.textPrimary,
                                    letterSpacing: 0.12,
                                    height: 1.2),
                              ),
                            ),
                          ],
                        ),
                        if (entries.length >= 2)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Toque em um plantÃ£o para selecionar e usar Limpar ou Trocar nele.',
                              style: TextStyle(
                                  fontSize: fsResumoHint,
                                  color: Colors.grey.shade600,
                                  fontStyle: FontStyle.italic),
                            ),
                          ),
                        const SizedBox(height: 12),
                        ...entries.map((e) {
                          final jaOrd = _jaTiradoOrdinarioDisplay(e);
                          final cor =
                              (e.colorHex != null && e.colorHex!.isNotEmpty)
                                  ? e.color
                                  : _corPorTipo(e);
                          final valorStr = e.isCompromisso
                              ? 'â€”'
                              : CurrencyFormats.formatBRL(e.totalValue);
                          final horas = e.hoursDay + e.hoursNight;
                          final subtitulo = e.isCompromisso
                              ? 'Compromisso'
                              : (horas > 0
                                  ? '${horas.toStringAsFixed(1)}h'
                                  : 'Valor fixo');
                          final isSelected = e.id != null && e.id == selectedId;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Material(
                              color: isSelected
                                  ? AppColors.primary.withOpacity(0.08)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                onTap: e.id == null
                                    ? null
                                    : () => selectedIdNotifier.value =
                                        isSelected ? null : e.id,
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 8),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 6,
                                        height: isUltraCompact ? 44 : 48,
                                        decoration: BoxDecoration(
                                          color: cor,
                                          borderRadius:
                                              BorderRadius.circular(3),
                                        ),
                                      ),
                                      if (entries.length >= 2) ...[
                                        const SizedBox(width: 8),
                                        Icon(
                                            isSelected
                                                ? Icons.check_circle_rounded
                                                : Icons
                                                    .radio_button_unchecked_rounded,
                                            size: 22,
                                            color: isSelected
                                                ? AppColors.primary
                                                : Colors.grey.shade400),
                                      ],
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            scaleEntryResumoTitleText(
                                              e,
                                              fontSize: fsResumoItemTitulo,
                                              color: const Color(0xFF1A237E),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              scaleEntryDiaSemanaDataHorario(e),
                                              style: scaleEntryResumoMetaTextStyle(
                                                fontSize: isUltraCompact ? 12.5 : 13.5,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                            ...scaleEntryResumoNumberLines(e).map(
                                              (linha) => Padding(
                                                padding: const EdgeInsets.only(top: 2),
                                                child: Text(
                                                  linha,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: const Color(0xFF1A237E),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Text(
                                              subtitulo,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade600),
                                            ),
                                            _scaleNotesGridBlock(
                                              e,
                                              fontSize: 11,
                                              showObsPrefix: true,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        valorStr,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: fsResumoValor,
                                          color: e.isCompromisso
                                              ? Colors.grey
                                              : (jaOrd
                                                  ? Colors.green
                                                  : Colors.orange.shade800),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 12),
                        RepaintBoundary(
                          child: FutureBuilder<
                              ({double ate2359, double de0007, bool temSplit})>(
                            future: _computeSplitDia(day, entries),
                            builder: (context, snap) {
                              final split = snap.data;
                              final temSplit = split?.temSplit ?? false;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 10, horizontal: 14),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color:
                                          AppColors.primary.withOpacity(0.25)),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (temSplit && split != null) ...[
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('AtÃ© 23:59 (padrÃ£o GO)',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.grey.shade800)),
                                          Text(
                                              CurrencyFormats.formatBRL(
                                                  split.ate2359),
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 14,
                                                  color: Color(0xFF1A237E))),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('00h Ã s 07h (prÃ³x. dia)',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.grey.shade800)),
                                          Text(
                                              CurrencyFormats.formatBRL(
                                                  split.de0007),
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 14,
                                                  color:
                                                      Colors.indigo.shade700)),
                                        ],
                                      ),
                                      if (_isLastDayOfMonth(day) &&
                                          split.de0007 > 0) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.indigo.shade50,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                                color: Colors.indigo.shade200),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(Icons.info_outline_rounded,
                                                  size: 14,
                                                  color:
                                                      Colors.indigo.shade700),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'O valor referente ao horÃ¡rio 00h00 Ã s 07h ficarÃ¡ para o prÃ³ximo mÃªs.',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors
                                                          .indigo.shade800),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ] else ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          'Banco de Horas: 05h Ã s 22h (diurno); 22h01 Ã s 05h (noturno).',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey.shade600),
                                        ),
                                      ],
                                      const Divider(height: 16),
                                    ],
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('Total do dia',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 14,
                                                color: Color(0xFF1A237E))),
                                        Text(
                                          CurrencyFormats.formatBRL(totalDia),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 16,
                                              color: Color(0xFF1A237E)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ).then((_) {
      selectedIdNotifier.dispose();
    });
  }

  /// BotÃ£o especial do calendÃ¡rio â€” mesmo shell premium dos demais CTAs do menu (largura total).
  Widget _menuMagicCalendarioCta(
    BuildContext context, {
    required VoidCallback onTap,
    required double panelWidth,
    bool ultraCompact = false,
    bool compact = false,
  }) {
    const color = Color(0xFF7C3AED);
    const iconGradient = [
      Color(0xFF5B21B6),
      Color(0xFF7C3AED),
      Color(0xFFD97706),
    ];
    final titleFs = _scalesScreenFontSize(
      context,
      ultraCompact ? 10 : (compact ? 10.5 : 11),
    );
    final subFs = _scalesScreenFontSize(
      context,
      ultraCompact ? 9 : 9.5,
    );
    final badgeFs = _scalesScreenFontSize(context, ultraCompact ? 8 : 8.5);
    final bgA = Color.lerp(Colors.white, color, 0.05)!;
    final bgB = Color.lerp(Colors.white, color, 0.11)!;
    final titleColor = Color.lerp(color, const Color(0xFF0F172A), 0.38)!;
    final iconSize = ultraCompact ? 17 : (compact ? 18 : 19);
    final iconPad = ultraCompact ? 6.0 : (compact ? 7.0 : 7.0);
    final useSideBySide = panelWidth >= 360 && !ultraCompact;

    Widget iconBadge() {
      return Container(
        padding: EdgeInsets.all(iconPad),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: iconGradient,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.28),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          Icons.auto_awesome_rounded,
          color: Colors.white,
          size: iconSize + 2,
        ),
      );
    }

    Widget textBlock({required TextAlign align}) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: useSideBySide
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFFD97706).withValues(alpha: 0.45),
              ),
            ),
            child: Text(
              'BOTÃƒO MÃGICO',
              textAlign: align,
              style: TextStyle(
                fontSize: badgeFs,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
                color: const Color(0xFFB45309),
              ),
            ),
          ),
          SizedBox(height: ultraCompact ? 5 : 6),
          Text(
            'PerÃ­odo automÃ¡tico',
            textAlign: align,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: titleFs,
              fontWeight: FontWeight.w900,
              height: 1.12,
              letterSpacing: 0.02,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'OrdinÃ¡rias Â· extras Â· compromissos',
            textAlign: align,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: subFs,
              fontWeight: FontWeight.w700,
              height: 1.15,
              color: AppColors.textMuted,
            ),
          ),
        ],
      );
    }

    final body = useSideBySide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              iconBadge(),
              const SizedBox(width: 12),
              Expanded(child: textBlock(align: TextAlign.start)),
              Icon(
                Icons.chevron_right_rounded,
                color: color.withValues(alpha: 0.75),
                size: compact ? 22 : 24,
              ),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconBadge(),
              SizedBox(height: ultraCompact ? 5 : 6),
              textBlock(align: TextAlign.center),
            ],
          );

    return Material(
      color: Colors.transparent,
      elevation: 0,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [bgA, bgB],
            ),
            border: Border.all(color: color.withValues(alpha: 0.34), width: 1),
            boxShadow: [
              BoxShadow(
                color: AppColors.deepBlueDark.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
              BoxShadow(
                color: color.withValues(alpha: 0.12),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: 44,
              minHeight: ultraCompact ? 52 : (compact ? 56 : 58),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: ultraCompact ? 8 : (compact ? 9 : 10),
                horizontal: ultraCompact ? 8 : (compact ? 10 : 12),
              ),
              child: body,
            ),
          ),
        ),
      ),
    );
  }

  /// CartÃ£o de aÃ§Ã£o do menu do dia â€” compacto, sombra suave e gradiente (alinhado ao premium Financeiro).
  Widget _menuActionButton(BuildContext context,
      {required IconData icon,
      required String label,
      required Color color,
      List<Color>? iconGradient,
      bool ultraCompact = false,
      bool compact = false,
      required VoidCallback onTap}) {
    final fs = _scalesScreenFontSize(
      context,
      ultraCompact ? 9.5 : (compact ? 10 : 10.5),
    );
    final ig = iconGradient ??
        <Color>[
          color,
          Color.lerp(color, Colors.black, 0.22) ?? color,
        ];
    final bgA = Color.lerp(Colors.white, color, 0.05)!;
    final bgB = Color.lerp(Colors.white, color, 0.11)!;
    return Material(
      color: Colors.transparent,
      elevation: 0,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [bgA, bgB],
            ),
            border: Border.all(color: color.withValues(alpha: 0.34), width: 1),
            boxShadow: [
              BoxShadow(
                color: AppColors.deepBlueDark.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
              BoxShadow(
                color: color.withValues(alpha: 0.1),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: 44,
              minHeight: ultraCompact ? 40 : (compact ? 44 : 48),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: ultraCompact ? 6 : (compact ? 7 : 8),
                horizontal: ultraCompact ? 6 : (compact ? 7 : 8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding:
                        EdgeInsets.all(ultraCompact ? 6 : (compact ? 7 : 7)),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: ig,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.28),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(icon,
                        color: Colors.white,
                        size: ultraCompact ? 17 : (compact ? 18 : 19)),
                  ),
                  SizedBox(height: ultraCompact ? 5 : 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: fs,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.02,
                      height: 1.12,
                      color: Color.lerp(color, const Color(0xFF0F172A), 0.38),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _limparDia(BuildContext context, DateTime day) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Limpar dia?'),
        content: Text(
            'Remover todos os lanÃ§amentos do dia ${DateFormat('dd/MM').format(day)}? '
            'Se houver folga de Produtividade, as ocorrÃªncias voltam a ficar disponÃ­veis para marcar outra data.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(_, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Limpar')),
        ],
      ),
    );
    if (confirm != true) return;
    final dayStart = DateTime(day.year, day.month, day.day);
    final toDelete = _allEntries
        .where(
            (e) => DateTime(e.date.year, e.date.month, e.date.day) == dayStart)
        .where((e) => e.id != null)
        .toList();
    await _removeAutoLancamentosBySourceIds(
        toDelete.map((e) => e.id!).toList());
    for (final e in toDelete) {
      await _syncDeleteScaleEntry(e, dialogContext: context);
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Dia limpo.')));
      setState(() {});
    }
  }

  /// Remove apenas o plantÃ£o/compromisso selecionado (usado quando o usuÃ¡rio escolhe um item no resumo do dia).
  Future<void> _limparPlantao(BuildContext context, ScaleEntry entry) async {
    if (entry.id == null) return;
    final isFolgaProd =
        ProdutividadeScaleMirrorService.isProdutividadeFolgaEntry(entry);
    final label = isFolgaProd
        ? 'Folga Â· Produtividade'
        : (entry.label ?? (entry.isCompromisso ? 'Compromisso' : 'PlantÃ£o'));
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isFolgaProd ? 'Remover folga?' : 'Limpar plantÃ£o?'),
        content: Text(
          isFolgaProd
              ? 'Remover a folga de Produtividade do dia ${DateFormat('dd/MM').format(entry.date)}? '
                  'As ocorrÃªncias voltam a ficar disponÃ­veis.'
              : 'Remover apenas "$label" do dia ${DateFormat('dd/MM').format(entry.date)}?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(_, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Limpar')),
        ],
      ),
    );
    if (confirm != true) return;
    await _removeAutoLancamentoBySourceId(entry.id!);
    await _syncDeleteScaleEntry(entry, dialogContext: context);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isFolgaProd
              ? 'Folga removida. OcorrÃªncias liberadas.'
              : 'PlantÃ£o removido.'),
        ),
      );
      setState(() {});
    }
  }

  Future<ScaleEntry?> _selecionarItemParaEditarDia(
    BuildContext context, {
    required List<ScaleEntry> entries,
    required DateTime day,
    ScaleEntry? selectedEntry,
  }) async {
    if (entries.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          const SnackBar(
              content: Text('NÃ£o hÃ¡ plantÃ£o/compromisso neste dia.')),
        );
      }
      return null;
    }
    if (selectedEntry != null) return selectedEntry;
    if (entries.length == 1) return entries.first;
    return showModalBottomSheet<ScaleEntry>(
      context: context,
      useSafeArea: true,
      useRootNavigator: true,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Escolha o item para editar',
                style: TextStyle(
                  fontSize: _scalesScreenFontSize(ctx, 17),
                  fontWeight: FontWeight.w900,
                  color: AppColors.deepBlue,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('dd/MM/yyyy').format(day),
                style: TextStyle(
                  fontSize: _scalesScreenFontSize(ctx, 12),
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              ...entries.map(
                (e) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor:
                        (e.colorHex != null && e.colorHex!.isNotEmpty)
                            ? e.color.withValues(alpha: 0.2)
                            : _corPorTipo(e).withValues(alpha: 0.2),
                    child: Icon(
                      e.isCompromisso
                          ? Icons.event_note_rounded
                          : Icons.work_outline_rounded,
                      size: 16,
                      color: (e.colorHex != null && e.colorHex!.isNotEmpty)
                          ? e.color
                          : _corPorTipo(e),
                    ),
                  ),
                  title: Text(e.label?.trim().isNotEmpty == true
                      ? e.label!.trim()
                      : 'PlantÃ£o'),
                  subtitle: Text(
                    '${DateFormat('dd/MM/yyyy', 'pt_BR').format(e.date)}\nDas ${e.start} Ã s ${e.end}',
                    style: TextStyle(
                      fontSize: _scalesScreenFontSize(ctx, 12),
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  trailing: Text(
                    e.isCompromisso
                        ? 'Sem financeiro'
                        : CurrencyFormats.formatBRL(e.totalValue),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: e.isCompromisso
                          ? AppColors.textMuted
                          : AppColors.primary,
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx, e),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Folga criada no mÃ³dulo Produtividade â€” remover aqui libera as ocorrÃªncias.
  Future<void> _dialogoEdicaoSomenteProdutividadeFolga(
    BuildContext context,
    ScaleEntry e,
  ) async {
    final dataStr = DateFormat('dd/MM/yyyy', 'pt_BR').format(e.date);
    final cor = (e.colorHex ?? kProdutividadeFolgaCalendarDefaultHex);
    final corPreview = AppColors.vividShift(
      ScaleEntry(
        date: e.date,
        start: e.start,
        end: e.end,
        colorHex: cor,
      ).color,
    );
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            Icon(Icons.layers_rounded, color: AppColors.accent, size: 26),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Folga Â· Produtividade',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Data da folga: $dataStr\n\n'
                'Este dia foi marcado no mÃ³dulo Produtividade / OcorrÃªncias. '
                'A cor abaixo Ã© a mesma exibida no calendÃ¡rio de Escalas.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.38,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: corPreview,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.black12),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Cor no calendÃ¡rio: $cor',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Para remover: use Â«Remover folgaÂ» aqui ou Â«Limpar data da folgaÂ» em Produtividade â€º OcorrÃªncias.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'close'),
            child: const Text('Fechar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, 'remove'),
            child: const Text('Remover folga'),
          ),
        ],
      ),
    );
    if (action != 'remove' || !context.mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover folga do calendÃ¡rio?'),
        content: const Text(
          'O dia serÃ¡ limpo no calendÃ¡rio de Escalas e as ocorrÃªncias vinculadas '
          'voltam a ficar disponÃ­veis para marcar folga noutra data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    await ProdutividadeScaleMirrorService.removeFromCalendarAndClearOcorrencias(
      userDocId: _userDocId,
      folgaDay: e.date,
    );
    if (context.mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Folga removida. CalendÃ¡rio limpo e ocorrÃªncias liberadas.',
          ),
        ),
      );
    }
  }

  /// Espelho da Agenda (`agenda_*`): formulÃ¡rio completo (Compromisso / AudiÃªncia).
  Future<void> _abrirEdicaoEspelhoAgenda(
    BuildContext context,
    ScaleEntry e,
  ) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    try {
      final msg = await ScaleEntryAgendaEdit.openFullEditor(
        context: context,
        entry: e,
        userDocId: _userDocId,
        profile: widget.profile,
      );
      if (msg != null && mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao atualizar: ${err.toString().split('\n').first}',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _abrirEdicaoCompletaCompromissoPlantao(
    BuildContext context,
    ScaleEntry e,
  ) async {
    if (e.id == null) return;
    if (ProdutividadeScaleMirrorService.isProdutividadeFolgaEntry(e)) {
      await _dialogoEdicaoSomenteProdutividadeFolga(context, e);
      return;
    }
    final sid = e.id!.trim();
    if (e.isCompromisso && scaleEntryRequiresFullEditor(e)) {
      await ScaleEntryAgendaEdit.editScaleEntry(
        context: context,
        entry: e,
        userDocId: _userDocId,
        profile: widget.profile,
        onPlantaoQuickEdit: () async {},
        onSaved: () {
          if (mounted) {
            _loadLocations();
            setState(() {});
          }
        },
      );
      return;
    }
    final origemSrc = (e.source ?? '').trim().toLowerCase();
    if (origemSrc.startsWith('agenda_') || scaleEntryUsesAgendaFullEditor(e)) {
      await _abrirEdicaoEspelhoAgenda(context, e);
      return;
    }
    final locOrigem = matchShiftLocationForScaleEntry(e, _locations);
    final editarComoExpresso = e.isLancamentoExpresso ||
        (locOrigem == null &&
            (e.isCompromisso || (e.employerType ?? '').trim().isNotEmpty));
    if (editarComoExpresso) {
      await showLancamentoExpressoPlantaoSheet(
        context: context,
        uid: _userDocId,
        day: e.date,
        lockDate: true,
        initialFinanceiro: !e.isCompromisso && e.totalValue > 0,
        initialEmployer: _employerTypeFromScaleEntry(e) ?? EmployerType.state,
        editingEntry: e,
        onSalvar: () {
          if (mounted) {
            _loadLocations();
            setState(() {});
          }
        },
      );
      return;
    }
    final editarNoPreCadastro = locOrigem?.id != null;
    if (editarNoPreCadastro) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EditLocationScreen(
            uid: _userDocId,
            location: locOrigem,
          ),
        ),
      );
      if (mounted) {
        await _loadLocations();
        setState(() {});
      }
      return;
    }

    final nomeCtrl = TextEditingController(text: (e.label ?? '').trim());
    final observacoesCtrl = TextEditingController(text: (e.notes ?? '').trim());
    DateTime dataEscala = DateTime(e.date.year, e.date.month, e.date.day);
    TimeOfDay horaInicial = _parseTime(e.start);
    TimeOfDay horaFinal = _parseTime(e.end);
    var isCompromisso = e.isCompromisso;
    var semFinanceiro = e.isCompromisso || e.totalValue <= 0;
    var selectedColorHex = (e.colorHex ?? '#2D5BFF').replaceFirst('0xFF', '#');
    if (!selectedColorHex.startsWith('#'))
      selectedColorHex = '#$selectedColorHex';
    final scaleNumberCtrl = TextEditingController(
      text: scalePlantaoNumberFromEntry(e),
    );

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> colarNoCampo({
            required TextEditingController controller,
            required bool uppercase,
            required int? maxLen,
          }) async {
            final data = await Clipboard.getData(Clipboard.kTextPlain);
            final raw = (data?.text ?? '').trim();
            if (raw.isEmpty) return;
            var txt = uppercase ? raw.toUpperCase() : raw;
            if (maxLen != null && txt.length > maxLen) {
              txt = txt.substring(0, maxLen);
            }
            controller.text = txt;
            controller.selection = TextSelection.collapsed(offset: txt.length);
          }

          Future<void> escolherCor() async {
            final coresPremium = kColorPaletteHex.take(21).toList();
            final picked = await showModalBottomSheet<String>(
              context: ctx,
              useSafeArea: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              builder: (bctx) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Toque na cor para escolher',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: AppColors.deepBlue,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: coresPremium.map((hex) {
                          final h = hex.startsWith('#') ? hex : '#$hex';
                          final isSelected =
                              selectedColorHex.toUpperCase() == h.toUpperCase();
                          return InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () => Navigator.pop(bctx, h),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF000000 +
                                    int.parse(h.replaceFirst('#', ''),
                                        radix: 16)),
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.grey.shade300,
                                  width: isSelected ? 2.5 : 1.1,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Colors.black26, blurRadius: 2)
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.pop(bctx),
                          child: const Text('Cancelar'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
            if (picked != null && picked.isNotEmpty) {
              setModalState(() => selectedColorHex = picked);
            }
          }

          Future<void> pickTime(bool inicio) async {
            final t = await showTimePicker(
              context: ctx,
              initialTime: inicio ? horaInicial : horaFinal,
            );
            if (t == null) return;
            setModalState(() {
              if (inicio) {
                horaInicial = t;
              } else {
                horaFinal = t;
              }
            });
          }

          return KeyboardViewInsetPad(
            left: 20,
            right: 20,
            top: 16,
            bottom: 20,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        icon: const Icon(Icons.arrow_back_rounded),
                        tooltip: 'Voltar',
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Editar compromisso/plantÃ£o',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: AppColors.deepBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FastTextField(
                    controller: nomeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [UpperCaseTextFormatter()],
                    textInputAction: TextInputAction.next,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: const InputDecoration(
                      labelText: 'Nome',
                      hintText: 'NOME DO PLANTÃƒO/COMPROMISSO',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SizedBox(
                        width: 122,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked =
                                await pickSingleDateWithHolidayCalendar(
                              context: ctx,
                              initialDate: dataEscala,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030, 12, 31),
                            );
                            if (picked != null) {
                              setModalState(() => dataEscala = picked);
                            }
                          },
                          icon:
                              const Icon(Icons.edit_calendar_rounded, size: 18),
                          label:
                              Text(DateFormat('dd/MM/yyyy').format(dataEscala)),
                        ),
                      ),
                      SizedBox(
                        width: 112,
                        child: OutlinedButton.icon(
                          onPressed: () => pickTime(true),
                          icon: const Icon(Icons.access_time_rounded, size: 18),
                          label: Text(
                              '${horaInicial.hour.toString().padLeft(2, '0')}:${horaInicial.minute.toString().padLeft(2, '0')}'),
                        ),
                      ),
                      SizedBox(
                        width: 112,
                        child: OutlinedButton.icon(
                          onPressed: () => pickTime(false),
                          icon: const Icon(Icons.access_time_rounded, size: 18),
                          label: Text(
                              '${horaFinal.hour.toString().padLeft(2, '0')}:${horaFinal.minute.toString().padLeft(2, '0')}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!e.isAgendaMirror) ...[
                    FastTextField(
                      controller: scaleNumberCtrl,
                      contextMenuBuilder: _ptBrContextMenuBuilder,
                      textInputAction: TextInputAction.next,
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      inputFormatters: [UpperCaseTextFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'NÂº Escala',
                        hintText: 'EX.: 123456',
                        helperText: 'PlantÃ£o ou compromisso na escala',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonalIcon(
                        onPressed: () => colarNoCampo(
                          controller: scaleNumberCtrl,
                          uppercase: true,
                          maxLen: null,
                        ),
                        icon: const Icon(Icons.content_paste_rounded, size: 18),
                        label: const Text('Colar nÂº escala'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 40),
                        ),
                      ),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'SEI e RAI deste item sÃ£o editados em '
                        'AudiÃªncias/Compromissos.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  FastTextField(
                    controller: observacoesCtrl,
                    contextMenuBuilder: _ptBrContextMenuBuilder,
                    minLines: 3,
                    maxLines: 8,
                    maxLength: kScaleNotesMaxLength,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    textInputAction: TextInputAction.newline,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [UpperCaseTextFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'ObservaÃ§Ãµes',
                      hintText: 'Detalhes do plantÃ£o/compromisso',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      onPressed: () => colarNoCampo(
                        controller: observacoesCtrl,
                        uppercase: true,
                        maxLen: kScaleNotesMaxLength,
                      ),
                      icon: const Icon(Icons.content_paste_rounded, size: 18),
                      label: const Text('Colar observaÃ§Ã£o'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F9FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.18)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF000000 +
                                int.parse(
                                    selectedColorHex.replaceFirst('#', ''),
                                    radix: 16)),
                            border: Border.all(color: Colors.white, width: 1.6),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 2)
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Cor do lanÃ§amento',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: escolherCor,
                          icon: const Icon(Icons.palette_outlined, size: 18),
                          label: const Text('Toque na cor para escolher'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: isCompromisso,
                    onChanged: (v) => setModalState(() {
                      isCompromisso = v;
                      if (isCompromisso) semFinanceiro = true;
                    }),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Compromisso particular'),
                    subtitle: const Text('Sem valor financeiro'),
                  ),
                  if (!isCompromisso)
                    SwitchListTile(
                      value: semFinanceiro,
                      onChanged: (v) => setModalState(() => semFinanceiro = v),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('LanÃ§ar como nÃ£o financeiro'),
                      subtitle: const Text(
                          'Desativa cÃ¡lculo de valor neste lanÃ§amento'),
                    ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(ctx, false),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(ctx, true),
                          icon: const Icon(Icons.save_rounded),
                          label: const Text('Salvar'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (saved != true || !mounted) return;

    final nome = nomeCtrl.text.trim().toUpperCase();
    if (nome.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o nome do compromisso/plantÃ£o.')),
      );
      return;
    }

    final start =
        '${horaInicial.hour.toString().padLeft(2, '0')}:${horaInicial.minute.toString().padLeft(2, '0')}';
    final end =
        '${horaFinal.hour.toString().padLeft(2, '0')}:${horaFinal.minute.toString().padLeft(2, '0')}';
    final startDt = DateTime(dataEscala.year, dataEscala.month, dataEscala.day,
        horaInicial.hour, horaInicial.minute);
    var endDt = DateTime(dataEscala.year, dataEscala.month, dataEscala.day,
        horaFinal.hour, horaFinal.minute);
    if (endDt.isBefore(startDt) || endDt.isAtSameMomentAs(startDt)) {
      endDt = endDt.add(const Duration(days: 1));
    }

    var totalValue = 0.0;
    var hoursDay = 0.0;
    var hoursNight = 0.0;
    var dayRate = 0.0;
    var nightRate = 0.0;
    var employerType =
        e.employerType ?? locOrigem?.employerType.name ?? 'private';

    final financeiroAtivo = !isCompromisso && !semFinanceiro;
    if (financeiroAtivo) {
      if (locOrigem != null &&
          locOrigem.financialEnabled &&
          locOrigem.employerType == EmployerType.private &&
          locOrigem.paymentType == PaymentType.fixed &&
          locOrigem.baseValue > 0) {
        totalValue = locOrigem.baseValue;
        employerType = locOrigem.employerType.name;
      } else {
        final rates = await ScaleRatesService().getRatesForServiceDay(
          _userDocId,
          dataEscala,
        );
        final res = await ScaleRatesService().computeShiftForUid(
          uid: _userDocId,
          start: startDt,
          end: endDt,
          entryDate: dataEscala,
        );
        totalValue = (res['total'] ?? 0).toDouble();
        hoursDay = (res['hoursDay'] ?? 0).toDouble();
        hoursNight = (res['hoursNight'] ?? 0).toDouble();
        dayRate = rates
            .diurnoForWeekday(ScaleRates.weekdayToIndex(dataEscala.weekday));
        nightRate = rates
            .noturnoForWeekday(ScaleRates.weekdayToIndex(dataEscala.weekday));
      }
    }

    final notesRaw = observacoesCtrl.text.trim().toUpperCase();
    final notes = normalizeScaleNotesForSave(notesRaw);
    final plantaoPatch = ScalePlantaoEditValues(
      scaleNumber: e.isAgendaMirror ? '' : scaleNumberCtrl.text,
      notes: notes,
    );
    final scaleNumSalvo = plantaoPatch.scaleNumber.trim().toUpperCase();
    final abbrev = ShiftLocation.abbreviationFromName(nome);
    final updated = ScaleEntry(
      id: e.id,
      date: dataEscala,
      start: start,
      end: end,
      dayRate: dayRate,
      nightRate: nightRate,
      hoursDay: hoursDay,
      hoursNight: hoursNight,
      totalValue: totalValue,
      notes: notes,
      scaleNumber: e.isAgendaMirror
          ? e.scaleNumber
          : (scaleNumSalvo.isEmpty ? null : scaleNumSalvo),
      numeroSei: e.isAgendaMirror ? e.numeroSei : null,
      numeroOcorrencia: e.isAgendaMirror ? e.numeroOcorrencia : null,
      label: nome,
      abbreviation: abbrev.isNotEmpty ? abbrev : e.abbreviation,
      colorHex: selectedColorHex,
      paid: e.paid,
      isCompromisso: isCompromisso,
      employerType: financeiroAtivo ? employerType : '',
      reminder: e.reminder,
      reminderLeads: null,
    );

    try {
      final beforeSnap = await _scales.doc(e.id).get();
      final beforeData = beforeSnap.data() ?? <String, dynamic>{};
      final updateMap = updated.toMap()
        ..addAll(
          e.isAgendaMirror
              ? <String, dynamic>{'notes': notes}
              : scalePlantaoFirestorePatch(plantaoPatch),
        )
        ..['reminderLeads'] = FieldValue.delete()
        ..['notificationSoundId'] = FieldValue.delete()
        ..['notificationDeliveryMode'] = FieldValue.delete();
      final afterPlan = Map<String, dynamic>.from(beforeData)..addAll(updateMap);
      final deliveryReset = AgendaDeliveryReset.scaleScheduleChanged(
            beforeData, dataEscala, start) ||
        AgendaDeliveryReset.scaleNotifyPlanChanged(beforeData, afterPlan);
      if (deliveryReset) {
        updateMap.addAll(
          AgendaDeliveryReset.clearDeliveryFields(includeScaleNotificado: true),
        );
      }
      await _scales.doc(e.id).update(updateMap);
      unawaited(AgendaNotificationRescheduleHelper.afterScaleSave(
        userDocId: _userDocId,
        scaleRef: _scales.doc(e.id!),
        beforeData: beforeData,
        newDate: dataEscala,
        newStartHHmm: start,
        afterPlanSnapshot: afterPlan,
      ));
      if (financeiroAtivo) {
        await _syncAutoLancamentoViradaMes(
          sourceId: e.id!,
          sourceDate: dataEscala,
          startDt: startDt,
          endDt: endDt,
          financeiroAtivo: true,
          isCompromisso: isCompromisso,
          nome: nome,
          abbreviation: updated.abbreviation,
          colorHex: selectedColorHex,
          employerType: employerType,
        );
      } else {
        await _removeAutoLancamentoBySourceId(e.id!);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Compromisso/plantÃ£o atualizado com sucesso.')),
        );
        setState(() {});
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Erro ao salvar ediÃ§Ã£o: ${err.toString().split('\n').first}')),
        );
      }
    }
  }

  EmployerType? _employerTypeFromScaleEntry(ScaleEntry e) {
    switch ((e.employerType ?? '').trim().toLowerCase()) {
      case 'state':
        return EmployerType.state;
      case 'municipality':
        return EmployerType.municipality;
      case 'private':
        return EmployerType.private;
    }
    return null;
  }

  /// Abre seleÃ§Ã£o: plantÃµes prÃ©-cadastrados (locations) ou criar novo.
  Future<void> _abrirSelecaoPlantao(BuildContext context, DateTime day,
      {bool trocar = false,
      List<ScaleEntry>? entriesExistentes,
      bool limparSelecaoSeDiaVazioAoFechar = false}) async {
    final result = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (ctx) => SelecaoPlantaoSheet(
          uid: _userDocId,
          day: day,
          locations: _locations,
          trocar: trocar,
          entriesExistentes: entriesExistentes ?? [],
          onSalvar: () {
            if (mounted) {
              _loadLocations();
              setState(() {});
            }
          },
          onCriarNovo: () {
            Navigator.pop(ctx, true);
            _abrirFormularioEscala(context, initialDate: day);
          },
          onPeriodoAutomatico: trocar
              ? null
              : () {
                  // MantÃ©m [SelecaoPlantaoSheet]: voltar do mÃ¡gico retorna aos botÃµes do dia.
                  unawaited(_gerarEscalaAutomatica(ctx, initialDay: day));
                },
        ),
      ),
    );
    if (!mounted) return;
    if (limparSelecaoSeDiaVazioAoFechar && result != true) {
      final dayStart = DateTime(day.year, day.month, day.day);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final aindaVazio = !_allEntries.any(
            (e) => DateTime(e.date.year, e.date.month, e.date.day) == dayStart);
        if (aindaVazio && _isSameDay(_selectedDay, day)) {
          setState(() => _selectedDay = null);
        }
      });
    }
    setState(() {});
  }

  /// Abre ConfiguraÃ§Ãµes â†’ PlantÃµes (lista de plantÃµes recorrentes: editar/excluir/novo).
  void _preCadastrarPlantao(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LocationsScreen(uid: _userDocId)),
    );
    // Recarrega lista em background para nÃ£o travar a volta Ã  tela
    if (mounted) _loadLocations();
  }

  Future<void> _addScale(BuildContext context, {DateTime? initialDate}) async {
    _abrirFormularioEscala(context,
        initialDate: initialDate ?? _selectedDay ?? _focusedDay);
  }

  void _showOpcoesPlantao(ScaleEntry e) {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final turnoTerminou = _turnoJaTerminou(e);
    final fimTurno = _fimDoTurno(e);
    final podeConfirmarConclusao = e.isCompromisso || turnoTerminou;

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      useRootNavigator: true,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (e.paid)
              ListTile(
                leading: const Icon(Icons.pending_actions_rounded),
                title: const Text('Marcar como pendente'),
                subtitle: const Text('Volta a aparecer como pendente'),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (e.id == null) return;
                  try {
                    await _scales.doc(e.id).update({'paid': false});
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Marcado como pendente.')));
                  } catch (err) {
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                              'Erro: ${err.toString().split('\n').first}')));
                  }
                },
              )
            else if (e.isCompromisso)
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('Confirmar conclusÃ£o'),
                subtitle: const Text('Marcar compromisso como realizado'),
                onTap: () => _confirmarConclusao(ctx, e),
              )
            else if (podeConfirmarConclusao)
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('Confirmar conclusÃ£o'),
                subtitle: const Text('Confirmar que o serviÃ§o foi realizado'),
                onTap: () => _confirmarConclusao(ctx, e),
              )
            else
              ListTile(
                leading: Icon(Icons.lock_clock_rounded,
                    color: Colors.orange.shade700),
                title: const Text('Confirmar conclusÃ£o'),
                subtitle: Text(
                    'DisponÃ­vel apÃ³s o fim do turno (${DateFormat('dd/MM').format(fimTurno)} Ã s ${DateFormat('HH:mm').format(fimTurno)})'),
                enabled: false,
              ),
            ListTile(
              leading: const Icon(Icons.edit_calendar_rounded),
              title: const Text('Editar compromisso/plantÃ£o'),
              subtitle: const Text(
                'Editar nome, data, horÃ¡rio, cor e observaÃ§Ãµes',
              ),
              onTap: () async {
                Navigator.pop(ctx);
                await _abrirEdicaoCompletaCompromissoPlantao(context, e);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Excluir',
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.w600)),
              onTap: () async {
                Navigator.pop(ctx);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Excluir plantÃ£o?'),
                    content: Text(
                        '${e.label ?? 'PlantÃ£o'} em ${DateFormat('dd/MM').format(e.date)} serÃ¡ removido.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(_, false),
                          child: const Text('Cancelar')),
                      TextButton(
                          onPressed: () => Navigator.pop(_, true),
                          child: const Text('Excluir',
                              style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirm == true && e.id != null && mounted) {
                  try {
                    await _removeAutoLancamentoBySourceId(e.id!);
                    await _syncDeleteScaleEntry(e, dialogContext: context);
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('PlantÃ£o excluÃ­do.')));
                  } catch (err) {
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                              'Erro ao excluir: ${err.toString().split('\n').first}')));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// DiÃ¡logo de confirmaÃ§Ã£o e gravaÃ§Ã£o de "realizado" (paid).
  Future<void> _confirmarConclusao(
      BuildContext sheetContext, ScaleEntry e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar conclusÃ£o'),
        content: Text(
          'Confirmar que o serviÃ§o "${e.label ?? 'PlantÃ£o'}" do dia ${DateFormat('dd/MM').format(e.date)} foi realizado?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_, false),
              child: const Text('Cancelar')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(_, true),
            icon: const Icon(Icons.check_circle_rounded, size: 20),
            label: const Text('Sim, concluÃ­do'),
          ),
        ],
      ),
    );
    if (confirm != true || e.id == null) return;
    Navigator.pop(sheetContext);
    try {
      await _scales.doc(e.id).update({'paid': true});
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('ServiÃ§o confirmado como realizado.')));
      setState(() {});
    } catch (err) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro: ${err.toString().split('\n').first}')));
    }
  }

  void _showLimpezaDialog() {
    final ref = _focusedDay;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      barrierColor: Colors.black54,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ScaleBulkClearSheet(
        ref: ref,
        onClearWeek: () => _executarLimpeza(semana: ref),
        onClearMonth: () => _executarLimpeza(mes: ref),
        onClearPeriod: _showLimpezaPorPeriodoDialog,
        onClearRecentBatches: _showRemoverUltimosLancamentosDialog,
      ),
    );
  }

  Future<void> _showRemoverUltimosLancamentosDialog() async {
    final lotes = await _loadRecentMagicBatches();
    if (!mounted) return;

    if (lotes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Nenhum lanÃ§amento recente encontrado no botÃ£o mÃ¡gico nos Ãºltimos 3 dias.'),
      ));
      return;
    }

    final selecionados = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          return AlertDialog(
            title: const Text('Remover Ãºltimos lanÃ§amentos'),
            content: SizedBox(
              width: 560,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.62,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Selecione os lanÃ§amentos criados no botÃ£o mÃ¡gico (somente Ãºltimos 3 dias).',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...lotes.map((lote) {
                        final checked = selecionados.contains(lote.batchId);
                        final principal = lote.previewNome.isNotEmpty
                            ? lote.previewNome
                            : 'LanÃ§amentos automÃ¡ticos';
                        final subtitulo =
                            '${DateFormat('dd/MM/yyyy HH:mm').format(lote.criadoEm)} Â· ${lote.quantidade} ${lote.quantidade == 1 ? 'lanÃ§amento' : 'lanÃ§amentos'}';
                        final diaFaixa = lote.diaInicio.year ==
                                    lote.diaFim.year &&
                                lote.diaInicio.month == lote.diaFim.month &&
                                lote.diaInicio.day == lote.diaFim.day
                            ? DateFormat('dd/MM/yyyy').format(lote.diaInicio)
                            : '${DateFormat('dd/MM').format(lote.diaInicio)} a ${DateFormat('dd/MM').format(lote.diaFim)}';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: checked
                                ? const Color(0xFFEEF2FF)
                                : const Color(0xFFF8FAFF),
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                setStateDialog(() {
                                  if (checked) {
                                    selecionados.remove(lote.batchId);
                                  } else {
                                    selecionados.add(lote.batchId);
                                  }
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Checkbox(
                                      value: checked,
                                      onChanged: (_) {
                                        setStateDialog(() {
                                          if (checked) {
                                            selecionados.remove(lote.batchId);
                                          } else {
                                            selecionados.add(lote.batchId);
                                          }
                                        });
                                      },
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            principal,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF1A237E),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            subtitulo,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            'PerÃ­odo dos itens: $diaFaixa',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE0E7FF),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        '${lote.quantidade}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF1E3A8A),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: selecionados.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.delete_sweep_rounded),
                label: Text('Remover selecionados (${selecionados.length})'),
              ),
            ],
          );
        },
      ),
    );

    if (ok == true && selecionados.isNotEmpty) {
      await _removerLotesMagicosByIds(selecionados);
    }
  }

  Future<List<_MagicBatchPreview>> _loadRecentMagicBatches() async {
    final now = DateTime.now();
    final inicio = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 2));
    final snap = await _scales
        .where('createdByMagic', isEqualTo: true)
        .where('magicGeneratedAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
        .orderBy('magicGeneratedAt', descending: true)
        .limit(800)
        .get();

    final byBatch = <String, _MagicBatchAccumulator>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final batchId = (data['magicBatchId'] ?? '').toString().trim();
      if (batchId.isEmpty) continue;
      final createdTs = data['magicGeneratedAt'];
      if (createdTs is! Timestamp) continue;
      final createdAt = createdTs.toDate();
      final label = (data['label'] ?? '').toString().trim();
      DateTime itemDate = createdAt;
      final dt = data['date'];
      if (dt is Timestamp) {
        final d = dt.toDate();
        itemDate = DateTime(d.year, d.month, d.day);
      }

      final acc = byBatch.putIfAbsent(
        batchId,
        () => _MagicBatchAccumulator(
          batchId: batchId,
          criadoEm: createdAt,
          previewNome: label,
          quantidade: 0,
          diaInicio: itemDate,
          diaFim: itemDate,
        ),
      );
      if (createdAt.isAfter(acc.criadoEm)) acc.criadoEm = createdAt;
      if (acc.previewNome.isEmpty && label.isNotEmpty) acc.previewNome = label;
      acc.quantidade += 1;
      if (itemDate.isBefore(acc.diaInicio)) acc.diaInicio = itemDate;
      if (itemDate.isAfter(acc.diaFim)) acc.diaFim = itemDate;
    }

    final items = byBatch.values
        .map(
          (a) => _MagicBatchPreview(
            batchId: a.batchId,
            criadoEm: a.criadoEm,
            previewNome: a.previewNome,
            quantidade: a.quantidade,
            diaInicio: a.diaInicio,
            diaFim: a.diaFim,
          ),
        )
        .toList()
      ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
    return items;
  }

  Future<void> _removerLotesMagicosByIds(Set<String> batchIds) async {
    try {
      final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final batchId in batchIds) {
        final snap = await _scales
            .where('magicBatchId', isEqualTo: batchId)
            .where('createdByMagic', isEqualTo: true)
            .get();
        docs.addAll(snap.docs);
      }
      if (docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Nenhum lanÃ§amento encontrado para remover.')));
        }
        return;
      }

      final ids = docs.map((d) => d.id).toList();
      final plantaoIds =
          ids.where((id) => !id.startsWith('agenda_')).toList();
      if (plantaoIds.isNotEmpty) {
        await _removeAutoLancamentosBySourceIds(plantaoIds);
      }
      await ExpressCompromissoAgendaSync.deleteByMagicBatchIds(
        userDocId: _userDocId,
        batchIds: batchIds,
      );
      bool ficouPendente = false;
      for (final batchId in batchIds) {
        final check = await _scales
            .where('magicBatchId', isEqualTo: batchId)
            .where('createdByMagic', isEqualTo: true)
            .limit(1)
            .get(const GetOptions(source: Source.server));
        if (check.docs.isNotEmpty) {
          ficouPendente = true;
          break;
        }
      }
      if (mounted) {
        if (ficouPendente) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Alguns lanÃ§amentos ainda nÃ£o foram removidos no servidor. Tente novamente.')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  '${docs.length} ${docs.length == 1 ? 'lanÃ§amento removido' : 'lanÃ§amentos removidos'} com sucesso no banco e no calendÃ¡rio.')));
        }
        _refreshCalendarView();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Erro ao remover lanÃ§amentos: ${e.toString().split('\n').first}')));
      }
    }
  }

  /// Abre o dialog para escolher data inicial e final; antes de limpar pede confirmaÃ§Ã£o.
  void _showLimpezaPorPeriodoDialog() {
    DateTime dataInicial = DateTime(_focusedDay.year, _focusedDay.month, 1);
    DateTime dataFinal = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('Limpar por perÃ­odo'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Data inicial',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today_rounded, size: 20),
                    label: Text(DateFormat('dd/MM/yyyy').format(dataInicial)),
                    onPressed: () async {
                      final picked = await pickSingleDateWithHolidayCalendar(
                        context: ctx,
                        initialDate: dataInicial,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030, 12, 31),
                      );
                      if (picked != null)
                        setState(() => dataInicial =
                            DateTime(picked.year, picked.month, picked.day));
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Data final',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today_rounded, size: 20),
                    label: Text(DateFormat('dd/MM/yyyy').format(dataFinal)),
                    onPressed: () async {
                      final picked = await pickSingleDateWithHolidayCalendar(
                        context: ctx,
                        initialDate: dataFinal,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030, 12, 31),
                      );
                      if (picked != null)
                        setState(() => dataFinal =
                            DateTime(picked.year, picked.month, picked.day));
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () async {
                  final inicio = DateTime(
                      dataInicial.year, dataInicial.month, dataInicial.day);
                  final fim =
                      DateTime(dataFinal.year, dataFinal.month, dataFinal.day);
                  if (fim.isBefore(inicio)) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'Data final deve ser igual ou posterior Ã  data inicial.')));
                    return;
                  }
                  Navigator.pop(ctx);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Confirmar limpeza'),
                      content: Text(
                        'Deseja realmente limpar o perÃ­odo de ${DateFormat('dd/MM/yyyy').format(inicio)} a ${DateFormat('dd/MM/yyyy').format(fim)}? Esta aÃ§Ã£o nÃ£o pode ser desfeita.',
                      ),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('Cancelar')),
                        FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: Colors.red),
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Sim, limpar perÃ­odo'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true)
                    await _executarLimpeza(
                        periodoInicio: inicio, periodoFim: fim);
                },
                child: const Text('Limpar perÃ­odo'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _limparOpcao(BuildContext ctx, String titulo, String subtitulo,
      IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () {
            Navigator.pop(ctx);
            onTap();
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: Colors.red.shade700, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo,
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: Colors.red.shade800)),
                      Text(subtitulo,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade700)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.red.shade700),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _executarLimpeza(
      {DateTime? dia,
      DateTime? semana,
      DateTime? mes,
      DateTime? ano,
      DateTime? periodoInicio,
      DateTime? periodoFim}) async {
    DateTime start;
    DateTime end;
    String msg;
    if (dia != null) {
      start = DateTime(dia.year, dia.month, dia.day);
      end = DateTime(dia.year, dia.month, dia.day, 23, 59, 59);
      msg = 'Dia ${DateFormat('dd/MM').format(dia)} removido.';
    } else if (semana != null) {
      // Segunda-feira (weekday=1) como inÃ­cio da semana; evita datas negativas
      start = DateTime(semana.year, semana.month, semana.day)
          .subtract(Duration(days: semana.weekday - 1));
      end = start.add(const Duration(days: 6));
      end = DateTime(end.year, end.month, end.day, 23, 59, 59);
      msg = 'Semana removida.';
    } else if (mes != null) {
      start = DateTime(mes.year, mes.month, 1);
      end = DateTime(mes.year, mes.month + 1, 0, 23, 59, 59);
      msg = 'MÃªs removido.';
    } else if (ano != null) {
      start = DateTime(ano.year, 1, 1);
      end = DateTime(ano.year, 12, 31, 23, 59, 59);
      msg = 'Ano removido.';
    } else if (periodoInicio != null && periodoFim != null) {
      start =
          DateTime(periodoInicio.year, periodoInicio.month, periodoInicio.day);
      end = DateTime(
          periodoFim.year, periodoFim.month, periodoFim.day, 23, 59, 59);
      msg = 'PerÃ­odo removido.';
    } else {
      return;
    }
    try {
      final snap = await _scales
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();
      final docs = snap.docs;
      if (docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Nenhum lanÃ§amento encontrado para remover.')));
        }
        return;
      }
      final ids = docs.map((d) => d.id).toList();
      await _removeAutoLancamentosBySourceIds(ids);
      // RemoÃ§Ã£o em lote (atÃ© 500 por batch) â€” mais rÃ¡pido que um delete por vez
      const int batchLimit = 500;
      for (int i = 0; i < docs.length; i += batchLimit) {
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in docs.skip(i).take(batchLimit)) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
      final check = await _scales
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .limit(1)
          .get(const GetOptions(source: Source.server));
      if (mounted) {
        if (check.docs.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Ainda existem lanÃ§amentos no perÃ­odo no banco. Tente remover novamente.')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text('$msg RemoÃ§Ã£o concluÃ­da no banco e no calendÃ¡rio.')));
        }
        _refreshCalendarView();
      }
    } catch (err) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Erro ao limpar: ${err.toString().split('\n').first}')));
    }
  }

  void _refreshCalendarView() {
    if (!mounted) return;
    setState(() {
      final focused = _focusedDay;
      _focusedDay = DateTime(focused.year, focused.month, focused.day);
      if (_selectedDay != null) {
        final s = _selectedDay!;
        _selectedDay = DateTime(s.year, s.month, s.day);
      }
    });
  }

  Future<void> _irParaDataEspecifica() async {
    final picked = await pickSingleDateWithHolidayCalendar(
      context: context,
      initialDate: _selectedDay ?? _focusedDay,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030, 12, 31),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDay = picked;
        _focusedDay = picked;
      });
      _ensureScalesStreamBound();
    }
  }

  Future<void> _gerarEscalaAutomatica(
    BuildContext context, {
    DateTime? initialDay,
  }) async {
    if (!mounted) return;
    // iPhone/Safari: precisa de delay para o gesture/context estabilizar; evita modal nÃ£o abrir.
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    _showGeracaoAutomaticaDialog(context, initialDay: initialDay);
  }

  /// Regimes de escala: ciclo em dias e quais dias do ciclo sÃ£o trabalho (0 = 1Âº dia do ciclo a partir da data inicial).
  /// PadrÃ£o 24xN: 1 dia de plantÃ£o (24h) + folga em horas convertida em dias corridos (NÃ·24). Ex.: 24x96 â†’ 1+4=5 dias de ciclo.
  /// [Expediente] usa os dias da semana escolhidos no diÃ¡logo (padrÃ£o segâ€“sex).
  /// [RepeteCadaNdias] plantÃ£o exatamente a cada [repetirACadaDias] dias corridos a partir do dia inicial.
  static ({int cycleDays, List<int> workDaysInCycle}) _regimePara(
    String regime, {
    int customTrabalho = 24,
    int customFolga = 72,
    int repetirACadaDias = 7,
  }) {
    switch (regime) {
      /// 16 h de plantÃ£o (horÃ¡rios do prÃ©-cadastro escolhido) + 56 h de folga â‰ˆ 2 dias corridos; ciclo 3 dias (1 trabalho + 2 folga).
      case '16x56':
        return (cycleDays: 3, workDaysInCycle: [0]);
      case '12x36':
        return (cycleDays: 2, workDaysInCycle: [0]);
      case '24x48':
        return (cycleDays: 3, workDaysInCycle: [0]);
      case '24x72':
        return (cycleDays: 4, workDaysInCycle: [0]);
      case '24x96':
        return (cycleDays: 5, workDaysInCycle: [0]); // 1 + 96/24
      case '24x144':
        return (cycleDays: 7, workDaysInCycle: [0]); // 1 + 144/24
      case '24x192':
        return (cycleDays: 9, workDaysInCycle: [0]); // 1 + 192/24
      case '12x24x72':
        return (cycleDays: 5, workDaysInCycle: [0, 2]);
      case 'Expediente':
        return (
          cycleDays: 7,
          workDaysInCycle: [0, 1, 2, 3, 4]
        ); // ignorado: ver expedienteDiasSemana no loop de geraÃ§Ã£o
      case 'RepeteCadaNdias':
        {
          final n = repetirACadaDias.clamp(2, 90);
          return (cycleDays: n, workDaysInCycle: [0]);
        }
      case 'Personalizado':
        {
          // Horas totais do ciclo (trabalho + folga) â†’ dias corridos do ciclo (ex.: 12+36=48hâ†’2 dias;
          // 12+48=60hâ†’3 dias: 1 plantÃ£o + 2 folgas). Evita somar ceil(trab)+ceil(folga) e inflar o ciclo.
          final th = customTrabalho.clamp(1, 24 * 31);
          final fh = customFolga.clamp(0, 24 * 365);
          final cycleHours = th + fh;
          final cycleDays = math.max(1, (cycleHours / 24).ceil());
          final workSpanDays =
              math.max(1, math.min(cycleDays, (th / 24).ceil()));
          return (
            cycleDays: cycleDays,
            workDaysInCycle: List.generate(workSpanDays, (i) => i),
          );
        }
      default:
        return (cycleDays: 4, workDaysInCycle: [0]);
    }
  }

  /// Resumo curto dos dias (1=Seg â€¦ 7=Dom) para o botÃ£o de expediente.
  String _resumoDiasExpediente(Set<int> dias) {
    const names = {
      1: 'Seg',
      2: 'Ter',
      3: 'Qua',
      4: 'Qui',
      5: 'Sex',
      6: 'SÃ¡b',
      7: 'Dom'
    };
    final sorted = dias.toList()..sort();
    if (sorted.isEmpty) return 'Escolher dias';
    return sorted.map((d) => names[d] ?? '?').join(', ');
  }

  Future<Set<int>?> _showExpedienteDiasSemanaDialog(
      BuildContext context, Set<int> current) {
    return showDialog<Set<int>>(
      context: context,
      builder: (c) => _ExpedienteDiasSemanaDialog(initial: current),
    );
  }

  Future<void> _executarGeracaoAutomaticaV2(
    BuildContext context, {
    required DateTime start,
    required DateTime end,
    required String regime,
    int customTrabalho = 24,
    int customFolga = 72,
    int repetirACadaDias = 7,
    required String tipoGeracao,
    required String turno,
    required String nome,
    required String startStr,
    required String endStr,
    required String colorHex,
    ShiftLocation? location,
    List<int>? diasDaSemana,

    /// Regime Expediente: dias com plantÃ£o (DateTime.weekday 1â€“7). Se vazio, usa segâ€“sex.
    List<int>? expedienteDiasSemana,
  }) async {
    final startNorm = DateTime(start.year, start.month, start.day);
    final endNorm = DateTime(end.year, end.month, end.day);
    final totalDays = endNorm.difference(startNorm).inDays + 1;
    if (totalDays < 1) return;
    final useDiasDaSemana = regime == 'DiaSemana' &&
        (diasDaSemana != null && diasDaSemana.isNotEmpty);
    final Set<int> diasSet = useDiasDaSemana ? diasDaSemana.toSet() : {};
    final Set<int> expedienteSet = regime == 'Expediente'
        ? ((expedienteDiasSemana != null && expedienteDiasSemana.isNotEmpty)
            ? expedienteDiasSemana.toSet()
            : {1, 2, 3, 4, 5})
        : {};
    final Map<int, Set<String>> feriadosNacionaisPorAno = {};
    if (regime == 'Expediente') {
      for (int y = startNorm.year; y <= endNorm.year; y++) {
        feriadosNacionaisPorAno[y] = HolidayHelper.getFeriados(y)
            .where((f) => !f.isOptional)
            .map((f) => '${f.date.year}-${f.date.month}-${f.date.day}')
            .toSet();
      }
    }
    final r = useDiasDaSemana
        ? (cycleDays: 1, workDaysInCycle: [0])
        : _regimePara(
            regime,
            customTrabalho: customTrabalho,
            customFolga: customFolga,
            repetirACadaDias: repetirACadaDias,
          );
    final magicBatchId =
        'magic_${DateTime.now().millisecondsSinceEpoch}_${_focusedDay.year}${_focusedDay.month.toString().padLeft(2, '0')}';
    final entriesWithRefs = <({
      DocumentReference<Map<String, dynamic>> ref,
      Map<String, dynamic> data
    })>[];
    final compromissosParaAgenda = <GeracaoAutomaticaCompromissoItem>[];
    final pendingViradaMes = <({
      String sourceId,
      DateTime sourceDate,
      DateTime startDt,
      DateTime endDt,
      String nome,
      String? abbreviation,
      String colorHex,
      String employerType,
    })>[];
    for (int dayIndex = 0; dayIndex < totalDays; dayIndex++) {
      final d = startNorm.add(Duration(days: dayIndex));
      if (d.isAfter(endNorm)) break;
      if (useDiasDaSemana) {
        if (!diasSet.contains(d.weekday)) continue;
      } else if (regime == 'Expediente') {
        if (!expedienteSet.contains(d.weekday)) continue;
        // Expediente: pula feriado nacional em dia Ãºtil (seg-sex).
        final isDiaUtil =
            d.weekday >= DateTime.monday && d.weekday <= DateTime.friday;
        if (isDiaUtil) {
          final key = '${d.year}-${d.month}-${d.day}';
          final feriadosAno =
              feriadosNacionaisPorAno[d.year] ?? const <String>{};
          if (feriadosAno.contains(key)) continue;
        }
      } else {
        if (r.cycleDays < 1) continue;
        final dayInCycle = dayIndex % r.cycleDays;
        if (!r.workDaysInCycle.contains(dayInCycle)) continue;
      }
      final isCompromisso = tipoGeracao == 'Compromisso';
      final sp = startStr.split(':');
      final ep = endStr.split(':');
      final sh = int.tryParse(sp.first.trim()) ?? 8;
      final sm = sp.length > 1 ? (int.tryParse(sp[1].trim()) ?? 0) : 0;
      final eh = int.tryParse(ep.first.trim()) ?? 18;
      final em = ep.length > 1 ? (int.tryParse(ep[1].trim()) ?? 0) : 0;
      final startDt = DateTime(d.year, d.month, d.day, sh, sm);
      var endDt = DateTime(d.year, d.month, d.day, eh, em);
      if (eh < sh || (eh == sh && em <= sm)) {
        endDt = DateTime(d.year, d.month, d.day + 1, eh, em);
      }
      double totalValue = 0;
      double hoursDay = 0, hoursNight = 0;
      double dayRate = 0, nightRate = 0;
      // Calcular valor SOMENTE se prÃ©-cadastro tiver financeiro ativado (Estado, MunicÃ­pio ou Particular).
      // Se financeiro nÃ£o estÃ¡ ativado no prÃ©-cadastro, tratar como compromisso (sem valor).
      final financeiroAtivo = location != null && location!.financialEnabled;
      final considerarValor = !isCompromisso && financeiroAtivo;
      final isParticularValorFixo = considerarValor &&
          location != null &&
          location!.employerType == EmployerType.private &&
          (location!.paymentType == PaymentType.fixed ||
              location!.baseValue > 0);
      if (considerarValor) {
        if (isParticularValorFixo &&
            location != null &&
            location!.baseValue > 0) {
          totalValue = location!.baseValue;
        } else {
          final res = await ScaleRatesService().computeShiftForUid(
            uid: _userDocId,
            start: startDt,
            end: endDt,
            entryDate: d,
          );
          totalValue = (res['total'] ?? 0).toDouble();
          hoursDay = (res['hoursDay'] ?? 0).toDouble();
          hoursNight = (res['hoursNight'] ?? 0).toDouble();
          final rates =
              await ScaleRatesService().getRatesForServiceDay(_userDocId, d);
          dayRate =
              rates.diurnoForWeekday(ScaleRates.weekdayToIndex(d.weekday));
          nightRate =
              rates.noturnoForWeekday(ScaleRates.weekdayToIndex(d.weekday));
        }
      }
      // Armazenar como compromisso quando nÃ£o hÃ¡ valor (compromisso explÃ­cito ou prÃ©-cadastro sem financeiro)
      final isCompromissoEntry =
          isCompromisso || (location != null && !location!.financialEnabled);
      final hoje = DateTime(
          DateTime.now().year, DateTime.now().month, DateTime.now().day);
      final isRetroativo = d.isBefore(hoje);
      final abbrev =
          location?.abbreviation ?? ShiftLocation.abbreviationFromName(nome);
      final colorNorm = colorHex.startsWith('#') ? colorHex : '#$colorHex';
      if (isCompromissoEntry) {
        compromissosParaAgenda.add(
          GeracaoAutomaticaCompromissoItem(
            date: d,
            startHHmm: startStr,
            endHHmm: endStr,
            title: nome,
            colorHex: colorNorm,
          ),
        );
        continue;
      }
      final entry = ScaleEntry(
        date: d,
        start: startStr,
        end: endStr,
        dayRate: dayRate,
        nightRate: nightRate,
        hoursDay: hoursDay,
        hoursNight: hoursNight,
        totalValue: totalValue,
        label: nome,
        abbreviation: abbrev.isNotEmpty ? abbrev : null,
        colorHex: colorNorm,
        paid: isRetroativo,
        isCompromisso: false,
        employerType: location?.employerType.name,
      );
      final ref = _scales.doc();
      final map = entry.toMap();
      map['createdByMagic'] = true;
      map['magicBatchId'] = magicBatchId;
      map['magicGeneratedAt'] = FieldValue.serverTimestamp();
      entriesWithRefs.add((ref: ref, data: map));
      if (considerarValor &&
          !isParticularValorFixo &&
          !isCompromissoEntry &&
          ScaleRates.isLastDayOfMonth(d) &&
          _isCrossingToNextDay(startDt, endDt)) {
        pendingViradaMes.add((
          sourceId: ref.id,
          sourceDate: d,
          startDt: startDt,
          endDt: endDt,
          nome: nome,
          abbreviation: abbrev.isNotEmpty ? abbrev : null,
          colorHex: colorHex.startsWith('#') ? colorHex : '#$colorHex',
          employerType: location?.employerType.name ?? 'state',
        ));
      }
    }
    // GravaÃ§Ã£o em lote (atÃ© 500 por batch) â€” evita lentidÃ£o de um add por vez
    const int batchLimit = 500;
    try {
      for (int i = 0; i < entriesWithRefs.length; i += batchLimit) {
        final batch = FirebaseFirestore.instance.batch();
        final slice = entriesWithRefs.skip(i).take(batchLimit).toList();
        for (final item in slice) {
          batch.set(item.ref, item.data);
        }
        await batch.commit();
      }
      for (final p in pendingViradaMes) {
        await _syncAutoLancamentoViradaMes(
          sourceId: p.sourceId,
          sourceDate: p.sourceDate,
          startDt: p.startDt,
          endDt: p.endDt,
          financeiroAtivo: true,
          isCompromisso: false,
          nome: p.nome,
          abbreviation: p.abbreviation,
          colorHex: p.colorHex,
          employerType: p.employerType,
        );
      }
      var compromissosAgenda = 0;
      if (compromissosParaAgenda.isNotEmpty) {
        compromissosAgenda =
            await ExpressCompromissoAgendaSync.upsertManyFromGeracaoAutomatica(
          userDocId: _userDocId,
          magicBatchId: magicBatchId,
          items: compromissosParaAgenda,
        );
      }
      if (mounted) {
        final plantoes = entriesWithRefs.length;
        String msg;
        if (plantoes > 0 && compromissosAgenda > 0) {
          msg =
              '$plantoes ${plantoes == 1 ? 'plantÃ£o' : 'plantÃµes'} e $compromissosAgenda '
              '${compromissosAgenda == 1 ? 'compromisso' : 'compromissos'} gerados '
              '(Escalas + Agenda + Painel).';
        } else if (compromissosAgenda > 0) {
          msg =
              '$compromissosAgenda ${compromissosAgenda == 1 ? 'compromisso' : 'compromissos'} gerados '
              '(calendÃ¡rio Escalas, Agenda e Painel em aberto).';
        } else {
          msg =
              '$plantoes ${plantoes == 1 ? 'plantÃ£o' : 'plantÃµes'} gerados.';
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        setState(() {});
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro ao gerar: ${e.toString().split('\n').first}')));
    }
  }

  /// DiÃ¡logo: geraÃ§Ã£o automÃ¡tica com regime, perÃ­odo e atalho para plantÃ£o.
  void _showGeracaoAutomaticaDialog(
    BuildContext context, {
    DateTime? initialDay,
  }) async {
    final ref = initialDay ?? _focusedDay;
    int ano = ref.year;
    bool habilitarFinanceiro =
        false; // NÃ£o = compromisso; Sim = plantÃ£o/frente paga
    String tipoGeracao = 'Compromisso';
    String turno = 'Diurno';
    String regime = '24x72';
    int customTrabalho = 24, customFolga = 72;
    String periodo = 'Intervalo'; // Apenas por perÃ­odo (data inicial e final)
    // Dia inicial = dia tocado no calendÃ¡rio ou mÃªs focado; evita alinhar ciclo 24x96 ao dia 1 sem querer.
    DateTime? dataInicioPer = DateTime(ref.year, ref.month, ref.day);
    DateTime? dataFimPer = DateTime(ref.year, ref.month + 1, 0);

    /// Regime "Repete a cada N dias" (plantÃµes a cada N dias corridos a partir do dia inicial).
    int repetirACadaDiasState = 8;
    final repetirNdiasCtrl = TextEditingController(text: '8');
    ShiftLocation? locSelecionada;

    /// true = Compromisso (sem valor), nÃ£o exige prÃ©-cadastro; false = PlantÃ£o com valor (exige prÃ©-cadastro).
    bool gerarComoCompromisso = false;
    final nomeCtrl = TextEditingController(text: '');
    final compromissoStartCtrl = TextEditingController(text: '08:00');
    final compromissoEndCtrl = TextEditingController(text: '18:00');
    final customTrabCtrl = TextEditingController(text: '$customTrabalho');
    final customFolgaCtrl = TextEditingController(text: '$customFolga');
    String selectedColorHex = _hexCompromisso;
    String startStr = '08:00', endStr = '18:00';
    bool paletteExpandida = false;

    /// Para regime "DiaSemana": dias selecionados (1=Segunda .. 7=Domingo).
    Set<int> diasDaSemanaSelecionados = {};

    /// Expediente: dias com plantÃ£o (1=Segunda .. 7=Domingo). PadrÃ£o segâ€“sex.
    Set<int> expedienteDiasSemana = {1, 2, 3, 4, 5};
    final diaSemanaStartCtrl = TextEditingController(text: '08:00');
    final diaSemanaEndCtrl = TextEditingController(text: '18:00');

    if (!mounted) return;
    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        useRootNavigator: true,
        barrierColor: Colors.black54,
        enableDrag: true,
        isDismissible: false,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(0))),
        builder: (ctx) {
          final sheetSafeBottom = MediaQuery.paddingOf(ctx).bottom + 24;
          return FractionallySizedBox(
            heightFactor: 0.98,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFF8FAFF), Color(0xFFF2F6FF)],
                ),
              ),
              child: KeyboardViewInsetPad(
                left: 16,
                right: 16,
                top: 12,
                bottom: sheetSafeBottom,
                child: StatefulBuilder(
                  builder: (ctx, setModalState) {
                    final stackedTypeSelector =
                        MediaQuery.textScalerOf(ctx).scale(1.0) >= 1.18 ||
                            MediaQuery.sizeOf(ctx).width < 520;
                    return SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 52,
                              height: 5,
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  const Color(0xFF4F46E5)
                                      .withValues(alpha: 0.12),
                                  AppColors.accent.withValues(alpha: 0.14),
                                  const Color(0xFFFDE68A)
                                      .withValues(alpha: 0.2),
                                ],
                              ),
                              border: Border.all(
                                color: const Color(0xFF4F46E5)
                                    .withValues(alpha: 0.28),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF4F46E5)
                                      .withValues(alpha: 0.12),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    IconButton(
                                      icon:
                                          const Icon(Icons.arrow_back_rounded),
                                      onPressed: () => Navigator.pop(ctx),
                                      tooltip: 'Voltar',
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.grey.shade200,
                                        foregroundColor:
                                            const Color(0xFF1A237E),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Icon(Icons.auto_awesome_rounded,
                                        color: Colors.amber.shade700, size: 28),
                                    const SizedBox(width: 10),
                                    const Expanded(
                                      child: Text('GeraÃ§Ã£o automÃ¡tica',
                                          style: TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF1A237E))),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                    'Gere plantÃµes com valor (lista de plantÃµes recorrentes) ou compromissos sem valor financeiro. '
                                    'Compromissos em sÃ©rie tambÃ©m entram no Painel (em aberto) e no mÃ³dulo Agenda/AudiÃªncias.',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade700)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: const Color(0xFF4F46E5)
                                    .withValues(alpha: 0.12),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF1A237E)
                                      .withValues(alpha: 0.06),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.category_rounded,
                                        size: 18, color: Color(0xFF4338CA)),
                                    SizedBox(width: 8),
                                    Text('Tipo de geraÃ§Ã£o',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.2)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (stackedTypeSelector) ...[
                                  Column(
                                    children: [
                                      SizedBox(
                                        width: double.infinity,
                                        child: _magicGradientChoice(
                                          selected: !gerarComoCompromisso,
                                          label: 'PlantÃ£o (lista de plantÃµes recorrentes)',
                                          icon: Icons.bolt_rounded,
                                          onTap: () => setModalState(() =>
                                              gerarComoCompromisso = false),
                                          selectedGradient: const [
                                            Color(0xFF1D4ED8),
                                            Color(0xFF2563EB),
                                            Color(0xFF0EA5E9),
                                          ],
                                          idleAccent: const Color(0xFF2563EB),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        child: _magicGradientChoice(
                                          selected: gerarComoCompromisso,
                                          label: 'Compromisso particular',
                                          icon: Icons.event_note_rounded,
                                          onTap: () => setModalState(() {
                                            gerarComoCompromisso = true;
                                            tipoGeracao = 'Compromisso';
                                            selectedColorHex = _hexCompromisso;
                                          }),
                                          selectedGradient: const [
                                            Color(0xFF0F766E),
                                            Color(0xFF14B8A6),
                                            Color(0xFF2DD4BF),
                                          ],
                                          idleAccent: _corCompromisso,
                                        ),
                                      ),
                                    ],
                                  ),
                                ] else ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _magicGradientChoice(
                                          selected: !gerarComoCompromisso,
                                          label: 'PlantÃ£o (lista de plantÃµes recorrentes)',
                                          icon: Icons.bolt_rounded,
                                          onTap: () => setModalState(() =>
                                              gerarComoCompromisso = false),
                                          selectedGradient: const [
                                            Color(0xFF1D4ED8),
                                            Color(0xFF2563EB),
                                            Color(0xFF0EA5E9),
                                          ],
                                          idleAccent: const Color(0xFF2563EB),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _magicGradientChoice(
                                          selected: gerarComoCompromisso,
                                          label: 'Compromisso particular',
                                          icon: Icons.event_note_rounded,
                                          onTap: () => setModalState(() {
                                            gerarComoCompromisso = true;
                                            tipoGeracao = 'Compromisso';
                                            selectedColorHex = _hexCompromisso;
                                          }),
                                          selectedGradient: const [
                                            Color(0xFF0F766E),
                                            Color(0xFF14B8A6),
                                            Color(0xFF2DD4BF),
                                          ],
                                          idleAccent: _corCompromisso,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: const Color(0xFF0EA5E9)
                                    .withValues(alpha: 0.16),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF0F172A)
                                      .withValues(alpha: 0.05),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      gerarComoCompromisso
                                          ? Icons.event_note_rounded
                                          : Icons.medical_services_rounded,
                                      size: 18,
                                      color: const Color(0xFF0369A1),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      gerarComoCompromisso
                                          ? 'Compromisso'
                                          : 'PlantÃ£o da lista de plantÃµes recorrentes',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.2),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (gerarComoCompromisso) ...[
                                  const Text(
                                      'Compromisso particular: toque num Ã­cone para preencher rÃ¡pido â€” ou abra a lista completa.',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                  const SizedBox(height: 10),
                                  CommitmentQuickIconsRow(
                                    currentName: nomeCtrl.text,
                                    onPick: (p) {
                                      setModalState(() {
                                        final start = compromissoStartCtrl.text
                                                .trim()
                                                .isEmpty
                                            ? '08:00'
                                            : compromissoStartCtrl.text.trim();
                                        final end = compromissoEndCtrl.text
                                                .trim()
                                                .isEmpty
                                            ? '18:00'
                                            : compromissoEndCtrl.text.trim();
                                        nomeCtrl.text =
                                            ShiftLocation.fullNameWithSchedule(
                                          p.name.toUpperCase(),
                                          start,
                                          end,
                                        );
                                        selectedColorHex =
                                            hexFromCommitmentColor(p.color);
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: FastTextField(
                                          controller: compromissoStartCtrl,
                                          decoration: InputDecoration(
                                            labelText: 'InÃ­cio',
                                            hintText: '08:00',
                                            border: const OutlineInputBorder(),
                                            isDense: true,
                                            suffixIcon: IconButton(
                                              icon: const Icon(
                                                  Icons.access_time_rounded,
                                                  size: 22),
                                              tooltip: 'Abrir relÃ³gio (24h)',
                                              onPressed: () async {
                                                final parts =
                                                    compromissoStartCtrl.text
                                                        .trim()
                                                        .split(':');
                                                final h = int.tryParse(
                                                        parts.isNotEmpty
                                                            ? parts[0]
                                                            : '') ??
                                                    8;
                                                final m = parts.length > 1
                                                    ? (int.tryParse(parts[1]) ??
                                                        0)
                                                    : 0;
                                                final t = await showTimePicker(
                                                  context: ctx,
                                                  initialTime: TimeOfDay(
                                                      hour: h.clamp(0, 23),
                                                      minute: m.clamp(0, 59)),
                                                  builder: (context, child) =>
                                                      MediaQuery(
                                                    data: MediaQuery.of(context)
                                                        .copyWith(
                                                            alwaysUse24HourFormat:
                                                                true),
                                                    child: child!,
                                                  ),
                                                );
                                                if (t != null) {
                                                  compromissoStartCtrl.text =
                                                      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                                                  startStr =
                                                      compromissoStartCtrl.text;
                                                  endStr = compromissoEndCtrl
                                                          .text
                                                          .trim()
                                                          .isEmpty
                                                      ? '18:00'
                                                      : compromissoEndCtrl.text
                                                          .trim();
                                                  final base = ShiftLocation
                                                      .baseNameFromFull(
                                                          nomeCtrl.text);
                                                  nomeCtrl.text = ShiftLocation
                                                      .fullNameWithSchedule(
                                                          base.isEmpty
                                                              ? 'COMPROMISSO'
                                                              : base,
                                                          startStr,
                                                          endStr);
                                                  setModalState(() {});
                                                }
                                              },
                                            ),
                                          ),
                                          keyboardType: TextInputType.datetime,
                                          onChanged: (_) {
                                            startStr = compromissoStartCtrl.text
                                                    .trim()
                                                    .isEmpty
                                                ? '08:00'
                                                : compromissoStartCtrl.text
                                                    .trim();
                                            endStr = compromissoEndCtrl.text
                                                    .trim()
                                                    .isEmpty
                                                ? '18:00'
                                                : compromissoEndCtrl.text
                                                    .trim();
                                            final base =
                                                ShiftLocation.baseNameFromFull(
                                                    nomeCtrl.text);
                                            nomeCtrl.text = ShiftLocation
                                                .fullNameWithSchedule(
                                                    base.isEmpty
                                                        ? 'COMPROMISSO'
                                                        : base,
                                                    startStr,
                                                    endStr);
                                            setModalState(() {});
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: FastTextField(
                                          controller: compromissoEndCtrl,
                                          decoration: InputDecoration(
                                            labelText: 'Fim',
                                            hintText: '18:00',
                                            border: const OutlineInputBorder(),
                                            isDense: true,
                                            suffixIcon: IconButton(
                                              icon: const Icon(
                                                  Icons.access_time_rounded,
                                                  size: 22),
                                              tooltip: 'Abrir relÃ³gio (24h)',
                                              onPressed: () async {
                                                final parts = compromissoEndCtrl
                                                    .text
                                                    .trim()
                                                    .split(':');
                                                final h = int.tryParse(
                                                        parts.isNotEmpty
                                                            ? parts[0]
                                                            : '') ??
                                                    18;
                                                final m = parts.length > 1
                                                    ? (int.tryParse(parts[1]) ??
                                                        0)
                                                    : 0;
                                                final t = await showTimePicker(
                                                  context: ctx,
                                                  initialTime: TimeOfDay(
                                                      hour: h.clamp(0, 23),
                                                      minute: m.clamp(0, 59)),
                                                  builder: (context, child) =>
                                                      MediaQuery(
                                                    data: MediaQuery.of(context)
                                                        .copyWith(
                                                            alwaysUse24HourFormat:
                                                                true),
                                                    child: child!,
                                                  ),
                                                );
                                                if (t != null) {
                                                  compromissoEndCtrl.text =
                                                      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                                                  startStr =
                                                      compromissoStartCtrl.text
                                                              .trim()
                                                              .isEmpty
                                                          ? '08:00'
                                                          : compromissoStartCtrl
                                                              .text
                                                              .trim();
                                                  endStr =
                                                      compromissoEndCtrl.text;
                                                  final base = ShiftLocation
                                                      .baseNameFromFull(
                                                          nomeCtrl.text);
                                                  nomeCtrl.text = ShiftLocation
                                                      .fullNameWithSchedule(
                                                          base.isEmpty
                                                              ? 'COMPROMISSO'
                                                              : base,
                                                          startStr,
                                                          endStr);
                                                  setModalState(() {});
                                                }
                                              },
                                            ),
                                          ),
                                          keyboardType: TextInputType.datetime,
                                          onChanged: (_) {
                                            startStr = compromissoStartCtrl.text
                                                    .trim()
                                                    .isEmpty
                                                ? '08:00'
                                                : compromissoStartCtrl.text
                                                    .trim();
                                            endStr = compromissoEndCtrl.text
                                                    .trim()
                                                    .isEmpty
                                                ? '18:00'
                                                : compromissoEndCtrl.text
                                                    .trim();
                                            final base =
                                                ShiftLocation.baseNameFromFull(
                                                    nomeCtrl.text);
                                            nomeCtrl.text = ShiftLocation
                                                .fullNameWithSchedule(
                                                    base.isEmpty
                                                        ? 'COMPROMISSO'
                                                        : base,
                                                    startStr,
                                                    endStr);
                                            setModalState(() {});
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  FastTextField(
                                    controller: nomeCtrl,
                                    decoration: InputDecoration(
                                      labelText:
                                          'DescriÃ§Ã£o â€” completa com horÃ¡rio',
                                      hintText: 'EX: REUNIÃƒO, CULTO, FOLGA',
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                      suffixIcon: IconButton(
                                        tooltip: 'Escolher da lista',
                                        icon: const Icon(
                                          Icons.arrow_drop_down_circle_rounded,
                                          color: AppColors.primary,
                                        ),
                                        onPressed: () async {
                                          final base =
                                              ShiftLocation.baseNameFromFull(
                                                  nomeCtrl.text);
                                          final selected =
                                              await showCommitmentDescriptionPicker(
                                            context: ctx,
                                            uid: _userDocId,
                                            initialQuery: base,
                                          );
                                          if (selected == null) return;
                                          final start = compromissoStartCtrl
                                                  .text
                                                  .trim()
                                                  .isEmpty
                                              ? '08:00'
                                              : compromissoStartCtrl.text
                                                  .trim();
                                          final end = compromissoEndCtrl.text
                                                  .trim()
                                                  .isEmpty
                                              ? '18:00'
                                              : compromissoEndCtrl.text.trim();
                                          final preset =
                                              kCommitmentPresetByName[selected
                                                  .toLowerCase()
                                                  .trim()];
                                          setModalState(() {
                                            nomeCtrl.text = ShiftLocation
                                                .fullNameWithSchedule(
                                              selected.toUpperCase(),
                                              start,
                                              end,
                                            );
                                            if (preset != null) {
                                              selectedColorHex =
                                                  hexFromCommitmentColor(
                                                      preset.color);
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                    textCapitalization:
                                        TextCapitalization.characters,
                                    inputFormatters: [UpperCaseTextFormatter()],
                                    onSubmitted: (_) {
                                      final base =
                                          ShiftLocation.baseNameFromFull(
                                              nomeCtrl.text);
                                      startStr = compromissoStartCtrl.text
                                              .trim()
                                              .isEmpty
                                          ? '08:00'
                                          : compromissoStartCtrl.text.trim();
                                      endStr =
                                          compromissoEndCtrl.text.trim().isEmpty
                                              ? '18:00'
                                              : compromissoEndCtrl.text.trim();
                                      nomeCtrl.text =
                                          ShiftLocation.fullNameWithSchedule(
                                              base.isEmpty
                                                  ? 'COMPROMISSO'
                                                  : base,
                                              startStr,
                                              endStr);
                                      setModalState(() {});
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  const Text('Cor no calendÃ¡rio',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12)),
                                  const SizedBox(height: 6),
                                  SizedBox(
                                    height: 44,
                                    child: ListView(
                                      scrollDirection: Axis.horizontal,
                                      children:
                                          kColorPaletteHex.take(72).map((hex) {
                                        final h =
                                            hex.startsWith('#') ? hex : '#$hex';
                                        final isSelected = selectedColorHex
                                                .toUpperCase()
                                                .replaceFirst('#', '') ==
                                            h
                                                .replaceFirst('#', '')
                                                .toUpperCase();
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(right: 8),
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () => setModalState(
                                                () => selectedColorHex = h),
                                            child: Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                color: Color(0xFF000000 +
                                                    int.parse(
                                                        h.replaceFirst('#', ''),
                                                        radix: 16)),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                    color: isSelected
                                                        ? Colors.blue
                                                        : Colors.grey.shade300,
                                                    width: isSelected ? 2 : 1),
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ] else ...[
                                  const Text('PlantÃ£o (obrigatÃ³rio para valor)',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 6),
                                  SizedBox(
                                    width: double.infinity,
                                    child: _magicFullWidthCta(
                                      onPressed: () async {
                                        final loc =
                                            await _abrirSelecaoPlantaoParaGeracao(
                                                context);
                                        if (loc != null && mounted) {
                                          setModalState(() {
                                            locSelecionada = loc;
                                            habilitarFinanceiro = true;
                                            tipoGeracao = 'PagoHora';
                                            startStr = loc.startTime;
                                            endStr = loc.endTime;
                                            diaSemanaStartCtrl.text =
                                                loc.startTime;
                                            diaSemanaEndCtrl.text = loc.endTime;
                                            final ep = loc.endTime.split(':');
                                            final eh =
                                                int.tryParse(ep.first.trim()) ??
                                                    18;
                                            turno = (eh <= 7 ||
                                                    (loc.startTime
                                                            .startsWith('22') ||
                                                        loc.startTime
                                                            .startsWith('23')))
                                                ? 'Noturno'
                                                : 'Diurno';
                                          });
                                          _loadLocations();
                                        }
                                      },
                                      icon: Icons.add_rounded,
                                      label: locSelecionada != null
                                          ? '${locSelecionada!.name} (lista de plantÃµes recorrentes)'
                                          : 'Selecionar na lista de plantÃµes recorrentes ou criar novo',
                                      gradient: locSelecionada != null
                                          ? const [
                                              Color(0xFF059669),
                                              Color(0xFF10B981),
                                              Color(0xFF34D399),
                                            ]
                                          : const [
                                              Color(0xFF4F46E5),
                                              Color(0xFF6366F1),
                                              Color(0xFF818CF8),
                                            ],
                                    ),
                                  ),
                                  if (locSelecionada == null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                          'Selecione um plantÃ£o acima para gerar com valor.',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.orange.shade700,
                                              fontWeight: FontWeight.w500)),
                                    ),
                                  if (locSelecionada != null) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color: Colors.blue.shade200),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.access_time_rounded,
                                              size: 20,
                                              color: Color(0xFF1A237E)),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              'HorÃ¡rio: ${locSelecionada!.startTime} Ã s ${locSelecionada!.endTime}  (da lista de plantÃµes recorrentes)',
                                              style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF1A237E)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: const Color(0xFF4F46E5)
                                    .withValues(alpha: 0.12),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF1A237E)
                                      .withValues(alpha: 0.06),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.sync_alt_rounded,
                                        size: 18, color: Color(0xFF4338CA)),
                                    SizedBox(width: 8),
                                    Text('Regime de escala',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.2)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      '24x72',
                                      '24x96',
                                      '12x36',
                                      '16x56',
                                      '24x192',
                                      '12x24x72',
                                      'Expediente',
                                    ].map((r) {
                                      final sel = regime == r;
                                      return _magicRegimePill(
                                        label: r,
                                        selected: sel,
                                        onTap: () async {
                                          if (r == 'Expediente') {
                                            final setDias =
                                                await _showExpedienteDiasSemanaDialog(
                                                    ctx, expedienteDiasSemana);
                                            if (!ctx.mounted) return;
                                            if (setDias == null) return;
                                            setModalState(() {
                                              regime = 'Expediente';
                                              expedienteDiasSemana = setDias;
                                            });
                                          } else {
                                            setModalState(() {
                                              regime = r;
                                            });
                                          }
                                        },
                                      );
                                    }).toList(),
                                  ),
                                ),
                                if (regime == 'Expediente') ...[
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: _magicSecondaryCta(
                                      onPressed: () async {
                                        final setDias =
                                            await _showExpedienteDiasSemanaDialog(
                                                ctx, expedienteDiasSemana);
                                        if (!ctx.mounted || setDias == null)
                                          return;
                                        setModalState(() =>
                                            expedienteDiasSemana = setDias);
                                      },
                                      icon: Icons.edit_calendar_rounded,
                                      label:
                                          'Dias: ${_resumoDiasExpediente(expedienteDiasSemana)}',
                                      accentGradient: const [
                                        Color(0xFF2563EB),
                                        Color(0xFF60A5FA),
                                      ],
                                      selected: true,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: _magicSecondaryCta(
                                    onPressed: () => setModalState(
                                        () => regime = 'Personalizado'),
                                    icon: Icons.tune_rounded,
                                    label: regime == 'Personalizado'
                                        ? 'Personalizado (${customTrabalho}h trab / ${customFolga}h folga)'
                                        : 'Personalizado (horas trab / folga)',
                                    accentGradient: const [
                                      Color(0xFF7C3AED),
                                      Color(0xFFA78BFA),
                                    ],
                                    selected: regime == 'Personalizado',
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => setModalState(() {
                                      regime = 'RepeteCadaNdias';
                                      repetirACadaDiasState = int.tryParse(
                                              repetirNdiasCtrl.text.trim()) ??
                                          repetirACadaDiasState;
                                    }),
                                    borderRadius: BorderRadius.circular(16),
                                    child: Ink(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            const Color(0xFF4F46E5)
                                                .withOpacity(0.92),
                                            const Color(0xFF7C3AED)
                                                .withOpacity(0.88),
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF4F46E5)
                                                .withOpacity(0.35),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 14),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: Colors.white
                                                    .withOpacity(0.2),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: const Icon(
                                                  Icons.repeat_rounded,
                                                  color: Colors.white,
                                                  size: 22),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(
                                                        regime ==
                                                                'RepeteCadaNdias'
                                                            ? 'Repete a cada $repetirACadaDiasState dias'
                                                            : 'Repete a cada â€¦ dias',
                                                        style: const TextStyle(
                                                            color: Colors.white,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            fontSize: 15),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 8,
                                                                vertical: 2),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors
                                                              .amber.shade400,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                        ),
                                                        child: const Text(
                                                            'PREMIUM',
                                                            style: TextStyle(
                                                                fontSize: 10,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w900,
                                                                color: Color(
                                                                    0xFF1E1B4B))),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'PlantÃ£o a cada N dias corridos a partir do dia inicial (ex.: 2, 3, 8â€¦).',
                                                    style: TextStyle(
                                                        color: Colors.white
                                                            .withOpacity(0.9),
                                                        fontSize: 12),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Icon(
                                                regime == 'RepeteCadaNdias'
                                                    ? Icons.check_circle_rounded
                                                    : Icons
                                                        .chevron_right_rounded,
                                                color: Colors.white,
                                                size: 26),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (regime == 'RepeteCadaNdias') ...[
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      2,
                                      3,
                                      4,
                                      5,
                                      6,
                                      7,
                                      8,
                                      10,
                                      14,
                                      15,
                                      21,
                                      30
                                    ].map((n) {
                                      final sel = repetirACadaDiasState == n;
                                      return FilterChip(
                                        label: Text('A cada $n'),
                                        selected: sel,
                                        onSelected: (_) {
                                          setModalState(() {
                                            repetirACadaDiasState = n;
                                            repetirNdiasCtrl.text = '$n';
                                          });
                                        },
                                        selectedColor: const Color(0xFF4F46E5)
                                            .withOpacity(0.2),
                                        checkmarkColor: const Color(0xFF4F46E5),
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 8),
                                  FastTextField(
                                    controller: repetirNdiasCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText:
                                          'Outro intervalo (2 a 90 dias)',
                                      hintText: 'Ex: 8',
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                      prefixIcon: const Icon(
                                          Icons.numbers_rounded,
                                          size: 20),
                                      filled: true,
                                      fillColor: const Color(0xFFF5F3FF),
                                    ),
                                    onChanged: (v) {
                                      final parsed = int.tryParse(v.trim());
                                      if (parsed != null &&
                                          parsed >= 2 &&
                                          parsed <= 90) {
                                        setModalState(() =>
                                            repetirACadaDiasState = parsed);
                                      }
                                    },
                                  ),
                                ],
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      setModalState(() => regime = 'DiaSemana'),
                                  icon: const Icon(
                                      Icons.calendar_view_week_rounded,
                                      size: 18),
                                  label: Text(regime == 'DiaSemana'
                                      ? 'Personalizar dia da semana (${diasDaSemanaSelecionados.length} dia(s))'
                                      : 'Personalizar dia da semana'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: regime == 'DiaSemana'
                                        ? AppColors.primary
                                        : null,
                                    minimumSize:
                                        const Size(double.infinity, 44),
                                  ),
                                ),
                                if (regime == 'Personalizado') ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                          child: FastTextField(
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                            labelText: 'Trabalho (h)',
                                            border: OutlineInputBorder(),
                                            isDense: true),
                                        controller: customTrabCtrl,
                                        onChanged: (v) => customTrabalho =
                                            int.tryParse(v) ?? 24,
                                      )),
                                      const SizedBox(width: 12),
                                      Expanded(
                                          child: FastTextField(
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                            labelText: 'Folga (h)',
                                            border: OutlineInputBorder(),
                                            isDense: true),
                                        controller: customFolgaCtrl,
                                        onChanged: (v) =>
                                            customFolga = int.tryParse(v) ?? 72,
                                      )),
                                    ],
                                  ),
                                ],
                                if (regime == 'DiaSemana') ...[
                                  const SizedBox(height: 12),
                                  const Text('Dias da semana',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13)),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [1, 2, 3, 4, 5, 6, 7].map((w) {
                                      const labels = {
                                        1: 'Segunda',
                                        2: 'TerÃ§a',
                                        3: 'Quarta',
                                        4: 'Quinta',
                                        5: 'Sexta',
                                        6: 'SÃ¡bado',
                                        7: 'Domingo'
                                      };
                                      final sel =
                                          diasDaSemanaSelecionados.contains(w);
                                      return FilterChip(
                                        label: Text(labels[w]!),
                                        selected: sel,
                                        onSelected: (_) {
                                          setModalState(() {
                                            if (sel)
                                              diasDaSemanaSelecionados
                                                  .remove(w);
                                            else
                                              diasDaSemanaSelecionados.add(w);
                                          });
                                        },
                                        selectedColor:
                                            AppColors.primary.withOpacity(0.2),
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 10),
                                  const Text('HorÃ¡rio',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13)),
                                  const SizedBox(height: 6),
                                  Text(
                                      'Clique no relÃ³gio ou digite no formato 24h (ex: 08:00, 22:30)',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600)),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: FastTextField(
                                          controller: diaSemanaStartCtrl,
                                          decoration: InputDecoration(
                                            labelText: 'Hora inÃ­cio',
                                            hintText: '08:00',
                                            border: const OutlineInputBorder(),
                                            isDense: true,
                                            suffixIcon: IconButton(
                                              icon: const Icon(
                                                  Icons.access_time_rounded,
                                                  size: 22),
                                              tooltip: 'Abrir relÃ³gio (24h)',
                                              onPressed: () async {
                                                final parts = diaSemanaStartCtrl
                                                    .text
                                                    .trim()
                                                    .split(':');
                                                final h = int.tryParse(
                                                        parts.isNotEmpty
                                                            ? parts[0]
                                                            : '') ??
                                                    8;
                                                final m = parts.length > 1
                                                    ? (int.tryParse(parts[1]) ??
                                                        0)
                                                    : 0;
                                                final t = await showTimePicker(
                                                  context: ctx,
                                                  initialTime: TimeOfDay(
                                                      hour: h.clamp(0, 23),
                                                      minute: m.clamp(0, 59)),
                                                  builder: (context, child) =>
                                                      MediaQuery(
                                                    data: MediaQuery.of(context)
                                                        .copyWith(
                                                            alwaysUse24HourFormat:
                                                                true),
                                                    child: child!,
                                                  ),
                                                );
                                                if (t != null) {
                                                  diaSemanaStartCtrl.text =
                                                      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                                                  setModalState(() {});
                                                }
                                              },
                                            ),
                                          ),
                                          keyboardType: TextInputType.datetime,
                                          onChanged: (_) =>
                                              setModalState(() {}),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: FastTextField(
                                          controller: diaSemanaEndCtrl,
                                          decoration: InputDecoration(
                                            labelText: 'Hora fim',
                                            hintText: '18:00',
                                            border: const OutlineInputBorder(),
                                            isDense: true,
                                            suffixIcon: IconButton(
                                              icon: const Icon(
                                                  Icons.access_time_rounded,
                                                  size: 22),
                                              tooltip: 'Abrir relÃ³gio (24h)',
                                              onPressed: () async {
                                                final parts = diaSemanaEndCtrl
                                                    .text
                                                    .trim()
                                                    .split(':');
                                                final h = int.tryParse(
                                                        parts.isNotEmpty
                                                            ? parts[0]
                                                            : '') ??
                                                    18;
                                                final m = parts.length > 1
                                                    ? (int.tryParse(parts[1]) ??
                                                        0)
                                                    : 0;
                                                final t = await showTimePicker(
                                                  context: ctx,
                                                  initialTime: TimeOfDay(
                                                      hour: h.clamp(0, 23),
                                                      minute: m.clamp(0, 59)),
                                                  builder: (context, child) =>
                                                      MediaQuery(
                                                    data: MediaQuery.of(context)
                                                        .copyWith(
                                                            alwaysUse24HourFormat:
                                                                true),
                                                    child: child!,
                                                  ),
                                                );
                                                if (t != null) {
                                                  diaSemanaEndCtrl.text =
                                                      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                                                  setModalState(() {});
                                                }
                                              },
                                            ),
                                          ),
                                          keyboardType: TextInputType.datetime,
                                          onChanged: (_) =>
                                              setModalState(() {}),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: const Color(0xFFF59E0B)
                                    .withValues(alpha: 0.22),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFF59E0B)
                                      .withValues(alpha: 0.1),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.date_range_rounded,
                                        size: 18, color: Color(0xFFD97706)),
                                    SizedBox(width: 8),
                                    Text('Dia inicial e perÃ­odo',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.2)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  regime == 'DiaSemana'
                                      ? 'SerÃ£o gerados plantÃµes apenas nos dias da semana marcados acima, entre a data inicial e a data final.'
                                      : regime == 'RepeteCadaNdias'
                                          ? 'PlantÃ£o no dia inicial e depois a cada N dias corridos (ex.: N=8 â†’ mesmo dia do mÃªs â€œsaltandoâ€ de 8 em 8 dias).'
                                          : regime == 'Expediente'
                                              ? 'Expediente: plantÃµes sÃ³ nos dias marcados no diÃ¡logo (padrÃ£o segâ€“sex). Use â€œDias: â€¦â€ para folgar um dia da semana.'
                                              : regime == 'Personalizado'
                                                  ? 'Personalizado: informe horas de trabalho e horas de folga no ciclo (ex.: 12 + 48 = 60 h â†’ ciclo de 3 dias: 1 plantÃ£o + 2 folgas). O ciclo em dias Ã© (trabalho+folga)Ã·24 arredondado para cima; quantos dias seguidos de plantÃ£o depende das horas de trabalho.'
                                                  : regime == '16x56'
                                                      ? '16x56: usa o inÃ­cio e o fim do horÃ¡rio do plantÃ£o que escolher na lista de plantÃµes recorrentes (ou os horÃ¡rios do compromisso, se gerar sem valor). Ciclo de 3 dias corridos: 1 dia de plantÃ£o + 2 dias de folga; depois repete. O dia inicial Ã© sempre o 1.Âº plantÃ£o.'
                                                      : 'O dia inicial Ã© sempre o 1Âº plantÃ£o. Regimes 24xN: 1 dia plantÃ£o + folga em horas Ã·24 (ex.: 24x96 = ciclo 5 dias: plantÃ£o, 4 folga). 24x144 = ciclo 7; 24x192 = ciclo 9. Ex. 24x72 a partir de 24/02: 24/02, 28/02, 04/03â€¦',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                    'PerÃ­odo mÃ¡ximo: 24 meses a partir do mÃªs atual.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.orange.shade700,
                                        fontWeight: FontWeight.w500)),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('Dia em que seu plantÃ£o comeÃ§a',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.grey.shade700)),
                                          const SizedBox(height: 4),
                                          OutlinedButton.icon(
                                            onPressed: () async {
                                              final d =
                                                  await pickSingleDateWithHolidayCalendar(
                                                      context: ctx,
                                                      initialDate:
                                                          dataInicioPer ??
                                                              DateTime.now(),
                                                      firstDate: DateTime(2020),
                                                      lastDate: DateTime(2030));
                                              if (d != null)
                                                setModalState(
                                                    () => dataInicioPer = d);
                                            },
                                            icon: const Icon(
                                                Icons
                                                    .play_circle_outline_rounded,
                                                size: 16),
                                            label: Text(
                                                DateFormat('dd/MM/yy').format(
                                                    dataInicioPer ??
                                                        DateTime.now()),
                                                style: const TextStyle(
                                                    fontSize: 12)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('AtÃ© quando gerar',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.grey.shade700)),
                                          const SizedBox(height: 4),
                                          OutlinedButton.icon(
                                            onPressed: () async {
                                              final agora = DateTime.now();
                                              // Trava: sempre 24 meses a partir do mÃªs atual (nÃ£o alÃ©m disso)
                                              final limiteAPartirDoMesAtual =
                                                  DateTime(agora.year + 2,
                                                      agora.month, agora.day);
                                              final ini =
                                                  dataInicioPer ?? agora;
                                              // TambÃ©m nÃ£o pode ser mais que 24 meses apÃ³s a data inicial
                                              final limiteAPartirDoInicio =
                                                  DateTime(ini.year + 2,
                                                      ini.month, ini.day);
                                              final lastDate =
                                                  limiteAPartirDoInicio.isBefore(
                                                          limiteAPartirDoMesAtual)
                                                      ? limiteAPartirDoInicio
                                                      : limiteAPartirDoMesAtual;
                                              final d =
                                                  await pickSingleDateWithHolidayCalendar(
                                                      context: ctx,
                                                      initialDate: dataFimPer ??
                                                          lastDate,
                                                      firstDate: ini,
                                                      lastDate: lastDate);
                                              if (d != null)
                                                setModalState(
                                                    () => dataFimPer = d);
                                            },
                                            icon: const Icon(
                                                Icons.calendar_today_rounded,
                                                size: 16),
                                            label: Text(
                                                DateFormat('dd/MM/yy').format(
                                                    dataFimPer ??
                                                        DateTime.now()),
                                                style: const TextStyle(
                                                    fontSize: 12)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 26),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              icon: const Icon(Icons.auto_awesome_rounded),
                              label: Text((gerarComoCompromisso ||
                                      locSelecionada != null)
                                  ? 'Gerar perÃ­odo'
                                  : 'Selecione um plantÃ£o acima'),
                              style: FilledButton.styleFrom(
                                backgroundColor: (gerarComoCompromisso ||
                                        locSelecionada != null)
                                    ? Colors.amber.shade700
                                    : Colors.grey,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: (gerarComoCompromisso ||
                                      locSelecionada != null)
                                  ? () async {
                                      if (gerarComoCompromisso) {
                                        startStr = compromissoStartCtrl.text
                                                .trim()
                                                .isEmpty
                                            ? '08:00'
                                            : compromissoStartCtrl.text.trim();
                                        endStr = compromissoEndCtrl.text
                                                .trim()
                                                .isEmpty
                                            ? '18:00'
                                            : compromissoEndCtrl.text.trim();
                                      }
                                      final nome = gerarComoCompromisso
                                          ? ShiftLocation.fullNameWithSchedule(
                                              ShiftLocation.baseNameFromFull(
                                                          nomeCtrl.text)
                                                      .isEmpty
                                                  ? 'COMPROMISSO'
                                                  : ShiftLocation
                                                      .baseNameFromFull(
                                                          nomeCtrl.text),
                                              startStr,
                                              endStr)
                                          : locSelecionada!.name;
                                      if (gerarComoCompromisso &&
                                          ShiftLocation.baseNameFromFull(nome)
                                              .isEmpty) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content: Text(
                                                    'Informe o nome do compromisso.')));
                                        return;
                                      }
                                      if (!gerarComoCompromisso &&
                                          locSelecionada == null) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                          content: Text(
                                              'Selecione um plantÃ£o da lista de plantÃµes recorrentes para gerar com valor.'),
                                          backgroundColor: Colors.orange,
                                        ));
                                        return;
                                      }
                                      if (dataInicioPer == null ||
                                          dataFimPer == null) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content:
                                                    Text('Defina o perÃ­odo.')));
                                        return;
                                      }
                                      if (regime == 'DiaSemana' &&
                                          diasDaSemanaSelecionados.isEmpty) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content: Text(
                                                    'Marque pelo menos um dia da semana em Personalizar dia da semana.')));
                                        return;
                                      }
                                      if (regime == 'Expediente' &&
                                          expedienteDiasSemana.isEmpty) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content: Text(
                                                    'Marque pelo menos um dia de expediente.')));
                                        return;
                                      }
                                      if (regime == 'RepeteCadaNdias') {
                                        final n = int.tryParse(
                                                repetirNdiasCtrl.text.trim()) ??
                                            repetirACadaDiasState;
                                        if (n < 2 || n > 90) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                            content: Text(
                                                'Intervalo â€œa cada N diasâ€: use um nÃºmero entre 2 e 90.'),
                                            backgroundColor: Colors.orange,
                                          ));
                                          return;
                                        }
                                      }
                                      final ini = dataInicioPer!;
                                      final fim = dataFimPer!;
                                      final fimNorm = DateTime(
                                          fim.year, fim.month, fim.day);
                                      final iniNorm = DateTime(
                                          ini.year, ini.month, ini.day);
                                      if (fimNorm.isBefore(iniNorm)) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                          content: Text(
                                              'A data final deve ser igual ou posterior Ã  data inicial.'),
                                        ));
                                        return;
                                      }
                                      // Trava 1: mÃ¡ximo 24 meses a partir da data inicial
                                      final limiteAPartirDoInicio = DateTime(
                                          iniNorm.year + 2,
                                          iniNorm.month,
                                          iniNorm.day);
                                      if (fimNorm
                                          .isAfter(limiteAPartirDoInicio)) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                          content: Text(
                                              'O perÃ­odo nÃ£o pode ultrapassar 24 meses a partir da data inicial. Ajuste a data final.'),
                                          backgroundColor: Colors.orange,
                                        ));
                                        return;
                                      }
                                      // Trava 2: sempre 24 meses a partir do mÃªs atual â€” nÃ£o pode gerar alÃ©m disso
                                      final agora = DateTime.now();
                                      final limiteAPartirDoMesAtual = DateTime(
                                          agora.year + 2,
                                          agora.month,
                                          agora.day);
                                      if (fimNorm
                                          .isAfter(limiteAPartirDoMesAtual)) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                          content: Text(
                                            'PerÃ­odo mÃ¡ximo: 24 meses a partir do mÃªs atual. A data final nÃ£o pode ultrapassar ${DateFormat('dd/MM/yyyy').format(limiteAPartirDoMesAtual)}.',
                                          ),
                                          backgroundColor: Colors.orange,
                                        ));
                                        return;
                                      }
                                      // Para Personalizado, ler valores atuais dos controllers
                                      final ct = regime == 'Personalizado'
                                          ? (int.tryParse(
                                                  customTrabCtrl.text) ??
                                              24)
                                          : customTrabalho;
                                      final cf = regime == 'Personalizado'
                                          ? (int.tryParse(
                                                  customFolgaCtrl.text) ??
                                              72)
                                          : customFolga;
                                      final repDias = regime ==
                                              'RepeteCadaNdias'
                                          ? (int.tryParse(repetirNdiasCtrl.text
                                                      .trim()) ??
                                                  repetirACadaDiasState)
                                              .clamp(2, 90)
                                          : 7;
                                      final startStrGerarRaw = regime ==
                                              'DiaSemana'
                                          ? (diaSemanaStartCtrl.text
                                                  .trim()
                                                  .isEmpty
                                              ? '08:00'
                                              : diaSemanaStartCtrl.text.trim())
                                          : (locSelecionada?.startTime ??
                                              startStr);
                                      final endStrGerarRaw = regime == 'DiaSemana'
                                          ? (diaSemanaEndCtrl.text
                                                  .trim()
                                                  .isEmpty
                                              ? '18:00'
                                              : diaSemanaEndCtrl.text.trim())
                                          : (locSelecionada?.endTime ?? endStr);
                                      final startStrGerar = startStrGerarRaw;
                                      final endStrGerar = endStrGerarRaw;
                                      Navigator.pop(ctx);
                                      // Usar a cor do plantÃ£o prÃ©-cadastrado quando houver um selecionado.
                                      String colorParaGeracao =
                                          selectedColorHex.startsWith('#')
                                              ? selectedColorHex
                                              : '#$selectedColorHex';
                                      if (locSelecionada != null) {
                                        final locHex = locSelecionada!.colorHex
                                            .replaceFirst(
                                                RegExp(r'^0x',
                                                    caseSensitive: false),
                                                '');
                                        colorParaGeracao = locHex.length >= 6
                                            ? '#${locHex.substring(locHex.length - 6).toUpperCase()}'
                                            : colorParaGeracao;
                                      }
                                      await _executarGeracaoAutomaticaV2(
                                        context,
                                        start: dataInicioPer!,
                                        end: dataFimPer!,
                                        regime: regime,
                                        customTrabalho: ct,
                                        customFolga: cf,
                                        repetirACadaDias: repDias,
                                        tipoGeracao: gerarComoCompromisso
                                            ? 'Compromisso'
                                            : tipoGeracao,
                                        turno: turno,
                                        nome: nome,
                                        startStr: startStrGerar,
                                        endStr: endStrGerar,
                                        colorHex: colorParaGeracao,
                                        location: gerarComoCompromisso
                                            ? null
                                            : locSelecionada,
                                        diasDaSemana: regime == 'DiaSemana'
                                            ? diasDaSemanaSelecionados.toList()
                                            : null,
                                        expedienteDiasSemana:
                                            regime == 'Expediente'
                                                ? expedienteDiasSemana.toList()
                                                : null,
                                      );
                                    }
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
    } catch (e, st) {
      debugPrint('_showGeracaoAutomaticaDialog: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'NÃ£o foi possÃ­vel abrir a geraÃ§Ã£o automÃ¡tica. Tente novamente. ($e)')),
        );
      }
    }
    nomeCtrl.dispose();
    compromissoStartCtrl.dispose();
    compromissoEndCtrl.dispose();
    customTrabCtrl.dispose();
    customFolgaCtrl.dispose();
    repetirNdiasCtrl.dispose();
    diaSemanaStartCtrl.dispose();
    diaSemanaEndCtrl.dispose();
  }

  /// Abre sheet para escolher plantÃ£o prÃ©-cadastrado ou criar novo; ao criar, salva em locations e retorna.
  Future<ShiftLocation?> _abrirSelecaoPlantaoParaGeracao(
      BuildContext context) async {
    return showModalBottomSheet<ShiftLocation>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('PlantÃ£o para geraÃ§Ã£o',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                    'Escolha um plantÃ£o da lista de plantÃµes recorrentes ou crie um novo (serÃ¡ salvo no banco de plantÃµes).',
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                const SizedBox(height: 20),
                if (_locations.isNotEmpty) ...[
                  const Text('Lista de plantÃµes recorrentes',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  ..._locations.map((loc) => ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: loc.color,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: loc.color.withValues(alpha: 0.95),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: loc.color.withValues(alpha: 0.35),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                        title: Text(loc.name),
                        subtitle: Text('${loc.startTime} - ${loc.endTime}'),
                        onTap: () => Navigator.pop(ctx, loc),
                      )),
                  const SizedBox(height: 16),
                ],
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await Navigator.of(ctx).push<bool>(
                        MaterialPageRoute(
                            builder: (_) =>
                                EditLocationScreen(uid: _userDocId)));
                    if (ok == true && mounted) {
                      await _loadLocations();
                      if (_locations.isNotEmpty) {
                        Navigator.pop(ctx, _locations.last);
                      }
                    }
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Criar novo plantÃ£o (salva no banco)'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _executarGeracaoAutomatica(
    BuildContext context, {
    required int ano,
    required String tipoGeracao,
    required String turno,
    required String nome,
    required List<int> weekdays,
    required String colorHex,
  }) async {
    final startYear = DateTime(ano, 1, 1);
    final endYear = DateTime(ano, 12, 31);
    final magicBatchId =
        'magic_${DateTime.now().millisecondsSinceEpoch}_${ano.toString()}';
    int countPlantoes = 0;
    final compromissosParaAgenda = <GeracaoAutomaticaCompromissoItem>[];
    for (var d = DateTime(startYear.year, startYear.month, startYear.day);
        !d.isAfter(endYear);
        d = d.add(const Duration(days: 1))) {
      if (!weekdays.contains(d.weekday)) continue;
      final isCompromisso = tipoGeracao == 'Compromisso';
      String startStr = '08:00', endStr = '18:00';
      if (tipoGeracao == 'PagoHora') {
        if (turno == 'Noturno') {
          startStr = '22:00';
          endStr = '06:00';
        }
      }
      final startDt = turno == 'Noturno'
          ? DateTime(d.year, d.month, d.day, 22, 0)
          : DateTime(d.year, d.month, d.day, 8, 0);
      var endDt = turno == 'Noturno'
          ? DateTime(d.year, d.month, d.day + 1, 6, 0)
          : DateTime(d.year, d.month, d.day, 18, 0);
      double totalValue = 0;
      double hoursDay = 0, hoursNight = 0;
      double dayRate = 0, nightRate = 0;
      if (!isCompromisso) {
        final res = await ScaleRatesService().computeShiftForUid(
          uid: _userDocId,
          start: startDt,
          end: endDt,
          entryDate: d,
        );
        totalValue = (res['total'] ?? 0).toDouble();
        hoursDay = (res['hoursDay'] ?? 0).toDouble();
        hoursNight = (res['hoursNight'] ?? 0).toDouble();
        final rates =
            await ScaleRatesService().getRatesForServiceDay(_userDocId, d);
        dayRate = rates.diurnoForWeekday(ScaleRates.weekdayToIndex(d.weekday));
        nightRate =
            rates.noturnoForWeekday(ScaleRates.weekdayToIndex(d.weekday));
      }
      final hoje = DateTime(
          DateTime.now().year, DateTime.now().month, DateTime.now().day);
      final isRetroativo = d.isBefore(hoje);
      final abbrev = ShiftLocation.abbreviationFromName(nome);
      final colorNorm = colorHex.startsWith('#') ? colorHex : '#$colorHex';
      if (isCompromisso) {
        compromissosParaAgenda.add(
          GeracaoAutomaticaCompromissoItem(
            date: d,
            startHHmm: startStr,
            endHHmm: endStr,
            title: nome,
            colorHex: colorNorm,
          ),
        );
        continue;
      }
      final entry = ScaleEntry(
        date: d,
        start: startStr,
        end: endStr,
        dayRate: dayRate,
        nightRate: nightRate,
        hoursDay: hoursDay,
        hoursNight: hoursNight,
        totalValue: totalValue,
        label: nome,
        abbreviation: abbrev.isNotEmpty ? abbrev : null,
        colorHex: colorNorm,
        paid: isRetroativo,
        isCompromisso: false,
      );
      try {
        final map = entry.toMap();
        map['createdByMagic'] = true;
        map['magicBatchId'] = magicBatchId;
        map['magicGeneratedAt'] = FieldValue.serverTimestamp();
        final docRef = await _scales.add(map);
        unawaited(AgendaNotificationRescheduleHelper.afterScaleSave(
          userDocId: _userDocId,
          scaleRef: docRef,
        ));
        if (tipoGeracao == 'PagoHora' &&
            turno == 'Noturno' &&
            ScaleRates.isLastDayOfMonth(d) &&
            _isCrossingToNextDay(startDt, endDt)) {
          await _syncAutoLancamentoViradaMes(
            sourceId: docRef.id,
            sourceDate: d,
            startDt: startDt,
            endDt: endDt,
            financeiroAtivo: true,
            isCompromisso: false,
            nome: nome,
            abbreviation: abbrev.isNotEmpty ? abbrev : null,
            colorHex: colorNorm,
            employerType: 'state',
          );
        }
        countPlantoes++;
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text('Erro ao gerar: ${e.toString().split('\n').first}')));
        return;
      }
    }
    var compromissosAgenda = 0;
    if (compromissosParaAgenda.isNotEmpty) {
      try {
        compromissosAgenda =
            await ExpressCompromissoAgendaSync.upsertManyFromGeracaoAutomatica(
          userDocId: _userDocId,
          magicBatchId: magicBatchId,
          items: compromissosParaAgenda,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Erro ao gerar compromissos na Agenda: ${e.toString().split('\n').first}')));
        }
        return;
      }
    }
    if (countPlantoes > 0 || compromissosAgenda > 0) {
      unawaited(AgendaNotificationRescheduleHelper.afterItemChanged(
        userDocId: _userDocId,
        queueRebuild: true,
      ));
    }
    if (mounted) {
      final total = countPlantoes + compromissosAgenda;
      final msg = tipoGeracao == 'Compromisso'
          ? '$compromissosAgenda ${compromissosAgenda == 1 ? 'compromisso' : 'compromissos'} gerados para $ano '
              '(Escalas, Agenda e Painel em aberto).'
          : '$total ${total == 1 ? 'lanÃ§amento' : 'lanÃ§amentos'} gerados para $ano.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      setState(() {
        _focusedDay = DateTime(ano, DateTime.now().month.clamp(1, 12), 1);
        _selectedDay = _focusedDay;
      });
      _ensureScalesStreamBound();
    }
  }

  /// Horas diurnas/noturnas para PDF: usa valores gravados na escala ou recalcula pelo turno.
  (double hd, double hn) _hoursDayNightForPdfEntry(
      ScaleEntry e, ScaleRates rates, {bool goiasPerServiceDay = false}) {
    if (e.hoursDay > 0 || e.hoursNight > 0) {
      return (e.hoursDay, e.hoursNight);
    }
    final ratesForCalc = goiasPerServiceDay
        ? ScaleRatesPeriodService().ratesForServiceDay(e.date)
        : rates;
    final startParts = e.start.split(':');
    final endParts = e.end.split(':');
    final sh = int.tryParse(startParts.first) ?? 8;
    final sm = startParts.length > 1 ? (int.tryParse(startParts[1]) ?? 0) : 0;
    final eh = int.tryParse(endParts.first) ?? 18;
    final em = endParts.length > 1 ? (int.tryParse(endParts[1]) ?? 0) : 0;
    var startDt = DateTime(e.date.year, e.date.month, e.date.day, sh, sm);
    var endDt = DateTime(e.date.year, e.date.month, e.date.day, eh, em);
    if (endDt.isBefore(startDt) || endDt.isAtSameMomentAs(startDt)) {
      endDt = endDt.add(const Duration(days: 1));
    }
    final res = ratesForCalc.computeShiftMainEntryLastDayOfMonth(
      start: startDt,
      end: endDt,
      entryDate: e.date,
    );
    return (
      (res['hoursDay'] ?? 0).toDouble(),
      (res['hoursNight'] ?? 0).toDouble(),
    );
  }

  /// Resumo do topo do PDF (mÃªs detalhado / alinhado ao painel).
  ResumoBancoHorasPdf _resumoBancoHorasFromEntries(
      List<ScaleEntry> entries, DateTime hoje, ScaleRates rates,
      {bool goiasPerServiceDay = false}) {
    double hdT = 0, hnT = 0, hdR = 0, hnR = 0, hdP = 0, hnP = 0, vr = 0, vp = 0;
    final linhasCat = <Map<String, dynamic>>[];
    for (final e in entries) {
      final (hd, hn) = _hoursDayNightForPdfEntry(e, rates,
          goiasPerServiceDay: goiasPerServiceDay);
      hdT += hd;
      hnT += hn;
      if (e.effectiveJaTiradoParaExibicao(hoje)) {
        hdR += hd;
        hnR += hn;
      } else {
        hdP += hd;
        hnP += hn;
      }
      if (!e.isCompromisso && e.totalValue > 0) {
        if (e.effectiveJaTiradoParaExibicaoComLocais(hoje, _locations)) {
          vr += e.totalValue;
        } else {
          vp += e.totalValue;
        }
      }
      linhasCat.add({
        'isCompromisso': e.isCompromisso,
        'temFinanceiro': e.temFinanceiroHabilitadoNoPainel,
        'employerType': _employerTypeForEntry(e, _locations),
        'jaTirado': e.effectiveJaTiradoParaExibicao(hoje),
        'hoursDay': hd,
        'hoursNight': hn,
        'valor': e.totalValue,
        'paid': e.paid,
      });
    }
    return ResumoBancoHorasPdf(
      horasDiurnasTotal: hdT,
      horasNoturnasTotal: hnT,
      horasDiurnasRealizadas: hdR,
      horasNoturnasRealizadas: hnR,
      horasDiurnasPendentes: hdP,
      horasNoturnasPendentes: hnP,
      valorJaRecebido: vr,
      valorAReceber: vp,
      categorias: RelatorioService.buildCategoriasResumoBancoHoras(linhasCat),
    );
  }

  /// Abre diÃ¡logo de filtro (data inicial/final, padrÃ£o GoiÃ¡s) e gera PDF.
  Future<void> _gerarPdfEscalas() async {
    DateTime dataInicio = DateTime(_focusedDay.year, _focusedDay.month, 1);
    DateTime dataFim = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);
    bool usarPadraoGoias = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.print_outlined, color: AppColors.primary),
              const SizedBox(width: 10),
              const Text('RelatÃ³rio de produtividade'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Escolha o perÃ­odo para ver sua produtividade:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final d = await pickSingleDateWithHolidayCalendar(
                              context: ctx,
                              initialDate: dataInicio,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030));
                          if (d != null) setState(() => dataInicio = d);
                        },
                        icon:
                            const Icon(Icons.calendar_today_rounded, size: 18),
                        label: Text(DateFormat('dd/MM/yy').format(dataInicio)),
                      ),
                    ),
                    const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('atÃ©')),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final d = await pickSingleDateWithHolidayCalendar(
                              context: ctx,
                              initialDate: dataFim,
                              firstDate: dataInicio,
                              lastDate: DateTime(2030));
                          if (d != null) setState(() => dataFim = d);
                        },
                        icon:
                            const Icon(Icons.calendar_today_rounded, size: 18),
                        label: Text(DateFormat('dd/MM/yy').format(dataFim)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                CheckboxListTile(
                  value: usarPadraoGoias,
                  onChanged: (v) => setState(() => usarPadraoGoias = v ?? true),
                  title: const Text('Usar padrÃ£o Estado de GoiÃ¡s',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                      'O mÃªs encerra Ã  meia-noite (00:00 do dia seguinte): atÃ© 23:59 no Ãºltimo dia; o trecho apÃ³s 00:00 do 1Âº entra no mÃªs seguinte. PadrÃ£o particular: desmarque.',
                      style: TextStyle(fontSize: 12)),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.print_rounded),
                label: const Text('Gerar PDF')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await _executarGeracaoPdf(dataInicio, dataFim, usarPadraoGoias);
  }

  Future<void> _executarGeracaoPdf(
      DateTime dataInicio, DateTime dataFim, bool usarPadraoGoias) async {
    final periodo =
        '${DateFormat('dd/MM/yyyy').format(dataInicio)} a ${DateFormat('dd/MM/yyyy').format(dataFim)}';
    double totalRecebido = 0, totalPendente = 0;
    double horasProximoMes = 0, valorProximoMes = 0;
    double hdT = 0, hnT = 0, hdR = 0, hnR = 0, hdP = 0, hnP = 0;
    final escalas = <Map<String, dynamic>>[];
    final linhasPdfCat = <Map<String, dynamic>>[];
    final rates = usarPadraoGoias
        ? await ScaleRatesService().getGlobalRatesOnly()
        : await ScaleRatesService().getRates(uid: _userDocId);
    final goiasPerDay = usarPadraoGoias;
    final hojePdf =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

    for (final e in _allEntries) {
      if (e.date.isBefore(
              DateTime(dataInicio.year, dataInicio.month, dataInicio.day)) ||
          e.date.isAfter(DateTime(dataFim.year, dataFim.month, dataFim.day)))
        continue;

      final (hdRow, hnRow) = _hoursDayNightForPdfEntry(e, rates,
          goiasPerServiceDay: goiasPerDay);
      hdT += hdRow;
      hnT += hnRow;
      if (e.effectiveJaTiradoParaExibicao(hojePdf)) {
        hdR += hdRow;
        hnR += hnRow;
      } else {
        hdP += hdRow;
        hnP += hnRow;
      }

      final dataPlantao = DateTime(e.date.year, e.date.month, e.date.day);
      final jaEff = e.effectiveJaTiradoParaExibicao(hojePdf);
      final statusServico = dataPlantao.isAfter(hojePdf)
          ? 'A confirmar'
          : (jaEff ? 'JÃ¡ tirado' : 'A tirar');
      final horasLinha = RelatorioService.formatHorasLinhaPdf(hdRow, hnRow);
      final horasCompacta =
          RelatorioService.formatHorasLinhaPdfCompact(hdRow, hnRow);
      if (e.isCompromisso) {
        linhasPdfCat.add({
          'isCompromisso': true,
          'temFinanceiro': false,
          'employerType': _employerTypeForEntry(e, _locations),
          'jaTirado': jaEff,
          'hoursDay': hdRow,
          'hoursNight': hnRow,
          'valor': 0.0,
          'paid': e.paid,
        });
        escalas.add({
          'data': DateFormat('dd/MM/yyyy').format(e.date),
          'numeroEscala': e.scaleNumber ?? '',
          'compromisso': e.label ?? 'Compromisso',
          'valor': 'R\$ 0,00',
          'status': statusServico,
          'horasLinha': horasLinha,
          'horasCompacta': horasCompacta,
          'observacao': e.notes ?? '',
        });
        continue;
      }

      final startParts = e.start.split(':');
      final endParts = e.end.split(':');
      final sh = int.tryParse(startParts.first) ?? 8;
      final sm = startParts.length > 1 ? (int.tryParse(startParts[1]) ?? 0) : 0;
      final eh = int.tryParse(endParts.first) ?? 18;
      final em = endParts.length > 1 ? (int.tryParse(endParts[1]) ?? 0) : 0;
      final startDt = DateTime(e.date.year, e.date.month, e.date.day, sh, sm);
      var endDt = DateTime(e.date.year, e.date.month, e.date.day, eh, em);
      if (endDt.isBefore(startDt) || endDt.isAtSameMomentAs(startDt)) {
        endDt = endDt.add(const Duration(days: 1));
      }

      double valorMes = e.totalValue;
      if (usarPadraoGoias &&
          e.date.year == dataFim.year &&
          e.date.month == dataFim.month &&
          e.date.day == dataFim.day &&
          endDt.day != e.date.day) {
        final fimDia =
            DateTime(e.date.year, e.date.month, e.date.day, 23, 59, 59);
        final iniProx =
            DateTime(e.date.year, e.date.month, e.date.day + 1, 0, 0, 0);
        final res1 = await ScaleRatesService().computeShiftForUid(
          uid: _userDocId,
          start: startDt,
          end: fimDia,
          entryDate: e.date,
        );
        final res2 = await ScaleRatesService().computeShiftForUid(
          uid: _userDocId,
          start: iniProx,
          end: endDt,
          entryDate: e.date.add(const Duration(days: 1)),
        );
        valorMes = (res1['total'] ?? 0).toDouble();
        final prox = (res2['total'] ?? 0).toDouble();
        valorProximoMes += prox;
        horasProximoMes += (res2['hoursDay'] ?? 0).toDouble() +
            (res2['hoursNight'] ?? 0).toDouble();
      }

      // Escalas sem valor: exibir R$ 0,00 no PDF.
      final valorStr =
          valorMes == 0 ? 'R\$ 0,00' : CurrencyFormats.formatBRL(valorMes);
      if (e.paid)
        totalRecebido += valorMes;
      else
        totalPendente += valorMes;
      linhasPdfCat.add({
        'isCompromisso': false,
        'temFinanceiro': e.temFinanceiroHabilitadoNoPainel,
        'employerType': _employerTypeForEntry(e, _locations),
        'jaTirado': jaEff,
        'hoursDay': hdRow,
        'hoursNight': hnRow,
        'valor': valorMes,
        'paid': e.paid,
      });
      escalas.add({
        'data': DateFormat('dd/MM/yyyy').format(e.date),
        'numeroEscala': e.scaleNumber ?? '',
        'compromisso': e.label ?? 'PlantÃ£o',
        'valor': valorStr,
        'status': statusServico,
        'horasLinha': horasLinha,
        'horasCompacta': horasCompacta,
        'observacao': e.notes ?? '',
      });
    }

    escalas
        .sort((a, b) => (a['data'] as String).compareTo(b['data'] as String));

    String? notaProximoMes;
    if (usarPadraoGoias && (valorProximoMes > 0 || horasProximoMes > 0)) {
      notaProximoMes =
          '${horasProximoMes.toStringAsFixed(1)} horas e ${CurrencyFormats.formatBRL(valorProximoMes)} serÃ£o pagos no mÃªs seguinte conforme padrÃ£o do Estado de GoiÃ¡s (valor apÃ³s 23:59).';
    }

    final resumoPdf = ResumoBancoHorasPdf(
      horasDiurnasTotal: hdT,
      horasNoturnasTotal: hnT,
      horasDiurnasRealizadas: hdR,
      horasNoturnasRealizadas: hnR,
      horasDiurnasPendentes: hdP,
      horasNoturnasPendentes: hnP,
      valorJaRecebido: totalRecebido,
      valorAReceber: totalPendente,
      categorias:
          RelatorioService.buildCategoriasResumoBancoHoras(linhasPdfCat),
    );

    try {
      final filenameBase = RelatorioService.reportFilenameFromPeriod(
          'banco_horas', dataInicio, dataFim);
      final (bytes, _) = await RelatorioService.buildRelatorioEscalasBytes(
        periodo: periodo,
        escalas: escalas,
        totalRecebido: totalRecebido,
        totalPendente: totalPendente,
        notaProximoMes: notaProximoMes,
        suggestedFilename: filenameBase,
        reportTitle: 'RelatÃ³rio Banco de Horas â€” Escalas',
        resumoBancoHoras: resumoPdf,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              ReportPreviewScreen(bytes: bytes, filename: filenameBase),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Erro ao gerar PDF: ${e.toString().split('\n').first}')),
        );
      }
    }
  }

  /// Bottom sheet: PadrÃ£o GO (hora) / Personalizado (dia), dia + hora inicial/final, valor estimado, controle financeiro, salvar.
  /// Data do plantÃ£o pode ser alterada (retroativa ou futura); ao salvar, grava na data escolhida e calcula valores pelo dia/horÃ¡rio.
  void _abrirFormularioEscala(BuildContext context, {DateTime? initialDate}) {
    DateTime dataEscala = initialDate ?? _selectedDay ?? _focusedDay;
    bool controleFinanceiroAtivo =
        true; // Ativar controle financeiro das horas (calcula e grava valor)
    String employerTypeConfig =
        'state'; // Estado / MunicÃ­pio / Particular â€” padrÃ£o Estado; sÃ³ aparece quando financeiro ativo
    String tipoCalculo = 'PadrÃ£o GO';
    bool isCompromisso = false;
    TimeOfDay horaInicial = const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay horaFinal = const TimeOfDay(hour: 18, minute: 0);
    ScaleRates? ratesCache;
    bool ratesLoaded = false;
    Map<String, double>? estimateRes;
    String? estimateKey;
    String selectedColorHex = _hexDiurno;

    /// PadrÃ£o do sistema: usuÃ¡rio deve buscar no prÃ©-cadastro antes de salvar.
    bool selecionouPreCadastro = false;

    /// Cor hex 6 chars (sem #) do prÃ©-cadastro quando inÃ­cio Ã© diurno; usada ao ajustar sÃ³ o horÃ¡rio.
    String? preCadastroDiurnoHex6;
    void syncCorPorHorarioInicio() {
      final h = horaInicial.hour;
      if (h >= 22 || h < 6) {
        selectedColorHex = _hexNoturno;
      } else {
        selectedColorHex = (preCadastroDiurnoHex6 != null &&
                preCadastroDiurnoHex6!.length == 6)
            ? preCadastroDiurnoHex6!
            : _hexDiurno;
      }
    }

    // Nome jÃ¡ com horÃ¡rio (igual prÃ©-cadastro): padrÃ£o Diurno 08:00â€“18:00
    final nomeCtrl = TextEditingController(
        text: ShiftLocation.fullNameWithSchedule('PLANTÃƒO', '08:00', '18:00'));
    final valorPersonalizadoCtrl = TextEditingController();
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (routeCtx) {
          return Scaffold(
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
              title: const Text(
                'Configurar PlantÃ£o',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Fechar',
                onPressed: () => Navigator.of(routeCtx).pop(),
              ),
            ),
            body: StatefulBuilder(
              builder: (ctx, setModalState) {
            if (!ratesLoaded) {
              ratesLoaded = true;
              ScaleRatesService()
                  .getRatesForServiceDay(_userDocId, dataEscala)
                  .then((r) {
                if (ctx.mounted) setModalState(() => ratesCache = r);
              });
            }
            // Valor estimado: PadrÃ£o GO com dia + hora inicial/final
            DateTime startDt = DateTime(dataEscala.year, dataEscala.month,
                dataEscala.day, horaInicial.hour, horaInicial.minute);
            DateTime endDt = DateTime(dataEscala.year, dataEscala.month,
                dataEscala.day, horaFinal.hour, horaFinal.minute);
            if (endDt.isBefore(startDt) || endDt.isAtSameMomentAs(startDt))
              endDt = endDt.add(const Duration(days: 1));
            final estKey =
                '${dataEscala.toIso8601String()}_${horaInicial.hour}:${horaInicial.minute}_${horaFinal.hour}:${horaFinal.minute}_$tipoCalculo';
            if (estimateKey != estKey &&
                !isCompromisso &&
                controleFinanceiroAtivo &&
                (employerTypeConfig != 'private' ||
                    tipoCalculo == 'PadrÃ£o GO')) {
              estimateKey = estKey;
              ScaleRatesService()
                  .computeShiftForUid(
                    uid: _userDocId,
                    start: startDt,
                    end: endDt,
                    entryDate: dataEscala,
                  )
                  .then((r) {
                if (ctx.mounted) setModalState(() => estimateRes = r);
              });
            }
            final res = estimateRes;
            final valorEstimado = (res?['total'] ?? 0.0);
            final hoursDay = (res?['hoursDay'] ?? 0.0);
            final hoursNight = (res?['hoursNight'] ?? 0.0);

            final sheetSafeBottomForm = MediaQuery.paddingOf(ctx).bottom + 25;
            return KeyboardViewInsetPad(
              left: 25,
              right: 25,
              top: 12,
              bottom: sheetSafeBottomForm,
              child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      const Text(
                          'PlantÃ£o com valor: busque na lista de plantÃµes recorrentes. Compromisso particular: marque a opÃ§Ã£o abaixo e salve.',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A237E))),
                      const SizedBox(height: 10),
                      if (_locations.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                  'Nenhum plantÃ£o na lista de plantÃµes recorrentes. Crie o primeiro para depois escolher aqui.',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade700)),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final ok = await Navigator.of(ctx).push<bool>(
                                      MaterialPageRoute(
                                          builder: (_) => EditLocationScreen(
                                              uid: _userDocId)));
                                  if (ok == true && mounted) {
                                    await _loadLocations();
                                    setModalState(() {});
                                  }
                                },
                                icon: const Icon(Icons.add_rounded),
                                label: const Text(
                                    'Criar primeiro plantÃ£o na lista de plantÃµes recorrentes'),
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final loc =
                                  await showModalBottomSheet<ShiftLocation>(
                                context: ctx,
                                useSafeArea: true,
                                useRootNavigator: true,
                                barrierColor: Colors.black54,
                                shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(24))),
                                builder: (_) => DraggableScrollableSheet(
                                  initialChildSize: 0.5,
                                  expand: false,
                                  builder: (__, scrollController) => ListView(
                                    controller: scrollController,
                                    padding: const EdgeInsets.all(20),
                                    children: [
                                      const Text('Buscar na lista de plantÃµes recorrentes',
                                          style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 8),
                                      Text(
                                          'Escolha um plantÃ£o para preencher os dados automaticamente. Depois, basta marcar a data.',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey.shade600)),
                                      const SizedBox(height: 16),
                                      ..._locations.map((l) => ListTile(
                                            leading: Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color: l.color,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: l.color
                                                      .withValues(alpha: 0.95),
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: l.color.withValues(
                                                        alpha: 0.35),
                                                    blurRadius: 6,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            title: Text(l.name),
                                            subtitle: Text(
                                                '${ShiftLocation.employerTypeLabel(l.employerType)} Â· ${l.startTime} - ${l.endTime}'),
                                            onTap: () => Navigator.pop(_, l),
                                          )),
                                    ],
                                  ),
                                ),
                              );
                              if (loc != null && ctx.mounted) {
                                nomeCtrl.text =
                                    ShiftLocation.fullNameWithSchedule(
                                        loc.name, loc.startTime, loc.endTime);
                                employerTypeConfig = loc.employerType.name;
                                controleFinanceiroAtivo = loc.financialEnabled;
                                isCompromisso = !loc.financialEnabled;
                                // Particular + valor fixo: reconhecer por paymentType.fixed OU baseValue > 0 (evita nÃ£o calcular)
                                final isParticularComValorFixo =
                                    loc.employerType == EmployerType.private &&
                                        (loc.paymentType == PaymentType.fixed ||
                                            loc.baseValue > 0);
                                tipoCalculo = isParticularComValorFixo
                                    ? 'Personalizado'
                                    : 'PadrÃ£o GO';
                                if (isParticularComValorFixo &&
                                    loc.baseValue > 0)
                                  valorPersonalizadoCtrl.text =
                                      CurrencyFormats.formatBRLInput(
                                          loc.baseValue);
                                final startParts = loc.startTime.split(':');
                                final endParts = loc.endTime.split(':');
                                horaInicial = TimeOfDay(
                                    hour: int.tryParse(startParts.first) ?? 8,
                                    minute: startParts.length > 1
                                        ? int.tryParse(startParts[1]) ?? 0
                                        : 0);
                                horaFinal = TimeOfDay(
                                    hour: int.tryParse(endParts.first) ?? 18,
                                    minute: endParts.length > 1
                                        ? int.tryParse(endParts[1]) ?? 0
                                        : 0);
                                final hIni = horaInicial.hour;
                                final noturnoInicio = (hIni >= 22 || hIni < 6);
                                String locHex = loc.colorHex
                                    .replaceFirst(
                                        RegExp(r'^0x', caseSensitive: false),
                                        '')
                                    .replaceFirst('#', '');
                                if (locHex.length > 6)
                                  locHex = locHex.substring(locHex.length - 6);
                                preCadastroDiurnoHex6 =
                                    noturnoInicio ? null : locHex;
                                selectedColorHex =
                                    noturnoInicio ? _hexNoturno : locHex;
                                selecionouPreCadastro = true;
                                setModalState(() {});
                              }
                            },
                            icon: const Icon(Icons.search_rounded, size: 20),
                            label: const Text('Buscar na lista de plantÃµes recorrentes'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      const SizedBox(height: 4),
                      SwitchListTile(
                        title:
                            const Text('Ativar controle financeiro das horas'),
                        subtitle: const Text(
                            'Ative para calcular e registrar o valor (Estado/MunicÃ­pio: PadrÃ£o GO; Particular: valor combinado).'),
                        value: controleFinanceiroAtivo,
                        onChanged: (v) =>
                            setModalState(() => controleFinanceiroAtivo = v),
                        activeColor: Colors.green,
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (controleFinanceiroAtivo && !isCompromisso) ...[
                        const SizedBox(height: 12),
                        const Text('VÃ­nculo',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                            'Estado/MunicÃ­pio: PadrÃ£o GO. Particular: vigilantes/serviÃ§o privado â€” informe valor.',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                                child: _buildVinculoChip(
                                    ctx,
                                    setModalState,
                                    'state',
                                    'Estado',
                                    AppColors.vinculoEstado,
                                    Icons.account_balance_rounded,
                                    employerTypeConfig, () {
                              employerTypeConfig = 'state';
                              tipoCalculo = 'PadrÃ£o GO';
                            })),
                            const SizedBox(width: 8),
                            Expanded(
                                child: _buildVinculoChip(
                                    ctx,
                                    setModalState,
                                    'municipality',
                                    'MunicÃ­pio',
                                    AppColors.vinculoMunicipio,
                                    Icons.location_city_rounded,
                                    employerTypeConfig, () {
                              employerTypeConfig = 'municipality';
                              tipoCalculo = 'PadrÃ£o GO';
                            })),
                            const SizedBox(width: 8),
                            Expanded(
                                child: _buildVinculoChip(
                                    ctx,
                                    setModalState,
                                    'private',
                                    'Particular',
                                    AppColors.vinculoParticular,
                                    Icons.person_rounded,
                                    employerTypeConfig, () {
                              employerTypeConfig = 'private';
                              tipoCalculo = 'Personalizado';
                            })),
                          ],
                        ),
                      ],
                      if (controleFinanceiroAtivo &&
                          !isCompromisso &&
                          employerTypeConfig == 'private') ...[
                        const SizedBox(height: 16),
                        const Text('Tipo de RemuneraÃ§Ã£o',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            ChoiceChip(
                              label: const Text('PadrÃ£o GO (Hora)'),
                              selected: tipoCalculo == 'PadrÃ£o GO',
                              onSelected: (_) => setModalState(
                                  () => tipoCalculo = 'PadrÃ£o GO'),
                              selectedColor: const Color(0xFF2962FF),
                              labelStyle: TextStyle(
                                  color: tipoCalculo == 'PadrÃ£o GO'
                                      ? Colors.white
                                      : Colors.black87),
                            ),
                            const SizedBox(width: 10),
                            ChoiceChip(
                              label: const Text('Personalizado (Dia)'),
                              selected: tipoCalculo == 'Personalizado',
                              onSelected: (_) => setModalState(
                                  () => tipoCalculo = 'Personalizado'),
                              selectedColor: const Color(0xFF2962FF),
                              labelStyle: TextStyle(
                                  color: tipoCalculo == 'Personalizado'
                                      ? Colors.white
                                      : Colors.black87),
                            ),
                          ],
                        ),
                        if (tipoCalculo == 'Personalizado') ...[
                          const SizedBox(height: 12),
                          BrlAmountTextField(
                            controller: valorPersonalizadoCtrl,
                            decoration: InputDecoration(
                              labelText: 'Valor total / diÃ¡ria (R\$)',
                              hintText: '0,00',
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide:
                                      BorderSide(color: Colors.grey.shade300)),
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(height: 16),
                      CheckboxListTile(
                        value: isCompromisso,
                        onChanged: (v) => setModalState(() {
                          isCompromisso = v ?? false;
                          if (isCompromisso) {
                            selectedColorHex = _hexCompromisso;
                            horaInicial = const TimeOfDay(hour: 8, minute: 0);
                            horaFinal = const TimeOfDay(hour: 18, minute: 0);
                            nomeCtrl.text = ShiftLocation.fullNameWithSchedule(
                                ShiftLocation.baseNameFromFull(nomeCtrl.text),
                                '08:00',
                                '18:00');
                          }
                        }),
                        title: const Text(
                            'Compromisso particular (folga, sem valor)'),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (isCompromisso) ...[
                        const SizedBox(height: 12),
                        const Text('HorÃ¡rio do compromisso',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.access_time_rounded,
                                    size: 18),
                                label: Text(
                                    '${horaInicial.hour.toString().padLeft(2, '0')}:${horaInicial.minute.toString().padLeft(2, '0')}'),
                                onPressed: () async {
                                  final t = await showTimePicker(
                                      context: ctx, initialTime: horaInicial);
                                  if (t != null)
                                    setModalState(() {
                                      horaInicial = t;
                                      final start =
                                          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                                      final end =
                                          '${horaFinal.hour.toString().padLeft(2, '0')}:${horaFinal.minute.toString().padLeft(2, '0')}';
                                      final base =
                                          ShiftLocation.baseNameFromFull(
                                              nomeCtrl.text);
                                      nomeCtrl.text =
                                          ShiftLocation.fullNameWithSchedule(
                                              base, start, end);
                                    });
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.access_time_rounded,
                                    size: 18),
                                label: Text(
                                    '${horaFinal.hour.toString().padLeft(2, '0')}:${horaFinal.minute.toString().padLeft(2, '0')}'),
                                onPressed: () async {
                                  final t = await showTimePicker(
                                      context: ctx, initialTime: horaFinal);
                                  if (t != null)
                                    setModalState(() {
                                      horaFinal = t;
                                      final start =
                                          '${horaInicial.hour.toString().padLeft(2, '0')}:${horaInicial.minute.toString().padLeft(2, '0')}';
                                      final end =
                                          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                                      final base =
                                          ShiftLocation.baseNameFromFull(
                                              nomeCtrl.text);
                                      nomeCtrl.text =
                                          ShiftLocation.fullNameWithSchedule(
                                              base, start, end);
                                    });
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                            'Nome serÃ¡ exibido com o horÃ¡rio (ex: FOLGA 08:00 Ã€S 18:00). Edite o texto abaixo.',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600)),
                      ],
                      if (!isCompromisso) ...[
                        const SizedBox(height: 16),
                        const Text('Dia e horÃ¡rio do plantÃ£o',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                            'Toque na data para alterar (retroativa ou futura). O plantÃ£o serÃ¡ lanÃ§ado na data escolhida.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () async {
                                    final picked =
                                        await pickSingleDateWithHolidayCalendar(
                                      context: ctx,
                                      initialDate: dataEscala,
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime(2030, 12, 31),
                                    );
                                    if (picked != null)
                                      setModalState(() => dataEscala = picked);
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12, horizontal: 12),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                          color: Colors.grey.shade300),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.calendar_today_rounded,
                                            size: 20,
                                            color: Colors.grey.shade600),
                                        const SizedBox(width: 8),
                                        Text(
                                            DateFormat('dd/MM/yyyy')
                                                .format(dataEscala),
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600)),
                                        const Spacer(),
                                        Icon(Icons.edit_calendar_rounded,
                                            size: 18,
                                            color: Colors.grey.shade600),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.access_time_rounded,
                                    size: 18),
                                label: Text(
                                    '${horaInicial.hour.toString().padLeft(2, '0')}:${horaInicial.minute.toString().padLeft(2, '0')}'),
                                onPressed: () async {
                                  final t = await showTimePicker(
                                      context: ctx, initialTime: horaInicial);
                                  if (t != null)
                                    setModalState(() {
                                      horaInicial = t;
                                      final start =
                                          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                                      final end =
                                          '${horaFinal.hour.toString().padLeft(2, '0')}:${horaFinal.minute.toString().padLeft(2, '0')}';
                                      final basePlantao =
                                          ShiftLocation.baseNameFromFull(
                                              nomeCtrl.text);
                                      nomeCtrl.text =
                                          ShiftLocation.fullNameWithSchedule(
                                              basePlantao, start, end);
                                      syncCorPorHorarioInicio();
                                    });
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.access_time_rounded,
                                    size: 18),
                                label: Text(
                                    '${horaFinal.hour.toString().padLeft(2, '0')}:${horaFinal.minute.toString().padLeft(2, '0')}'),
                                onPressed: () async {
                                  final t = await showTimePicker(
                                      context: ctx, initialTime: horaFinal);
                                  if (t != null)
                                    setModalState(() {
                                      horaFinal = t;
                                      final start =
                                          '${horaInicial.hour.toString().padLeft(2, '0')}:${horaInicial.minute.toString().padLeft(2, '0')}';
                                      final end =
                                          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                                      final basePlantao =
                                          ShiftLocation.baseNameFromFull(
                                              nomeCtrl.text);
                                      nomeCtrl.text =
                                          ShiftLocation.fullNameWithSchedule(
                                              basePlantao, start, end);
                                    });
                                },
                              ),
                            ),
                          ],
                        ),
                        if ((employerTypeConfig != 'private' ||
                                tipoCalculo == 'PadrÃ£o GO') &&
                            estimateRes != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2962FF).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color:
                                      const Color(0xFF2962FF).withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Valor estimado desta frente:',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600)),
                                Text(CurrencyFormats.formatBRL(valorEstimado),
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF1A237E))),
                              ],
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(height: 12),
                      FastTextField(
                        controller: nomeCtrl,
                        decoration: InputDecoration(
                          labelText: isCompromisso
                              ? 'Nome (base) * â€” horÃ¡rio completa automaticamente'
                              : 'Nome do Compromisso / Escala *',
                          border: const OutlineInputBorder(),
                          hintText: isCompromisso
                              ? 'EX: FOLGA, CULTO, REUNIÃƒO'
                              : 'EX: PLANTÃƒO NOTURNO - GO',
                        ),
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [UpperCaseTextFormatter()],
                        onSubmitted: (_) {
                          if (isCompromisso) {
                            final base =
                                ShiftLocation.baseNameFromFull(nomeCtrl.text);
                            final start =
                                '${horaInicial.hour.toString().padLeft(2, '0')}:${horaInicial.minute.toString().padLeft(2, '0')}';
                            final end =
                                '${horaFinal.hour.toString().padLeft(2, '0')}:${horaFinal.minute.toString().padLeft(2, '0')}';
                            nomeCtrl.text = ShiftLocation.fullNameWithSchedule(
                                base.isEmpty ? 'COMPROMISSO' : base,
                                start,
                                end);
                            setModalState(() {});
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      const SizedBox(height: 14),
                      const Text('Cor no calendÃ¡rio (identifique lugar/tipo)',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: kColorPaletteHex.take(72).map((hex) {
                            final isSelected = selectedColorHex
                                    .toUpperCase()
                                    .replaceFirst('#', '') ==
                                hex.replaceFirst('#', '').toUpperCase();
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => setModalState(() =>
                                    selectedColorHex =
                                        hex.startsWith('#') ? hex : '#$hex'),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Color(0xFF000000 +
                                        int.parse(hex.replaceFirst('#', ''),
                                            radix: 16)),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.grey.shade300,
                                        width: isSelected ? 3 : 1),
                                    boxShadow: [
                                      BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: isSelected ? 6 : 2)
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!isCompromisso) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.blue.shade100),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded,
                                  size: 18, color: Colors.blue.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'PlantÃ£o serÃ¡ lanÃ§ado em ${DateFormat('dd/MM/yyyy').format(dataEscala)}. Valor calculado conforme dia e horÃ¡rio.',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue.shade900,
                                      fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (!selecionouPreCadastro && !isCompromisso)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                              'Clique em "Buscar na lista de plantÃµes recorrentes" e escolha um plantÃ£o para salvar com valor. Ou marque "Compromisso particular" para sem valor.',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.orange.shade700)),
                        ),
                      if (selecionouPreCadastro || isCompromisso) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Lembretes usam o padrÃ£o de ConfiguraÃ§Ãµes â†’ NotificaÃ§Ãµes.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                (selecionouPreCadastro || isCompromisso)
                                    ? const Color(0xFF1A237E)
                                    : Colors.grey,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15)),
                          ),
                          onPressed: (selecionouPreCadastro || isCompromisso)
                              ? () async {
                                  final nome =
                                      nomeCtrl.text.trim().toUpperCase();
                                  final nomeBase =
                                      ShiftLocation.baseNameFromFull(nome);
                                  final faltando = <String>[];
                                  if (nomeBase.isEmpty) {
                                    faltando.add(isCompromisso
                                        ? 'Nome (base)'
                                        : 'Nome do compromisso/escala');
                                  }
                                  if (faltando.isNotEmpty) {
                                    final texto = faltando.length == 1
                                        ? 'NÃ£o foi possÃ­vel salvar. Preencha: ${faltando.single} (obrigatÃ³rio).'
                                        : 'NÃ£o foi possÃ­vel salvar. Campos obrigatÃ³rios: ${faltando.join(' e ')}.';
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(texto)));
                                    return;
                                  }
                                  double totalValue = 0;
                                  double hoursDay = 0, hoursNight = 0;
                                  String start =
                                      '${horaInicial.hour.toString().padLeft(2, '0')}:${horaInicial.minute.toString().padLeft(2, '0')}';
                                  String end =
                                      '${horaFinal.hour.toString().padLeft(2, '0')}:${horaFinal.minute.toString().padLeft(2, '0')}';
                                  final nomeComHorario =
                                      ShiftLocation.fullNameWithSchedule(
                                          nomeBase, start, end);
                                  double dayRate = 0, nightRate = 0;
                                  if (isCompromisso ||
                                      !controleFinanceiroAtivo) {
                                    totalValue = 0;
                                  } else if (employerTypeConfig == 'private' &&
                                      tipoCalculo == 'Personalizado') {
                                    totalValue = CurrencyFormats.parseBRLInput(
                                            valorPersonalizadoCtrl.text) ??
                                        0;
                                  } else {
                                    // PadrÃ£o GO: usa dia + hora inicial/final selecionados
                                    final startDt = DateTime(
                                        dataEscala.year,
                                        dataEscala.month,
                                        dataEscala.day,
                                        horaInicial.hour,
                                        horaInicial.minute);
                                    var endDt = DateTime(
                                        dataEscala.year,
                                        dataEscala.month,
                                        dataEscala.day,
                                        horaFinal.hour,
                                        horaFinal.minute);
                                    if (endDt.isBefore(startDt) ||
                                        endDt.isAtSameMomentAs(startDt))
                                      endDt =
                                          endDt.add(const Duration(days: 1));
                                    final res = await ScaleRatesService()
                                        .computeShiftForUid(
                                      uid: _userDocId,
                                      start: startDt,
                                      end: endDt,
                                      entryDate: dataEscala,
                                    );
                                    final rates = await ScaleRatesService()
                                        .getRatesForServiceDay(
                                            _userDocId, dataEscala);
                                    totalValue = res['total'] ?? 0;
                                    hoursDay = res['hoursDay'] ?? 0;
                                    hoursNight = res['hoursNight'] ?? 0;
                                    dayRate = rates.diurnoForWeekday(
                                        ScaleRates.weekdayToIndex(
                                            dataEscala.weekday));
                                    nightRate = rates.noturnoForWeekday(
                                        ScaleRates.weekdayToIndex(
                                            dataEscala.weekday));
                                  }
                                  // Cor escolhida na paleta (ou padrÃ£o por tipo)
                                  final colorHex =
                                      selectedColorHex.startsWith('#')
                                          ? selectedColorHex
                                          : '#$selectedColorHex';
                                  // Lembretes: opcionalmente personalizados neste formulÃ¡rio (campo reminderLeads na escala).
                                  // PlantÃ£o retroativo: data no passado = usuÃ¡rio esqueceu de lanÃ§ar â€” marcar jÃ¡ realizado
                                  final hoje = DateTime(DateTime.now().year,
                                      DateTime.now().month, DateTime.now().day);
                                  final isRetroativo =
                                      dataEscala.isBefore(hoje);
                                  // Iniciais nÃ£o sÃ£o mais campo de entrada; manter apenas auto-geraÃ§Ã£o
                                  // para compatibilidade com dados antigos e notificaÃ§Ãµes.
                                  final autoAbbrev =
                                      ShiftLocation.abbreviationFromName(
                                          nomeBase);
                                  final abbrevFinal = autoAbbrev.isNotEmpty
                                      ? autoAbbrev.substring(
                                          0, autoAbbrev.length.clamp(1, 6))
                                      : '';
                                  final entry = ScaleEntry(
                                    date: dataEscala,
                                    start: start,
                                    end: end,
                                    dayRate: dayRate,
                                    nightRate: nightRate,
                                    hoursDay: hoursDay,
                                    hoursNight: hoursNight,
                                    totalValue: totalValue,
                                    label: nomeComHorario,
                                    abbreviation: abbrevFinal.isNotEmpty
                                        ? abbrevFinal
                                        : null,
                                    colorHex: colorHex,
                                    paid: isRetroativo,
                                    isCompromisso: isCompromisso,
                                    employerType: employerTypeConfig,
                                    reminderLeads: null,
                                    notificationSoundId: null,
                                    notificationDeliveryMode: null,
                                  );
                                  try {
                                    HapticFeedback.lightImpact();
                                    final createdDoc =
                                        await _scales.add(entry.toMap());
                                    unawaited(
                                      AgendaNotificationRescheduleHelper
                                          .afterScaleSave(
                                        userDocId: _userDocId,
                                        scaleRef: createdDoc,
                                        newDate: dataEscala,
                                        newStartHHmm: start,
                                      ),
                                    );
                                    final startDt = DateTime(
                                        dataEscala.year,
                                        dataEscala.month,
                                        dataEscala.day,
                                        horaInicial.hour,
                                        horaInicial.minute);
                                    var endDt = DateTime(
                                        dataEscala.year,
                                        dataEscala.month,
                                        dataEscala.day,
                                        horaFinal.hour,
                                        horaFinal.minute);
                                    if (endDt.isBefore(startDt) ||
                                        endDt.isAtSameMomentAs(startDt)) {
                                      endDt =
                                          endDt.add(const Duration(days: 1));
                                    }
                                    await _syncAutoLancamentoViradaMes(
                                      sourceId: createdDoc.id,
                                      sourceDate: dataEscala,
                                      startDt: startDt,
                                      endDt: endDt,
                                      financeiroAtivo: controleFinanceiroAtivo,
                                      isCompromisso: isCompromisso,
                                      nome: nomeComHorario,
                                      abbreviation: abbrevFinal.isNotEmpty
                                          ? abbrevFinal
                                          : null,
                                      colorHex: colorHex,
                                      employerType: employerTypeConfig,
                                    );
                                    // Gerar prÃ©-cadastro: salva em locations para o usuÃ¡rio escolher em outras datas
                                    final locHex = colorHex.startsWith('#')
                                        ? colorHex
                                        : '#$colorHex';
                                    final paymentType = (employerTypeConfig ==
                                                'private' &&
                                            tipoCalculo == 'Personalizado' &&
                                            !isCompromisso &&
                                            controleFinanceiroAtivo)
                                        ? PaymentType.fixed
                                        : PaymentType.perHour;
                                    final baseVal = (employerTypeConfig ==
                                                'private' &&
                                            tipoCalculo == 'Personalizado' &&
                                            !isCompromisso)
                                        ? (CurrencyFormats.parseBRLInput(
                                                valorPersonalizadoCtrl.text) ??
                                            0)
                                        : 0.0;
                                    // Usar mesmas iniciais da escala para o prÃ©-cadastro (frente de serviÃ§o)
                                    final locMap = <String, dynamic>{
                                      'name': nomeComHorario,
                                      'abbreviation': abbrevFinal.isNotEmpty
                                          ? abbrevFinal
                                          : ShiftLocation.abbreviationFromName(
                                              nomeBase),
                                      'colorHex': locHex,
                                      'startTime': start,
                                      'endTime': end,
                                      'notifyEnabled': true,
                                      'financialEnabled':
                                          controleFinanceiroAtivo &&
                                              !isCompromisso,
                                      'paymentType': paymentType.name,
                                      'employerType': employerTypeConfig,
                                      'baseValue': baseVal,
                                      'bonus': 0,
                                      'discount': 0,
                                      'nightDifferentialEnabled': false,
                                      'nightDifferentialPercent': 20,
                                      'nightStart': '22:00',
                                      'nightEnd': '05:00',
                                      'sortOrder': _locations.length,
                                    };
                                    final existing = _locations
                                        .where((l) =>
                                            l.name.trim().toLowerCase() ==
                                            nomeComHorario.trim().toLowerCase())
                                        .firstOrNull;
                                    if (existing?.id != null) {
                                      await _locationsRef
                                          .doc(existing!.id)
                                          .update(locMap);
                                    } else {
                                      await _locationsRef.add(locMap);
                                    }
                                    if (mounted) {
                                      _loadLocations();
                                      setState(() {
                                        _selectedDay = dataEscala;
                                        _focusedDay = dataEscala;
                                      });
                                      _ensureScalesStreamBound();
                                    }
                                    // Mostrar opÃ§Ã£o: Novo PlantÃ£o (voltar ao calendÃ¡rio) ou Finalizar (fechar e voltar ao calendÃ¡rio)
                                    if (ctx.mounted) {
                                      await showDialog<void>(
                                        context: ctx,
                                        barrierDismissible: false,
                                        builder: (dialogContext) => AlertDialog(
                                          title: const Row(
                                            children: [
                                              Icon(Icons.check_circle_rounded,
                                                  color: AppColors.success,
                                                  size: 28),
                                              SizedBox(width: 12),
                                              Text('PlantÃ£o salvo'),
                                            ],
                                          ),
                                          content: const Text(
                                            'PlantÃ£o salvo na agenda e lista de plantÃµes recorrentes atualizada. Na prÃ³xima vez, clique na data e escolha este plantÃ£o.',
                                            style: TextStyle(height: 1.4),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () {
                                                Navigator.pop(dialogContext);
                                                if (ctx.mounted)
                                                  Navigator.pop(ctx);
                                              },
                                              child: const Text('Novo PlantÃ£o'),
                                            ),
                                            FilledButton(
                                              onPressed: () {
                                                Navigator.pop(dialogContext);
                                                if (ctx.mounted)
                                                  Navigator.pop(ctx);
                                              },
                                              child: const Text('Finalizar'),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted)
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content: Text(
                                                  'Erro ao salvar: ${e.toString().split('\n').first}')));
                                  }
                                }
                              : null,
                          child: const Text('Salvar na Agenda',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                ),
              ),
            );
          },
        ),
          );
        },
      ),
    );
  }
}

class _MagicBatchAccumulator {
  final String batchId;
  DateTime criadoEm;
  String previewNome;
  int quantidade;
  DateTime diaInicio;
  DateTime diaFim;

  _MagicBatchAccumulator({
    required this.batchId,
    required this.criadoEm,
    required this.previewNome,
    required this.quantidade,
    required this.diaInicio,
    required this.diaFim,
  });
}

class _MagicBatchPreview {
  final String batchId;
  final DateTime criadoEm;
  final String previewNome;
  final int quantidade;
  final DateTime diaInicio;
  final DateTime diaFim;

  const _MagicBatchPreview({
    required this.batchId,
    required this.criadoEm,
    required this.previewNome,
    required this.quantidade,
    required this.diaInicio,
    required this.diaFim,
  });
}

/// DiÃ¡logo: escolher dias da semana do expediente (DateTime.weekday 1â€“7).
class _ExpedienteDiasSemanaDialog extends StatefulWidget {
  final Set<int> initial;

  const _ExpedienteDiasSemanaDialog({required this.initial});

  @override
  State<_ExpedienteDiasSemanaDialog> createState() =>
      _ExpedienteDiasSemanaDialogState();
}

class _ExpedienteDiasSemanaDialogState
    extends State<_ExpedienteDiasSemanaDialog> {
  static const List<(String label, int weekday)> _itens = [
    ('Segunda-feira', DateTime.monday),
    ('TerÃ§a-feira', DateTime.tuesday),
    ('Quarta-feira', DateTime.wednesday),
    ('Quinta-feira', DateTime.thursday),
    ('Sexta-feira', DateTime.friday),
    ('SÃ¡bado', DateTime.saturday),
    ('Domingo', DateTime.sunday),
  ];

  late Set<int> _sel;

  @override
  void initState() {
    super.initState();
    _sel = Set<int>.from(widget.initial);
    if (_sel.isEmpty) _sel = {1, 2, 3, 4, 5};
  }

  void _padraoSegundaASexta() {
    setState(() => _sel = {1, 2, 3, 4, 5});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dias de expediente'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Marque os dias em que hÃ¡ expediente. Se tiver folga em um dia da semana, desmarque esse dia.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            for (final e in _itens)
              CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text(e.$1),
                value: _sel.contains(e.$2),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _sel.add(e.$2);
                    } else {
                      _sel.remove(e.$2);
                    }
                  });
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _padraoSegundaASexta,
          child: const Text('Segunda a sexta'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (_sel.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Marque pelo menos um dia.')),
              );
              return;
            }
            Navigator.pop(context, Set<int>.from(_sel));
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Pintor para divisÃ£o diagonal na cÃ©lula do calendÃ¡rio (2 frentes de serviÃ§o).
class _DiagonalSplitPainter extends CustomPainter {
  final Color colorTopLeft;
  final Color colorBottomRight;

  _DiagonalSplitPainter(
      {required this.colorTopLeft, required this.colorBottomRight});

  @override
  void paint(Canvas canvas, Size size) {
    // TriÃ¢ngulo topo-esquerda: (0,0) -> (size.width,0) -> (0,size.height)
    final pathTopLeft = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(pathTopLeft, Paint()..color = colorTopLeft);
    // TriÃ¢ngulo base-direita: (size.width,0) -> (size.width,size.height) -> (0,size.height)
    final pathBottomRight = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(pathBottomRight, Paint()..color = colorBottomRight);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Pintor para N plantÃµes no mesmo dia: 2 = diagonal; 3+ = fatias angulares do centro (fracionamento).
class _CalendarDayNPartsPainter extends CustomPainter {
  final List<Color> colors;

  _CalendarDayNPartsPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    if (colors.isEmpty) return;
    if (colors.length == 1) {
      canvas.drawRect(Offset.zero & size, Paint()..color = colors.first);
      return;
    }
    if (colors.length == 2) {
      // Diagonal: topo-esquerda / base-direita
      final pathTopLeft = Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(pathTopLeft, Paint()..color = colors[0]);
      final pathBottomRight = Path()
        ..moveTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(pathBottomRight, Paint()..color = colors[1]);
      return;
    }
    // 3+ cores: fatias angulares a partir do centro (fracionamento em leque)
    final cx = size.width / 2;
    final cy = size.height / 2;
    final n = colors.length;
    const startAngle = -math.pi / 2; // topo (-90Â°)
    for (var i = 0; i < n; i++) {
      final angle1 = startAngle + (i * 2 * math.pi / n);
      final angle2 = startAngle + ((i + 1) * 2 * math.pi / n);
      final p1 = _rayRectIntersection(cx, cy, angle1, size.width, size.height);
      final p2 = _rayRectIntersection(cx, cy, angle2, size.width, size.height);
      final path = Path()
        ..moveTo(cx, cy)
        ..lineTo(cx + p1.dx, cy + p1.dy)
        ..lineTo(cx + p2.dx, cy + p2.dy)
        ..close();
      canvas.save();
      canvas.clipRect(Offset.zero & size);
      canvas.drawPath(path, Paint()..color = colors[i]);
      canvas.restore();
    }
  }

  /// InterseÃ§Ã£o do raio (centro cx,cy + Ã¢ngulo) com a borda do retÃ¢ngulo [0,w]x[0,h].
  Offset _rayRectIntersection(
      double cx, double cy, double angle, double w, double h) {
    final dx = math.cos(angle);
    final dy = math.sin(angle);
    double t = double.infinity;
    if (dx > 1e-6) {
      final tRight = (w - cx) / dx;
      if (tRight > 0 && (cy + tRight * dy) >= 0 && (cy + tRight * dy) <= h)
        t = math.min(t, tRight);
    }
    if (dx < -1e-6) {
      final tLeft = -cx / dx;
      if (tLeft > 0 && (cy + tLeft * dy) >= 0 && (cy + tLeft * dy) <= h)
        t = math.min(t, tLeft);
    }
    if (dy > 1e-6) {
      final tBottom = (h - cy) / dy;
      if (tBottom > 0 && (cx + tBottom * dx) >= 0 && (cx + tBottom * dx) <= w)
        t = math.min(t, tBottom);
    }
    if (dy < -1e-6) {
      final tTop = -cy / dy;
      if (tTop > 0 && (cx + tTop * dx) >= 0 && (cx + tTop * dx) <= w)
        t = math.min(t, tTop);
    }
    if (t == double.infinity || t <= 0) t = 1;
    return Offset(dx * t, dy * t);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
