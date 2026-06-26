import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' hide showDatePicker;
import '../widgets/fast_text_field.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import '../models/user_profile.dart';
import '../services/user_categories_service.dart';
import '../services/functions_service.dart';
import '../services/logs_service.dart';
import '../models/scale_entry.dart';
import '../theme/app_colors.dart';
import '../widgets/skeleton_loader.dart';
import '../constants/date_time_formats.dart';
import '../constants/currency_formats.dart';
import '../widgets/brl_amount_text_field.dart';
import '../models/scale_rates.dart';
import '../services/relatorio_service.dart';
import 'report_preview_screen.dart';
import 'anexo_viewer_screen.dart';
import '../utils/anexo_viewer_helper.dart';
import '../utils/receipt_attachment_utils.dart';
import '../services/scale_rates_service.dart';
import '../utils/scale_entry_sei_ocorrencia.dart';
import '../services/ocorrencias_service.dart';
import '../utils/premium_upgrade.dart';
import '../models/shift_location.dart';
import '../utils/date_picker_a11y.dart';
import '../models/finance_account.dart';
import '../services/finance_accounts_service.dart';
import '../widgets/report_finance_charts_panel.dart';
import '../widgets/report_layout_responsive.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/firestore_query_batched_collect.dart';
import '../utils/firestore_reliable_read.dart';
import '../utils/friendly_error.dart';
import '../utils/pdf_financeiro_super_extrato.dart';
import '../services/express_compromisso_agenda_sync.dart';
import '../utils/keyboard_form_scaffold.dart';
import '../utils/home_shell_layout.dart';
import '../widgets/finance_confirm_payment_sheet.dart';
/// Relatórios — Clean Premium (PADRAO_VISUAL_CLEAN_PREMIUM.md).
/// Apenas filtro de período; abaixo aparecem os dados da consulta.
/// Funções mantidas: Imprimir, Exportar PDF, Compartilhar (WhatsApp).
const double _radiusCard = 20.0;
const double _radiusButton = 16.0;
const double _paddingCard = 16.0;
const int _criticalExportRowsThreshold = 1400;
/// Leituras Firestore para PDF: evita ficar indefinido com rede fraca ou bug do cliente Web.
const Duration _kReportsExportFirestoreTimeout = Duration(minutes: 3);

class ReportsScreen extends StatefulWidget {
  final String uid;
  final UserProfile profile;
  final void Function(int index)? onNavigateTo;

  const ReportsScreen({
    super.key,
    required this.uid,
    required this.profile,
    this.onNavigateTo,
  });

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

/// Tipo de relatório a emitir.
enum _TipoRelatorio { despesasReceitas, bancoHoras, produtividade }

class _ReportsScreenState extends State<ReportsScreen> {
  /// Padrão: 1 de janeiro do ano em curso até hoje. O utilizador ajusta o intervalo (datas ou atalhos) conforme o relatório.
  late DateTime _dateStart;
  late DateTime _dateEnd;
  _TipoRelatorio _tipoRelatorio = _TipoRelatorio.despesasReceitas;
  /// Filtro para relatório Banco de Horas: todos | state | municipality | private
  String _filtroVinculoBancoHoras = 'todos';
  /// Filtro Banco de Horas: todos | ja_tirados | a_tirar
  String _filtroJaTiradoBancoHoras = 'todos';
  /// Filtro para relatório Produtividade: todos | sem folga | usadas folga
  String _filtroProdutividade = 'todos';
  /// Padrão: despesas pagas e receitas recebidas (usuário pode alterar).
  String _filtroDespesas = 'pagos';
  String _filtroReceitas = 'recebidos';

  /// Cache de futures por período/tipo para não recriar a cada build (evita lentidão).
  String _reportDataKey = '';
  Future<Map<String, dynamic>>? _reportDataFuture;
  String _horasKey = '';
  Future<Map<String, dynamic>>? _horasFuture;
  String _produtividadeKey = '';
  Future<Map<String, dynamic>>? _produtividadeFuture;
  String _exportFinanceKey = '';
  Future<Map<String, dynamic>>? _exportFinanceFuture;
  String _exportBancoHorasKey = '';
  Future<Map<String, dynamic>>? _exportBancoHorasFuture;
  String _exportProdutividadeKey = '';
  Future<Map<String, dynamic>>? _exportProdutividadeFuture;
  String _txPairKey = '';
  Future<Map<String, List<Map<String, dynamic>>>>? _txPairFuture;
  final Map<String, Uint8List> _pdfBytesCache = {};
  final Map<String, DateTime> _pdfCacheTime = {};
  static const Duration _pdfCacheTtl = Duration(minutes: 5);

  String get _userDocId => firestoreUserDocIdForAppShell(widget.uid);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Padrão: mês civil em curso (o utilizador muda com atalhos ou datas).
    _dateStart = DateTime(now.year, now.month, 1);
    _dateEnd = DateTime(now.year, now.month + 1, 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(RelatorioService.warmUpPdfAssets());
    });
  }

  /// Atualiza todos os relatórios (pull-to-refresh e após voltar de outro módulo com dados novos).
  void _refreshAllReportCaches() {
    setState(() {
      _reportDataKey = '';
      _reportDataFuture = null;
      _horasKey = '';
      _horasFuture = null;
      _produtividadeKey = '';
      _produtividadeFuture = null;
      _exportFinanceKey = '';
      _exportFinanceFuture = null;
      _exportBancoHorasKey = '';
      _exportBancoHorasFuture = null;
      _exportProdutividadeKey = '';
      _exportProdutividadeFuture = null;
      _txPairKey = '';
      _txPairFuture = null;
      _pdfBytesCache.clear();
      _pdfCacheTime.clear();
    });
  }

  CollectionReference<Map<String, dynamic>> get _tx =>
      FirebaseFirestore.instance.collection('users').doc(_userDocId).collection('transactions');
  CollectionReference<Map<String, dynamic>> get _scales =>
      FirebaseFirestore.instance.collection('users').doc(_userDocId).collection('scales');

  // Tema: alinhar Relatórios ao ColorScheme (modo claro/escuro) e ao aspeto premium do app.
  bool get _reportDark => Theme.of(context).brightness == Brightness.dark;
  ColorScheme get _cs => Theme.of(context).colorScheme;
  Color get _reportOnSurface => _cs.onSurface;
  Color get _reportOnSurfaceVar => _cs.onSurfaceVariant;
  Color get _reportSurface => _cs.surface;
  Color get _reportSurfaceContainer => _cs.surfaceContainerHighest;

  List<Color> get _periodCardGradientColors {
    if (_reportDark) {
      final s = _reportSurface;
      return [
        s,
        Color.lerp(s, const Color(0xFF0F7668), 0.2) ?? s,
        Color.lerp(s, const Color(0xFF1E3A5F), 0.24) ?? s,
      ];
    }
    return const [Color(0xFFFFFFFF), Color(0xFFEFFBF4), Color(0xFFF0F7FF)];
  }

  List<BoxShadow> get _cardShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: _reportDark ? 0.45 : 0.07),
          blurRadius: _reportDark ? 20 : 10,
          offset: const Offset(0, 4),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 720;
    final padding = MediaQuery.paddingOf(context);
    final leftPad = isNarrow && padding.left > 16 ? padding.left : (isNarrow ? 16.0 : 24.0);
    final rightPad = isNarrow && padding.right > 16 ? padding.right : (isNarrow ? 16.0 : 24.0);
    final bottomPad = widget.onNavigateTo != null
        ? (isNarrow ? 12.0 : 8.0)
        : (isNarrow ? 24.0 : 0.0) + padding.bottom;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      resizeToAvoidBottomInset: scaffoldKeyboardResizeToAvoidBottomInset(
        embeddedInHomeShell: widget.onNavigateTo != null,
      ),
      body: RefreshIndicator(
        color: _cs.primary,
        onRefresh: () async {
          _refreshAllReportCaches();
          await Future.delayed(const Duration(milliseconds: 120));
        },
        child: RepaintBoundary(
          child: CustomScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
          SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SafeArea(
                  top: false,
                  left: true,
                  right: true,
                  bottom: true,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(leftPad, isNarrow ? 14 : 10, rightPad, bottomPad),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: reportContentWidth(constraints.maxWidth),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildPeriodFilter(),
                            const SizedBox(height: 20),
                            _buildActionButtons(),
                            const SizedBox(height: 24),
                            _buildReportContent(),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        ),
      ),
      ),
    );
  }

  /// Chip colorido estilo premium (Relatórios).
  Widget _premiumChoiceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Color accent,
  }) {
    final darker = Color.lerp(accent, Colors.black, 0.14) ?? accent;
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: selected ? LinearGradient(colors: [accent, darker], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
              color: selected ? null : _reportSurfaceContainer,
              border: Border.all(color: accent.withValues(alpha: selected ? 0 : 0.65), width: selected ? 0 : 2),
              boxShadow: selected
                  ? [BoxShadow(color: accent.withValues(alpha: 0.42), blurRadius: 12, offset: const Offset(0, 5))]
                  : [BoxShadow(color: accent.withValues(alpha: 0.1), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  const Icon(Icons.check_rounded, size: 18, color: Colors.white),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: selected ? Colors.white : accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static bool _sameCalendarDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _matchesQuickMesAtual() {
    final now = DateTime.now();
    final s = DateTime(now.year, now.month, 1);
    final e = DateTime(now.year, now.month + 1, 0);
    return _sameCalendarDay(_dateStart, s) && _sameCalendarDay(_dateEnd, e);
  }

  bool _matchesQuickMesAnterior() {
    final now = DateTime.now();
    final lm = DateTime(now.year, now.month - 1);
    final s = DateTime(lm.year, lm.month, 1);
    final e = DateTime(lm.year, lm.month + 1, 0);
    return _sameCalendarDay(_dateStart, s) && _sameCalendarDay(_dateEnd, e);
  }

  bool _matchesQuickUltimos7Dias() {
    final now = DateTime.now();
    final s = now.subtract(const Duration(days: 7));
    final start = DateTime(s.year, s.month, s.day);
    final end = DateTime(now.year, now.month, now.day);
    return _sameCalendarDay(_dateStart, start) && _sameCalendarDay(_dateEnd, end);
  }

  bool _matchesQuickAno() {
    final now = DateTime.now();
    final s = DateTime(now.year, 1, 1);
    final e = DateTime(now.year, 12, 31);
    return _sameCalendarDay(_dateStart, s) && _sameCalendarDay(_dateEnd, e);
  }

  /// Botões de data do filtro (Período) — legíveis no claro e no escuro.
  ButtonStyle _dateOutlineStyle() => OutlinedButton.styleFrom(
        foregroundColor: _reportOnSurface,
        side: BorderSide(color: _cs.outlineVariant.withValues(alpha: _reportDark ? 0.55 : 0.5)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusButton)),
      );

  void _applyQuickReportPeriod(String key) {
    final now = DateTime.now();
    setState(() {
      switch (key) {
        case 'mes_atual':
          _dateStart = DateTime(now.year, now.month, 1);
          _dateEnd = DateTime(now.year, now.month + 1, 0);
          break;
        case 'mes_ant':
          final lm = DateTime(now.year, now.month - 1);
          _dateStart = DateTime(lm.year, lm.month, 1);
          _dateEnd = DateTime(lm.year, lm.month + 1, 0);
          break;
        case 'semana':
          final s = now.subtract(const Duration(days: 7));
          _dateStart = DateTime(s.year, s.month, s.day);
          _dateEnd = DateTime(now.year, now.month, now.day);
          break;
        case 'ano':
          _dateStart = DateTime(now.year, 1, 1);
          _dateEnd = DateTime(now.year, 12, 31);
          break;
      }
    });
  }

  Widget _buildPeriodFilter() {
    return Container(
      padding: const EdgeInsets.all(_paddingCard),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _periodCardGradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(_radiusCard),
        boxShadow: _cardShadow,
        border: Border.all(
          color: AppColors.primary.withValues(alpha: _reportDark ? 0.32 : 0.14),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, Color.lerp(AppColors.primary, AppColors.accent, 0.45)!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.28), blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: const Icon(Icons.date_range_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Período',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _reportOnSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Defina início e fim ou use um atalho. O conteúdo abaixo atualiza na hora. '
            'Despesas e receitas usam a data do lançamento; Banco de horas segue a data do plantão.',
            style: TextStyle(fontSize: 13, color: _reportOnSurfaceVar, height: 1.35),
          ),
          const SizedBox(height: 12),
          Wrap(
            children: [
              _premiumChoiceChip(
                label: 'Mês atual',
                selected: _matchesQuickMesAtual(),
                onTap: () => _applyQuickReportPeriod('mes_atual'),
                accent: const Color(0xFF0891B2),
              ),
              _premiumChoiceChip(
                label: 'Mês anterior',
                selected: _matchesQuickMesAnterior(),
                onTap: () => _applyQuickReportPeriod('mes_ant'),
                accent: const Color(0xFF6366F1),
              ),
              _premiumChoiceChip(
                label: '7 dias',
                selected: _matchesQuickUltimos7Dias(),
                onTap: () => _applyQuickReportPeriod('semana'),
                accent: const Color(0xFF059669),
              ),
              _premiumChoiceChip(
                label: 'Ano',
                selected: _matchesQuickAno(),
                onTap: () => _applyQuickReportPeriod('ano'),
                accent: const Color(0xFFEA580C),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 380;
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      style: _dateOutlineStyle(),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _dateStart.isBefore(_dateEnd) ? _dateStart : _dateEnd,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                          initialDatePickerMode: DatePickerMode.day,
                        );
                        if (d != null) setState(() => _dateStart = d);
                      },
                      icon: const Icon(Icons.calendar_today_rounded, size: 18),
                      label: Text(DateTimeFormats.dateBR.format(_dateStart)),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text('até', style: TextStyle(fontWeight: FontWeight.w600, color: _reportOnSurfaceVar)),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: _dateOutlineStyle(),
                      onPressed: () async {
                        final firstAllowed = _dateStart.isBefore(_dateEnd) ? _dateStart : _dateEnd;
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _dateEnd,
                          firstDate: firstAllowed,
                          lastDate: DateTime(2030),
                          initialDatePickerMode: DatePickerMode.day,
                        );
                        if (d != null) setState(() => _dateEnd = d);
                      },
                      icon: const Icon(Icons.calendar_today_rounded, size: 18),
                      label: Text(DateTimeFormats.dateBR.format(_dateEnd)),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: _dateOutlineStyle(),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _dateStart.isBefore(_dateEnd) ? _dateStart : _dateEnd,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                          initialDatePickerMode: DatePickerMode.day,
                        );
                        if (d != null) setState(() => _dateStart = d);
                      },
                      icon: const Icon(Icons.calendar_today_rounded, size: 18),
                      label: Text(DateTimeFormats.dateBR.format(_dateStart)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('até', style: TextStyle(fontWeight: FontWeight.w600, color: _reportOnSurfaceVar)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: _dateOutlineStyle(),
                      onPressed: () async {
                        final firstAllowed = _dateStart.isBefore(_dateEnd) ? _dateStart : _dateEnd;
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _dateEnd,
                          firstDate: firstAllowed,
                          lastDate: DateTime(2030),
                          initialDatePickerMode: DatePickerMode.day,
                        );
                        if (d != null) setState(() => _dateEnd = d);
                      },
                      icon: const Icon(Icons.calendar_today_rounded, size: 18),
                      label: Text(DateTimeFormats.dateBR.format(_dateEnd)),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Text(
            'Tipo de relatório',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _reportOnSurface),
          ),
          const SizedBox(height: 10),
          Wrap(
            children: [
              _premiumChoiceChip(
                label: 'Despesas e Receitas',
                selected: _tipoRelatorio == _TipoRelatorio.despesasReceitas,
                onTap: () => setState(() => _tipoRelatorio = _TipoRelatorio.despesasReceitas),
                accent: AppColors.primary,
              ),
              _premiumChoiceChip(
                label: 'Banco de Horas',
                selected: _tipoRelatorio == _TipoRelatorio.bancoHoras,
                onTap: () => setState(() => _tipoRelatorio = _TipoRelatorio.bancoHoras),
                accent: AppColors.accent,
              ),
              _premiumChoiceChip(
                label: 'Produtividade / Ocorrências',
                selected: _tipoRelatorio == _TipoRelatorio.produtividade,
                onTap: () => setState(() => _tipoRelatorio = _TipoRelatorio.produtividade),
                accent: AppColors.logoOrange,
              ),
            ],
          ),
          if (_tipoRelatorio == _TipoRelatorio.produtividade) ...[
            const SizedBox(height: 16),
            Text(
              'Filtro',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _reportOnSurfaceVar),
            ),
            const SizedBox(height: 6),
            Wrap(
              children: [
                _premiumChoiceChip(
                  label: 'Todos',
                  selected: _filtroProdutividade == 'todos',
                  onTap: () => setState(() => _filtroProdutividade = 'todos'),
                  accent: AppColors.primary,
                ),
                _premiumChoiceChip(
                  label: 'Sem marcar folga',
                  selected: _filtroProdutividade == 'sem_folga',
                  onTap: () => setState(() => _filtroProdutividade = 'sem_folga'),
                  accent: const Color(0xFFEA580C),
                ),
                _premiumChoiceChip(
                  label: 'Usadas para folga',
                  selected: _filtroProdutividade == 'usadas_folga',
                  onTap: () => setState(() => _filtroProdutividade = 'usadas_folga'),
                  accent: AppColors.accent,
                ),
              ],
            ),
          ],
          if (_tipoRelatorio == _TipoRelatorio.bancoHoras) ...[
            const SizedBox(height: 16),
            Text(
              'Vínculo',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _reportOnSurfaceVar),
            ),
            const SizedBox(height: 6),
            Wrap(
              children: [
                _premiumChoiceChip(
                  label: 'Todos',
                  selected: _filtroVinculoBancoHoras == 'todos',
                  onTap: () => setState(() => _filtroVinculoBancoHoras = 'todos'),
                  accent: AppColors.primary,
                ),
                _premiumChoiceChip(
                  label: 'Estado',
                  selected: _filtroVinculoBancoHoras == 'state',
                  onTap: () => setState(() => _filtroVinculoBancoHoras = 'state'),
                  accent: AppColors.deepBlue,
                ),
                _premiumChoiceChip(
                  label: 'Município',
                  selected: _filtroVinculoBancoHoras == 'municipality',
                  onTap: () => setState(() => _filtroVinculoBancoHoras = 'municipality'),
                  accent: AppColors.accent,
                ),
                _premiumChoiceChip(
                  label: 'Particular',
                  selected: _filtroVinculoBancoHoras == 'private',
                  onTap: () => setState(() => _filtroVinculoBancoHoras = 'private'),
                  accent: const Color(0xFF9333EA),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Situação do plantão',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _reportOnSurfaceVar),
            ),
            const SizedBox(height: 6),
            Wrap(
              children: [
                _premiumChoiceChip(
                  label: 'Todos',
                  selected: _filtroJaTiradoBancoHoras == 'todos',
                  onTap: () => setState(() => _filtroJaTiradoBancoHoras = 'todos'),
                  accent: AppColors.primary,
                ),
                _premiumChoiceChip(
                  label: 'Já tirados',
                  selected: _filtroJaTiradoBancoHoras == 'ja_tirados',
                  onTap: () => setState(() => _filtroJaTiradoBancoHoras = 'ja_tirados'),
                  accent: AppColors.success,
                ),
                _premiumChoiceChip(
                  label: 'A tirar',
                  selected: _filtroJaTiradoBancoHoras == 'a_tirar',
                  onTap: () => setState(() => _filtroJaTiradoBancoHoras = 'a_tirar'),
                  accent: const Color(0xFF2563EB),
                ),
              ],
            ),
          ],
          if (_tipoRelatorio == _TipoRelatorio.despesasReceitas) ...[
            const SizedBox(height: 16),
            Text(
              'Despesas',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _reportOnSurfaceVar),
            ),
            const SizedBox(height: 6),
            Wrap(
              children: [
                _premiumChoiceChip(
                  label: 'Todos',
                  selected: _filtroDespesas == 'todos',
                  onTap: () => setState(() => _filtroDespesas = 'todos'),
                  accent: AppColors.primary,
                ),
                _premiumChoiceChip(
                  label: 'Pagas',
                  selected: _filtroDespesas == 'pagos',
                  onTap: () => setState(() => _filtroDespesas = 'pagos'),
                  accent: AppColors.success,
                ),
                _premiumChoiceChip(
                  label: 'Pendentes',
                  selected: _filtroDespesas == 'pendentes',
                  onTap: () => setState(() => _filtroDespesas = 'pendentes'),
                  accent: const Color(0xFFF59E0B),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Receitas',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _reportOnSurfaceVar),
            ),
            const SizedBox(height: 6),
            Wrap(
              children: [
                _premiumChoiceChip(
                  label: 'Todos',
                  selected: _filtroReceitas == 'todos',
                  onTap: () => setState(() => _filtroReceitas = 'todos'),
                  accent: AppColors.primary,
                ),
                _premiumChoiceChip(
                  label: 'Pagas',
                  selected: _filtroReceitas == 'recebidos',
                  onTap: () => setState(() => _filtroReceitas = 'recebidos'),
                  accent: AppColors.success,
                ),
                _premiumChoiceChip(
                  label: 'Pendentes',
                  selected: _filtroReceitas == 'pendentes',
                  onTap: () => setState(() => _filtroReceitas = 'pendentes'),
                  accent: const Color(0xFFF59E0B),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    // Só pode emitir relatórios com licença ativa (trial ou plano pago). Sem licença = modo só visualização.
    final canEmit = widget.profile.hasActiveLicense;
    final isNarrow = MediaQuery.of(context).size.width < 400;
    final buttons = [
      _actionBtn(
        Icons.print_outlined,
        'Imprimir',
        const Color(0xFF0F766E),
        canEmit ? _onImprimir : () => mostrarAvisoSeLicencaInativa(context, widget.profile),
      ),
      _actionBtn(
        Icons.picture_as_pdf_rounded,
        'PDF — Super Premium',
        AppColors.logoOrange,
        canEmit ? _onExportarPdf : () => mostrarAvisoSeLicencaInativa(context, widget.profile),
      ),
      _actionBtn(
        Icons.share_rounded,
        isNarrow ? 'Compartilhar' : 'Compartilhar (WhatsApp)',
        const Color(0xFF059669),
        canEmit ? _onCompartilhar : () => mostrarAvisoSeLicencaInativa(context, widget.profile),
      ),
    ];
    // No celular: Wrap para os 3 botões caberem (ou scroll horizontal com padding para o último aparecer completo).
    if (isNarrow) {
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          buttons[0],
          buttons[1],
          buttons[2],
        ],
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        children: [
          buttons[0],
          const SizedBox(width: 12),
          buttons[1],
          const SizedBox(width: 12),
          buttons[2],
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color bg, VoidCallback onPressed) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        elevation: 2,
        shadowColor: bg.withValues(alpha: 0.45),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusButton)),
      ),
    );
  }

  double _toDoubleDynamic(dynamic v, [double fallback = 0]) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? fallback;
    return fallback;
  }

  int _toIntDynamic(dynamic v, [int fallback = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  DateTime? _extractScaleDateDynamic(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  DateTime? _extractAnyDateDynamic(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is int) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(raw);
      } catch (_) {
        return null;
      }
    }
    if (raw is String) {
      final s = raw.trim();
      if (s.isEmpty) return null;
      final iso = DateTime.tryParse(s);
      if (iso != null) return iso;
      final parts = s.split('/');
      if (parts.length == 3) {
        final d = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final y = int.tryParse(parts[2]);
        if (d != null && m != null && y != null) {
          try {
            return DateTime(y, m, d);
          } catch (_) {
            return null;
          }
        }
      }
    }
    return null;
  }

  int _financeBatchYieldSize() {
    final days = _dateEnd.difference(_dateStart).inDays + 1;
    if (days <= 31) return 320;
    if (days <= 93) return 240;
    if (days <= 186) return 180;
    return 120;
  }

  int _bancoHorasBatchYieldSize() {
    final days = _dateEnd.difference(_dateStart).inDays + 1;
    if (days <= 31) return 300;
    if (days <= 93) return 220;
    if (days <= 186) return 160;
    return 120;
  }

  String _financeExportCacheKey() =>
      'f_${_dateStart.millisecondsSinceEpoch}_${_dateEnd.millisecondsSinceEpoch}_${_filtroDespesas}_${_filtroReceitas}_super_v1';

  String _bancoHorasExportCacheKey() =>
      'bh_${_dateStart.millisecondsSinceEpoch}_${_dateEnd.millisecondsSinceEpoch}_$_filtroVinculoBancoHoras$_filtroJaTiradoBancoHoras';

  String _produtividadeExportCacheKey() =>
      'p_${_dateStart.millisecondsSinceEpoch}_${_dateEnd.millisecondsSinceEpoch}_$_filtroProdutividade';

  String _txPeriodCacheKey() =>
      'tx_${_dateStart.millisecondsSinceEpoch}_${_dateEnd.millisecondsSinceEpoch}';

  Future<Map<String, List<Map<String, dynamic>>>> _loadTransactionsPair() async {
    final start = DateTime(_dateStart.year, _dateStart.month, _dateStart.day);
    final end = DateTime(_dateEnd.year, _dateEnd.month, _dateEnd.day, 23, 59, 59);
    final snap = await firestoreQueryGetReliable(
      _tx
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .orderBy('date', descending: false),
    ).timeout(
          _kReportsExportFirestoreTimeout,
          onTimeout: () => throw TimeoutException('Lista de lançamentos (período): tempo esgotado.'),
        );
    final expenses = <Map<String, dynamic>>[];
    final incomes = <Map<String, dynamic>>[];
    var n = 0;
    for (final d in snap.docs) {
      final data = d.data();
      data['id'] = d.id;
      final type = (data['type'] ?? '').toString();
      if (type == 'expense') {
        expenses.add(data);
      } else if (type == 'income') {
        incomes.add(data);
      }
      n++;
      if (n % 180 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return {
      'expense': expenses,
      'income': incomes,
    };
  }

  Future<Map<String, List<Map<String, dynamic>>>> _getTransactionsPairCached() {
    final key = _txPeriodCacheKey();
    if (_txPairKey != key || _txPairFuture == null) {
      _txPairKey = key;
      _txPairFuture = _loadTransactionsPair();
    }
    return _txPairFuture!;
  }

  Future<Map<String, dynamic>> _loadFinanceExportData() async {
    // Firestore Web: evitar duas queries pesadas em paralelo na mesma coleção (reduz INTERNAL ASSERTION / travamentos).
    final txPair = await _getTransactionsPairCached();
    final saldoAbertura = await _loadSaldoAbertura();
    final accounts = await FinanceAccountsService().listOnce(_userDocId);
    return {
      'expenseListRaw': txPair['expense'] ?? const <Map<String, dynamic>>[],
      'incomeListRaw': txPair['income'] ?? const <Map<String, dynamic>>[],
      'saldoAbertura': saldoAbertura,
      'financeAccList': accounts,
    };
  }

  Future<Map<String, dynamic>> _getFinanceExportDataCached() {
    final key = _financeExportCacheKey();
    if (_exportFinanceKey != key || _exportFinanceFuture == null) {
      _exportFinanceKey = key;
      _exportFinanceFuture = _loadFinanceExportData();
    }
    return _exportFinanceFuture!;
  }

  Future<Map<String, dynamic>> _getBancoHorasExportDataCached() {
    final key = _bancoHorasExportCacheKey();
    if (_exportBancoHorasKey != key || _exportBancoHorasFuture == null) {
      _exportBancoHorasKey = key;
      _exportBancoHorasFuture = _loadHorasValores();
    }
    return _exportBancoHorasFuture!;
  }

  Future<Map<String, dynamic>> _getProdutividadeExportDataCached() {
    final key = _produtividadeExportCacheKey();
    if (_exportProdutividadeKey != key || _exportProdutividadeFuture == null) {
      _exportProdutividadeKey = key;
      _exportProdutividadeFuture = _loadProdutividadeData();
    }
    return _exportProdutividadeFuture!;
  }

  String _pdfCacheKey() {
    switch (_tipoRelatorio) {
      case _TipoRelatorio.despesasReceitas:
        return 'pdf_fin_${_financeExportCacheKey()}';
      case _TipoRelatorio.bancoHoras:
        return 'pdf_bh_${_bancoHorasExportCacheKey()}';
      case _TipoRelatorio.produtividade:
        return 'pdf_prod_${_produtividadeExportCacheKey()}';
    }
  }

  Uint8List? _getPdfFromCache(String key) {
    final bytes = _pdfBytesCache[key];
    final t = _pdfCacheTime[key];
    if (bytes == null || t == null) return null;
    if (DateTime.now().difference(t) > _pdfCacheTtl) {
      _pdfBytesCache.remove(key);
      _pdfCacheTime.remove(key);
      return null;
    }
    return bytes;
  }

  void _putPdfInCache(String key, Uint8List bytes) {
    _pdfBytesCache[key] = bytes;
    _pdfCacheTime[key] = DateTime.now();
  }

  Future<Map<String, dynamic>> _loadProdutividadeData() async {
    final start = DateTime(_dateStart.year, _dateStart.month, _dateStart.day);
    final end = DateTime(_dateEnd.year, _dateEnd.month, _dateEnd.day, 23, 59, 59);
    final service = OcorrenciasService();

    List<Map<String, dynamic>> base;
    try {
      base = await service.getByPeriod(_userDocId, start, end);
    } catch (_) {
      // Fallback robusto para casos com índice/tipagem irregular no Firestore.
      final all = await service.getAll(_userDocId);
      base = all.where((e) {
        final d = _extractAnyDateDynamic(e['date']);
        if (d == null) return false;
        return !d.isBefore(start) && !d.isAfter(end);
      }).toList();
    }

    final todas = base.map((e) {
      final date = _extractAnyDateDynamic(e['date']);
      final folgaDate = _extractAnyDateDynamic(e['folgaDate']);
      return <String, dynamic>{
        ...e,
        'date': date ?? e['date'],
        'folgaDate': folgaDate,
        'pontuacao': _toIntDynamic(e['pontuacao']),
        'numeroOcorrencia': (e['numeroOcorrencia'] ?? '').toString().trim(),
        'naturezaLabel': (e['naturezaLabel'] ?? '').toString().trim(),
        'observacao': (e['observacao'] ?? '').toString().trim(),
      };
    }).toList()
      ..sort((a, b) {
        final da = _extractAnyDateDynamic(a['date']) ?? DateTime(1900);
        final db = _extractAnyDateDynamic(b['date']) ?? DateTime(1900);
        return da.compareTo(db);
      });

    final semFolga = todas.where((e) => e['folgaDate'] == null).toList();
    final comFolga = todas.where((e) => e['folgaDate'] != null).toList();
    final byFolga = <String, List<Map<String, dynamic>>>{};
    final diasSemana = ['Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado', 'Domingo'];
    for (final e in comFolga) {
      final folgaDt = _extractAnyDateDynamic(e['folgaDate']);
      if (folgaDt == null) continue;
      final key = DateTimeFormats.dateBR.format(folgaDt);
      byFolga.putIfAbsent(key, () => []).add(e);
    }
    final usadasFolga = byFolga.entries.map((ent) {
      final dt = _extractAnyDateDynamic(ent.value.first['folgaDate']) ?? DateTime.now();
      return {
        'folgaDate': ent.key,
        'diaSemana': diasSemana[dt.weekday - 1],
        'ocorrencias': ent.value,
      };
    }).toList();
    return {
      'todas': todas,
      'semFolga': semFolga,
      'usadasFolga': usadasFolga,
    };
  }

  /// Execução de export sem banner persistente de progresso.
  Future<T> _runWithPdfProgress<T>({
    required String message,
    required Future<T> Function() action,
  }) async {
    if (!mounted) {
      throw StateError('reports_pdf_unmounted');
    }
    return action();
  }

  void _onImprimir() => _exportarOuImprimir();
  void _onExportarPdf() => _exportarOuImprimir();

  /// Monta bytes do PDF (Firestore + composição). Preview abre **fora** do overlay para não esconder erros.
  Future<(Uint8List, String, bool)> _montarPayloadPdfRelatorio({
    required String periodo,
    required String filenameBase,
    required String pdfKey,
  }) async {
    if (_tipoRelatorio == _TipoRelatorio.despesasReceitas) {
      final raw = await _getFinanceExportDataCached().timeout(
        _kReportsExportFirestoreTimeout,
        onTimeout: () => throw TimeoutException('Dados financeiros: tempo esgotado.'),
      );
      final expenseListRaw = raw['expenseListRaw'] as List<Map<String, dynamic>>;
      final incomeListRaw = raw['incomeListRaw'] as List<Map<String, dynamic>>;
      final expenseList = _filterByStatus(expenseListRaw, _filtroDespesas);
      final incomeList = _filterByStatus(incomeListRaw, _filtroReceitas);
      final saldoAbertura = raw['saldoAbertura'] as double;
      final totalDespesas = expenseList.fold<double>(0, (s, e) => s + ((e['amount'] ?? 0) as num).toDouble());
      final totalReceitas = incomeList.fold<double>(0, (s, e) => s + ((e['amount'] ?? 0) as num).toDouble());
      final batchYield = _financeBatchYieldSize();

      String dataStr(dynamic ts) {
        if (ts == null) return '';
        if (ts is DateTime) return DateTimeFormats.dateBR.format(ts);
        if (ts is Timestamp) return DateTimeFormats.dateBR.format(ts.toDate());
        return '';
      }

      void pushRow(Map<String, dynamic> e, bool income, List<Map<String, dynamic>> out) {
        final dt = _extractAnyDateDynamic(e['date']);
        final sortMs = dt?.millisecondsSinceEpoch ?? 0;
        final cat = (e['category'] ?? '').toString().trim();
        final desc = (e['description'] ?? '').toString().trim();
        final rawDesc = (cat.isNotEmpty ? 'Categoria: $cat' : '') +
            (cat.isNotEmpty && desc.isNotEmpty ? ' — ' : '') +
            (desc.isNotEmpty ? 'Descrição: $desc' : (cat.isEmpty ? (income ? 'Receita' : 'Despesa') : ''));
        final descricao = RelatorioService.sanitizeForReport(rawDesc.trim().isEmpty ? (income ? 'Receita' : 'Despesa') : rawDesc);
        final tituloLinha = desc.isNotEmpty ? desc : (income ? 'Receita' : 'Despesa');
        out.add({
          'sortMs': sortMs,
          'data': dataStr(e['date']),
          'categoria': cat,
          'titulo': tituloLinha,
          'descricao': descricao,
          'tipo': income ? 'receita' : 'despesa',
          'valor': ((e['amount'] ?? 0) as num).toDouble(),
        });
      }

      final transacoes = <Map<String, dynamic>>[];
      var i = 0;
      for (final e in incomeList) {
        pushRow(e, true, transacoes);
        i++;
        if (i > 0 && i % batchYield == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
      for (final e in expenseList) {
        pushRow(e, false, transacoes);
        i++;
        if (i > 0 && i % batchYield == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
      transacoes.sort((a, b) => (a['sortMs'] as int).compareTo(b['sortMs'] as int));

      final logo = await RelatorioService.loadPdfLogoBytesOnce();
      final bytes = await gerarPdfFinanceiroSuperExtrato(
        transacoes: transacoes,
        nomeUsuario: widget.profile.name,
        conta: 'Todas as contas',
        periodo: periodo,
        saldoAbertura: saldoAbertura,
        totalReceitas: totalReceitas,
        totalDespesas: totalDespesas,
        logoPngBytes: logo,
      );
      _putPdfInCache(pdfKey, bytes);
      return (bytes, filenameBase, false);
    }

    if (_tipoRelatorio == _TipoRelatorio.bancoHoras) {
      final data = await _getBancoHorasExportDataCached().timeout(
        _kReportsExportFirestoreTimeout,
        onTimeout: () => throw TimeoutException('Banco de horas: tempo esgotado.'),
      );
      final items = (data['items'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      double totalRecebido = 0;
      double totalPendente = 0;
      double hdT = 0, hnT = 0, hdR = 0, hnR = 0, hdP = 0, hnP = 0;
      final escalas = <Map<String, dynamic>>[];
      final linhasPdfCat = <Map<String, dynamic>>[];
      final hoje = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      final batchYield = _bancoHorasBatchYieldSize();
      for (var i = 0; i < items.length; i++) {
        final e = items[i];
        final date = e['date'];
        final dt = date is DateTime ? date : (date is Timestamp ? date.toDate() : DateTime.now());
        final dataPlantao = DateTime(dt.year, dt.month, dt.day);
        final jaTirado = e['jaTirado'] == true;
        final status = dataPlantao.isAfter(hoje)
            ? 'A confirmar'
            : (jaTirado ? 'Já tirado' : 'A tirar');
        final valor = _toDoubleDynamic(e['valor']);
        final isCompromisso = e['isCompromisso'] == true;
        if (!isCompromisso && valor > 0) {
          if (jaTirado) {
            totalRecebido += valor;
          } else {
            totalPendente += valor;
          }
        }
        final hDay = _toDoubleDynamic(e['hoursDay']);
        final hNight = _toDoubleDynamic(e['hoursNight']);
        hdT += hDay;
        hnT += hNight;
        if (jaTirado) {
          hdR += hDay;
          hnR += hNight;
        } else {
          hdP += hDay;
          hnP += hNight;
        }
        linhasPdfCat.add({
          'isCompromisso': isCompromisso,
          'temFinanceiro': e['temFinanceiro'] == true,
          'employerType': (e['employerType'] ?? 'private').toString(),
          'jaTirado': jaTirado,
          'hoursDay': hDay,
          'hoursNight': hNight,
          'valor': valor,
          'paid': e['paid'] == true,
        });
        // Escalas sem valor (compromisso ou 0): R$ 0,00 no PDF. Incluir Nº Escala igual ao módulo Escalas.
        final valorStr = (isCompromisso || valor == 0)
            ? 'R\$ 0,00'
            : CurrencyFormats.formatBRL(valor);
        escalas.add({
          'sortDate': dt,
          'data': DateTimeFormats.dateBR.format(dt),
          'numeroEscala': (e['scaleNumber'] ?? '').toString(),
          'compromisso': (e['label'] ?? 'Plantão').toString(),
          'valor': valorStr,
          'status': status,
          'observacao': (e['notes'] ?? '').toString(),
          'horasLinha': RelatorioService.formatHorasLinhaPdf(hDay, hNight),
          'horasCompacta': RelatorioService.formatHorasLinhaPdfCompact(hDay, hNight),
        });
        if (i > 0 && i % batchYield == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
      escalas.sort((a, b) => (a['sortDate'] as DateTime).compareTo(b['sortDate'] as DateTime));
      for (final row in escalas) {
        row.remove('sortDate');
      }
      final vinculoPart = _filtroVinculoBancoHoras == 'todos'
          ? ''
          : ' (Vínculo: ${_filtroVinculoBancoHoras == 'state' ? 'Estado' : _filtroVinculoBancoHoras == 'municipality' ? 'Município' : 'Particular'})';
      final sitPart = _filtroJaTiradoBancoHoras == 'todos'
          ? ''
          : _filtroJaTiradoBancoHoras == 'ja_tirados'
              ? ' · Já tirados'
              : ' · A tirar';
      final vinculoLabel = 'Relatório Banco de Horas$vinculoPart$sitPart';
      final resumoPdf = ResumoBancoHorasPdf(
        horasDiurnasTotal: hdT,
        horasNoturnasTotal: hnT,
        horasDiurnasRealizadas: hdR,
        horasNoturnasRealizadas: hnR,
        horasDiurnasPendentes: hdP,
        horasNoturnasPendentes: hnP,
        valorJaRecebido: totalRecebido,
        valorAReceber: totalPendente,
        categorias: RelatorioService.buildCategoriasResumoBancoHoras(linhasPdfCat),
        horasPlantaoMarcadoPago: _toDoubleDynamic(data['horasPlantaoMarcadoPago']),
        quantidadeCompromissos: _toIntDynamic(data['qtdCompromissos']),
        horasCompromissos: _toDoubleDynamic(data['horasCompromissos']),
        horasProfissionalSemFinanceiroPainel:
            _toDoubleDynamic(data['horasProfissionalSemFinanceiro']),
      );
      await Future<void>.delayed(const Duration(milliseconds: 32));
      final (bytes, _) = await RelatorioService.buildRelatorioEscalasBytes(
        periodo: periodo,
        escalas: escalas,
        totalRecebido: totalRecebido,
        totalPendente: totalPendente,
        notaProximoMes: null,
        reportTitle: vinculoLabel,
        suggestedFilename: filenameBase,
        resumoBancoHoras: resumoPdf,
      );
      final avisoVolume = items.length >= _criticalExportRowsThreshold;
      _putPdfInCache(pdfKey, bytes);
      return (bytes, filenameBase, avisoVolume);
    }

    if (_tipoRelatorio == _TipoRelatorio.produtividade) {
      final data = await _getProdutividadeExportDataCached().timeout(
        _kReportsExportFirestoreTimeout,
        onTimeout: () => throw TimeoutException('Produtividade: tempo esgotado.'),
      );
      final semFolga = (data['semFolga'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      final usadasFolga = (data['usadasFolga'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      String filtro = 'todos';
      if (_filtroProdutividade == 'sem_folga') filtro = 'sem_folga';
      if (_filtroProdutividade == 'usadas_folga') filtro = 'usadas_folga';
      await Future<void>.delayed(const Duration(milliseconds: 32));
      final (bytes, _) = await RelatorioService.buildRelatorioProdutividadeOcorrenciasBytes(
        periodo: periodo,
        semFolga: semFolga,
        usadasFolga: usadasFolga,
        filtro: filtro,
        suggestedFilename: filenameBase,
      );
      _putPdfInCache(pdfKey, bytes);
      return (bytes, filenameBase, false);
    }

    throw StateError('tipo_relatorio_pdf');
  }

  /// Gera PDF conforme tipo selecionado e abre o preview primeiro (depois usuário compartilha, imprime ou salva).
  Future<void> _exportarOuImprimir() async {
    final periodo = '${DateTimeFormats.dateBR.format(_dateStart)} a ${DateTimeFormats.dateBR.format(_dateEnd)}';
    final String filtroProdutividadeSufixo = _filtroProdutividade == 'sem_folga'
        ? 'sem folga'
        : _filtroProdutividade == 'usadas_folga'
            ? 'usadas folga'
            : '';
    final filenameBase = _tipoRelatorio == _TipoRelatorio.despesasReceitas
        ? RelatorioService.reportFilenameFromPeriod('despesa_receita', _dateStart, _dateEnd)
        : _tipoRelatorio == _TipoRelatorio.bancoHoras
            ? RelatorioService.reportFilenameFromPeriod('banco_horas', _dateStart, _dateEnd)
            : RelatorioService.reportFilenameFromPeriod(
                'produtividade_ocorrencias',
                _dateStart,
                _dateEnd,
                filtroProdutividadeSufixo.isEmpty ? null : filtroProdutividadeSufixo,
              );
    final pdfKey = _pdfCacheKey();

    final cachedBytes = _getPdfFromCache(pdfKey);
    if (cachedBytes != null) {
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ReportPreviewScreen(bytes: cachedBytes, filename: filenameBase),
        ),
      );
      return;
    }

    try {
      final triple = await _runWithPdfProgress<(Uint8List, String, bool)>(
        message: 'A gerar o PDF…',
        action: () => _montarPayloadPdfRelatorio(
          periodo: periodo,
          filenameBase: filenameBase,
          pdfKey: pdfKey,
        ),
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ReportPreviewScreen(bytes: triple.$1, filename: triple.$2),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível gerar o PDF. Tente período menor ou verifique a rede.\n${friendlyMessage(e)}',
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  /// Compartilha conforme o tipo de relatório selecionado (Despesas/Receitas ou Banco de Horas).
  Future<void> _onCompartilhar() async {
    final periodo = '${DateTimeFormats.dateBR.format(_dateStart)} a ${DateTimeFormats.dateBR.format(_dateEnd)}';
    String text;
    String subject;

    if (_tipoRelatorio == _TipoRelatorio.despesasReceitas) {
      final txPair = await _getTransactionsPairCached();
      final expenseListRaw = txPair['expense'] ?? const <Map<String, dynamic>>[];
      final incomeListRaw = txPair['income'] ?? const <Map<String, dynamic>>[];
      final expenseList = _filterByStatus(expenseListRaw, _filtroDespesas);
      final incomeList = _filterByStatus(incomeListRaw, _filtroReceitas);
      final saldoAbertura = await _loadSaldoAbertura();
      final totalDespesas = expenseList.fold<double>(0, (s, e) => s + ((e['amount'] ?? 0) as num).toDouble());
      final totalReceitas = incomeList.fold<double>(0, (s, e) => s + ((e['amount'] ?? 0) as num).toDouble());
      final saldoPeriodo = totalReceitas - totalDespesas;
      final saldoAcumulado = saldoAbertura + saldoPeriodo;
      text = '''
Relatório WISDOMAPP - Despesas e Receitas
Período: $periodo

Saldo de abertura: ${CurrencyFormats.formatBRL(saldoAbertura)}
Receitas: ${CurrencyFormats.formatBRL(totalReceitas)}
Despesas: ${CurrencyFormats.formatBRL(totalDespesas)}
Saldo (acum.): ${CurrencyFormats.formatBRL(saldoAcumulado)}
''';
      subject = 'RELATORIO FINANCEIRO WISDOMAPP';
    } else if (_tipoRelatorio == _TipoRelatorio.produtividade) {
      final data = await _loadProdutividadeData();
      final semFolga = (data['semFolga'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      final usadasFolga = (data['usadasFolga'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      text = '''
Relatório WISDOMAPP - Produtividade / Ocorrências
Período: $periodo

Sem marcar folga: ${semFolga.length}
Usadas para folga: ${usadasFolga.fold<int>(0, (s, g) => s + (((g['ocorrencias'] as List?)?.length) ?? 0))}
''';
      subject = 'RELATORIO PRODUTIVIDADE OCORRENCIAS WISDOMAPP';
    } else {
      final data = await _loadHorasValores();
      final items = (data['items'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      final totalHoras = _toDoubleDynamic(data['totalHoras']);
      final totalValor = _toDoubleDynamic(data['totalValor']);
      final hExtra = _toDoubleDynamic(data['horasPlantaoMarcadoPago']);
      final qComp = _toIntDynamic(data['qtdCompromissos']);
      final hComp = _toDoubleDynamic(data['horasCompromissos']);
      final hSemFin = _toDoubleDynamic(data['horasProfissionalSemFinanceiro']);
      final hoje = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      final sb = StringBuffer();
      sb.writeln('Relatório WISDOMAPP - Banco de Horas');
      sb.writeln('Período: $periodo');
      sb.writeln('');
      sb.writeln('Total de horas: ${totalHoras.toStringAsFixed(1)} h');
      sb.writeln('Valor total: ${CurrencyFormats.formatBRL(totalValor)}');
      sb.writeln('Horas em plantões «pago» (incl. hora extra): ${hExtra.toStringAsFixed(1)} h');
      sb.writeln('Compromissos: $qComp · ${hComp.toStringAsFixed(1)} h');
      sb.writeln('Plantões sem financeiro no painel: ${hSemFin.toStringAsFixed(1)} h');
      sb.writeln('');
      for (final e in items) {
        final dt = e['date'];
        final date = dt is DateTime ? dt : (dt is Timestamp ? dt.toDate() : DateTime.now());
        final dataPlantao = DateTime(date.year, date.month, date.day);
        final jaT = e['jaTirado'] == true;
        final status =
            dataPlantao.isAfter(hoje) ? 'A confirmar' : (jaT ? 'Já tirado' : 'A tirar');
        final isC = e['isCompromisso'] == true;
        final temFin = e['temFinanceiro'] == true;
        final tag = isC
            ? ' [Compromisso]'
            : (!temFin ? ' [Sem fin. painel]' : '');
        sb.writeln(
            '${DateTimeFormats.dateBR.format(date)} · ${(e['label'] ?? 'Plantão')} · ${CurrencyFormats.formatBRL(_toDoubleDynamic(e['valor']))} ($status)$tag');
      }
      text = sb.toString();
      subject = 'RELATORIO BANCO DE HORAS WISDOMAPP';
    }

    await Share.share(text.trim(), subject: subject);
  }

  Widget _chipResumoOcorrencias(String label, int total, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        '$label: $total',
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }

  Widget _statusFolgaChip(DateTime? folgaDate) {
    final jaTirado = folgaDate != null;
    final color = jaTirado ? Colors.green.shade700 : Colors.orange.shade700;
    final label = jaTirado ? 'Já tirado' : 'Folga a tirar';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11),
      ),
    );
  }

  Widget _buildOcorrenciasGridPremium(List<Map<String, dynamic>> rows) {
    final sorted = [...rows]
      ..sort((a, b) {
        final da = _extractAnyDateDynamic(a['date']) ?? DateTime(1900);
        final db = _extractAnyDateDynamic(b['date']) ?? DateTime(1900);
        return da.compareTo(db);
      });
    return LayoutBuilder(
      builder: (context, c) {
        final minGridWidth = c.maxWidth < 980 ? 980.0 : c.maxWidth;
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: _reportSurface,
            borderRadius: BorderRadius.circular(_radiusCard),
            border: Border.all(
              color: _reportDark
                  ? _cs.outline.withValues(alpha: 0.32)
                  : AppColors.deepBlueDark.withValues(alpha: 0.1),
            ),
            boxShadow: _cardShadow,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minGridWidth),
              child: DataTable(
                columnSpacing: 18,
                horizontalMargin: 12,
                headingRowHeight: 48,
                dataRowMinHeight: 52,
                dataRowMaxHeight: 60,
                dividerThickness: 0.8,
                headingTextStyle: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _reportOnSurface,
                  fontSize: 12.5,
                ),
                dataTextStyle: TextStyle(
                  fontSize: 12.5,
                  color: _reportOnSurface,
                ),
                dataRowColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return AppColors.primary.withValues(alpha: 0.08);
                  }
                  return null;
                }),
                columns: const [
                  DataColumn(label: Text('Data')),
                  DataColumn(label: Text('Nº ocorrência')),
                  DataColumn(label: Text('Natureza')),
                  DataColumn(label: Text('Pontos')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Folga')),
                ],
                rows: sorted.map((e) {
                  final dt = _extractAnyDateDynamic(e['date']);
                  final folgaDt = _extractAnyDateDynamic(e['folgaDate']);
                  return DataRow(cells: [
                    DataCell(Text(dt == null ? '-' : DateTimeFormats.dateBR.format(dt))),
                    DataCell(
                      Text(
                        ((e['numeroOcorrencia'] ?? '').toString().trim()).isEmpty
                            ? '-'
                            : (e['numeroOcorrencia'] ?? '').toString(),
                      ),
                    ),
                    DataCell(
                      Text(
                        ((e['naturezaLabel'] ?? '').toString().trim()).isEmpty
                            ? '-'
                            : (e['naturezaLabel'] ?? '').toString(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DataCell(Text('${_toIntDynamic(e['pontuacao'])}')),
                    DataCell(_statusFolgaChip(folgaDt)),
                    DataCell(Text(folgaDt == null ? '-' : DateTimeFormats.dateBR.format(folgaDt))),
                  ]);
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Conteúdo conforme tipo de relatório selecionado.
  Widget _buildReportContent() {
    if (_tipoRelatorio == _TipoRelatorio.produtividade) {
      final key =
          '${_dateStart.millisecondsSinceEpoch}_${_dateEnd.millisecondsSinceEpoch}_$_filtroProdutividade';
      if (_produtividadeKey != key) {
        _produtividadeKey = key;
        _produtividadeFuture = _loadProdutividadeData();
      }
      return FutureBuilder<Map<String, dynamic>>(
        future: _produtividadeFuture,
        builder: (context, snap) {
          if (snap.hasError) {
            return _emptyCard(
              'Erro ao carregar produtividade. Atualize e tente novamente.\n\nDetalhe: ${snap.error}',
            );
          }
          if (!snap.hasData) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
              child: SkeletonListLoader(itemCount: 5, itemHeight: 56),
            );
          }
          final data = snap.data!;
          final todas = (data['todas'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
          final semFolga = (data['semFolga'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
          final usadasFolga = (data['usadasFolga'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
          final totalUsadas = usadasFolga.fold<int>(0, (s, g) => s + (((g['ocorrencias'] as List?)?.length) ?? 0));
          final showRows = _filtroProdutividade == 'sem_folga'
              ? semFolga
              : _filtroProdutividade == 'usadas_folga'
                  ? usadasFolga
                      .expand((g) => ((g['ocorrencias'] as List?) ?? const []).cast<Map<String, dynamic>>())
                      .toList()
                  : todas;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Relatório Produtividade / Ocorrências'),
              const SizedBox(height: 8),
              Text(
                '${DateTimeFormats.dateBR.format(_dateStart)} a ${DateTimeFormats.dateBR.format(_dateEnd)}',
                style: TextStyle(fontSize: 13, color: _reportOnSurfaceVar),
              ),
              const SizedBox(height: 6),
              Text(
                'Grade Super Premium com todas as ocorrências do período e status da folga.',
                style: TextStyle(fontSize: 12, color: _reportOnSurfaceVar, height: 1.3),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chipResumoOcorrencias('Total', todas.length, AppColors.primary),
                  _chipResumoOcorrencias('Folga a tirar', semFolga.length, Colors.orange.shade700),
                  _chipResumoOcorrencias('Já tirado', totalUsadas, Colors.green.shade700),
                ],
              ),
              const SizedBox(height: 12),
              if (showRows.isEmpty)
                _emptyCard('Nenhuma ocorrência encontrada para este filtro/período.')
              else
                _buildOcorrenciasGridPremium(showRows),
              const SizedBox(height: 32),
            ],
          );
        },
      );
    }

    if (_tipoRelatorio == _TipoRelatorio.bancoHoras) {
      final key = '${_dateStart.millisecondsSinceEpoch}_${_dateEnd.millisecondsSinceEpoch}_$_filtroVinculoBancoHoras$_filtroJaTiradoBancoHoras';
      if (_horasKey != key) {
        _horasKey = key;
        _horasFuture = _loadHorasValores();
      }
      return FutureBuilder<Map<String, dynamic>>(
        future: _horasFuture,
        builder: (context, snap) {
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
              child: _emptyCard(
                'Erro ao carregar banco de horas. Atualize e tente novamente.\n\nDetalhe: ${snap.error}',
              ),
            );
          }
          if (!snap.hasData) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
              child: SkeletonListLoader(itemCount: 5, itemHeight: 56),
            );
          }
          final data = snap.data!;
          final items = (data['items'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _sectionTitle('Relatório Banco de Horas'),
              const SizedBox(height: 8),
              Text(
                '${DateTimeFormats.dateBR.format(_dateStart)} a ${DateTimeFormats.dateBR.format(_dateEnd)}',
                style: TextStyle(fontSize: 13, color: _reportOnSurfaceVar),
              ),
              const SizedBox(height: 6),
              Text(
                'Inclui horas «pago»/extra, compromissos e plantões sem financeiro no painel.',
                style: TextStyle(fontSize: 12, color: _reportOnSurfaceVar, height: 1.3),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: Colors.amber.shade800, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        RelatorioService.kNotaPadraoGoias,
                        style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _horasResumoCard(data),
              if (data['truncated'] == true)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 18, color: Colors.orange.shade800),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Mostrando até $_kBancoHorasMaxDocs plantões. Reduza o período ou os filtros para ver todos.',
                            style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      'Nenhum plantão no período selecionado.',
                      style: TextStyle(fontSize: 14, color: _reportOnSurfaceVar, fontStyle: FontStyle.italic),
                    ),
                  ),
                )
              else ...[
                const SizedBox(height: 20),
                _sectionTitle('Detalhamento'),
                const SizedBox(height: 8),
                ...items.map((e) => _buildBancoHorasPlantaoTile(
                  e,
                  onRefresh: () => setState(() {
                    _horasKey = DateTime.now().millisecondsSinceEpoch.toString();
                    _horasFuture = _loadHorasValores();
                  }),
                )),
              ],
              const SizedBox(height: 32),
            ],
          );
        },
      );
    }

    final key = 'dr_${_dateStart.millisecondsSinceEpoch}_${_dateEnd.millisecondsSinceEpoch}_${_filtroDespesas}_$_filtroReceitas';
    if (_reportDataKey != key) {
      _reportDataKey = key;
      _reportDataFuture = _loadAllReportData();
    }
    return FutureBuilder<Map<String, dynamic>>(
      future: _reportDataFuture,
        builder: (context, snap) {
        if (!snap.hasData) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
            child: SkeletonListLoader(itemCount: 6, itemHeight: 56),
          );
        }
        final data = snap.data!;
        final totalReceitas = (data['totalReceitas'] ?? 0.0) as double;
        final totalDespesas = (data['totalDespesas'] ?? 0.0) as double;
        final saldoAbertura = (data['saldoAbertura'] ?? 0.0) as double;
        final expenseList = (data['expenseList'] as List<Map<String, dynamic>>?) ?? [];
        final incomeList = (data['incomeList'] as List<Map<String, dynamic>>?) ?? [];
        final horasData = data['horasData'] as Map<String, dynamic>?;
        final porConta = (data['porConta'] as List<Map<String, dynamic>>?) ?? [];
        final gastosPorCategoria = (data['gastosPorCategoria'] as List<Map<String, dynamic>>?) ?? [];
        final receitasPorCategoria = (data['receitasPorCategoria'] as List<Map<String, dynamic>>?) ?? [];
        final saldoPeriodo = totalReceitas - totalDespesas;
        final saldoAcumulado = saldoAbertura + saldoPeriodo;
        final evolucao = computeReportFinanceEvolucao(
          incomeList: incomeList,
          expenseList: expenseList,
          rangeStart: _dateStart,
          rangeEnd: _dateEnd,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Resumo do período'),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (_, c) {
                final narrow = c.maxWidth < kReportGridBreakpointCompact;
                final mov = narrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ReportFinanceStatCard(title: 'Receitas', value: totalReceitas, color: const Color(0xFF16A34A)),
                          const SizedBox(height: 10),
                          ReportFinanceStatCard(title: 'Despesas', value: totalDespesas, color: const Color(0xFFDC2626)),
                          const SizedBox(height: 10),
                          ReportFinanceStatCard(
                            title: 'Saldo no período',
                            value: saldoPeriodo,
                            color: saldoPeriodo >= 0 ? const Color(0xFF0D9488) : const Color(0xFFB91C1C),
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: ReportFinanceStatCard(title: 'Receitas', value: totalReceitas, color: const Color(0xFF16A34A))),
                          const SizedBox(width: 8),
                          Expanded(child: ReportFinanceStatCard(title: 'Despesas', value: totalDespesas, color: const Color(0xFFDC2626))),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ReportFinanceStatCard(
                              title: 'Saldo no período',
                              value: saldoPeriodo,
                              color: saldoPeriodo >= 0 ? const Color(0xFF0D9488) : const Color(0xFFB91C1C),
                            ),
                          ),
                        ],
                      );
                final saldo = narrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ReportFinanceStatCard(
                            title: 'Saldo de abertura',
                            value: saldoAbertura,
                            color: saldoAbertura >= 0 ? AppColors.saldoPositive : AppColors.saldoNegative,
                          ),
                          const SizedBox(height: 10),
                          ReportFinanceStatCard(
                            title: 'Saldo (acum.)',
                            value: saldoAcumulado,
                            color: saldoAcumulado >= 0 ? AppColors.saldoPositive : AppColors.saldoNegative,
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ReportFinanceStatCard(
                              title: 'Saldo de abertura',
                              value: saldoAbertura,
                              color: saldoAbertura >= 0 ? AppColors.saldoPositive : AppColors.saldoNegative,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ReportFinanceStatCard(
                              title: 'Saldo (acum.)',
                              value: saldoAcumulado,
                              color: saldoAcumulado >= 0 ? AppColors.saldoPositive : AppColors.saldoNegative,
                            ),
                          ),
                        ],
                      );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    mov,
                    const SizedBox(height: 10),
                    saldo,
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            _sectionTitle('Painel visual'),
            const SizedBox(height: 8),
            ReportFinanceEvolucaoLineChart(data: evolucao),
            if (porConta.isNotEmpty) ...[
              const SizedBox(height: 16),
              ReportFinancePorContaPanel(rows: porConta),
            ],
            const SizedBox(height: 16),
            ReportFinanceBiCharts(
              totalReceitas: totalReceitas,
              totalDespesas: totalDespesas,
              gastosPorCategoria: gastosPorCategoria,
              receitasPorCategoria: receitasPorCategoria,
            ),
            const SizedBox(height: 28),
            _sectionTitle('Despesas'),
            const SizedBox(height: 12),
            _transactionList(expenseList, AppColors.error, 'expense', () => setState(() { _reportDataFuture = _loadAllReportData(); })),
            const SizedBox(height: 28),
            _sectionTitle('Receitas'),
            const SizedBox(height: 12),
            _transactionList(incomeList, AppColors.success, 'income', () => setState(() { _reportDataFuture = _loadAllReportData(); })),
            if (horasData != null && _toDoubleDynamic(horasData['totalHoras']) > 0) ...[
              const SizedBox(height: 28),
              _sectionTitle('Horas e Valores'),
              const SizedBox(height: 12),
              _horasResumoCard(horasData),
            ],
            const SizedBox(height: 32),
          ],
        );
      },
    );
  }

  /// Saldo de abertura: soma de receitas e despesas pagas com data efetiva anterior ao início do período (igual ao painel).
  Future<double> _loadSaldoAbertura() async {
    final start = DateTime(_dateStart.year, _dateStart.month, _dateStart.day);
    final allDocs = await firestoreQueryCollectDocumentsBatched(
      _tx
          .where('date', isLessThan: Timestamp.fromDate(start))
          .orderBy('date', descending: false),
    ).timeout(
          _kReportsExportFirestoreTimeout,
          onTimeout: () => throw TimeoutException('Saldo de abertura: tempo esgotado.'),
        );
    double saldo = 0;
    var n = 0;
    for (final doc in allDocs) {
      final d = doc.data();
      final ts = d['date'];
      if (ts is! Timestamp) continue;
      final date = ts.toDate();
      final paidAtTs = d['paidAt'];
      final paidAt = paidAtTs is Timestamp ? paidAtTs.toDate() : null;
      final effectiveDate = paidAt ?? date;
      if (effectiveDate.isBefore(start)) {
        final isPaid = (d['status'] ?? 'paid').toString() == 'paid';
        if (!isPaid) continue;
        final amount = (d['amount'] ?? 0).toDouble();
        final type = (d['type'] ?? 'expense').toString();
        if (type == 'income') {
          saldo += amount;
        } else {
          saldo -= amount.abs();
        }
      }
      n++;
      if (n % 220 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return saldo;
  }

  Future<Map<String, dynamic>> _loadAllReportData() async {
    final txPair = await _getTransactionsPairCached();
    if (kIsWeb) {
      await Future<void>.delayed(const Duration(milliseconds: 48));
    }
    final saldoAbertura = await _loadSaldoAbertura();
    final accounts = await FinanceAccountsService().listOnce(_userDocId);
    final expenseListRaw = txPair['expense'] ?? const <Map<String, dynamic>>[];
    final incomeListRaw = txPair['income'] ?? const <Map<String, dynamic>>[];
    final expenseList = _filterByStatus(expenseListRaw, _filtroDespesas);
    final incomeList = _filterByStatus(incomeListRaw, _filtroReceitas);
    final accountLabels = {for (final a in accounts) a.id: a.displayName};
    final totalReceitas = incomeList.fold<double>(0, (s, e) => s + ((e['amount'] ?? 0) as num).toDouble());
    final totalDespesas = expenseList.fold<double>(0, (s, e) => s + ((e['amount'] ?? 0) as num).toDouble());
    final porConta = computeReportPorConta(incomeList, expenseList, accountLabels);
    final gastosPorCategoria = computeReportGastosPorCategoria(expenseList);
    final receitasPorCategoria = computeReportReceitasPorCategoria(incomeList);
    // Pré-preenche o cache de exportação/PDF (evita 2.ª leitura Firestore + saldo + contas ao gerar PDF).
    _exportFinanceKey = _financeExportCacheKey();
    _exportFinanceFuture = Future.value({
      'expenseListRaw': List<Map<String, dynamic>>.from(expenseListRaw),
      'incomeListRaw': List<Map<String, dynamic>>.from(incomeListRaw),
      'saldoAbertura': saldoAbertura,
      'financeAccList': accounts,
    });
    return {
      'expenseList': expenseList,
      'incomeList': incomeList,
      'totalReceitas': totalReceitas,
      'totalDespesas': totalDespesas,
      'saldoAbertura': saldoAbertura,
      'horasData': null,
      'previsaoData': null,
      'porConta': porConta,
      'gastosPorCategoria': gastosPorCategoria,
      'receitasPorCategoria': receitasPorCategoria,
    };
  }

  Widget _sectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.accent, AppColors.primary],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: _reportOnSurface,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _transactionList(List<Map<String, dynamic>> items, Color accentColor, String type, VoidCallback? onRefresh) {
    if (items.isEmpty) {
      return _emptyCard('Nenhum lançamento no período.');
    }
    final byPeriod = _groupByPeriod(items, (e) {
      final ts = e['date'];
      return ts is Timestamp ? ts.toDate() : DateTime.now();
    });
    final periodEntries = byPeriod.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return LayoutBuilder(
      builder: (context, c) {
        final stackSub = c.maxWidth < kReportSubtotalStackBreakpoint;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (periodEntries.isNotEmpty) ...[
              ...periodEntries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: stackSub
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: accentColor.withValues(alpha: 0.18)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  e.key,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: _reportOnSurfaceVar,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  CurrencyFormats.formatBRL(e.value),
                                  textAlign: TextAlign.end,
                                  style: TextStyle(fontWeight: FontWeight.w900, color: accentColor, fontSize: 16),
                                ),
                              ],
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(e.key, style: TextStyle(fontWeight: FontWeight.w600, color: _reportOnSurfaceVar, fontSize: 14)),
                              Text(
                                CurrencyFormats.formatBRL(e.value),
                                style: TextStyle(fontWeight: FontWeight.w800, color: accentColor, fontSize: 15),
                              ),
                            ],
                          ),
                  )),
              const SizedBox(height: 16),
            ],
            _ReportPaginatedTiles(
              items: items,
              itemBuilder: (e) => _transactionTile(e, accentColor, type, onRefresh),
            ),
          ],
        );
      },
    );
  }

  Widget _transactionTile(Map<String, dynamic> e, Color accentColor, String type, VoidCallback? onRefresh) {
    final ts = e['date'];
    final date = ts is Timestamp ? ts.toDate() : DateTime.now();
    final cat = (e['category'] ?? '').toString().trim();
    final desc = (e['description'] ?? '').toString().trim();
    final catLabel = cat.isNotEmpty ? cat : (type == 'income' ? 'Receita' : 'Despesa');
    final amount = _toDoubleDynamic(e['amount']);
    final receipt = Map<String, dynamic>.from(e['receipt'] ?? {});
    final hasReceiptView = ReceiptAttachmentUtils.hasViewableReceipt(receipt);
    final docId = (e['id'] ?? '').toString();
    final isPending = (e['status'] ?? 'paid').toString() != 'paid';
    // Layout em coluna para Android/iPhone: conteúdo com largura total e ações abaixo, evita texto espremido
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _reportSurface,
        borderRadius: BorderRadius.circular(_radiusCard),
        boxShadow: _cardShadow,
        border: _reportDark ? Border.all(color: _cs.outline.withValues(alpha: 0.28)) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: accentColor.withOpacity(0.12),
                  radius: 22,
                  child: Icon(Icons.receipt_long_rounded, color: accentColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Categoria: $catLabel',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _reportOnSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Descrição: $desc',
                          style: TextStyle(fontSize: 13, color: _reportOnSurfaceVar),
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        '${CurrencyFormats.formatBRL(amount)} · ${DateTimeFormats.dateBR.format(date)}',
                        style: TextStyle(fontSize: 12, color: _reportOnSurfaceVar),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (isPending && docId.isNotEmpty)
                  FilledButton.tonalIcon(
                    onPressed: () => _confirmarPagamentoTx(context, docId, onRefresh),
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    label: const Text('Confirmar pagamento', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: AppColors.success.withOpacity(0.15),
                      foregroundColor: AppColors.success,
                    ),
                  ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.attach_file_rounded, size: 22),
                  onPressed: () => mostrarComprovanteReceipt(context, receipt),
                  tooltip: 'Ver anexo',
                ),
                IconButton(
                  icon: Icon(Icons.edit_outlined, size: 22, color: AppColors.primary),
                  onPressed: docId.isEmpty ? null : () => _showEditTxDialog(context, e, type, onRefresh),
                  tooltip: 'Editar',
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, size: 22, color: Colors.red.shade400),
                  onPressed: docId.isEmpty ? null : () => _confirmDeleteTx(context, docId, type, onRefresh),
                  tooltip: 'Excluir',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Confirma pagamento/recebimento: sheet premium (data, banco, comprovante).
  Future<void> _confirmarPagamentoTx(BuildContext context, String docId, VoidCallback? onRefresh) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    if (docId.isEmpty) return;
    final txRef = _tx.doc(docId);
    final preSnap = await txRef.get();
    if (!preSnap.exists) return;
    final preData = preSnap.data() ?? {};
    final txType = (preData['type'] ?? 'expense').toString();
    final isIncome = txType == 'income';
    final rawAid = (preData['financeAccountId'] ?? '').toString().trim();
    final financeAccounts = await FinanceAccountsService().listOnce(_userDocId);
    if (!context.mounted) return;

    final result = await showFinanceConfirmPaymentSheet(
      context: context,
      isIncome: isIncome,
      financeAccounts: financeAccounts,
      initialFinanceAccountId: rawAid.isEmpty ? null : rawAid,
      orphanAccountId: rawAid,
      canAttachReceipt: widget.profile.temAcessoPremium,
      amountPreview: (preData['amount'] as num?)?.toDouble(),
      categoryPreview: (preData['category'] ?? '').toString(),
      descriptionPreview: (preData['description'] ?? '').toString(),
    );
    if (result == null || !context.mounted) return;

    try {
      await commitFinanceConfirmPayment(
        txRef: txRef,
        uid: widget.uid,
        result: result,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isIncome ? 'Recebimento confirmado.' : 'Pagamento confirmado.'),
        behavior: SnackBarBehavior.floating,
      ));
      onRefresh?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro ao confirmar: ${e.toString().split('\n').first}'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _verAnexo(String url, [String? fileName]) async {
    if (!mounted) return;
    mostrarAnexoNaMesmaTela(context, url: url, fileName: fileName ?? 'Anexo');
  }

  Future<void> _confirmDeleteTx(BuildContext context, String docId, String type, VoidCallback? onRefresh) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir lançamento?'),
        content: const Text('Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirm != true) return;
    final snap = await _tx.doc(docId).get();
    final data = snap.data() ?? {};
    final amount = (data['amount'] ?? 0).toDouble();
    final category = (data['category'] ?? '').toString();
    await _tx.doc(docId).delete();
    await LogsService().saveLog(
      modulo: 'Relatórios',
      acao: type == 'income' ? 'Excluiu receita' : 'Excluiu despesa',
      detalhes: '${category.isEmpty ? 'Categoria' : category} · ${CurrencyFormats.formatBRL(amount)}',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lançamento excluído.')));
      onRefresh?.call();
    }
  }

  /// Igual ao módulo Financeiro (`finance_screen.dart` `_editTx`): status Pago/Pendente, conta e comprovante.
  Future<void> _showEditTxDialog(BuildContext context, Map<String, dynamic> current, String type, VoidCallback? onRefresh) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final docId = (current['id'] ?? '').toString();
    if (docId.isEmpty) return;
    final loaded = await UserCategoriesService().load(_userDocId);
    final categories = type == 'income' ? loaded.income : loaded.expense;
    if (!context.mounted) return;
    final amountCtrl = TextEditingController(
      text: CurrencyFormats.formatBRLInput((current['amount'] ?? 0).toDouble()),
    );
    final descCtrl = TextEditingController(text: (current['description'] ?? '').toString());
    final currentCat = (current['category'] ?? '').toString().trim();
    final catCtrl = TextEditingController(text: currentCat.isEmpty ? (categories.isNotEmpty ? categories.first : '') : currentCat);
    String selectedCategory = (currentCat.isEmpty || categories.contains(currentCat)) ? (currentCat.isEmpty ? (categories.isNotEmpty ? categories.first : '__outra__') : currentCat) : '__outra__';
    if (selectedCategory.isEmpty) selectedCategory = categories.isNotEmpty ? categories.first : '__outra__';
    String status = (current['status'] ?? 'paid').toString();
    DateTime date = (current['date'] is Timestamp) ? (current['date'] as Timestamp).toDate() : DateTime.now();

    final receipt = Map<String, dynamic>.from(current['receipt'] ?? {});
    final hasExistingReceiptLink = ReceiptAttachmentUtils.hasViewableReceipt(receipt);
    bool removeReceipt = false;
    Uint8List? newReceiptBytes;
    String newReceiptName = '';
    String? newReceiptMime;

    final financeAccounts = await FinanceAccountsService().listOnce(_userDocId);
    final rawAid = (current['financeAccountId'] ?? '').toString().trim();
    var selectedFinanceAccountId = rawAid.isEmpty ? null : rawAid;
    if (type == 'expense' &&
        financeAccounts.isNotEmpty &&
        (selectedFinanceAccountId == null || selectedFinanceAccountId.trim().isEmpty)) {
      selectedFinanceAccountId = financeAccounts.first.id;
    }
    if (!context.mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          final hasExistingReceipt = hasExistingReceiptLink && !removeReceipt && newReceiptBytes == null;
          final hasNewReceipt = newReceiptBytes != null;
          final showComprovante = widget.profile.temAcessoPremium;
          final orphan = selectedFinanceAccountId != null &&
              selectedFinanceAccountId!.isNotEmpty &&
              !financeAccounts.any((a) => a.id == selectedFinanceAccountId);

          return AlertDialog(
            title: Text(type == 'income' ? 'Editar Receita' : 'Editar Despesa'),
            content: RepaintBoundary(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BrlAmountTextField(
                      controller: amountCtrl,
                      decoration: const InputDecoration(labelText: 'Valor', isDense: true),
                    ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    decoration: const InputDecoration(labelText: 'Categoria'),
                    items: [
                      ...categories.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                      const DropdownMenuItem(value: '__outra__', child: Text('Outra (digite abaixo)')),
                    ],
                    onChanged: (v) {
                      setState(() {
                        selectedCategory = v ?? categories.first;
                        if (selectedCategory != '__outra__') catCtrl.text = selectedCategory;
                      });
                    },
                  ),
                  if (selectedCategory == '__outra__') ...[
                    const SizedBox(height: 8),
                    FastTextField(controller: catCtrl, decoration: const InputDecoration(labelText: 'Nome da categoria')),
                  ],
                  const SizedBox(height: 10),
                  FastTextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Descrição')),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: Text('Data: ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}')),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                          if (picked != null) setState(() => date = picked);
                        },
                        child: const Text('Alterar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: 'paid', child: Text('Pago')),
                      DropdownMenuItem(value: 'pending', child: Text('Pendente')),
                    ],
                    onChanged: (v) => setState(() => status = v ?? 'paid'),
                  ),
                  const SizedBox(height: 12),
                  const Text('Conta', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 6),
                  if (financeAccounts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        rawAid.isNotEmpty
                            ? 'Esta movimentação está vinculada a uma conta removida. Cadastre uma conta em Bancos e cartões e selecione-a abaixo, ou use “Remover vínculo” se for receita.'
                            : 'Cadastre ao menos uma conta em Financeiro → Bancos e cartões. Despesas exigem conta vinculada.',
                        style: TextStyle(fontSize: 12, color: _reportOnSurfaceVar, height: 1.35),
                      ),
                    )
                  else
                    DropdownButtonFormField<String?>(
                      value: selectedFinanceAccountId,
                      decoration: const InputDecoration(labelText: 'Conta do lançamento', isDense: true),
                      items: [
                        if (type == 'income')
                          const DropdownMenuItem<String?>(value: null, child: Text('Sem conta vinculada (opcional)')),
                        ...financeAccounts.map(
                          (a) => DropdownMenuItem<String?>(value: a.id, child: Text(a.displayName, overflow: TextOverflow.ellipsis)),
                        ),
                        if (orphan)
                          DropdownMenuItem<String?>(value: rawAid, child: const Text('Manter vínculo antigo')),
                      ],
                      onChanged: (v) => setState(() => selectedFinanceAccountId = v),
                    ),
                  if (financeAccounts.isEmpty && rawAid.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() => selectedFinanceAccountId = null),
                      child: const Text('Remover vínculo (só use se for receita)'),
                    ),
                  if (showComprovante) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const Text('Comprovante', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 8),
                    if (hasExistingReceipt)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.visibility_rounded, size: 18),
                              label: const Text('Ver anexo'),
                              onPressed: () async {
                                if (!hasExistingReceiptLink) return;
                                await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => AnexoViewerScreen(
                                      url: ReceiptAttachmentUtils.viewUrl(receipt),
                                      fileName: ReceiptAttachmentUtils.fileName(receipt),
                                      storagePath: ReceiptAttachmentUtils.storagePath(receipt),
                                      mimeType: ReceiptAttachmentUtils.mimeType(receipt),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.delete_outline_rounded, size: 18),
                            label: const Text('Remover'),
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                            onPressed: () => setState(() { removeReceipt = true; newReceiptBytes = null; }),
                          ),
                        ],
                      ),
                    if (hasNewReceipt)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text(newReceiptName, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                            TextButton(
                              onPressed: () => setState(() { newReceiptBytes = null; newReceiptName = ''; newReceiptMime = null; removeReceipt = false; }),
                              child: const Text('Remover'),
                            ),
                          ],
                        ),
                      ),
                    OutlinedButton.icon(
                      icon: Icon(hasExistingReceipt || hasNewReceipt ? Icons.swap_horiz_rounded : Icons.attach_file_rounded, size: 18),
                      label: Text(hasExistingReceipt || hasNewReceipt ? 'Trocar comprovante' : 'Anexar comprovante'),
                      onPressed: () async {
                        final pick = await FilePicker.platform.pickFiles(withData: true);
                        if (pick == null || pick.files.isEmpty) return;
                        final f = pick.files.first;
                        final bytes = f.bytes ?? Uint8List(0);
                        final ext = (f.extension ?? '').toLowerCase();
                        if (!['pdf','png','jpg','jpeg'].contains(ext)) {
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Use PDF, PNG ou JPG.')));
                          return;
                        }
                        if (bytes.lengthInBytes > 5 * 1024 * 1024) {
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Arquivo grande. Máx. 5 MB.')));
                          return;
                        }
                        setState(() {
                          removeReceipt = false;
                          newReceiptBytes = bytes;
                          newReceiptName = f.name;
                          newReceiptMime = ext == 'pdf' ? 'application/pdf' : (ext == 'png' ? 'image/png' : 'image/jpeg');
                        });
                      },
                    ),
                  ],
                ],
              ),
            ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: () {
                  if (type == 'expense' &&
                      financeAccounts.isNotEmpty &&
                      (selectedFinanceAccountId == null || selectedFinanceAccountId!.trim().isEmpty)) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Selecione a conta da despesa.')),
                    );
                    return;
                  }
                  if (type == 'expense' && financeAccounts.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Cadastre uma conta em Bancos e cartões antes de salvar a despesa.')),
                    );
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true || !context.mounted) return;
    final amount = CurrencyFormats.parseBRLInput(amountCtrl.text) ?? 0;
    String categoryFinal = catCtrl.text.trim();
    if (categoryFinal.isEmpty || categoryFinal == '__outra__') categoryFinal = type == 'income' ? 'Receita' : 'Despesa';
    if (amount.isNaN || amount.isInfinite || amount <= 0) return;

    final updateData = <String, dynamic>{
      'amount': amount,
      'category': categoryFinal,
      'description': descCtrl.text.trim(),
      'status': status,
      'date': Timestamp.fromDate(date),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final aid = selectedFinanceAccountId?.trim() ?? '';
    if (aid.isEmpty) {
      updateData['financeAccountId'] = FieldValue.delete();
    } else {
      updateData['financeAccountId'] = aid;
    }

    if (widget.profile.temAcessoPremium) {
      if (removeReceipt) {
        updateData['receipt'] = FieldValue.delete();
      } else if (newReceiptBytes != null && newReceiptBytes!.isNotEmpty && newReceiptName.isNotEmpty && newReceiptMime != null) {
        try {
          final fn = FunctionsService();
          final txPath = 'users/${_userDocId}/transactions/$docId';
          await fn.uploadReceiptToStorage(txPath: txPath, filename: newReceiptName, bytes: newReceiptBytes!, mimeType: newReceiptMime!);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao anexar comprovante: $e')));
          }
        }
      }
    }

    await _tx.doc(docId).update(updateData);
    await LogsService().saveLog(
      modulo: 'Relatórios',
      acao: type == 'income' ? 'Editou receita' : 'Editou despesa',
      detalhes: '${categoryFinal} · ${CurrencyFormats.formatBRL(amount)}',
    );
    if (context.mounted) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lançamento atualizado.')));
      onRefresh?.call();
    }
  }

  /// Tile de um plantão no detalhamento do Relatório Banco de Horas: data, label, Nº escala, Observação (abaixo), valor, Editar e Remover (com confirmação).
  Widget _buildBancoHorasPlantaoTile(Map<String, dynamic> e, {VoidCallback? onRefresh}) {
    final dt = e['date'];
    final date = dt is DateTime ? dt : (dt is Timestamp ? dt.toDate() : DateTime.now());
    final hoje = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final dataPlantao = DateTime(date.year, date.month, date.day);
    final jaT = e['jaTirado'] == true;
    final statusTxt =
        dataPlantao.isAfter(hoje) ? 'A confirmar' : (jaT ? 'Já tirado' : 'A tirar');
    final scaleId = (e['scaleId'] ?? '').toString();
    final scaleNumber = (e['scaleNumber'] ?? '').toString().trim();
    final notesStr = (e['notes'] ?? '').toString().trim();
    final isComp = e['isCompromisso'] == true;
    final temFin = e['temFinanceiro'] == true;
    final bar = isComp ? AppColors.accent : (temFin ? AppColors.primary : const Color(0xFF7C3AED));
    final outline =
        _reportDark ? _cs.outline.withValues(alpha: 0.32) : AppColors.deepBlueDark.withValues(alpha: 0.06);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _reportSurface,
        borderRadius: BorderRadius.circular(_radiusCard),
        border: Border(
          left: BorderSide(width: 4, color: bar),
          top: BorderSide(color: outline),
          right: BorderSide(color: outline),
          bottom: BorderSide(color: outline),
        ),
        boxShadow: _cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radiusCard),
        child: LayoutBuilder(
          builder: (context, c) {
                    final stack = c.maxWidth < kReportTileStackBreakpoint;
                    final details = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (isComp) _tagPlantaoChip('Compromisso', AppColors.accent),
                            if (!isComp && !temFin) _tagPlantaoChip('Sem fin. painel', const Color(0xFF7C3AED)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          DateTimeFormats.dateBR.format(date),
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 12, color: _reportOnSurface),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (e['label'] ?? '').toString(),
                          style: TextStyle(
                              color: _reportOnSurfaceVar, fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Nº escala: ${scaleNumber.isEmpty ? '-' : scaleNumber}',
                          style: TextStyle(fontSize: 11, color: _reportOnSurfaceVar, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          RelatorioService.formatHorasLinhaPdf(
                            _toDoubleDynamic(e['hoursDay']),
                            _toDoubleDynamic(e['hoursNight']),
                          ),
                          style: TextStyle(fontSize: 11, color: _reportOnSurfaceVar, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Status: $statusTxt',
                          style: TextStyle(
                            fontSize: 11,
                            color: statusTxt == 'A confirmar'
                                ? Colors.orange.shade800
                                : (jaT ? Colors.green.shade800 : Colors.blue.shade800),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Obs.: ${notesStr.isEmpty ? '-' : notesStr}',
                          style: TextStyle(fontSize: 11, color: _reportOnSurfaceVar),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    );
                    final valorTxt = Text(
                      CurrencyFormats.formatBRL(_toDoubleDynamic(e['valor'])),
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, color: AppColors.primary, fontSize: 15),
                    );
                    final editBtn = FilledButton.tonal(
                      onPressed: () => _editarPlantaoRelatorio(context, e, onRefresh),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(40, 40),
                        padding: EdgeInsets.zero,
                        backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                        foregroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Icon(Icons.edit_outlined, size: 20),
                    );
                    final delBtn = FilledButton.tonal(
                      onPressed: () => _confirmarRemoverPlantaoRelatorio(context, e, onRefresh),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(40, 40),
                        padding: EdgeInsets.zero,
                        backgroundColor: AppColors.error.withValues(alpha: 0.12),
                        foregroundColor: AppColors.error,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Icon(Icons.delete_outline_rounded, size: 20),
                    );
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      child: stack
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                details,
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(child: valorTxt),
                                    if (scaleId.isNotEmpty) ...[editBtn, const SizedBox(width: 8), delBtn],
                                  ],
                                ),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: details),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    valorTxt,
                                    if (scaleId.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      editBtn,
                                      const SizedBox(height: 6),
                                      delBtn,
                                    ],
                                  ],
                                ),
                              ],
                            ),
                    );
          },
        ),
      ),
    );
  }

  Widget _tagPlantaoChip(String label, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: c),
      ),
    );
  }

  Future<void> _editarPlantaoRelatorio(BuildContext context, Map<String, dynamic> e, VoidCallback? onRefresh) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final scaleId = (e['scaleId'] ?? '').toString();
    if (scaleId.isEmpty) return;
    final scaleNumberCtrl = TextEditingController(text: (e['scaleNumber'] ?? '').toString());
    final observacoesCtrl = TextEditingController(text: (e['notes'] ?? '').toString());
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar plantão'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FastTextField(
                controller: scaleNumberCtrl,
                decoration: const InputDecoration(
                  labelText: 'Número da escala',
                  hintText: 'EX.: 123',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.none,
              ),
              const SizedBox(height: 16),
              FastTextField(
                controller: observacoesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Observações (máx. 20 caracteres)',
                  hintText: 'Aceita acentos e caracteres especiais',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                maxLines: 2,
                maxLength: 20,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                textCapitalization: TextCapitalization.sentences,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (saved != true || !context.mounted) return;
    try {
      final notesRaw = observacoesCtrl.text.trim();
      final notes = normalizeScaleNotesForSave(notesRaw);
      await _scales.doc(scaleId).update({
        'scaleNumber': scaleNumberCtrl.text.trim(),
        'notes': notes.isEmpty ? FieldValue.delete() : notes,
      });
      if (context.mounted) {
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plantão atualizado.')));
        onRefresh?.call();
      }
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao atualizar: ${err.toString().split('\n').first}'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _confirmarRemoverPlantaoRelatorio(BuildContext context, Map<String, dynamic> e, VoidCallback? onRefresh) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final scaleId = (e['scaleId'] ?? '').toString();
    if (scaleId.isEmpty) return;
    final label = (e['label'] ?? 'Plantão').toString();
    final dt = e['date'];
    final date = dt is DateTime ? dt : (dt is Timestamp ? dt.toDate() : DateTime.now());
    final dateStr = DateTimeFormats.dateBR.format(date);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover plantão?'),
        content: Text(
          'O plantão "$label" do dia $dateStr será excluído da escala. Esta ação não pode ser desfeita.\n\nDeseja continuar?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final snap = await _scales.doc(scaleId).get();
      if (snap.exists) {
        final entry = ScaleEntry.fromDoc(snap);
        await ExpressCompromissoAgendaSync.deleteScaleWithAgendaSync(
          userDocId: _userDocId,
          entry: entry,
        );
      } else if (ExpressCompromissoAgendaSync.reminderIdFromScaleDocId(scaleId) !=
          null) {
        await ExpressCompromissoAgendaSync.deleteLinkedFromScaleDoc(
          userDocId: _userDocId,
          scaleDocId: scaleId,
        );
      } else {
        await _scales.doc(scaleId).delete();
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plantão removido.')));
        onRefresh?.call();
      }
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao remover: ${err.toString().split('\n').first}'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Widget _horasResumoCard(Map<String, dynamic> data) {
    final totalHorasDiurnas = _toDoubleDynamic(data['totalHorasDiurnas']);
    final totalHorasNoturnas = _toDoubleDynamic(data['totalHorasNoturnas']);
    final totalValor = _toDoubleDynamic(data['totalValor']);
    Widget blocoHoras(String label, String valor, Color corValor) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _reportOnSurfaceVar),
              softWrap: true),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              maxLines: 1,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900, color: corValor),
            ),
          ),
        ],
      );
    }

    Widget blocoValorTotal() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Valor total',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _reportOnSurfaceVar),
              softWrap: true),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              CurrencyFormats.formatBRLTight(totalValor),
              maxLines: 1,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.success),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(_paddingCard),
      decoration: BoxDecoration(
        color: _reportSurface,
        borderRadius: BorderRadius.circular(_radiusCard),
        boxShadow: _cardShadow,
        border: Border.all(
          color: _reportDark ? _cs.outline.withValues(alpha: 0.32) : AppColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumo do período',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _reportOnSurfaceVar),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) {
              final scale =
                  MediaQuery.textScalerOf(context).scale(14) / 14.0;
              final stack = c.maxWidth < kReportGridBreakpointCompact || scale > 1.12;
              if (stack) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    blocoHoras('Total horas diurnas',
                        '${totalHorasDiurnas.toStringAsFixed(1)} h',
                        AppColors.primary),
                    const SizedBox(height: 14),
                    blocoHoras(
                        'Total horas noturnas',
                        '${totalHorasNoturnas.toStringAsFixed(1)} h',
                        Colors.indigo.shade700),
                    const SizedBox(height: 14),
                    blocoValorTotal(),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: blocoHoras(
                        'Total horas diurnas',
                        '${totalHorasDiurnas.toStringAsFixed(1)} h',
                        AppColors.primary),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: blocoHoras(
                        'Total horas noturnas',
                        '${totalHorasNoturnas.toStringAsFixed(1)} h',
                        Colors.indigo.shade700),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: blocoValorTotal()),
                ],
              );
            },
          ),
          const Divider(height: 22),
          Text(
            'Indicadores complementares',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _reportOnSurfaceVar,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Hora extra: horas em plantões marcados como «pago». Compromissos não usam financeiro no painel.',
            style: TextStyle(fontSize: 11, color: _reportOnSurfaceVar, height: 1.3),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _metricChipReport(
                'Pago / hora extra',
                '${_fmtHorasUi(_toDoubleDynamic(data['horasPlantaoMarcadoPago']))} h',
                AppColors.logoOrange,
              ),
              _metricChipReport(
                'Compromissos',
                '${_toIntDynamic(data['qtdCompromissos'])} · ${_fmtHorasUi(_toDoubleDynamic(data['horasCompromissos']))} h',
                AppColors.accent,
              ),
              _metricChipReport(
                'Profissional sem fin. painel',
                '${_fmtHorasUi(_toDoubleDynamic(data['horasProfissionalSemFinanceiro']))} h',
                const Color(0xFF7C3AED),
              ),
            ],
          ),
          if (data['resumoBancoPdf'] is Map<String, dynamic>) ...[
            const Divider(height: 28),
            Text(
              'Resumo alinhado ao PDF (realizadas / pendentes)',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary),
            ),
            const SizedBox(height: 10),
            ..._linhasResumoBancoPdfUi(data['resumoBancoPdf'] as Map<String, dynamic>),
          ],
          if (data['categoriasBanco'] is List && (data['categoriasBanco'] as List).isNotEmpty) ...[
            const Divider(height: 28),
            Text(
              'Por categoria (escalas / compromissos e vínculos)',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary),
            ),
            const SizedBox(height: 10),
            ..._linhasCategoriasBancoHorasUi(
              (data['categoriasBanco'] as List).cast<ResumoBancoHorasCategoriaPdf>(),
            ),
          ],
        ],
      ),
    );
  }

  String _fmtHorasUi(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

  Widget _metricChipReport(String title, String value, Color accent) {
    return Container(
      constraints: const BoxConstraints(minWidth: 148),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.42)),
        color: accent.withValues(alpha: 0.08),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: accent,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: _reportOnSurface,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _linhasCategoriasBancoHorasUi(List<ResumoBancoHorasCategoriaPdf> cats) {
    return cats.map((c) {
      final qTot = c.qtdJaTirado + c.qtdATirar;
      final hTot = c.horasJaTirado + c.horasATirar;
      final vJa = c.mostrarColunaValor ? CurrencyFormats.formatBRL(c.valorJaRecebido) : '-';
      final vP = c.mostrarColunaValor ? CurrencyFormats.formatBRL(c.valorATirar) : '-';
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c.titulo,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.primary),
            ),
            const SizedBox(height: 4),
            Text(
              'Quantidade: ${c.qtdJaTirado} já tirados · ${c.qtdATirar} a tirar (total $qTot)',
              style: TextStyle(fontSize: 11, color: _reportOnSurfaceVar, height: 1.3),
            ),
            Text(
              'Horas: ${_fmtHorasUi(c.horasJaTirado)} h já · ${_fmtHorasUi(c.horasATirar)} h a tirar (total ${_fmtHorasUi(hTot)} h)',
              style: TextStyle(fontSize: 11, color: _reportOnSurfaceVar, height: 1.3),
            ),
            Text(
              'Valores: $vJa recebidos · $vP a receber',
              style: TextStyle(fontSize: 11, color: _reportOnSurfaceVar, height: 1.3),
            ),
          ],
        ),
      );
    }).toList();
  }

  /// Mesmas métricas do bloco [ResumoBancoHorasPdf] no topo do PDF de banco de horas.
  List<Widget> _linhasResumoBancoPdfUi(Map<String, dynamic> m) {
    String h(String key) => _toDoubleDynamic(m[key]).toStringAsFixed(1);
    String fmt(num v) => CurrencyFormats.formatBRL(v);
    Widget linha(String esq, String dir) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                esq,
                style: TextStyle(fontSize: 11, color: _reportOnSurfaceVar, height: 1.25),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              dir,
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
          ],
        ),
      );
    }

    final vRec = _toDoubleDynamic(m['valorJaRecebido']);
    final vPend = _toDoubleDynamic(m['valorAReceber']);
    return [
      linha('Horas diurnas (total)', '${h('horasDiurnasTotal')} h'),
      linha('Horas noturnas (total)', '${h('horasNoturnasTotal')} h'),
      linha('Diurnas realizadas / pendentes', '${h('horasDiurnasRealizadas')} h / ${h('horasDiurnasPendentes')} h'),
      linha('Noturnas realizadas / pendentes', '${h('horasNoturnasRealizadas')} h / ${h('horasNoturnasPendentes')} h'),
      linha('Valores já recebidos', fmt(vRec)),
      linha('Valores a receber', fmt(vPend)),
      linha('Total valores no período', fmt(vRec + vPend)),
      linha('Horas «pago» / hora extra', '${h('horasPlantaoMarcadoPago')} h'),
      linha('Compromissos (quantidade)', '${m['qtdCompromissos'] ?? 0}'),
      linha('Horas em compromissos', '${h('horasCompromissos')} h'),
      linha('Horas sem financeiro no painel', '${h('horasProfissionalSemFinanceiro')} h'),
    ];
  }

  Widget _emptyCard(String message) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _reportSurface,
        borderRadius: BorderRadius.circular(_radiusCard),
        boxShadow: _cardShadow,
        border: _reportDark ? Border.all(color: _cs.outline.withValues(alpha: 0.28)) : null,
      ),
      child: Center(
        child: Text(message, style: TextStyle(color: _reportOnSurfaceVar, fontSize: 14)),
      ),
    );
  }

  Map<String, double> _groupByPeriod(List<Map<String, dynamic>> items, DateTime Function(Map<String, dynamic>) getDate) {
    final map = <String, double>{};
    for (final e in items) {
      final d = getDate(e);
      final key = _periodKey(d);
      final amount = (e['amount'] ?? 0) as num;
      map[key] = (map[key] ?? 0) + amount.toDouble();
    }
    return map;
  }

  /// Agrupa por dia no período selecionado (apenas data inicial e final).
  String _periodKey(DateTime d) => DateTimeFormats.dateBR.format(d);

  /// Filtra lista de transações por status: todos | pagos/recebidos (paid) | pendentes.
  static List<Map<String, dynamic>> _filterByStatus(List<Map<String, dynamic>> list, String filter) {
    if (filter == 'todos') return list;
    final onlyPaid = (filter == 'pagos' || filter == 'recebidos');
    return list.where((e) {
      final isPaid = (e['status'] ?? 'paid').toString() == 'paid';
      return onlyPaid ? isPaid : !isPaid;
    }).toList();
  }

  /// Retorna (início real, fim real) do plantão em DateTime.
  (DateTime, DateTime) _actualStartEnd(ScaleEntry e) {
    final partsStart = e.start.split(':');
    final partsEnd = e.end.split(':');
    final sh = int.tryParse(partsStart.first) ?? 0;
    final sm = partsStart.length > 1 ? (int.tryParse(partsStart[1]) ?? 0) : 0;
    final eh = int.tryParse(partsEnd.first) ?? 0;
    final em = partsEnd.length > 1 ? (int.tryParse(partsEnd[1]) ?? 0) : 0;
    final actualStart = DateTime(e.date.year, e.date.month, e.date.day, sh, sm, 0);
    final actualEnd = (eh * 60 + em) <= (sh * 60 + sm)
        ? DateTime(e.date.year, e.date.month, e.date.day + 1, eh, em, 0)
        : DateTime(e.date.year, e.date.month, e.date.day, eh, em, 0);
    return (actualStart, actualEnd);
  }

  static String _employerTypeForEntry(ScaleEntry e, List<ShiftLocation> locations) {
    if (e.employerType != null && e.employerType!.isNotEmpty) return e.employerType!;
    final labelBase = (e.label ?? '').trim().toUpperCase();
    final abbr = (e.abbreviation ?? '').trim().toUpperCase();
    if (labelBase.isEmpty && abbr.isEmpty) return 'private';
    for (final loc in locations) {
      final nameBase = ShiftLocation.baseNameFromFull(loc.name).toUpperCase();
      final locAbbr = loc.abbreviation.trim().toUpperCase();
      if (nameBase.isNotEmpty && (labelBase.contains(nameBase) || nameBase.contains(labelBase))) return loc.employerType.name;
      if (locAbbr.isNotEmpty && (abbr == locAbbr || labelBase.contains(locAbbr))) return loc.employerType.name;
    }
    return 'private';
  }

  /// Limite de segurança por leitura; períodos longos usam paginação (não mais 1000 docs = ano/mês cortado).
  static const int _maxHorasItems = 1000;
  static const int _kBancoHorasQueryBatch = 500;
  static const int _kBancoHorasMaxDocs = 15000;

  Future<Map<String, dynamic>> _loadHorasValores() async {
    try {
      final start = DateTime(_dateStart.year, _dateStart.month, _dateStart.day);
      final end = DateTime(_dateEnd.year, _dateEnd.month, _dateEnd.day, 23, 59, 59);
      final diaAnterior = start.subtract(const Duration(days: 1));
      List<QueryDocumentSnapshot<Map<String, dynamic>>> scaleDocs;
      try {
        scaleDocs = [];
        QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
        while (scaleDocs.length < _kBancoHorasMaxDocs) {
          var q = _scales
              .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(diaAnterior))
              .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
              .orderBy('date');
          if (cursor != null) {
            q = q.startAfterDocument(cursor);
          }
          final batch = await firestoreQueryGetReliable(q.limit(_kBancoHorasQueryBatch));
          if (batch.docs.isEmpty) break;
          scaleDocs.addAll(batch.docs);
          cursor = batch.docs.last;
          if (batch.docs.length < _kBancoHorasQueryBatch) break;
        }
      } catch (_) {
        // Fallback definitivo: busca local e filtra por período (evita quebrar por índice/tipo legado).
        final fallbackSnap = await firestoreQueryGetReliable(_scales.limit(_maxHorasItems * 3));
        scaleDocs = fallbackSnap.docs.where((d) {
          final dt = _extractScaleDateDynamic(d.data()['date']);
          if (dt == null) return true; // deixa parse tentar (legado), sem derrubar
          return !dt.isBefore(diaAnterior) && !dt.isAfter(end);
        }).take(_kBancoHorasMaxDocs).toList();
      }
      final asyncDeps = await Future.wait<dynamic>([
        firestoreQueryGetReliable(
          FirebaseFirestore.instance.collection('users').doc(_userDocId).collection('locations'),
        ),
        ScaleRatesService().getRates(uid: _userDocId),
      ]);
      final locationsSnap = asyncDeps[0] as QuerySnapshot<Map<String, dynamic>>;
      final locations = locationsSnap.docs
          .map((d) => ShiftLocation.fromMap(d.id, d.data()))
          .where((l) => l.name.isNotEmpty || l.abbreviation.isNotEmpty)
          .toList();
      final rates = asyncDeps[1] as ScaleRates;
      final items = <Map<String, dynamic>>[];
      double totalHoras = 0, totalValor = 0, totalHorasDiurnas = 0, totalHorasNoturnas = 0;
      final byPeriod = <String, Map<String, double>>{};
      final hojeRef =
          DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

      for (final doc in scaleDocs) {
        final docSnap = doc as DocumentSnapshot<Map<String, dynamic>>;
        // Espelhos da Agenda não entram no Banco de Horas — eles têm
        // relatório próprio em "Compromissos e Audiências" (Agenda).
        // Sem este filtro, audiências/compromissos da Agenda apareceriam
        // duplicados aqui e no relatório da Agenda.
        final sd = docSnap.data() ?? const {};
        if (sd['isAgendaMirror'] == true) continue;
        if (sd['isProdutividadeFolgaMirror'] == true) continue;
        ScaleEntry e;
        try {
          e = ScaleEntry.fromDoc(docSnap);
        } catch (_) {
          // Evita quebrar o relatório inteiro por um registro legado mal tipado.
          continue;
        }
        final employerType = _employerTypeForEntry(e, locations);
        if (_filtroVinculoBancoHoras != 'todos' && employerType != _filtroVinculoBancoHoras) continue;
        final (actualStart, actualEnd) = _actualStartEnd(e);
        double h;
        double v;
        double hDay = 0, hNight = 0;
        DateTime displayDate = e.date;
        if (actualStart.isBefore(start)) {
          if (actualEnd.isBefore(start) || actualEnd.isAtSameMomentAs(start)) continue;
          final clampEnd = actualEnd.isAfter(end) ? end : actualEnd;
          final res = await ScaleRatesService().computeShiftForUid(
            uid: _userDocId,
            start: start,
            end: clampEnd,
            entryDate: e.date,
          );
          hDay = (res['hoursDay'] ?? 0).toDouble();
          hNight = (res['hoursNight'] ?? 0).toDouble();
          h = hDay + hNight;
          v = res['total'] ?? 0;
          displayDate = start;
        } else if (actualEnd.isAfter(end)) {
          final res = await ScaleRatesService().computeShiftForUid(
            uid: _userDocId,
            start: actualStart,
            end: end,
            entryDate: e.date,
          );
          hDay = (res['hoursDay'] ?? 0).toDouble();
          hNight = (res['hoursNight'] ?? 0).toDouble();
          h = hDay + hNight;
          v = res['total'] ?? 0;
        } else {
          hDay = e.hoursDay;
          hNight = e.hoursNight;
          h = hDay + hNight;
          v = e.totalValue;
        }
        final jaTirado = e.effectiveJaTiradoParaExibicaoComLocais(hojeRef, locations);
        if (_filtroJaTiradoBancoHoras == 'ja_tirados' && !jaTirado) continue;
        if (_filtroJaTiradoBancoHoras == 'a_tirar' && jaTirado) continue;
        totalHoras += h;
        totalValor += v;
        totalHorasDiurnas += hDay;
        totalHorasNoturnas += hNight;
        final key = _periodKey(displayDate);
        byPeriod[key] ??= {'horas': 0, 'valor': 0};
        byPeriod[key]!['horas'] = (byPeriod[key]!['horas'] ?? 0) + h;
        byPeriod[key]!['valor'] = (byPeriod[key]!['valor'] ?? 0) + v;
        final label = (e.label ?? '').toString().trim().isEmpty ? 'Plantão' : (e.label ?? 'Plantão');
        items.add({
          'scaleId': docSnap.id,
          'label': label,
          'date': displayDate,
          'horas': h,
          'valor': v,
          'scaleNumber': e.scaleNumber ?? '',
          'notes': e.notes ?? '',
          'isCompromisso': e.isCompromisso,
          'employerType': employerType,
          'hoursDay': hDay,
          'hoursNight': hNight,
          'paid': e.paid,
          'jaTirado': jaTirado,
          'temFinanceiro': e.temFinanceiroPainelComLocais(locations),
        });
      }

      // Relatório Banco de Horas usa apenas escalas (plantões lançados em Escalas ou pelo atalho com pré-cadastro).
      // Não incluir calculator_entries para que todas as linhas mostrem o nome do plantão (pré-cadastro), igual às escalas.
      double horasPlantaoMarcadoPago = 0;
      int qtdCompromissos = 0;
      double horasCompromissos = 0;
      double horasProfissionalSemFinanceiro = 0;
      for (final it in items) {
        final h = _toDoubleDynamic(it['horas']);
        final isC = it['isCompromisso'] == true;
        final temFin = it['temFinanceiro'] == true;
        final paid = it['paid'] == true;
        if (isC) {
          qtdCompromissos++;
          horasCompromissos += h;
        } else {
          if (paid) horasPlantaoMarcadoPago += h;
          if (!temFin) horasProfissionalSemFinanceiro += h;
        }
      }
      items.sort((a, b) {
        final da = a['date'];
        final db = b['date'];
        final ad = da is DateTime ? da : (da is Timestamp ? da.toDate() : DateTime(2000));
        final bd = db is DateTime ? db : (db is Timestamp ? db.toDate() : DateTime(2000));
        return ad.compareTo(bd);
      });
      double rHdT = 0,
          rHnT = 0,
          rHdR = 0,
          rHnR = 0,
          rHdP = 0,
          rHnP = 0,
          rVrec = 0,
          rVpend = 0;
      for (final it in items) {
        final hDay = _toDoubleDynamic(it['hoursDay']);
        final hNight = _toDoubleDynamic(it['hoursNight']);
        rHdT += hDay;
        rHnT += hNight;
        if (it['jaTirado'] == true) {
          rHdR += hDay;
          rHnR += hNight;
        } else {
          rHdP += hDay;
          rHnP += hNight;
        }
        final valor = _toDoubleDynamic(it['valor']);
        if (it['isCompromisso'] != true && valor > 0) {
          if (it['jaTirado'] == true) {
            rVrec += valor;
          } else {
            rVpend += valor;
          }
        }
      }
      final linhasCat = items
          .map((it) => <String, dynamic>{
                'isCompromisso': it['isCompromisso'] == true,
                'temFinanceiro': it['temFinanceiro'] == true,
                'employerType': (it['employerType'] ?? 'private').toString(),
                'jaTirado': it['jaTirado'] == true,
                'hoursDay': _toDoubleDynamic(it['hoursDay']),
                'hoursNight': _toDoubleDynamic(it['hoursNight']),
                'valor': _toDoubleDynamic(it['valor']),
                'paid': it['paid'] == true,
              })
          .toList();
      final categoriasBanco = RelatorioService.buildCategoriasResumoBancoHoras(linhasCat);

      final truncated = scaleDocs.length >= _kBancoHorasMaxDocs;
      return {
        'totalHoras': totalHoras,
        'totalValor': totalValor,
        'totalHorasDiurnas': totalHorasDiurnas,
        'totalHorasNoturnas': totalHorasNoturnas,
        'items': items,
        'byPeriod': byPeriod,
        'truncated': truncated,
        'categoriasBanco': categoriasBanco,
        'horasPlantaoMarcadoPago': horasPlantaoMarcadoPago,
        'qtdCompromissos': qtdCompromissos,
        'horasCompromissos': horasCompromissos,
        'horasProfissionalSemFinanceiro': horasProfissionalSemFinanceiro,
        'resumoBancoPdf': {
          'horasDiurnasTotal': rHdT,
          'horasNoturnasTotal': rHnT,
          'horasDiurnasRealizadas': rHdR,
          'horasNoturnasRealizadas': rHnR,
          'horasDiurnasPendentes': rHdP,
          'horasNoturnasPendentes': rHnP,
          'valorJaRecebido': rVrec,
          'valorAReceber': rVpend,
          'horasPlantaoMarcadoPago': horasPlantaoMarcadoPago,
          'qtdCompromissos': qtdCompromissos,
          'horasCompromissos': horasCompromissos,
          'horasProfissionalSemFinanceiro': horasProfissionalSemFinanceiro,
        },
      };
    } catch (_) {
      // Blindagem final: nunca derrubar a tela de Relatórios por erro de leitura no banco de horas.
      return {
        'totalHoras': 0.0,
        'totalValor': 0.0,
        'totalHorasDiurnas': 0.0,
        'totalHorasNoturnas': 0.0,
        'items': const <Map<String, dynamic>>[],
        'byPeriod': const <String, Map<String, double>>{},
        'truncated': false,
        'categoriasBanco': const <ResumoBancoHorasCategoriaPdf>[],
        'horasPlantaoMarcadoPago': 0.0,
        'qtdCompromissos': 0,
        'horasCompromissos': 0.0,
        'horasProfissionalSemFinanceiro': 0.0,
        'resumoBancoPdf': const <String, dynamic>{},
      };
    }
  }
}

/// Lista de lançamentos do relatório renderizada em blocos (paginação leve).
/// Evita construir centenas de cartões de uma vez (jank no Android), mostrando
/// um lote inicial e ampliando com "Carregar mais". Cada instância é isolada.
class _ReportPaginatedTiles extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final Widget Function(Map<String, dynamic> item) itemBuilder;

  const _ReportPaginatedTiles({
    required this.items,
    required this.itemBuilder,
  });

  @override
  State<_ReportPaginatedTiles> createState() => _ReportPaginatedTilesState();
}

class _ReportPaginatedTilesState extends State<_ReportPaginatedTiles> {
  static const int _pageSize = 60;
  int _limit = _pageSize;

  @override
  void didUpdateWidget(covariant _ReportPaginatedTiles oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Período/filtro mudou: volta ao primeiro lote.
    if (!identical(oldWidget.items, widget.items)) {
      _limit = _pageSize;
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.items.length;
    final shown = total < _limit ? total : _limit;
    final remaining = total - shown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shown; i++)
          RepaintBoundary(child: widget.itemBuilder(widget.items[i])),
        if (remaining > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _limit += _pageSize),
                icon: const Icon(Icons.expand_more_rounded, size: 20),
                label: Text('Carregar mais ($remaining restantes)'),
              ),
            ),
          ),
      ],
    );
  }
}
