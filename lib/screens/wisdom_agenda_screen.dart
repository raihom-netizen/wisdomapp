import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/user_profile.dart';
import '../screens/compromisso_form_page.dart';
import '../constants/currency_formats.dart';
import '../models/finance_account.dart';
import '../services/compromisso_reminder_service.dart';
import '../services/finance_accounts_service.dart';
import '../services/fixed_expense_preferences_service.dart';
import '../services/fixed_income_preferences_service.dart';
import '../services/google_calendar_sync_service.dart';
import '../services/relatorio_service.dart';
import 'report_preview_screen.dart';
import '../shared/utils/holiday_helper.dart';
import '../theme/agenda_modern_ui.dart';
import '../theme/app_colors.dart';
import '../utils/agenda_finance_pending_utils.dart';
import '../utils/finance_account_balance_utils.dart';
import '../utils/finance_transactions_hub.dart';
import '../utils/finance_transactions_realtime.dart';
import '../widgets/finance_transfer_bottom_sheet.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/premium_upgrade.dart';
import '../widgets/agenda_finance_pending_item_card.dart';
import '../widgets/agenda_open_item_card.dart';
import '../widgets/finance_transaction_edit_dialog.dart';
import '../widgets/agenda_pdf_export_sheet.dart';
import '../widgets/google_calendar_integration_toggle.dart';
import '../widgets/shell_keyboard_bottom_pad.dart';

enum _AgendaMesAba { financeiro, particular }

/// Módulo **Agenda** WISDOMAPP — calendário premium (padrão Controle Total),
/// resumo do dia, feriados e grid de compromissos com edição/exclusão.
class WisdomAgendaScreen extends StatefulWidget {
  const WisdomAgendaScreen({
    super.key,
    required this.uid,
    required this.profile,
    this.isShellVisible = true,
    this.shellScrollController,
    this.onNavigateTo,
  });

  final String uid;
  final UserProfile profile;
  final bool isShellVisible;
  final ScrollController? shellScrollController;
  final void Function(int index)? onNavigateTo;

  @override
  State<WisdomAgendaScreen> createState() => _WisdomAgendaScreenState();
}

class _WisdomAgendaScreenState extends State<WisdomAgendaScreen> {
  static const _corCompromisso = Color(0xFF12B5A5);

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Set<DateTime> _googleBusyDays = {};
  Map<DateTime, List<GoogleCalendarEventItem>> _googleEventsByDay = {};
  bool _googleSyncLoading = false;
  bool _googleEnabled = false;
  StreamSubscription<bool>? _googleEnabledSub;
  int _streamGeneration = 0;
  int _mesAbaIndex = 0;

  _AgendaMesAba get _mesAba => _AgendaMesAba.values[_mesAbaIndex];

  String get _userDocId => firestoreUserDocIdForAppShell(widget.uid);

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    unawaited(GoogleCalendarSyncService.completeWebOAuthReturnIfNeeded());
    unawaited(_bootstrapGoogleCalendar());
    _googleEnabledSub =
        GoogleCalendarSyncService.enabledStream(_userDocId).listen(
      (enabled) {
        if (!mounted) return;
        if (_googleEnabled != enabled) {
          setState(() => _googleEnabled = enabled);
          if (enabled) {
            _refreshGoogleDays();
          } else {
            setState(() => _googleBusyDays = {});
          }
        }
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _googleEnabledSub?.cancel();
    super.dispose();
  }

  void _retryStream() => setState(() => _streamGeneration++);

  Future<void> _bootstrapGoogleCalendar() async {
    if (_userDocId.isEmpty) return;
    await GoogleCalendarSyncService.warmUpIfEnabled(_userDocId);
    if (mounted) await _refreshGoogleDays();
  }

  Future<void> _refreshGoogleDays() async {
    if (_userDocId.isEmpty) return;
    if (!await GoogleCalendarSyncService.isEnabled(_userDocId)) {
      if (mounted) {
        setState(() {
          _googleBusyDays = {};
          _googleEventsByDay = {};
        });
      }
      return;
    }
    setState(() => _googleSyncLoading = true);
    try {
      final events = await GoogleCalendarSyncService.fetchEventsForMonth(
        _focusedDay,
        userDocId: _userDocId,
      );
      final byDay = GoogleCalendarSyncService.groupEventsByDay(events);
      if (mounted) {
        setState(() {
          _googleEventsByDay = byDay;
          _googleBusyDays = byDay.keys.toSet();
        });
      }
    } finally {
      if (mounted) setState(() => _googleSyncLoading = false);
    }
  }

  Set<String> _linkedGoogleEventIds(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs
        .map((d) => (d.data()['googleEventId'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  bool _isSameDay(DateTime? a, DateTime b) {
    if (a == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Color _colorFromHex(String? raw) {
    if (raw == null || raw.trim().isEmpty) return _corCompromisso;
    var c = raw.trim().replaceAll('#', '');
    if (c.length == 6) c = 'FF$c';
    final v = int.tryParse(c, radix: 16);
    if (v == null) return _corCompromisso;
    return Color(v);
  }

  DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Janela de lembretes: ano focado ± repetições anuais (evita stream sem filtro).
  (DateTime, DateTime) _remindersQueryBounds() {
    final y = _focusedDay.year;
    final start = DateTime(y - 1, 1, 1);
    final end = DateTime(y + 6, 12, 31, 23, 59, 59);
    return (start, end);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _remindersPeriodStream() {
    final (start, end) = _remindersQueryBounds();
    return FirebaseFirestore.instance
        .collection('users')
        .doc(_userDocId)
        .collection('reminders')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('date')
        .limit(2500)
        .snapshots();
  }

  String _focusedMonthTitle() {
    final raw = DateFormat("MMMM 'de' y", 'pt_BR').format(_focusedDay);
    return raw[0].toUpperCase() + raw.substring(1);
  }

  List<Map<String, dynamic>> _itemsForFocusedMonth(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final start = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final end = DateTime(_focusedDay.year, _focusedDay.month + 1, 0, 23, 59, 59);
    final items = <Map<String, dynamic>>[];
    for (final doc in docs) {
      final data = doc.data();
      final date = CompromissoReminderService.dateFromDoc(data);
      if (date == null) continue;
      if (date.isBefore(start) || date.isAfter(end)) continue;
      items.add({...data, 'id': doc.id});
    }
    items.sort((a, b) {
      final da = CompromissoReminderService.dateFromDoc(a);
      final db = CompromissoReminderService.dateFromDoc(b);
      if (da == null || db == null) return 0;
      final cmp = da.compareTo(db);
      if (cmp != 0) return cmp;
      return (a['time'] ?? '').toString().compareTo((b['time'] ?? '').toString());
    });
    return items;
  }

  List<Map<String, dynamic>> _itemsForDateRange(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime start,
    DateTime end,
  ) {
    final startDay = _dayKey(start);
    final endDay = DateTime(end.year, end.month, end.day, 23, 59, 59);
    final items = <Map<String, dynamic>>[];
    for (final doc in docs) {
      final data = doc.data();
      final date = CompromissoReminderService.dateFromDoc(data);
      if (date == null) continue;
      if (date.isBefore(startDay) || date.isAfter(endDay)) continue;
      items.add({...data, 'id': doc.id});
    }
    items.sort((a, b) {
      final da = CompromissoReminderService.dateFromDoc(a);
      final db = CompromissoReminderService.dateFromDoc(b);
      if (da == null || db == null) return 0;
      final cmp = da.compareTo(db);
      if (cmp != 0) return cmp;
      return (a['time'] ?? '').toString().compareTo((b['time'] ?? '').toString());
    });
    return items;
  }

  List<Map<String, dynamic>> _financeItemsForDateRange(
    Map<DateTime, List<AgendaFinancePendingItem>> financeByDay,
    DateTime start,
    DateTime end,
  ) {
    final out = <Map<String, dynamic>>[];
    final endDay = _dayKey(end);
    for (final entry in financeByDay.entries) {
      final day = entry.key;
      if (day.isBefore(_dayKey(start)) || day.isAfter(endDay)) continue;
      for (final item in entry.value) {
        out.add({
          'agendaRowKind': 'finance',
          'financeType': item.type,
          ...item.data,
        });
      }
    }
    out.sort((a, b) {
      final da = agendaFinanceEffectiveDay(a);
      final db = agendaFinanceEffectiveDay(b);
      if (da == null || db == null) return 0;
      final cmp = da.compareTo(db);
      if (cmp != 0) return cmp;
      final ta = (a['description'] ?? a['category'] ?? '').toString();
      final tb = (b['description'] ?? b['category'] ?? '').toString();
      return ta.compareTo(tb);
    });
    return out;
  }

  List<Map<String, dynamic>> _googleItemsForDateRange(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime start,
    DateTime end,
  ) {
    final linked = _linkedGoogleEventIds(docs);
    final startDay = _dayKey(start);
    final endDay = _dayKey(end);
    final out = <Map<String, dynamic>>[];
    for (final entry in _googleEventsByDay.entries) {
      final day = entry.key;
      if (day.isBefore(startDay) || day.isAfter(endDay)) continue;
      for (final e in entry.value) {
        if (linked.contains(e.id)) continue;
        out.add({
          'agendaRowKind': 'google',
          'title': e.title,
          'date': Timestamp.fromDate(e.day),
          'time': e.timeStart,
          'endTime': e.timeEnd,
          'notes': e.notes,
        });
      }
    }
    out.sort((a, b) {
      final da = (a['date'] as Timestamp?)?.toDate();
      final db = (b['date'] as Timestamp?)?.toDate();
      if (da == null || db == null) return 0;
      final cmp = da.compareTo(db);
      if (cmp != 0) return cmp;
      return (a['time'] ?? '').toString().compareTo((b['time'] ?? '').toString());
    });
    return out;
  }

  String _periodoLabel(DateTime start, DateTime end) {
    final sameMonth =
        start.year == end.year && start.month == end.month && start.day == 1;
    if (sameMonth &&
        end.day ==
            DateTime(end.year, end.month + 1, 0).day) {
      final raw = DateFormat("MMMM 'de' y", 'pt_BR').format(start);
      return raw[0].toUpperCase() + raw.substring(1);
    }
    final a = DateFormat('dd/MM/y', 'pt_BR').format(start);
    final b = DateFormat('dd/MM/y', 'pt_BR').format(end);
    return '$a — $b';
  }

  List<GoogleCalendarEventItem> _googleParticularForMonth(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final linked = _linkedGoogleEventIds(docs);
    final out = <GoogleCalendarEventItem>[];
    for (final entry in _googleEventsByDay.entries) {
      final day = entry.key;
      if (day.year != _focusedDay.year || day.month != _focusedDay.month) {
        continue;
      }
      for (final e in entry.value) {
        if (!linked.contains(e.id)) out.add(e);
      }
    }
    out.sort((a, b) {
      final c = a.day.compareTo(b.day);
      if (c != 0) return c;
      return a.timeStart.compareTo(b.timeStart);
    });
    return out;
  }

  ({Color? fillColor, bool googleOnly}) _dayVisualCombined(
    DateTime day,
    Map<DateTime, List<QueryDocumentSnapshot<Map<String, dynamic>>>> byDay,
    Map<DateTime, List<AgendaFinancePendingItem>> financeByDay,
  ) {
    final key = _dayKey(day);
    final financeColor = _financeMarkerColor(day, financeByDay);
    final items = byDay[key] ?? [];
    final localColor = items.isNotEmpty
        ? _colorFromHex(items.first.data()['colorHex']?.toString())
        : null;
    if (localColor != null) {
      return (fillColor: localColor, googleOnly: false);
    }
    if (financeColor != null) {
      return (fillColor: financeColor, googleOnly: false);
    }
    if (_googleBusyDays.contains(key)) {
      return (fillColor: null, googleOnly: true);
    }
    return (fillColor: null, googleOnly: false);
  }

  Widget _buildModernMesAbas({required bool isNarrow}) {
    const financeColor = Color(0xFFF97316);
    const particularColor = Color(0xFF12B5A5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.deepBlue.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Expanded(
                child: _mesAbaChip(
                  label: 'Financeiros',
                  icon: Icons.payments_outlined,
                  selected: _mesAba == _AgendaMesAba.financeiro,
                  color: financeColor,
                  compact: isNarrow,
                  onTap: () => setState(() => _mesAbaIndex = 0),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _mesAbaChip(
                  label: 'Particulares',
                  icon: Icons.event_available_rounded,
                  selected: _mesAba == _AgendaMesAba.particular,
                  color: particularColor,
                  compact: isNarrow,
                  onTap: () => setState(() => _mesAbaIndex = 1),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4, left: 4),
          child: Text(
            'Filtra somente a lista de lançamentos do mês e do dia selecionado.',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _mesAbaChip({
    required String label,
    required IconData icon,
    required bool selected,
    required Color color,
    required bool compact,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: EdgeInsets.symmetric(
            vertical: compact ? 10 : 12,
            horizontal: compact ? 8 : 12,
          ),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    colors: [color, color.withValues(alpha: 0.82)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: selected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: compact ? 16 : 18,
                color: selected ? Colors.white : color,
              ),
              SizedBox(width: compact ? 4 : 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: compact ? 11.5 : 13,
                    color: selected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openExportPdfSheet(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs, {
    required Map<DateTime, List<AgendaFinancePendingItem>> financeByDay,
  }) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final opts = await AgendaPdfExportSheet.show(
      context,
      focusedDay: _focusedDay,
      initialFilter: _mesAba == _AgendaMesAba.financeiro
          ? AgendaPdfContentFilter.financeiro
          : AgendaPdfContentFilter.particular,
    );
    if (opts == null || !context.mounted) return;
    await _exportarPdf(context, allDocs, financeByDay: financeByDay, opts: opts);
  }

  Future<void> _exportarPdf(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs, {
    required Map<DateTime, List<AgendaFinancePendingItem>> financeByDay,
    required AgendaPdfExportOptions opts,
  }) async {
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
                  Text('A gerar o PDF…'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    try {
      final start = opts.rangeStart;
      final end = opts.rangeEnd;
      final items = _itemsForDateRange(allDocs, start, end);
      final financeItems = _financeItemsForDateRange(financeByDay, start, end);
      final googleItems = _googleItemsForDateRange(allDocs, start, end);
      final periodo = _periodoLabel(start, end);
      final filterSuffix = switch (opts.contentFilter) {
        AgendaPdfContentFilter.financeiro => '_financeiro',
        AgendaPdfContentFilter.particular => '_particular',
        AgendaPdfContentFilter.todos => '_completo',
      };
      final filename = RelatorioService.reportFilenameFromPeriod(
        'agenda$filterSuffix',
        start,
        end,
      );
      final (bytes, _) =
          await RelatorioService.buildRelatorioCompromissosAudienciaBytes(
        periodo: periodo,
        items: items,
        financeItems: financeItems,
        googleItems: googleItems,
        contentFilter: opts.contentFilter,
        suggestedFilename: filename,
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
            content: Text(
              'Erro ao gerar PDF: ${e.toString().split('\n').first}',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  double _dayNumFontSize(bool isNarrow) => isNarrow ? 26 : 24;

  double _dayRowHeight(bool isNarrow) => isNarrow ? 68 : 64;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterCompromissos(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs
        .where((d) => CompromissoReminderService.isCompromissoDoc(d.data()))
        .toList();
  }

  Map<DateTime, List<QueryDocumentSnapshot<Map<String, dynamic>>>> _groupByDay(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final map = <DateTime, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final doc in docs) {
      final date = CompromissoReminderService.dateFromDoc(doc.data());
      if (date == null) continue;
      final key = _dayKey(date);
      map.putIfAbsent(key, () => []).add(doc);
    }
    for (final list in map.values) {
      list.sort((a, b) {
        final ta = (a.data()['time'] ?? '').toString();
        final tb = (b.data()['time'] ?? '').toString();
        return ta.compareTo(tb);
      });
    }
    return map;
  }

  bool _isHolidayDay(DateTime day, Set<String> holidayKeys) {
    final k = DateFormat('yyyy-MM-dd').format(day);
    return holidayKeys.contains(k);
  }

  bool _isWeekend(DateTime day) =>
      day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

  Future<void> _openCompromissoForm({
    required BuildContext context,
    DateTime? initialDate,
    QueryDocumentSnapshot<Map<String, dynamic>>? existing,
    GoogleCalendarEventItem? googleEvent,
  }) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final result = await Navigator.of(context).push<CompromissoFormResult?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CompromissoFormPage(
          profile: widget.profile,
          hasActiveLicense: widget.profile.hasActiveLicense,
          existingDoc: existing,
          initialDate: initialDate,
          googleEventSeed: googleEvent,
        ),
      ),
    );
    if (result == null || !context.mounted) return;

    try {
      if (googleEvent != null && existing == null) {
        await CompromissoReminderService.upsertFromGoogleEvent(
          userDocId: _userDocId,
          googleEventId: googleEvent.id,
          result: result,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Compromisso atualizado no Google Calendar.'),
            ),
          );
        }
      } else if (existing != null) {
        final msg = await CompromissoReminderService.update(
          userDocId: _userDocId,
          doc: existing,
          result: result,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
      } else {
        await CompromissoReminderService.create(
          userDocId: _userDocId,
          result: result,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Compromisso salvo. Sincroniza com Google Calendar se ativo em Configurações.',
              ),
            ),
          );
        }
      }
      if (mounted) {
        setState(() => _selectedDay = _dayKey(result.date));
      }
      if (_googleEnabled) unawaited(_refreshGoogleDays());
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao gravar: ${e.toString().split('\n').first}',
            ),
          ),
        );
      }
    }
  }

  /// Abre formulário direto na data (sem segundo seletor).
  Future<void> _adicionarNaData(DateTime day) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    setState(() => _selectedDay = _dayKey(day));
    await _openCompromissoForm(context: context, initialDate: day);
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _selecionarCompromisso(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
  ) async {
    if (items.isEmpty) return null;
    if (items.length == 1) return items.first;
    return showModalBottomSheet<QueryDocumentSnapshot<Map<String, dynamic>>>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Qual compromisso?',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              ...items.map((doc) {
                final data = doc.data();
                final title = (data['title'] ?? 'Compromisso').toString();
                final time = (data['time'] ?? '').toString();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    leading: Icon(Icons.event_rounded, color: AppColors.primary),
                    title: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: time.isNotEmpty ? Text(time) : null,
                    onTap: () => Navigator.pop(ctx, doc),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Future<AgendaFinancePendingItem?> _selecionarFinancePending(
    BuildContext context,
    List<AgendaFinancePendingItem> items,
  ) async {
    if (items.isEmpty) return null;
    if (items.length == 1) return items.first;
    return showModalBottomSheet<AgendaFinancePendingItem>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Qual lançamento financeiro?',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              ...items.map((item) {
                final data = item.data;
                final desc =
                    (data['description'] ?? data['category'] ?? 'Lançamento')
                        .toString()
                        .trim();
                final amount = ((data['amount'] ?? 0) as num).toDouble().abs();
                final label = item.isIncome ? 'Receita' : 'Despesa';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: (item.isIncome
                                ? const Color(0xFF0EA5E9)
                                : const Color(0xFFF97316))
                            .withValues(alpha: 0.35),
                      ),
                    ),
                    leading: Icon(
                      item.isIncome
                          ? Icons.arrow_downward_rounded
                          : Icons.arrow_upward_rounded,
                      color: item.isIncome
                          ? const Color(0xFF0EA5E9)
                          : const Color(0xFFF97316),
                    ),
                    title: Text(
                      desc.isEmpty ? label : desc,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text('$label · R\$ ${amount.toStringAsFixed(2)}'),
                    onTap: () => Navigator.pop(ctx, item),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Future<GoogleCalendarEventItem?> _selecionarGoogleEvent(
    BuildContext context,
    List<GoogleCalendarEventItem> items,
  ) async {
    if (items.isEmpty) return null;
    if (items.length == 1) return items.first;
    return showModalBottomSheet<GoogleCalendarEventItem>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Qual evento Google?',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              ...items.map((event) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: GoogleCalendarSyncService.googleEventColor
                            .withValues(alpha: 0.35),
                      ),
                    ),
                    leading: const Icon(
                      Icons.event_rounded,
                      color: GoogleCalendarSyncService.googleEventColor,
                    ),
                    title: Text(
                      event.title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(event.horarioLabel),
                    onTap: () => Navigator.pop(ctx, event),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  List<GoogleCalendarEventItem> _externalGoogleEventsForDay(
    DateTime day,
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs,
  ) {
    if (!_googleEnabled) return const [];
    return GoogleCalendarSyncService.externalEventsForDay(
      day: day,
      googleEvents: _googleEventsByDay.values.expand((e) => e).toList(),
      linkedGoogleEventIds: _linkedGoogleEventIds(allDocs.toList()),
    );
  }

  Future<void> _editarItemDoDia({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
    required List<AgendaFinancePendingItem> financePending,
    List<GoogleCalendarEventItem> googleEvents = const [],
  }) async {
    if (items.isEmpty && financePending.isEmpty && googleEvents.isEmpty) return;

    final onlyLocal = items.isNotEmpty && financePending.isEmpty && googleEvents.isEmpty;
    final onlyFinance = financePending.isNotEmpty && items.isEmpty && googleEvents.isEmpty;
    final onlyGoogle = googleEvents.isNotEmpty && items.isEmpty && financePending.isEmpty;

    if (onlyLocal) {
      final doc = await _selecionarCompromisso(context, items);
      if (doc == null || !mounted) return;
      await _openCompromissoForm(context: context, existing: doc);
      return;
    }
    if (onlyFinance) {
      final item = await _selecionarFinancePending(context, financePending);
      if (item == null || !mounted) return;
      await _editFinancePending(item);
      return;
    }
    if (onlyGoogle) {
      final event = await _selecionarGoogleEvent(context, googleEvents);
      if (event == null || !mounted) return;
      await _openCompromissoForm(context: context, googleEvent: event);
      return;
    }
    if (!mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'O que deseja editar?',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.event_rounded, color: AppColors.primary),
                title: const Text('Compromisso particular'),
                onTap: () => Navigator.pop(ctx, 'compromisso'),
              ),
              if (googleEvents.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.event_rounded,
                      color: GoogleCalendarSyncService.googleEventColor),
                  title: const Text('Evento Google Calendar'),
                  onTap: () => Navigator.pop(ctx, 'google'),
                ),
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_rounded,
                    color: Color(0xFFF97316)),
                title: const Text('Receita ou despesa (Financeiro)'),
                onTap: () => Navigator.pop(ctx, 'financeiro'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'compromisso') {
      final doc = await _selecionarCompromisso(context, items);
      if (doc == null || !mounted) return;
      await _openCompromissoForm(context: context, existing: doc);
    } else if (choice == 'google') {
      final event = await _selecionarGoogleEvent(context, googleEvents);
      if (event == null || !mounted) return;
      await _openCompromissoForm(context: context, googleEvent: event);
    } else {
      final item = await _selecionarFinancePending(context, financePending);
      if (item == null || !mounted) return;
      await _editFinancePending(item);
    }
  }

  Future<void> _limparDiaAgenda(
    DateTime day,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items, {
    List<AgendaFinancePendingItem> financePending = const [],
    List<GoogleCalendarEventItem> googleEvents = const [],
    bool selective = false,
  }) async {
    if (items.isEmpty && financePending.isEmpty && googleEvents.isEmpty) return;

    if (selective) {
      await _limparCompromissosSeletivo(day, items, googleEvents);
      return;
    }

    var removedCompromissos = 0;
    var removedGoogle = 0;
    if (items.isNotEmpty || googleEvents.isNotEmpty) {
      final total = items.length + googleEvents.length;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Limpar compromissos do dia?'),
          content: Text(
            total == 1
                ? 'Remove 1 compromisso da Agenda neste dia (inclui Google Calendar se aplicável). Lançamentos do Financeiro não são alterados nesta etapa.'
                : 'Remove $total compromissos da Agenda neste dia (inclui Google Calendar se aplicável). Lançamentos do Financeiro não são alterados nesta etapa.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Limpar compromissos'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      if (items.isNotEmpty) {
        removedCompromissos = await CompromissoReminderService.clearDay(
          context: context,
          userDocId: _userDocId,
          day: day,
          docs: items,
          skipConfirm: true,
        );
      }
      for (final event in googleEvents) {
        try {
          await CompromissoReminderService.deleteGoogleOnlyEvent(
            userDocId: _userDocId,
            googleEventId: event.id,
          );
          removedGoogle++;
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Erro ao remover «${event.title}»: ${e.toString().split('\n').first}',
                ),
              ),
            );
          }
        }
      }
    }

    var removedFinance = 0;
    if (financePending.isNotEmpty && mounted) {
      final deleteFinance = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Lançamentos do Financeiro'),
          content: Text(
            financePending.length == 1
                ? 'Este dia tem 1 conta a pagar/receber no Financeiro. '
                    'Deseja excluir o lançamento do módulo Financeiro?\n\n'
                    'Se escolher «Manter», o dia continua colorido na Agenda '
                    'até quitar ou excluir no Financeiro.'
                : 'Este dia tem ${financePending.length} lançamentos pendentes no Financeiro. '
                    'Deseja excluí-los do módulo Financeiro?\n\n'
                    'Se escolher «Manter», os dias continuam coloridos na Agenda '
                    'até quitar ou excluir no Financeiro.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Manter no Financeiro'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Excluir do Financeiro'),
            ),
          ],
        ),
      );
      if (deleteFinance == true) {
        removedFinance = await _deleteFinancePendingBatch(financePending);
      }
    }

    if (!mounted) return;
    if (removedCompromissos > 0 || removedGoogle > 0 || removedFinance > 0) {
      final parts = <String>[];
      if (removedCompromissos > 0) {
        parts.add(
          '$removedCompromissos compromisso${removedCompromissos == 1 ? '' : 's'} removido${removedCompromissos == 1 ? '' : 's'}',
        );
      }
      if (removedGoogle > 0) {
        parts.add(
          '$removedGoogle evento${removedGoogle == 1 ? '' : 's'} Google removido${removedGoogle == 1 ? '' : 's'}',
        );
      }
      if (removedFinance > 0) {
        parts.add(
          '$removedFinance lançamento${removedFinance == 1 ? '' : 's'} excluído${removedFinance == 1 ? '' : 's'} do Financeiro',
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dia atualizado (${parts.join(' · ')}).')),
      );
      if (_googleEnabled) unawaited(_refreshGoogleDays());
    } else if (items.isEmpty && googleEvents.isEmpty && financePending.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lançamentos mantidos no Financeiro.'),
        ),
      );
    }
  }

  Future<int> _deleteFinancePendingBatch(List<AgendaFinancePendingItem> items) async {
    if (items.isEmpty) return 0;
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(_userDocId)
        .collection('transactions');
    var removed = 0;
    for (final item in items) {
      try {
        final pairId = (item.data['transferPairId'] ?? '').toString().trim();
        if (pairId.isNotEmpty) {
          final pairSnap = await col.where('transferPairId', isEqualTo: pairId).get();
          for (final pairDoc in pairSnap.docs) {
            await pairDoc.reference.delete();
            removed++;
          }
        } else {
          await col.doc(item.docId).delete();
          removed++;
        }
      } catch (_) {}
    }
    if (removed > 0) {
      FinanceTransactionsHub.notifyMutated(uid: _userDocId);
    }
    return removed;
  }

  Future<void> _editFinancePending(AgendaFinancePendingItem item) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final pairId = (item.data['transferPairId'] ?? '').toString().trim();
    if (pairId.isNotEmpty) {
      final accounts = await FinanceAccountsService().listOnce(_userDocId);
      if (!mounted) return;
      final saved = await FinanceTransferBottomSheet.showEdit(
        context,
        uid: widget.uid,
        profile: widget.profile,
        pairId: pairId,
        accounts: accounts,
        logModulo: 'Agenda',
      );
      if (saved && mounted) {
        FinanceTransactionsHub.notifyMutated(uid: _userDocId);
      }
      return;
    }
    final saved = await showFinanceTransactionEditDialog(
      context: context,
      uid: widget.uid,
      profile: widget.profile,
      docId: item.docId,
      current: item.data,
      type: item.type,
      logModulo: 'Agenda',
    );
    if (saved && mounted) {
      FinanceTransactionsHub.notifyMutated(uid: _userDocId);
    }
  }

  Future<void> _deleteFinancePending(AgendaFinancePendingItem item) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final desc = (item.data['description'] ?? item.data['category'] ?? 'Lançamento')
        .toString()
        .trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir lançamento?'),
        content: Text(
          desc.isEmpty
              ? 'Remover este lançamento pendente do Financeiro?'
              : 'Remover «$desc» do Financeiro?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final n = await _deleteFinancePendingBatch([item]);
    if (!mounted || n <= 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Lançamento excluído do Financeiro.')),
    );
  }

  Widget _menuActionButton({
    required IconData icon,
    required String label,
    required Color color,
    List<Color>? iconGradient,
    required VoidCallback onTap,
    bool fullWidth = false,
  }) {
    final ig = iconGradient ??
        <Color>[
          color,
          Color.lerp(color, Colors.black, 0.22) ?? color,
        ];
    final bgA = Color.lerp(Colors.white, color, 0.05)!;
    final bgB = Color.lerp(Colors.white, color, 0.11)!;
    final btn = Material(
      color: Colors.transparent,
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
            border: Border.all(color: color.withValues(alpha: 0.34)),
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
            constraints: const BoxConstraints(minHeight: 58),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: ig),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.28),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: Colors.white, size: 19),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
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
    return fullWidth ? btn : Expanded(child: btn);
  }

  String _resumoDiaSubtitle(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
    List<AgendaFinancePendingItem> financePending, {
    List<GoogleCalendarEventItem> googleEvents = const [],
  }) {
    final parts = <String>[];
    if (items.isNotEmpty) {
      parts.add(
        '${items.length} compromisso${items.length == 1 ? '' : 's'}',
      );
    }
    if (googleEvents.isNotEmpty) {
      parts.add(
        '${googleEvents.length} Google',
      );
    }
    if (financePending.isNotEmpty) {
      parts.add(
        '${financePending.length} lançamento${financePending.length == 1 ? '' : 's'} financeiro${financePending.length == 1 ? '' : 's'}',
      );
    }
    return parts.join(' · ');
  }

  void _mostrarMenuDiaAgenda(
    BuildContext context,
    DateTime day,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items, {
    List<AgendaFinancePendingItem> financePending = const [],
    List<GoogleCalendarEventItem> googleEvents = const [],
  }) {
    final dayStart = _dayKey(day);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final safeBottom = MediaQuery.viewPaddingOf(ctx).bottom;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + safeBottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.08),
                          AppColors.accent.withValues(alpha: 0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.14),
                      ),
                    ),
                    child: Text(
                      DateFormat("EEEE, d 'de' MMMM 'de' yyyy", 'pt_BR')
                          .format(dayStart),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: AppColors.deepBlue,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _menuActionButton(
                        icon: Icons.add_circle_rounded,
                        label: 'Adicionar compromisso',
                        color: const Color(0xFF10B981),
                        iconGradient: const [
                          Color(0xFF10B981),
                          Color(0xFF059669),
                        ],
                        onTap: () {
                          Navigator.pop(ctx);
                          unawaited(_adicionarNaData(dayStart));
                        },
                      ),
                      const SizedBox(width: 8),
                      _menuActionButton(
                        icon: Icons.edit_rounded,
                        label: items.isNotEmpty && financePending.isEmpty && googleEvents.isEmpty
                            ? 'Editar compromisso'
                            : financePending.isNotEmpty && items.isEmpty && googleEvents.isEmpty
                                ? 'Editar lançamento'
                                : googleEvents.isNotEmpty && items.isEmpty && financePending.isEmpty
                                    ? 'Editar Google'
                                    : 'Editar',
                        color: const Color(0xFF0EA5E9),
                        iconGradient: const [
                          Color(0xFF0EA5E9),
                          Color(0xFF2563EB),
                        ],
                        onTap: () async {
                          Navigator.pop(ctx);
                          if (!mounted) return;
                          await _editarItemDoDia(
                            items: items,
                            financePending: financePending,
                            googleEvents: googleEvents,
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _menuActionButton(
                    icon: Icons.delete_sweep_rounded,
                    label: 'Limpar dia',
                    color: const Color(0xFFEF4444),
                    iconGradient: const [
                      Color(0xFFF43F5E),
                      Color(0xFFDC2626),
                    ],
                    fullWidth: true,
                    onTap: () {
                      Navigator.pop(ctx);
                      unawaited(_mostrarOpcoesLimparDia(
                        dayStart,
                        items,
                        financePending: financePending,
                        googleEvents: googleEvents,
                      ));
                    },
                  ),
                  if (items.isNotEmpty || googleEvents.isNotEmpty || financePending.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Divider(height: 1),
                    const SizedBox(height: 14),
                    AgendaModernUI.sectionHeader(
                      title: 'Resumo do dia',
                      subtitle: _resumoDiaSubtitle(
                        items,
                        financePending,
                        googleEvents: googleEvents,
                      ),
                      icon: Icons.summarize_rounded,
                      color: AppColors.primary,
                    ),
                    if (items.isNotEmpty)
                      ...items.map((doc) {
                      final data = doc.data();
                      final color = _colorFromHex(data['colorHex']?.toString());
                      final title = (data['title'] ?? 'Compromisso').toString();
                      final time = (data['time'] ?? '').toString();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              Navigator.pop(ctx);
                              await _openCompromissoForm(
                                context: context,
                                existing: doc,
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 4,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 5,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15,
                                          ),
                                        ),
                                        if (time.isNotEmpty)
                                          Text(
                                            time,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: Colors.grey.shade500,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    if (googleEvents.isNotEmpty)
                      ...googleEvents.map((event) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () async {
                                Navigator.pop(ctx);
                                await _openCompromissoForm(
                                  context: context,
                                  googleEvent: event,
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 4,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 5,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: GoogleCalendarSyncService
                                            .googleEventColor,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            event.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 15,
                                            ),
                                          ),
                                          Text(
                                            '${event.horarioLabel} · Google',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: GoogleCalendarSyncService
                                                  .googleEventColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      color: Colors.grey.shade500,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    if (financePending.isNotEmpty)
                      ...financePending.map((item) {
                        final data = item.data;
                        final desc =
                            (data['description'] ?? data['category'] ?? 'Lançamento')
                                .toString()
                                .trim();
                        final amount =
                            ((data['amount'] ?? 0) as num).toDouble().abs();
                        final label = item.isIncome ? 'Receita' : 'Despesa';
                        final color = item.isIncome
                            ? const Color(0xFF0EA5E9)
                            : const Color(0xFFF97316);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () async {
                                Navigator.pop(ctx);
                                if (!mounted) return;
                                await _editFinancePending(item);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 4,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 5,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            desc.isEmpty ? label : desc,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 15,
                                            ),
                                          ),
                                          Text(
                                            '$label · R\$ ${amount.toStringAsFixed(2)} · Financeiro',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: color,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      color: Colors.grey.shade500,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final title = (data['title'] ?? 'Compromisso').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir compromisso?'),
        content: Text('Remover «$title»?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await CompromissoReminderService.deleteOne(
        userDocId: _userDocId,
        reminderDocId: doc.id,
        googleEventId: (data['googleEventId'] ?? '').toString(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Compromisso excluído.')),
        );
      }
      if (_googleEnabled) unawaited(_refreshGoogleDays());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: ${e.toString().split('\n').first}')),
        );
      }
    }
  }

  Future<void> _confirmDeleteGoogleEvent(GoogleCalendarEventItem event) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir evento Google?'),
        content: Text(
          'Remover «${event.title}» do Google Calendar?\n\n'
          'Esta ação também remove da Agenda WISDOMAPP.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await CompromissoReminderService.deleteGoogleOnlyEvent(
        userDocId: _userDocId,
        googleEventId: event.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Evento excluído do Google Calendar.')),
        );
      }
      if (_googleEnabled) unawaited(_refreshGoogleDays());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: ${e.toString().split('\n').first}')),
        );
      }
    }
  }

  Future<void> _limparCompromissosSeletivo(
    DateTime day,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
    List<GoogleCalendarEventItem> googleEvents,
  ) async {
    if (items.isEmpty && googleEvents.isEmpty) return;

    final selectedLocal = <String>{};
    final selectedGoogle = <String>{};

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final safeBottom = MediaQuery.viewPaddingOf(ctx).bottom;
            final anySelected =
                selectedLocal.isNotEmpty || selectedGoogle.isNotEmpty;
            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + safeBottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Selecionar para remover',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      DateFormat("d 'de' MMMM", 'pt_BR').format(day),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(ctx).height * 0.45,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            ...items.map((doc) {
                              final data = doc.data();
                              final title =
                                  (data['title'] ?? 'Compromisso').toString();
                              final time = (data['time'] ?? '').toString();
                              return CheckboxListTile(
                                value: selectedLocal.contains(doc.id),
                                onChanged: (v) {
                                  setSheetState(() {
                                    if (v == true) {
                                      selectedLocal.add(doc.id);
                                    } else {
                                      selectedLocal.remove(doc.id);
                                    }
                                  });
                                },
                                title: Text(title),
                                subtitle: time.isNotEmpty ? Text(time) : null,
                                secondary: const Icon(Icons.event_rounded),
                              );
                            }),
                            ...googleEvents.map((event) {
                              return CheckboxListTile(
                                value: selectedGoogle.contains(event.id),
                                onChanged: (v) {
                                  setSheetState(() {
                                    if (v == true) {
                                      selectedGoogle.add(event.id);
                                    } else {
                                      selectedGoogle.remove(event.id);
                                    }
                                  });
                                },
                                title: Text(event.title),
                                subtitle: Text('${event.horarioLabel} · Google'),
                                secondary: const Icon(
                                  Icons.event_rounded,
                                  color: GoogleCalendarSyncService.googleEventColor,
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: anySelected
                          ? () => Navigator.pop(ctx, true)
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      child: const Text('Remover selecionados'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;

    var removedLocal = 0;
    var removedGoogle = 0;

    for (final doc in items.where((d) => selectedLocal.contains(d.id))) {
      try {
        final data = doc.data();
        await CompromissoReminderService.deleteOne(
          userDocId: _userDocId,
          reminderDocId: doc.id,
          googleEventId: (data['googleEventId'] ?? '').toString(),
        );
        removedLocal++;
      } catch (_) {}
    }

    for (final event in googleEvents.where((e) => selectedGoogle.contains(e.id))) {
      try {
        await CompromissoReminderService.deleteGoogleOnlyEvent(
          userDocId: _userDocId,
          googleEventId: event.id,
        );
        removedGoogle++;
      } catch (_) {}
    }

    if (!mounted) return;
    if (removedLocal > 0 || removedGoogle > 0) {
      final parts = <String>[];
      if (removedLocal > 0) {
        parts.add('$removedLocal compromisso${removedLocal == 1 ? '' : 's'}');
      }
      if (removedGoogle > 0) {
        parts.add('$removedGoogle Google');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removido${parts.length == 1 && removedLocal + removedGoogle == 1 ? '' : 's'}: ${parts.join(' · ')}.')),
      );
      if (_googleEnabled) unawaited(_refreshGoogleDays());
    }
  }

  Future<void> _mostrarOpcoesLimparDia(
    DateTime day,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items, {
    List<AgendaFinancePendingItem> financePending = const [],
    List<GoogleCalendarEventItem> googleEvents = const [],
  }) async {
    if (items.isEmpty && googleEvents.isEmpty && financePending.isEmpty) return;

    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Limpar compromissos',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
              ),
              const SizedBox(height: 12),
              if (items.isNotEmpty || googleEvents.isNotEmpty) ...[
                ListTile(
                  leading: const Icon(Icons.delete_sweep_rounded, color: Colors.red),
                  title: const Text('Remover todos do dia'),
                  subtitle: const Text('Compromissos locais e Google Calendar'),
                  onTap: () => Navigator.pop(ctx, 'all'),
                ),
                ListTile(
                  leading: const Icon(Icons.checklist_rounded, color: AppColors.primary),
                  title: const Text('Selecionar quais remover'),
                  onTap: () => Navigator.pop(ctx, 'select'),
                ),
              ],
              if (financePending.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_rounded,
                      color: Color(0xFFF97316)),
                  title: const Text('Limpar lançamentos financeiros'),
                  onTap: () => Navigator.pop(ctx, 'finance'),
                ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || choice == null) return;
    switch (choice) {
      case 'all':
        await _limparDiaAgenda(
          day,
          items,
          financePending: financePending,
          googleEvents: googleEvents,
        );
      case 'select':
        await _limparCompromissosSeletivo(day, items, googleEvents);
        if (financePending.isNotEmpty && mounted) {
          await _limparDiaAgenda(
            day,
            const [],
            financePending: financePending,
            googleEvents: const [],
          );
        }
      case 'finance':
        await _limparDiaAgenda(
          day,
          const [],
          financePending: financePending,
          googleEvents: const [],
        );
    }
  }

  Widget _premiumCardShell({required Widget child}) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.deepBlue.withValues(alpha: 0.12)),
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
          child,
        ],
      ),
    );
  }

  Widget _dayCell({
    required DateTime day,
    required bool isToday,
    required bool isSelected,
    required bool isHoliday,
    required Color? fillColor,
    required bool googleOnly,
    required bool isNarrow,
  }) {
    final numSize = _dayNumFontSize(isNarrow);
    final redDay = isHoliday || _isWeekend(day);
    final hasFill = fillColor != null || googleOnly;
    final borderColor = fillColor ??
        (googleOnly
            ? GoogleCalendarSyncService.googleEventColor
            : AppColors.primary);

    if (isSelected && !hasFill) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            colors: AppColors.logoGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(2.5),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '${day.day}',
            style: TextStyle(
              color: redDay ? const Color(0xFFE53935) : AppColors.primary,
              fontWeight: FontWeight.w900,
              fontSize: numSize,
            ),
          ),
        ),
      );
    }

    if (isToday && !hasFill) {
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                color: redDay ? const Color(0xFFE53935) : AppColors.primary,
                fontWeight: FontWeight.w900,
                fontSize: numSize,
              ),
            ),
            Text(
              'Hoje',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
                fontSize: 10,
              ),
            ),
          ],
        ),
      );
    }

    if (hasFill) {
      final c = fillColor ?? GoogleCalendarSyncService.googleEventColor;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [c, c.withValues(alpha: 0.78)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.white : borderColor.withValues(alpha: 0.9),
            width: isSelected ? 2.5 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: c.withValues(alpha: 0.35),
              blurRadius: isSelected ? 8 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${day.day}',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: numSize * 0.92,
                  ),
                ),
                if (googleOnly && fillColor == null)
                  const Icon(Icons.cloud_rounded, color: Colors.white70, size: 10),
              ],
            ),
            if (isSelected)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Center(
      child: Text(
        '${day.day}',
        style: TextStyle(
          color: redDay ? const Color(0xFFE53935) : const Color(0xFF1A1C1E),
          fontWeight: redDay ? FontWeight.w900 : FontWeight.w700,
          fontSize: numSize,
        ),
      ),
    );
  }

  Color? _financeMarkerColor(
    DateTime day,
    Map<DateTime, List<AgendaFinancePendingItem>> financeByDay,
  ) {
    final items = financeByDay[_dayKey(day)];
    if (items == null || items.isEmpty) return null;
    if (items.any((e) => !e.isIncome)) return const Color(0xFFF97316);
    return const Color(0xFF0EA5E9);
  }

  Widget _buildCalendar(
    Map<DateTime, List<QueryDocumentSnapshot<Map<String, dynamic>>>> byDay,
    Set<String> holidayKeys,
    bool isNarrow,
    Map<DateTime, List<AgendaFinancePendingItem>> financeByDay,
  ) {
    return TableCalendar<QueryDocumentSnapshot<Map<String, dynamic>>>(
      locale: 'pt_BR',
      firstDay: DateTime(2020, 1, 1),
      lastDay: DateTime(2035, 12, 31),
      focusedDay: _focusedDay,
      selectedDayPredicate: (d) => _isSameDay(_selectedDay, d),
      calendarFormat: CalendarFormat.month,
      startingDayOfWeek: StartingDayOfWeek.monday,
      availableGestures: AvailableGestures.horizontalSwipe,
      holidayPredicate: (day) {
        final key = _dayKey(day);
        final hasItems = (byDay[key] ?? []).isNotEmpty;
        final hasFinance = (financeByDay[key] ?? []).isNotEmpty;
        return _isHolidayDay(day, holidayKeys) && !hasItems && !hasFinance;
      },
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: isNarrow ? 22 : 26,
          letterSpacing: -0.4,
          color: const Color(0xFF0F172A),
        ),
        leftChevronIcon: const Icon(Icons.chevron_left_rounded, color: AppColors.primary),
        rightChevronIcon: const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
        headerPadding: EdgeInsets.symmetric(vertical: isNarrow ? 6 : 10),
      ),
      daysOfWeekHeight: isNarrow ? 30 : 32,
      rowHeight: _dayRowHeight(isNarrow),
      calendarStyle: CalendarStyle(
        outsideDaysVisible: false,
        defaultTextStyle: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: _dayNumFontSize(isNarrow),
        ),
        weekendTextStyle: TextStyle(
          color: const Color(0xFFE53935),
          fontWeight: FontWeight.w900,
          fontSize: _dayNumFontSize(isNarrow),
        ),
        holidayTextStyle: TextStyle(
          color: const Color(0xFFE53935),
          fontWeight: FontWeight.w900,
          fontSize: _dayNumFontSize(isNarrow),
        ),
        todayDecoration: const BoxDecoration(shape: BoxShape.circle),
        selectedDecoration: const BoxDecoration(shape: BoxShape.circle),
        cellMargin: EdgeInsets.symmetric(
          horizontal: isNarrow ? 4 : 5,
          vertical: isNarrow ? 6 : 8,
        ),
      ),
      onPageChanged: (focused) {
        setState(() => _focusedDay = focused);
        unawaited(_refreshGoogleDays());
      },
      eventLoader: (day) => byDay[_dayKey(day)] ?? [],
      onDaySelected: (selected, focused) {
        setState(() {
          _selectedDay = selected;
          _focusedDay = focused;
        });
        if (!widget.profile.hasActiveLicense) {
          mostrarAvisoSeLicencaInativa(context, widget.profile);
          return;
        }
        final key = _dayKey(selected);
        final items = byDay[key] ?? [];
        final financeForDay = financeByDay[key] ?? const <AgendaFinancePendingItem>[];
        final allDocs = byDay.values.expand((e) => e);
        final googleForDay = _externalGoogleEventsForDay(selected, allDocs);
        if (items.isEmpty && financeForDay.isEmpty && googleForDay.isEmpty) {
          unawaited(_adicionarNaData(selected));
        } else {
          _mostrarMenuDiaAgenda(
            context,
            selected,
            items,
            financePending: financeForDay,
            googleEvents: googleForDay,
          );
        }
      },
      calendarBuilders: CalendarBuilders(
        dowBuilder: (context, day) {
          const names = ['SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SAB', 'DOM'];
          final idx = day.weekday - 1;
          final isWeekend = _isWeekend(day);
          return Center(
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
          );
        },
        todayBuilder: (context, day, _) {
          final visual = _dayVisualCombined(day, byDay, financeByDay);
          return _dayCell(
            day: day,
            isToday: true,
            isSelected: _isSameDay(_selectedDay, day),
            isHoliday: _isHolidayDay(day, holidayKeys),
            fillColor: visual.fillColor,
            googleOnly: visual.googleOnly,
            isNarrow: isNarrow,
          );
        },
        selectedBuilder: (context, day, _) {
          if (!_isSameDay(_selectedDay, day)) return null;
          final visual = _dayVisualCombined(day, byDay, financeByDay);
          return _dayCell(
            day: day,
            isToday: _isSameDay(DateTime.now(), day),
            isSelected: true,
            isHoliday: _isHolidayDay(day, holidayKeys),
            fillColor: visual.fillColor,
            googleOnly: visual.googleOnly,
            isNarrow: isNarrow,
          );
        },
        holidayBuilder: (context, day, _) {
          final visual = _dayVisualCombined(day, byDay, financeByDay);
          if (visual.fillColor != null || visual.googleOnly) return null;
          return _dayCell(
            day: day,
            isToday: _isSameDay(DateTime.now(), day),
            isSelected: _isSameDay(_selectedDay, day),
            isHoliday: true,
            fillColor: null,
            googleOnly: false,
            isNarrow: isNarrow,
          );
        },
        defaultBuilder: (context, day, _) {
          final visual = _dayVisualCombined(day, byDay, financeByDay);
          final isHol = _isHolidayDay(day, holidayKeys);
          if (visual.fillColor != null ||
              visual.googleOnly ||
              _isSameDay(DateTime.now(), day) ||
              isHol) {
            return _dayCell(
              day: day,
              isToday: _isSameDay(DateTime.now(), day),
              isSelected: _isSameDay(_selectedDay, day),
              isHoliday: isHol,
              fillColor: visual.fillColor,
              googleOnly: visual.googleOnly,
              isNarrow: isNarrow,
            );
          }
          return null;
        },
      ),
    );
  }

  Widget _buildRodapeTotalDia(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items, {
    List<AgendaFinancePendingItem> incomePending = const [],
    List<AgendaFinancePendingItem> expensePending = const [],
  }) {
    if (_selectedDay == null) return const SizedBox.shrink();
    final day = _selectedDay!;

    return _premiumCardShell(
      child: Padding(
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
                    Icons.today_rounded,
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
                        'Resumo do dia',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.55,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('EEEE, dd/MM/yyyy', 'pt_BR').format(day),
                        style: const TextStyle(
                          fontSize: 15,
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
            if (_mesAba == _AgendaMesAba.financeiro) ...[
              if (items.isEmpty &&
                  incomePending.isEmpty &&
                  expensePending.isEmpty)
                Text(
                  'Nenhum lançamento financeiro pendente neste dia.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                    height: 1.35,
                  ),
                )
              else ...[
                for (final item in incomePending)
                  _resumoFinancePendingLinha(item),
                for (final item in expensePending)
                  _resumoFinancePendingLinha(item),
              ],
            ] else if (items.isEmpty && expensePending.isEmpty && incomePending.isEmpty)
              Text(
                'Nenhum compromisso particular neste dia.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                  height: 1.35,
                ),
              )
            else ...[
              ...items.map((doc) {
                final data = doc.data();
                final color = _colorFromHex(data['colorHex']?.toString());
                final title = (data['title'] ?? 'Compromisso').toString();
                final time = (data['time'] ?? '').toString();
                final end = (data['endTime'] ?? '').toString();
                final notes = (data['notes'] ?? '').toString().trim();
                final horario = end.isNotEmpty ? '$time – $end' : time;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 5,
                        height: 42,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.35),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: Color(0xFF1A237E),
                              ),
                            ),
                            if (horario.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                horario,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                            if (notes.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                notes,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            const SizedBox(height: 4),
            FilledButton.icon(
              onPressed: () => _adicionarNaData(day),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text(
                'Adicionar compromisso',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                backgroundColor: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resumoFinancePendingLinha(AgendaFinancePendingItem item) {
    const incomeGradient = [Color(0xFF0EA5E9), Color(0xFF0284C7)];
    const expenseGradient = [Color(0xFFF97316), Color(0xFFEA580C)];
    final isIncome = item.isIncome;
    final gradient = isIncome ? incomeGradient : expenseGradient;
    final data = item.data;
    final desc = (data['description'] ?? data['category'] ?? '').toString().trim();
    final title = desc.isEmpty
        ? (isIncome ? 'Receita pendente' : 'Despesa pendente')
        : desc;
    final amount = ((data['amount'] ?? 0) as num).toDouble().abs();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 5,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: Color(0xFF1A237E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isIncome ? 'Receita pendente' : 'Despesa pendente',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: gradient.last,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  CurrencyFormats.formatBRL(amount),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: gradient.last,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMesGridModerno(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Map<DateTime, List<AgendaFinancePendingItem>> financeByDay,
  ) {
    final tituloMes = _focusedMonthTitle();
    var cardIndex = 0;

    if (_mesAba == _AgendaMesAba.financeiro) {
      final monthItems = <AgendaFinancePendingItem>[];
      for (final entry in financeByDay.entries) {
        final day = entry.key;
        if (day.year != _focusedDay.year || day.month != _focusedDay.month) {
          continue;
        }
        monthItems.addAll(entry.value);
      }
      monthItems.sort((a, b) {
        final da = agendaFinanceEffectiveDay(a.data);
        final db = agendaFinanceEffectiveDay(b.data);
        if (da == null || db == null) return 0;
        return da.compareTo(db);
      });
      if (monthItems.isEmpty) {
        return _premiumCardShell(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Nenhum compromisso financeiro pendente em $tituloMes.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        );
      }
      return _premiumCardShell(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AgendaModernUI.sectionHeader(
                title: 'Financeiros do mês',
                subtitle: '${monthItems.length} lançamento${monthItems.length == 1 ? '' : 's'} · $tituloMes',
                icon: Icons.payments_outlined,
                color: const Color(0xFFF97316),
              ),
              ...monthItems.map((item) {
                final idx = cardIndex++;
                final day = agendaFinanceEffectiveDay(item.data);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (day != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 6),
                        child: Text(
                          DateFormat('EEEE, dd/MM', 'pt_BR').format(day),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    AgendaFinancePendingItemCard(
                      item: item,
                      index: idx,
                      onEdit: () => _editFinancePending(item),
                      onDelete: () => _deleteFinancePending(item),
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      );
    }

    final monthItems = _itemsForFocusedMonth(docs);
    final googleMonth = _googleParticularForMonth(docs);
    final total = monthItems.length + googleMonth.length;
    if (total == 0) {
      return _premiumCardShell(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Nenhum compromisso particular em $tituloMes.'
            '${_googleEnabled ? ' Eventos Google aparecem aqui quando houver sync.' : ''}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
              height: 1.35,
            ),
          ),
        ),
      );
    }

    final docsById = {for (final d in docs) d.id: d};
    return _premiumCardShell(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AgendaModernUI.sectionHeader(
              title: 'Particulares do mês',
              subtitle: '$total item${total == 1 ? '' : 'ns'} · $tituloMes'
                  '${googleMonth.isNotEmpty ? ' · inclui Google Calendar' : ''}',
              icon: Icons.event_available_rounded,
              color: _corCompromisso,
            ),
            ...monthItems.map((row) {
              final id = (row['id'] ?? '').toString();
              final doc = docsById[id];
              if (doc == null) return const SizedBox.shrink();
              final idx = cardIndex++;
              final date = CompromissoReminderService.dateFromDoc(row);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (date != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 6),
                      child: Text(
                        DateFormat('EEEE, dd/MM', 'pt_BR').format(date),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  AgendaModernFadeIn(
                    index: idx,
                    child: AgendaOpenItemCard(
                      doc: doc,
                      isAudiencia: false,
                      profile: widget.profile,
                      onEdit: () => _openCompromissoForm(
                        context: context,
                        existing: doc,
                      ),
                      onDelete: () => _confirmDelete(doc),
                    ),
                  ),
                ],
              );
            }),
            ...googleMonth.map(
              (e) => _buildGoogleEventCard(e, cardIndex++),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRodapeFeriadosMes(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required Map<DateTime, List<AgendaFinancePendingItem>> financeByDay,
  }) {
    final feriados = HolidayHelper.getFeriadosDoMes(_focusedDay);
    final tituloMes = _focusedMonthTitle();

    return _premiumCardShell(
      child: Padding(
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
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.55,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tituloMes,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppColors.deepBlueDark,
                          height: 1.1,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Feriados nacionais do mês do calendário',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
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
                'Sem feriados nacionais neste mês.',
                style: TextStyle(
                  fontSize: 12,
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
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.09),
                          AppColors.accent.withValues(alpha: 0.06),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.deepBlue.withValues(alpha: 0.14),
                      ),
                    ),
                    child: Text(
                      '$data · ${f.name}$extra',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                }).toList(),
              ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => _openExportPdfSheet(
                context,
                docs,
                financeByDay: financeByDay,
              ),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
              label: Text('Exportar PDF — $tituloMes'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE65100),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleEventCard(GoogleCalendarEventItem event, int index) {
    const color = GoogleCalendarSyncService.googleEventColor;
    return AgendaModernFadeIn(
      index: index,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openCompromissoForm(
            context: context,
            googleEvent: event,
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: AgendaModernUI.modernCardDecoration(
              accent: color,
              elevated: true,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 5,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                event.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: Color(0xFF1A237E),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: color.withValues(alpha: 0.35),
                                ),
                              ),
                              child: const Text(
                                'GOOGLE',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: color,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          event.horarioLabel,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        if (event.notes.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            event.notes.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Editar',
                    icon: const Icon(Icons.edit_rounded, size: 20),
                    color: color,
                    onPressed: () => _openCompromissoForm(
                      context: context,
                      googleEvent: event,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Excluir',
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    color: Colors.red.shade700,
                    onPressed: () => _confirmDeleteGoogleEvent(event),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompromissosGrid(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
    List<GoogleCalendarEventItem> googleOnly, {
    List<AgendaFinancePendingItem> incomePending = const [],
    List<AgendaFinancePendingItem> expensePending = const [],
  }) {
    final financeCount = incomePending.length + expensePending.length;
    final particularCount = items.length + googleOnly.length;

    if (_mesAba == _AgendaMesAba.financeiro) {
      if (financeCount == 0) return const SizedBox.shrink();
      var cardIndex = 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AgendaFinancePendingDayBand(
            isIncome: true,
            count: incomePending.length,
            total: sumAgendaFinancePendingAmount(incomePending),
          ),
          AgendaFinancePendingDayBand(
            isIncome: false,
            count: expensePending.length,
            total: sumAgendaFinancePendingAmount(expensePending),
          ),
          AgendaModernUI.sectionHeader(
            title: 'Financeiros do dia',
            subtitle: '$financeCount lançamento${financeCount == 1 ? '' : 's'}',
            icon: Icons.payments_outlined,
            color: const Color(0xFFF97316),
          ),
          ...incomePending.map((item) {
            final idx = cardIndex++;
            return AgendaFinancePendingItemCard(
              item: item,
              index: idx,
              onEdit: () => _editFinancePending(item),
              onDelete: () => _deleteFinancePending(item),
            );
          }),
          ...expensePending.map((item) {
            final idx = cardIndex++;
            return AgendaFinancePendingItemCard(
              item: item,
              index: idx,
              onEdit: () => _editFinancePending(item),
              onDelete: () => _deleteFinancePending(item),
            );
          }),
        ],
      );
    }

    if (particularCount == 0) return const SizedBox.shrink();

    var cardIndex = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AgendaModernUI.sectionHeader(
          title: 'Particulares do dia',
          subtitle: '$particularCount item${particularCount == 1 ? '' : 'ns'}'
              '${googleOnly.isNotEmpty ? ' · Google Calendar' : ''}',
          icon: Icons.event_available_rounded,
          color: _corCompromisso,
        ),
        ...items.map((doc) {
          final idx = cardIndex++;
          return AgendaModernFadeIn(
            index: idx,
            child: AgendaOpenItemCard(
              doc: doc,
              isAudiencia: false,
              profile: widget.profile,
              onEdit: () => _openCompromissoForm(
                context: context,
                existing: doc,
              ),
              onDelete: () => _confirmDelete(doc),
            ),
          );
        }),
        ...googleOnly.asMap().entries.map(
              (e) => _buildGoogleEventCard(e.value, cardIndex + e.key),
            ),
      ],
    );
  }

  Map<DateTime, List<AgendaFinancePendingItem>> _mergeFinanceByDay(
    List<AgendaFinancePendingItem> income,
    List<AgendaFinancePendingItem> expense,
  ) {
    final map = <DateTime, List<AgendaFinancePendingItem>>{};
    for (final item in [...income, ...expense]) {
      final day = agendaFinanceEffectiveDay(item.data);
      if (day == null) continue;
      map.putIfAbsent(day, () => []).add(item);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final holidayKeys = HolidayHelper.getFeriados(_focusedDay.year)
        .map((h) => DateFormat('yyyy-MM-dd').format(h.date))
        .toSet();
    final isNarrow = MediaQuery.sizeOf(context).width < 520;

    // ignore: unused_local_variable — força rebuild ao tocar em «Tentar novamente»
    final _ = _streamGeneration;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: financeTransactionsPendingSnapshots(uid: _userDocId, type: 'income'),
      builder: (context, incomePendingSnap) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: financeTransactionsPendingSnapshots(uid: _userDocId, type: 'expense'),
          builder: (context, expensePendingSnap) {
            return StreamBuilder<Map<String, dynamic>>(
              stream: FixedIncomePreferencesService().watch(_userDocId),
              builder: (context, incomePrefsSnap) {
                return StreamBuilder<Map<String, dynamic>>(
                  stream: FixedExpensePreferencesService().watch(_userDocId),
                  builder: (context, expensePrefsSnap) {
                    return StreamBuilder<List<FinanceAccount>>(
                      stream: FinanceAccountsService().streamAccounts(_userDocId),
                      builder: (context, accSnap) {
                        final ccIds = FinanceAccountBalanceUtils.creditCardAccountIds(
                          accSnap.data ?? const [],
                        );
                        final showFixedIncome =
                            incomePrefsSnap.data?['showInPending'] as bool? ?? true;
                        final showFixedExpense =
                            expensePrefsSnap.data?['showInPending'] as bool? ?? true;
                        final monthsAhead = [
                          (incomePrefsSnap.data?['pendingMonthsAhead'] as int?) ??
                              defaultAgendaFinancePendingMonthsAhead(),
                          (expensePrefsSnap.data?['pendingMonthsAhead'] as int?) ??
                              defaultAgendaFinancePendingMonthsAhead(),
                        ].reduce((a, b) => a > b ? a : b).clamp(1, 12);
                        final limitDate = agendaFinancePendingLimitDate(monthsAhead);

                        final incomePendingAll = filterAgendaFinancePending(
                          docs: incomePendingSnap.data?.docs ?? const [],
                          type: 'income',
                          creditCardAccountIds: ccIds,
                          showFixedInPending: showFixedIncome,
                          limitDate: limitDate,
                        );
                        final expensePendingAll = filterAgendaFinancePending(
                          docs: expensePendingSnap.data?.docs ?? const [],
                          type: 'expense',
                          creditCardAccountIds: ccIds,
                          showFixedInPending: showFixedExpense,
                          limitDate: limitDate,
                        );
                        final financeByDay =
                            _mergeFinanceByDay(incomePendingAll, expensePendingAll);
                        final selectedKey =
                            _selectedDay != null ? _dayKey(_selectedDay!) : null;
                        final selectedIncome = selectedKey == null
                            ? const <AgendaFinancePendingItem>[]
                            : filterAgendaFinancePending(
                                docs: incomePendingSnap.data?.docs ?? const [],
                                type: 'income',
                                creditCardAccountIds: ccIds,
                                showFixedInPending: showFixedIncome,
                                limitDate: limitDate,
                                onlyDay: _selectedDay,
                              );
                        final selectedExpense = selectedKey == null
                            ? const <AgendaFinancePendingItem>[]
                            : filterAgendaFinancePending(
                                docs: expensePendingSnap.data?.docs ?? const [],
                                type: 'expense',
                                creditCardAccountIds: ccIds,
                                showFixedInPending: showFixedExpense,
                                limitDate: limitDate,
                                onlyDay: _selectedDay,
                              );

                        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          key: ValueKey(
                              'agenda-rem-${_focusedDay.year}-$_streamGeneration'),
                          stream: _remindersPeriodStream(),
                          builder: (context, snap) {
                            return _buildAgendaBody(
                              context,
                              snap: snap,
                              holidayKeys: holidayKeys,
                              isNarrow: isNarrow,
                              financeByDay: financeByDay,
                              selectedIncomePending: selectedIncome,
                              selectedExpensePending: selectedExpense,
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildAgendaBody(
    BuildContext context, {
    required AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap,
    required Set<String> holidayKeys,
    required bool isNarrow,
    required Map<DateTime, List<AgendaFinancePendingItem>> financeByDay,
    required List<AgendaFinancePendingItem> selectedIncomePending,
    required List<AgendaFinancePendingItem> selectedExpensePending,
  }) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_rounded,
                      size: 48, color: Colors.grey.shade500),
                  const SizedBox(height: 12),
                  const Text(
                    'Não foi possível carregar a agenda.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Toque abaixo para tentar novamente.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _retryStream,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          );
        }

        final docs = _filterCompromissos(snap.data?.docs ?? []);
        final byDay = _groupByDay(docs);
        final selectedItems = _selectedDay != null
            ? (byDay[_dayKey(_selectedDay!)] ??
                <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            : <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final googleOnly = _selectedDay != null && _googleEnabled
            ? GoogleCalendarSyncService.externalEventsForDay(
                day: _selectedDay!,
                googleEvents: _googleEventsByDay.values.expand((e) => e).toList(),
                linkedGoogleEventIds: _linkedGoogleEventIds(docs),
              )
            : <GoogleCalendarEventItem>[];

        final scroll = widget.shellScrollController ?? ScrollController();

        return ShellKeyboardBottomPad(
          child: CustomScrollView(
            controller: scroll,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isNarrow ? 8 : 12,
                    8,
                    isNarrow ? 8 : 12,
                    24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: AppColors.logoGradient,
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.28),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Text(
                          'Agenda — compromissos e financeiro pendente',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_userDocId.isNotEmpty)
                        GoogleCalendarIntegrationToggle(
                          userDocId: _userDocId,
                          compact: true,
                          onChanged: () {
                            unawaited(_refreshGoogleDays());
                            setState(() {});
                          },
                        ),
                      const SizedBox(height: 10),
                      Container(
                        padding: EdgeInsets.fromLTRB(
                          isNarrow ? 10 : 14,
                          isNarrow ? 8 : 12,
                          isNarrow ? 10 : 14,
                          isNarrow ? 12 : 16,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(isNarrow ? 22 : 28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.04),
                              blurRadius: 24,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            if (_googleSyncLoading)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 8),
                                child: LinearProgressIndicator(minHeight: 2),
                              ),
                            _buildCalendar(byDay, holidayKeys, isNarrow, financeByDay),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.info_outline_rounded,
                                    size: 14, color: Colors.grey.shade600),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Calendário com todos os compromissos: '
                                    'azul/laranja = financeiro · cores = particulares · '
                                    'nuvem = Google Calendar · vermelho = fim de semana/feriado.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildRodapeFeriadosMes(
                        docs,
                        financeByDay: financeByDay,
                      ),
                      if (_selectedDay != null) ...[
                        const SizedBox(height: 12),
                        _buildRodapeTotalDia(
                          selectedItems,
                          incomePending: selectedIncomePending,
                          expensePending: selectedExpensePending,
                        ),
                        const SizedBox(height: 12),
                        _buildCompromissosGrid(
                          selectedItems,
                          googleOnly,
                          incomePending: selectedIncomePending,
                          expensePending: selectedExpensePending,
                        ),
                      ],
                      const SizedBox(height: 12),
                      _buildModernMesAbas(isNarrow: isNarrow),
                      _buildMesGridModerno(docs, financeByDay),
                      const SizedBox(height: 8),
                      if (_googleEnabled)
                        Text(
                          'Calendário Google ativo — compromissos locais sincronizam automaticamente.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
  }
}
