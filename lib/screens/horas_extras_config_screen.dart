import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/currency_formats.dart';
import '../models/clt_labor_config.dart';
import '../models/controle_total_config.dart';
import '../models/scale_rates.dart';
import '../models/scale_rates_period.dart';
import '../services/auth_service.dart';
import '../services/clt_labor_config_service.dart';
import '../services/controle_total_config_service.dart';
import '../services/scale_rates_period_service.dart';
import '../services/scale_rates_service.dart';
import '../services/user_scale_rates_period_service.dart';
import '../constants/date_time_formats.dart';
import '../theme/app_colors.dart';
import '../widgets/admin_scale_rates_period_editor_page.dart';
import '../widgets/brl_amount_text_field.dart';
import '../widgets/fast_text_field.dart';
import '../widgets/horas_extras_source_tab_bar.dart';
import '../widgets/scale_rates_timeline_strip.dart';

/// Configuração de horas extras / banco de horas: Goiás (padrão), CLT ou personalizado.
class HorasExtrasConfigScreen extends StatefulWidget {
  final String uid;

  const HorasExtrasConfigScreen({super.key, required this.uid});

  @override
  State<HorasExtrasConfigScreen> createState() =>
      _HorasExtrasConfigScreenState();
}

class _HorasExtrasConfigScreenState extends State<HorasExtrasConfigScreen>
    with SingleTickerProviderStateMixin {
  static const _weekdayLabels = [
    'Dom',
    'Seg',
    'Ter',
    'Qua',
    'Qui',
    'Sex',
    'Sáb',
  ];

  late TabController _tabController;
  late List<TextEditingController> _diurnoControllers;
  late List<TextEditingController> _noturnoControllers;
  final _bonusPercentCtrl = TextEditingController(text: '0');
  final _bonusPerHourCtrl = TextEditingController(text: '0');
  final _tetoHorasCtrl = TextEditingController(text: '192');
  final _salaryCtrl = TextEditingController();
  final _monthlyHoursCtrl = TextEditingController(text: '220');
  final _fixedHourCtrl = TextEditingController(text: '0');

  String _hoursSource = ControleTotalConfig.hoursSourceGlobalGoias;
  String _serverType = ControleTotalConfig.serverTypeEstadual;
  CltLaborConfig _cltConfig = CltLaborConfig.defaults();
  List<ScaleRatesPeriod> _userPeriods = [];
  bool _loading = true;
  bool _saving = false;
  bool _showRetryBanner = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabControllerTick);
    _diurnoControllers = List.generate(7, (_) => TextEditingController());
    _noturnoControllers = List.generate(7, (_) => TextEditingController());
    _load();
  }

  void _onTabControllerTick() {
    if (!_tabController.indexIsChanging) {
      _onTabChanged();
    } else {
      setState(() {});
    }
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {
      final source = switch (_tabController.index) {
        0 => ControleTotalConfig.hoursSourceGlobalGoias,
        1 => ControleTotalConfig.hoursSourceClt,
        _ => ControleTotalConfig.hoursSourcePersonal,
      };
      _hoursSource = source;
    });
  }

  void _setBrl(TextEditingController c, double value) {
    c.text = CurrencyFormats.formatBRLInput(value);
  }

  double _parseBrl(TextEditingController c, [double def = 0]) =>
      CurrencyFormats.parseBRLInput(c.text) ?? def;

  void _syncTabFromSource() {
    final idx = switch (_hoursSource) {
      ControleTotalConfig.hoursSourceClt => 1,
      ControleTotalConfig.hoursSourcePersonal => 2,
      _ => 0,
    };
    if (_tabController.index != idx) {
      _tabController.index = idx;
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabControllerTick);
    _tabController.dispose();
    for (final c in _diurnoControllers) {
      c.dispose();
    }
    for (final c in _noturnoControllers) {
      c.dispose();
    }
    _bonusPercentCtrl.dispose();
    _bonusPerHourCtrl.dispose();
    _tetoHorasCtrl.dispose();
    _salaryCtrl.dispose();
    _monthlyHoursCtrl.dispose();
    _fixedHourCtrl.dispose();
    super.dispose();
  }

  void _applyCltToControllers(CltLaborConfig cfg) {
    _cltConfig = cfg;
    _setBrl(_salaryCtrl, cfg.monthlySalary);
    _monthlyHoursCtrl.text = cfg.monthlyHours.toString();
    _setBrl(_fixedHourCtrl, cfg.fixedHourOverride > 0 ? cfg.fixedHourOverride : 0);
  }

  CltLaborConfig _cltFromControllers() {
    return _cltConfig.copyWith(
      monthlySalary: _parseBrl(_salaryCtrl, _cltConfig.monthlySalary),
      monthlyHours:
          int.tryParse(_monthlyHoursCtrl.text) ?? _cltConfig.monthlyHours,
      fixedHourOverride: _parseBrl(_fixedHourCtrl, 0),
    );
  }

  Future<void> _retryAfterRefresh() async {
    setState(() => _loading = true);
    await AuthService().refreshToken();
    _showRetryBanner = false;
    await _load();
  }

  Future<void> _load() async {
    try {
      final config = await ControleTotalConfigService()
          .getConfig(widget.uid)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException(
              'Configuração demorou para carregar. Tente novamente.',
            ),
          );
      final rates = await ScaleRatesService()
          .getRates(uid: widget.uid)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () =>
                throw TimeoutException('Valores de escala demoraram para carregar.'),
          );
      final clt = await CltLaborConfigService().getConfig(widget.uid);
      final periods = await UserScaleRatesPeriodService().getPeriods(widget.uid);
      if (!mounted) return;
      setState(() {
        _hoursSource = config.hoursSource;
        _serverType = config.serverType;
        _bonusPercentCtrl.text = config.companyBonusPercent.toStringAsFixed(0);
        _setBrl(_bonusPerHourCtrl, config.companyBonusFixedPerHour);
        _tetoHorasCtrl.text = (config.tetoHorasMensal > 0
                ? config.tetoHorasMensal
                : ControleTotalConfig.tetoHorasMensalPadrao)
            .toStringAsFixed(0);
        for (int i = 0; i < 7; i++) {
          _setBrl(_diurnoControllers[i], rates.valueDiurno[i]);
          _setBrl(_noturnoControllers[i], rates.valueNoturno[i]);
        }
        _applyCltToControllers(clt);
        _userPeriods = periods;
        _loading = false;
      });
      _syncTabFromSource();
    } catch (e) {
      if (!mounted) return;
      final msg = e is TimeoutException ? e.message! : e.toString();
      final isPermissionDenied = msg.contains('permission-denied');
      setState(() {
        _loading = false;
        _showRetryBanner = isPermissionDenied;
      });
      if (mounted && !isPermissionDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar: $msg'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  ScaleRates _ratesFromControllers() {
    return ScaleRates(
      valueDiurno: _diurnoControllers.map((c) => _parseBrl(c)).toList(),
      valueNoturno: _noturnoControllers.map((c) => _parseBrl(c)).toList(),
    );
  }

  void _applyGoiasDefaultsToPersonal() {
    final def = ScaleRates.defaultRates;
    for (int i = 0; i < 7; i++) {
      _setBrl(_diurnoControllers[i], def.valueDiurno[i]);
      _setBrl(_noturnoControllers[i], def.valueNoturno[i]);
    }
    setState(() {});
  }

  void _activateCltDefaults() {
    setState(() {
      _hoursSource = ControleTotalConfig.hoursSourceClt;
      _applyCltToControllers(CltLaborConfig.defaults());
    });
    _tabController.animateTo(1);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Padrão CLT aplicado. Ajuste salário ou hora fixa e toque em Salvar.',
        ),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _openUserPeriodEditor({ScaleRatesPeriod? existing}) async {
    final period = await Navigator.of(context).push<ScaleRatesPeriod>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AdminScaleRatesPeriodEditorPage(
          existing: existing,
          brandBlue: AppColors.deepBlue,
          brandTeal: AppColors.accent,
        ),
      ),
    );
    if (period == null || !mounted) return;
    final list = List<ScaleRatesPeriod>.from(_userPeriods);
    final idx = list.indexWhere((p) => p.id == period.id);
    if (idx >= 0) {
      list[idx] = period;
    } else {
      list.add(period);
    }
    setState(() => _userPeriods = ScaleRatesPeriod.sortAsc(list));
    try {
      await UserScaleRatesPeriodService().savePeriods(widget.uid, _userPeriods);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              period.effectiveFrom.isAfter(DateTime.now())
                  ? 'Período agendado para ${DateTimeFormats.formatDateTimeSeconds(period.effectiveFrom)}.'
                  : 'Período salvo na sua linha do tempo.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar período: $e')),
        );
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final tetoHoras =
          double.tryParse(_tetoHorasCtrl.text.replaceAll(',', '.')) ??
              ControleTotalConfig.tetoHorasMensalPadrao;
      final config = ControleTotalConfig(
        hoursSource: _hoursSource,
        serverType: _serverType,
        companyBonusPercent:
            double.tryParse(_bonusPercentCtrl.text.replaceAll(',', '.')) ?? 0,
        companyBonusFixedPerHour: _parseBrl(_bonusPerHourCtrl),
        tetoHorasMensal: tetoHoras.clamp(1.0, 400.0),
      );
      await ControleTotalConfigService().setConfig(widget.uid, config);

      if (_hoursSource == ControleTotalConfig.hoursSourcePersonal) {
        await ScaleRatesService().setUserRates(widget.uid, _ratesFromControllers());
        if (_userPeriods.isNotEmpty) {
          await UserScaleRatesPeriodService()
              .savePeriods(widget.uid, _userPeriods);
        }
      } else if (_hoursSource == ControleTotalConfig.hoursSourceClt) {
        await CltLaborConfigService()
            .setConfig(widget.uid, _cltFromControllers());
      }

      ScaleRatesService().invalidateMemory(widget.uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Configuração salva. Calculadora e plantões usam os novos valores.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _tetoCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Teto de horas mensais',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Usado nas previsões (Meta) e nos alertas de Escalas. Padrão GO: 192 h.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            FastTextField(
              controller: _tetoHorasCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              decoration: const InputDecoration(
                labelText: 'Teto (horas/mês)',
                hintText: '192',
                suffixText: 'h',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _goiasTab() {
    return StreamBuilder<List<ScaleRatesPeriod>>(
      stream: ScaleRatesPeriodService().watchPeriods(),
      builder: (context, snap) {
        final periods =
            snap.data ?? ScaleRatesPeriodRegistry.bootstrapPeriods();
        final sorted = ScaleRatesPeriod.sortAsc(periods);
        final active = ScaleRatesPeriod.resolveAt(DateTime.now(), sorted);
        final rates = active?.rates ?? ScaleRates.defaultRates;

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.deepBlue,
                    AppColors.accent,
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.flag_rounded, color: Colors.white),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Padrão Estado de Goiás (AC4)',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Tabela oficial com histórico de reajustes. O sistema aplica automaticamente o período vigente na data do plantão.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ScaleRatesTimelineStrip(
              periods: sorted,
              title: 'Linha do tempo — tabelas GO',
              readOnly: true,
            ),
            const SizedBox(height: 16),
            if (active != null)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFDCFCE7),
                      const Color(0xFFECFDF5),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.35)),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Vigente agora: ${active.label}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Dom diurno ${CurrencyFormats.formatBRL(rates.valueDiurno[0])}/h · '
                      'noturno ${CurrencyFormats.formatBRL(rates.valueNoturno[0])}/h',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            _tetoCard(),
          ],
        );
      },
    );
  }

  Widget _cltPreviewRow(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(
            '${CurrencyFormats.formatBRL(value)}/h',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _cltTab() {
    final cfg = _cltFromControllers();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Material(
          elevation: 0,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: _activateCltDefaults,
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF059669), Color(0xFF10B981), Color(0xFF34D399)],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                child: Row(
                  children: [
                    Icon(Icons.gavel_rounded, color: Colors.white, size: 28),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ativar padrão sistema CLT',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'HE 50% dias úteis · 100% dom/feriado · noturno +20% · hora 52min30',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.touch_app_rounded, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Base de cálculo',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 12),
                BrlAmountTextField(
                  controller: _salaryCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Salário bruto mensal',
                    prefixText: 'R\$ ',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFFF8FAFC),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                FastTextField(
                  controller: _monthlyHoursCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: false),
                  decoration: const InputDecoration(
                    labelText: 'Horas mensais contratadas',
                    hintText: '220 (44h/sem) ou 180 (36h/sem)',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFFF8FAFC),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                BrlAmountTextField(
                  controller: _fixedHourCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ou valor fixo da hora cheia',
                    prefixText: 'R\$ ',
                    hintText: '0,00 = calcular pelo salário',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFFF8FAFC),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Regras legais (pré-configuradas)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 8),
                _ruleChip('HE dias úteis e sábado', '+${cfg.overtimeWeekdayPercent.toStringAsFixed(0)}%'),
                _ruleChip('HE domingo e feriado', '+${cfg.overtimeSundayHolidayPercent.toStringAsFixed(0)}%'),
                _ruleChip('Adicional noturno (22h–5h)', '+${cfg.nightAdditionalPercent.toStringAsFixed(0)}%'),
                _ruleChip('Hora noturna reduzida', cfg.nightHourReduced ? '52min30s' : '60min'),
                _ruleChip('Prorrogação após 5h (Súmula 60)', cfg.extendNightAfter5am ? 'Sim' : 'Não'),
                _ruleChip('Limite HE por dia (CLT art. 59)', '${cfg.maxDailyOvertimeHours}h'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          color: const Color(0xFFF0FDF4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Valores calculados',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 8),
                _cltPreviewRow('Hora normal', cfg.hourNormal),
                _cltPreviewRow('Hora noturna (+20%)', cfg.hourWithNightAdditional),
                _cltPreviewRow('HE dia útil (+50%)', cfg.hourOvertimeWeekday),
                _cltPreviewRow('HE dom/feriado (+100%)', cfg.hourOvertimeSundayHoliday),
                _cltPreviewRow('HE noturna (cascata)', cfg.hourOvertimeNight),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _tetoCard(),
      ],
    );
  }

  Widget _ruleChip(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF059669)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _loadVigenteGoiasToPersonal() async {
    await ScaleRatesPeriodService().ensureLoaded();
    final rates = ScaleRatesPeriodService().currentDisplayRates();
    for (int i = 0; i < 7; i++) {
      _setBrl(_diurnoControllers[i], rates.valueDiurno[i]);
      _setBrl(_noturnoControllers[i], rates.valueNoturno[i]);
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tabela vigente do sistema carregada. Salve para aplicar.'),
      ),
    );
  }

  Widget _personalTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        FilledButton.tonalIcon(
          onPressed: _loadVigenteGoiasToPersonal,
          icon: const Icon(Icons.cloud_download_rounded),
          label: const Text('Carregar padrão vigente do sistema'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFDBEAFE),
            foregroundColor: const Color(0xFF1D4ED8),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _openUserPeriodEditor(),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Criar novo padrão'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF7C3AED),
            side: const BorderSide(color: Color(0xFF8B5CF6), width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 12),
        ScaleRatesTimelineStrip(
          periods: _userPeriods,
          title: 'Sua linha do tempo',
          readOnly: false,
          onPeriodTap: (p) => _openUserPeriodEditor(existing: p),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Valores por dia (R\$/h)',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _applyGoiasDefaultsToPersonal,
                      icon: const Icon(Icons.restore_rounded, size: 18),
                      label: const Text('Copiar base GO'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Ignora o padrão Goiás. Use a linha do tempo para vigência ou edite a tabela atual.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                ...List.generate(7, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 40,
                          child: Text(
                            _weekdayLabels[i],
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          child: BrlAmountTextField(
                            controller: _diurnoControllers[i],
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: 'Diurno',
                              prefixText: 'R\$ ',
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: i == 0 || i >= 5
                                  ? const Color(0xFFFFF7ED)
                                  : const Color(0xFFF0F9FF),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: BrlAmountTextField(
                            controller: _noturnoControllers[i],
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: 'Noturno',
                              prefixText: 'R\$ ',
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: i == 0 || i >= 5
                                  ? const Color(0xFFFFF7ED)
                                  : const Color(0xFFF5F3FF),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tipo de servidor', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'estadual', label: Text('Estadual')),
                    ButtonSegment(value: 'municipal', label: Text('Municipal')),
                    ButtonSegment(value: 'privado', label: Text('Empresa')),
                  ],
                  selected: {_serverType},
                  onSelectionChanged: (v) => setState(() => _serverType = v.first),
                ),
                if (_serverType == 'privado') ...[
                  const SizedBox(height: 16),
                  FastTextField(
                    controller: _bonusPercentCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Bônus adicional (%)',
                      hintText: 'Ex: 10',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  BrlAmountTextField(
                    controller: _bonusPerHourCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Bônus fixo por hora',
                      prefixText: 'R\$ ',
                      hintText: 'Ex: 5,00',
                      filled: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _tetoCard(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FA),
      appBar: AppBar(
        title: const Text('Horas extras / Banco de horas'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.deepBlue,
                AppColors.primary,
                AppColors.accent.withValues(alpha: 0.85),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (!_loading)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Salvar', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!_loading)
              HorasExtrasSourceTabBar(
                selectedIndex: _tabController.index,
                onSelected: (i) {
                  _tabController.animateTo(i);
                  setState(() {});
                },
              ),
            if (_showRetryBanner)
              Material(
                color: AppColors.error,
                child: InkWell(
                  onTap: _retryAfterRefresh,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Licença atualizada. Toque para tentar novamente.',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _goiasTab(),
                        _cltTab(),
                        _personalTab(),
                      ],
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_rounded),
                  label: const Text('Salvar configuração'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
