import 'dart:async';

import 'package:flutter/material.dart' hide showDatePicker;
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import '../models/user_profile.dart';
import '../models/shift_location.dart';
import '../models/scale_rates_period.dart';
import '../services/scale_rates_period_service.dart';
import '../services/scale_rates_cache_notifier.dart';
import '../services/scale_rates_service.dart';
import '../constants/date_time_formats.dart';
import '../constants/currency_formats.dart';
import '../theme/gemini_theme.dart';
import '../theme/app_colors.dart';
import '../utils/premium_upgrade.dart';
import '../widgets/multi_date_month_picker_dialog.dart' as ct_picker;
import '../widgets/selecao_plantao_sheet.dart';
import 'locations_screen.dart';
import '../utils/date_picker_a11y.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/keyboard_form_scaffold.dart';
import '../utils/home_shell_layout.dart';

/// Estilo numérico legível em Android/iOS Safari: tabular figures, negrito.
const _numericStyle = TextStyle(
  fontFeatures: [FontFeature.tabularFigures()],
  fontWeight: FontWeight.w800,
);

/// Espaçamento e bordas Clean Premium (PADRAO_VISUAL_CLEAN_PREMIUM.md).
const _kPaddingScreen = 16.0;
const _kPaddingCard = 20.0;
const _kRadiusCard = 20.0;
const _kShadowBlur = 10.0;
const _kShadowOffset = 4.0;

class CalculatorScreen extends StatefulWidget {
  final String uid;
  final UserProfile profile;
  final VoidCallback? onIncluirPlantao;
  final void Function(int index)? onNavigateTo;

  const CalculatorScreen({super.key, required this.uid, required this.profile, this.onIncluirPlantao, this.onNavigateTo});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  double _resultadoTotal = 0.0;
  Map<String, double>? _resumoPeriodo;
  DateTime _dataInicial = DateTime.now();
  DateTime _dataFinal = DateTime.now();
  TimeOfDay _horaInicial = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _horaFinal = const TimeOfDay(hour: 18, minute: 0);
  bool _usaPeriodo = true;
  /// Plantões pré-cadastrados (Configurações / Locais) para "Lançar Plantão".
  List<ShiftLocation> _locations = [];
  Timer? _salvarCalculoDebounce;
  Timer? _ratesInvalidateDebounce;
  StreamSubscription<fa.User?>? _authUidSub;
  /// Evita que uma leitura antiga de taxas sobrescreva o valor após mudança rápida de data/hora.
  int _ratesLoadGen = 0;

  /// Apenas ano/mes/dia — mantem o deslocamento em dias entre inicio e fim ao mudar a primeira data manualmente.
  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Ao escolher nova data inicial (calendario), a data final acompanha com o mesmo numero de dias corridos.
  /// O preset "24 horas" continua a definir as duas datas de uma vez em [_aplicarPresetHoras] — sem mudanca aqui.
  void _syncEndDateToNewStartDate(DateTime novaInicial) {
    final startOld = _dateOnly(_dataInicial);
    final endOld = _dateOnly(_dataFinal);
    var deltaDias = endOld.difference(startOld).inDays;
    if (deltaDias < 0) deltaDias = 0;
    final startNew = _dateOnly(novaInicial);
    _dataInicial = startNew;
    _dataFinal = startNew.add(Duration(days: deltaDias));
  }

  /// Total de horas entre data/hora inicial e data/hora final (para modo período).
  double get _horasDoPeriodo {
    final inicio = DateTime(_dataInicial.year, _dataInicial.month, _dataInicial.day, _horaInicial.hour, _horaInicial.minute);
    var fim = DateTime(_dataFinal.year, _dataFinal.month, _dataFinal.day, _horaFinal.hour, _horaFinal.minute);
    if (fim.isBefore(inicio) || fim.isAtSameMomentAs(inicio)) fim = fim.add(const Duration(days: 1));
    return fim.difference(inicio).inMinutes / 60.0;
  }

  Future<void> _atualizarHorasDoPeriodo() async {
    if (!_usaPeriodo) return;
    final gen = ++_ratesLoadGen;
    final inicio = DateTime(_dataInicial.year, _dataInicial.month, _dataInicial.day, _horaInicial.hour, _horaInicial.minute);
    var fim = DateTime(_dataFinal.year, _dataFinal.month, _dataFinal.day, _horaFinal.hour, _horaFinal.minute);
    if (fim.isBefore(inicio) || fim.isAtSameMomentAs(inicio)) fim = fim.add(const Duration(days: 1));

    void commit(Map<String, double> res) {
      if (!mounted || gen != _ratesLoadGen) return;
      setState(() {
        _resultadoTotal = res['total'] ?? 0.0;
        _resumoPeriodo = res;
      });
      _salvarCalculoDebounce?.cancel();
      _salvarCalculoDebounce = Timer(const Duration(seconds: 2), () {
        if (!mounted || _resumoPeriodo == null || gen != _ratesLoadGen) return;
        _salvarCalculoNoBanco(_resumoPeriodo!);
      });
    }

    try {
      final uid = firestoreUserDocIdForAppShell(widget.uid);
      if (uid.isEmpty) {
        commit(ScaleRatesPeriodService().computeShift(start: inicio, end: fim));
      } else {
        final res = await ScaleRatesService().computeShiftForUid(
          uid: uid,
          start: inicio,
          end: fim,
          entryDate: _dataInicial,
        );
        commit(res);
      }
    } catch (e, st) {
      debugPrint('Calculadora: taxas Firestore / cálculo: $e\n$st');
      commit(ScaleRatesPeriodService().computeShift(start: inicio, end: fim));
    }
  }

  /// Grava o período e valor no Firestore (usa parâmetros de Configurações).
  Future<void> _salvarCalculoNoBanco(Map<String, double> res) async {
    if (!_usaPeriodo) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(firestoreUserDocIdForAppShell(widget.uid))
          .collection('calculator_entries')
          .add({
        'dateStart': DateTimeFormats.dateBR.format(_dataInicial),
        'dateEnd': DateTimeFormats.dateBR.format(_dataFinal),
        'timeStart': DateTimeFormats.formatTime(_horaInicial.hour, _horaInicial.minute),
        'timeEnd': DateTimeFormats.formatTime(_horaFinal.hour, _horaFinal.minute),
        'totalValue': res['total'] ?? 0.0,
        'hoursDay': res['hoursDay'] ?? 0.0,
        'hoursNight': res['hoursNight'] ?? 0.0,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    ScaleRatesCacheNotifier.instance.addListener(_onRatesCacheInvalidated);
    _authUidSub = fa.FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted) setState(() {});
    });
    if (_usaPeriodo) _atualizarHorasDoPeriodo();
    _loadLocations();
  }

  void _onRatesCacheInvalidated() {
    final nUid = ScaleRatesCacheNotifier.instance.lastUid;
    final myUid = firestoreUserDocIdForAppShell(widget.uid);
    if (nUid != null && nUid.isNotEmpty && nUid != myUid) return;
    _ratesInvalidateDebounce?.cancel();
    _ratesInvalidateDebounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) _atualizarHorasDoPeriodo();
    });
  }

  @override
  void dispose() {
    ScaleRatesCacheNotifier.instance.removeListener(_onRatesCacheInvalidated);
    _authUidSub?.cancel();
    _ratesInvalidateDebounce?.cancel();
    _salvarCalculoDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadLocations() async {
    try {
      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(firestoreUserDocIdForAppShell(widget.uid))
          .collection('locations');
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await ref.get(const GetOptions(source: Source.cache));
        if (snap.docs.isEmpty) {
          snap = await ref.get();
        }
      } catch (_) {
        snap = await ref.get();
      }
      if (!mounted) return;
      final list = snap.docs
          .map((d) => ShiftLocation.fromMap(d.id, d.data()))
          .where((l) => l.name.isNotEmpty || l.abbreviation.isNotEmpty)
          .toList();
      list.sort((a, b) => a.name.compareTo(b.name));
      setState(() => _locations = list);
    } catch (_) {}
  }

  /// Abre fluxo: escolher data → escolher pré-cadastrado ou cadastrar novo → lança na Escala.
  Future<void> _abrirLancarPlantao() async {
    final picked = DateTime(_dataInicial.year, _dataInicial.month, _dataInicial.day);
    await _loadLocations();
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => SelecaoPlantaoSheet(
          uid: firestoreUserDocIdForAppShell(widget.uid),
          day: picked,
          locations: _locations,
          trocar: false,
          entriesExistentes: const [],
          onSalvar: () => setState(() {}),
          onCriarNovo: () {
            Navigator.pop(ctx);
            Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => LocationsScreen(uid: firestoreUserDocIdForAppShell(widget.uid)),
                ),
            ).then((_) {
              if (mounted) _loadLocations();
            });
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 720;
    final embeddedInShell = widget.onNavigateTo != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      resizeToAvoidBottomInset: scaffoldKeyboardResizeToAvoidBottomInset(
        embeddedInHomeShell: embeddedInShell,
      ),
      body: keyboardScaffoldBody(
        SafeArea(
          bottom: homeShellSafeAreaBottom(embeddedInHomeShell: embeddedInShell),
          child: RepaintBoundary(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                isNarrow ? _kPaddingScreen : 24,
                isNarrow ? 6 : 4,
                isNarrow ? _kPaddingScreen : 24,
                homeShellScrollBottomPadding(
                  context,
                  embeddedInHomeShell: embeddedInShell,
                  tail: 12,
                ),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPeriodoDataHora(),
                      if (_usaPeriodo && _resumoPeriodo != null) ...[
                        const SizedBox(height: 20),
                        _buildResumoPeriodoCard(),
                      ],
                      const SizedBox(height: 20),
                      _buildDisplayResultado(),
                      const SizedBox(height: 20),
                      _buildBotaoLancarPlantao(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        embeddedInHomeShell: widget.onNavigateTo != null,
      ),
    );
  }

  /// Card destacado com resumo: total horas diurnas + valor, total horas noturnas + valor, valor total.
  /// Clean Premium: bordas 20, sombra sutil, valores em destaque (pill + tabular figures).
  Widget _buildResumoPeriodoCard() {
    final r = _resumoPeriodo!;
    final hDay = r['hoursDay'] ?? 0.0;
    final hNight = r['hoursNight'] ?? 0.0;
    final vDay = r['dayValue'] ?? 0.0;
    final vNight = r['nightValue'] ?? 0.0;
    final total = r['total'] ?? 0.0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(_kPaddingCard),
      decoration: BoxDecoration(
        color: GeminiTheme.surface,
        borderRadius: BorderRadius.circular(_kRadiusCard),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(color: AppColors.deepBlueDark.withValues(alpha: 0.08), blurRadius: 18, offset: const Offset(0, 8)),
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: _kShadowBlur, offset: const Offset(0, _kShadowOffset)),
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
                  color: AppColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.insights_rounded, color: AppColors.primary.withValues(alpha: 0.95), size: 24),
              ),
              const SizedBox(width: 12),
              const Text('Resumo do período', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: GeminiTheme.textPrimary)),
            ],
          ),
          const SizedBox(height: 20),
          _resumoRow('Total de horas diurnas', hDay, vDay),
          const SizedBox(height: 16),
          _resumoRow('Total de horas noturnas', hNight, vNight),
          const Divider(height: 28),
          const Text('Valor total',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: GeminiTheme.textPrimary),
              softWrap: true),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: _valuePill(CurrencyFormats.formatBRLTight(total),
                  fontSize: 20, color: GeminiTheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  /// Linha do resumo automático (zoom acessível): evita [Row] sem flex que corta valores à direita.
  Widget _linhaResumoAutomatico(String label, String valorLine, double fontSize) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: GeminiTheme.textSecondary),
          softWrap: true,
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            valorLine,
            style: _numericStyle.copyWith(
                fontSize: fontSize, color: GeminiTheme.textPrimary),
            maxLines: 1,
          ),
        ),
      ],
    );
  }

  /// Pill com valor em destaque: bordas arredondadas, numérico legível (Android/iOS Safari).
  Widget _valuePill(String text, {required double fontSize, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: _numericStyle.copyWith(fontSize: fontSize, color: color),
      ),
    );
  }

  Widget _resumoRow(String label, double horas, double valor) {
    final valueText =
        '${horas.toStringAsFixed(1)} h → ${CurrencyFormats.formatBRLTight(valor)}';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: GeminiTheme.textSecondary)),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: _valuePill(valueText, fontSize: 15, color: GeminiTheme.textPrimary),
          ),
        ),
      ],
    );
  }

  /// Resumo automático: horas diurna/noturna e valor (parâmetros de Configurações). Números legíveis (tabular figures).
  Widget _buildResumoAutomatico() {
    final r = _resumoPeriodo;
    if (r == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: GeminiTheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Total de horas', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: GeminiTheme.textSecondary)),
            Text('${_horasDoPeriodo.toStringAsFixed(1)} h', style: _numericStyle.copyWith(fontSize: 18, color: GeminiTheme.primary)),
          ],
        ),
      );
    }
    final hDay = r['hoursDay'] ?? 0.0;
    final hNight = r['hoursNight'] ?? 0.0;
    final vDay = r['dayValue'] ?? 0.0;
    final vNight = r['nightValue'] ?? 0.0;
    final total = r['total'] ?? 0.0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GeminiTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GeminiTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _linhaResumoAutomatico(
              'Horas diurnas',
              '${hDay.toStringAsFixed(1)} h → ${CurrencyFormats.formatBRLTight(vDay)}',
              14),
          const SizedBox(height: 10),
          _linhaResumoAutomatico(
              'Horas noturnas',
              '${hNight.toStringAsFixed(1)} h → ${CurrencyFormats.formatBRLTight(vNight)}',
              14),
          const Divider(height: 20),
          Text(
            'Valor total do serviço',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            softWrap: true,
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              CurrencyFormats.formatBRLTight(total),
              style: _numericStyle.copyWith(fontSize: 18, color: GeminiTheme.primary),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  /// Período: data inicial, data final, hora inicial, hora final — o sistema calcula o total de horas.
  /// Clean Premium: radius 20, sombra sutil.
  Widget _buildPeriodoDataHora() {
    return Container(
      padding: const EdgeInsets.all(_kPaddingCard),
      decoration: BoxDecoration(
        color: GeminiTheme.surface,
        borderRadius: BorderRadius.circular(_kRadiusCard),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(color: AppColors.deepBlueDark.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 6)),
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: _kShadowBlur, offset: const Offset(0, _kShadowOffset)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary.withValues(alpha: 0.12), AppColors.accent.withValues(alpha: 0.1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.edit_calendar_rounded, color: AppColors.primary.withValues(alpha: 0.95), size: 24),
              ),
              const SizedBox(width: 14),
              const Text('Período', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: GeminiTheme.textPrimary)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Toque em uma duração ou defina data e hora: o valor é atualizado automaticamente.',
            style: TextStyle(fontSize: 13, color: GeminiTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: _usaPeriodo,
            onChanged: (v) {
              setState(() => _usaPeriodo = v);
              if (v) unawaited(_atualizarHorasDoPeriodo());
            },
            title: const Text('Usar data e hora inicial/final'),
            contentPadding: EdgeInsets.zero,
          ),
          if (_usaPeriodo) ...[
            const SizedBox(height: 12),
            _buildPresetsPeriodo(),
            const SizedBox(height: 8),
            Text(
              'Datas e horários podem ser retroativos ou futuros. O valor é calculado conforme o dia e horário escolhidos.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (_, bc) {
                final stack = bc.maxWidth < 380;
                if (stack) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final d = await ct_picker.pickSingleDateWithHolidayCalendar(context: context, initialDate: _dataInicial, firstDate: DateTime(2020), lastDate: DateTime(2030));
                          if (d != null) {
                            setState(() => _syncEndDateToNewStartDate(d));
                            _atualizarHorasDoPeriodo();
                          }
                        },
                        icon: const Icon(Icons.calendar_today_rounded, size: 18),
                        label: Text(DateTimeFormats.dateBR.format(_dataInicial)),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final t = await showTimePicker(context: context, initialTime: _horaInicial);
                          if (t != null) {
                            setState(() => _horaInicial = t);
                            unawaited(_atualizarHorasDoPeriodo());
                          }
                        },
                        icon: const Icon(Icons.access_time_rounded, size: 18),
                        label: Text(DateTimeFormats.formatTime(_horaInicial.hour, _horaInicial.minute)),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final d = await ct_picker.pickSingleDateWithHolidayCalendar(context: context, initialDate: _dataFinal, firstDate: DateTime(2020), lastDate: DateTime(2030));
                          if (d != null) {
                            setState(() => _dataFinal = d);
                            unawaited(_atualizarHorasDoPeriodo());
                          }
                        },
                        icon: const Icon(Icons.calendar_today_rounded, size: 18),
                        label: Text(DateTimeFormats.dateBR.format(_dataFinal)),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final t = await showTimePicker(context: context, initialTime: _horaFinal);
                          if (t != null) {
                            setState(() => _horaFinal = t);
                            unawaited(_atualizarHorasDoPeriodo());
                          }
                        },
                        icon: const Icon(Icons.access_time_rounded, size: 18),
                        label: Text(DateTimeFormats.formatTime(_horaFinal.hour, _horaFinal.minute)),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final d = await ct_picker.pickSingleDateWithHolidayCalendar(context: context, initialDate: _dataInicial, firstDate: DateTime(2020), lastDate: DateTime(2030));
                              if (d != null) {
                                setState(() => _syncEndDateToNewStartDate(d));
                                _atualizarHorasDoPeriodo();
                              }
                            },
                            icon: const Icon(Icons.calendar_today_rounded, size: 16),
                            label: Text(DateTimeFormats.dateBR.format(_dataInicial), style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final t = await showTimePicker(context: context, initialTime: _horaInicial);
                              if (t != null) {
                            setState(() => _horaInicial = t);
                            unawaited(_atualizarHorasDoPeriodo());
                          }
                            },
                            icon: const Icon(Icons.access_time_rounded, size: 16),
                            label: Text(DateTimeFormats.formatTime(_horaInicial.hour, _horaInicial.minute), style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final d = await ct_picker.pickSingleDateWithHolidayCalendar(context: context, initialDate: _dataFinal, firstDate: DateTime(2020), lastDate: DateTime(2030));
                              if (d != null) {
                            setState(() => _dataFinal = d);
                            unawaited(_atualizarHorasDoPeriodo());
                          }
                            },
                            icon: const Icon(Icons.calendar_today_rounded, size: 16),
                            label: Text(DateTimeFormats.dateBR.format(_dataFinal), style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final t = await showTimePicker(context: context, initialTime: _horaFinal);
                              if (t != null) {
                            setState(() => _horaFinal = t);
                            unawaited(_atualizarHorasDoPeriodo());
                          }
                            },
                            icon: const Icon(Icons.access_time_rounded, size: 16),
                            label: Text(DateTimeFormats.formatTime(_horaFinal.hour, _horaFinal.minute), style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            _buildResumoAutomatico(),
          ],
        ],
      ),
    );
  }

  void _aplicarPresetHoras(int horas) {
    final hoje = DateTime.now();
    if (horas >= 24) {
      final amanha = hoje.add(const Duration(days: 1));
      setState(() {
        _dataInicial = hoje;
        _dataFinal = amanha;
        _horaInicial = const TimeOfDay(hour: 8, minute: 0);
        _horaFinal = const TimeOfDay(hour: 8, minute: 0);
      });
    } else {
      final endHour = 8 + horas;
      setState(() {
        _dataInicial = hoje;
        _dataFinal = hoje;
        _horaInicial = const TimeOfDay(hour: 8, minute: 0);
        _horaFinal = TimeOfDay(hour: endHour.clamp(0, 23), minute: 0);
      });
    }
    _atualizarHorasDoPeriodo();
  }

  /// Presets rápidos: 1h a 6h, Hoje 8h–18h, 12h, 24 horas — layout moderno em grid.
  Widget _buildPresetsPeriodo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.flash_on_rounded, size: 16, color: AppColors.logoOrange.withValues(alpha: 0.95)),
            const SizedBox(width: 6),
            Text(
              'Duração rápida',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: GeminiTheme.textSecondary, letterSpacing: 0.3),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [1, 2, 3, 4, 5, 6].map((h) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: h < 6 ? 8 : 0),
                child: _presetChipCompact('${h}h', () => _aplicarPresetHoras(h)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(Icons.work_history_rounded, size: 16, color: AppColors.primary.withValues(alpha: 0.85)),
            const SizedBox(width: 6),
            Text(
              'Plantão',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: GeminiTheme.textSecondary, letterSpacing: 0.3),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _presetChip('Hoje 8h–18h', _aplicarPresetHoje8a18),
            _presetChip('12h', () => _aplicarPresetHoras(12)),
            _presetChip('24 horas', () => _aplicarPresetHoras(24)),
          ],
        ),
      ],
    );
  }

  void _aplicarPresetHoje8a18() {
    final hoje = DateTime.now();
    setState(() {
      _dataInicial = hoje;
      _dataFinal = hoje;
      _horaInicial = const TimeOfDay(hour: 8, minute: 0);
      _horaFinal = const TimeOfDay(hour: 18, minute: 0);
    });
    _atualizarHorasDoPeriodo();
  }

  Widget _presetChip(String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
            boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_available_rounded, size: 18, color: AppColors.primary.withValues(alpha: 0.95)),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _presetChipCompact(String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary.withValues(alpha: 0.06), AppColors.accent.withValues(alpha: 0.06)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Center(
            child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary.withValues(alpha: 0.92))),
          ),
        ),
      ),
    );
  }

  /// Card VALOR ESTIMADO: gradiente Clean Premium (logo), número legível (tabular figures, tamanho responsivo).
  Widget _buildDisplayResultado() {
    final valorStr = CurrencyFormats.formatBRL(_resultadoTotal);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_kRadiusCard),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.logoGradient,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(color: AppColors.deepBlueDark.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 10)),
          BoxShadow(color: AppColors.accent.withValues(alpha: 0.2), blurRadius: 12, offset: const Offset(0, 4)),
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: _kShadowBlur, offset: const Offset(0, _kShadowOffset)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.payments_rounded, color: Colors.white.withValues(alpha: 0.95), size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'VALOR ESTIMADO',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.92), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.8),
                  ),
                ],
              ),
              Material(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: valorStr));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$valorStr copiado'), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy_all_rounded, size: 18, color: Colors.white.withValues(alpha: 0.96)),
                        const SizedBox(width: 6),
                        Text('Copiar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.96))),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (_, bc) {
              final width = bc.maxWidth;
              final fontSize = width < 320 ? 28.0 : (width < 400 ? 34.0 : 40.0);
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  );
                },
                child: Text(
                  valorStr,
                  key: ValueKey<String>(valorStr),
                  style: _numericStyle.copyWith(
                    color: Colors.white,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              );
            },
          ),
          if (_usaPeriodo) ...[
            const SizedBox(height: 8),
            Text(
              'Parâmetros de Configurações • atualizado conforme data e hora',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBotaoLancarPlantao() {
    final onTap = widget.profile.hasActiveLicense
        ? () {
            if (widget.onIncluirPlantao != null) {
              widget.onIncluirPlantao!();
            } else {
              _abrirLancarPlantao();
            }
          }
        : () => mostrarAvisoSeLicencaInativa(context, widget.profile);
    return Semantics(
      label: 'Incluir plantão',
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: AppColors.deepBlueDark.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 7)),
            BoxShadow(color: AppColors.accent.withValues(alpha: 0.18), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.deepBlueDark, AppColors.primary, AppColors.accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.post_add_rounded, color: Colors.white, size: 24),
                    const SizedBox(width: 10),
                    const Text(
                      'Incluir plantão',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

}
