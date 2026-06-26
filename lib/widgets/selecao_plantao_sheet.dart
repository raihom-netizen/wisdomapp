import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/shift_location.dart';
import '../models/scale_entry.dart';
import '../models/scale_rates.dart';
import '../services/scale_rates_cache_notifier.dart';
import '../services/scale_rates_service.dart';
import '../theme/app_colors.dart';
import '../constants/currency_formats.dart';
import 'package:intl/intl.dart';
import 'employer_vinculo_chips.dart';
import 'lancamento_expresso_plantao_sheet.dart';
import 'multi_date_month_picker_dialog.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/connectivity_offline.dart';
import '../utils/keyboard_form_scaffold.dart';
import '../screens/locations_screen.dart';
import '../services/express_compromisso_agenda_sync.dart';

/// Bottom sheet para selecionar plantão pré-cadastrado ou criar novo.
class SelecaoPlantaoSheet extends StatefulWidget {
  final String uid;
  final DateTime day;
  final List<ShiftLocation> locations;
  final bool trocar;
  final List<ScaleEntry> entriesExistentes;
  final VoidCallback onSalvar;
  final VoidCallback onCriarNovo;
  /// Geração automática por período (só inclusão em dia limpo; null = oculto).
  final VoidCallback? onPeriodoAutomatico;

  const SelecaoPlantaoSheet({
    super.key,
    required this.uid,
    required this.day,
    required this.locations,
    required this.trocar,
    required this.entriesExistentes,
    required this.onSalvar,
    required this.onCriarNovo,
    this.onPeriodoAutomatico,
  });

  @override
  State<SelecaoPlantaoSheet> createState() => _SelecaoPlantaoSheetState();
}

class _SelecaoPlantaoSheetState extends State<SelecaoPlantaoSheet> {
  String get _userDocId => firestoreUserDocIdForAppShell(widget.uid);

  /// Cópia mutável: atualiza ao voltar de «Lista de plantões recorrentes» (a rota fullscreen não recebe novo `widget.locations` automaticamente).
  late List<ShiftLocation> _locationsCache;

  final Set<String> _selectedKeys = {};
  final Map<String, Map<String, double>?> _valorByKey = {};
  /// Uma ou mais datas (mesmo mês) para lançar os itens do pré-cadastro de uma vez.
  late List<DateTime> _days;
  bool _loading = false;
  /// `null` = todos (Estado / Município / Particular).
  EmployerType? _filtroVinculo;

  /// Uma única leitura de taxas por sessão (invalida ao mudar parâmetros em Configurações).
  Future<ScaleRates>? _ratesMemo;
  VoidCallback? _ratesListener;

  Future<ScaleRates> _getRatesCached() =>
      _ratesMemo ??= ScaleRatesService().getEffectiveRates(_userDocId);

  static DateTime _normDay(DateTime d) => DateTime(d.year, d.month, d.day);

  List<DateTime> get _daysSorted =>
      _days.map(_normDay).toSet().toList()..sort((a, b) => a.compareTo(b));

  DateTime get _dayParaResumo => _daysSorted.isNotEmpty ? _daysSorted.first : _normDay(widget.day);

  String _keyForLoc(ShiftLocation loc) {
    if (loc.id != null && loc.id!.isNotEmpty) return loc.id!;
    return '${loc.name}\t${loc.startTime}\t${loc.endTime}';
  }

  ShiftLocation? _findLocByKey(String key) {
    for (final l in _locationsCache) {
      if (_keyForLoc(l) == key) return l;
    }
    return null;
  }

  List<ShiftLocation> get _locationsFiltradas {
    if (_filtroVinculo == null) return _locationsCache;
    return _locationsCache.where((l) => l.employerType == _filtroVinculo).toList();
  }

  void _setFiltroVinculo(EmployerType? v) {
    setState(() {
      _filtroVinculo = v;
      _selectedKeys.removeWhere((k) {
        final loc = _findLocByKey(k);
        return loc != null && v != null && loc.employerType != v;
      });
    });
  }

  /// Botão premium para Plantão/Compromisso expresso: gradiente, sombra e ícone em pill branca translúcida.
  Widget _premiumExpressoButton({
    required IconData icon,
    required String label,
    required List<Color> gradient,
    required VoidCallback onTap,
    String? subtitle,
    double titleFontSize = 14.5,
    EdgeInsetsGeometry padding =
        const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: gradient.last.withValues(alpha: 0.35),
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
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: Colors.white.withValues(alpha: 0.18),
          highlightColor: Colors.white.withValues(alpha: 0.08),
          child: Padding(
            padding: padding,
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: titleFontSize,
                          letterSpacing: 0.1,
                          shadows: const [
                            Shadow(
                              color: Color(0x55000000),
                              blurRadius: 2,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w600,
                            fontSize: 11.5,
                            height: 1.2,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _autoViradaMarker(String sourceId) => '[AUTO_VIRADA_MES:$sourceId]';
  String _autoViradaNote(String sourceId) =>
      'Lançamento automático (virada de mês) ${_autoViradaMarker(sourceId)}';

  bool _isLastDayOfMonth(DateTime d) => ScaleRates.isLastDayOfMonth(d);

  bool _isCrossingToNextDay(DateTime startDt, DateTime endDt) {
    return startDt.year != endDt.year ||
        startDt.month != endDt.month ||
        startDt.day != endDt.day;
  }

  (DateTime startDt, DateTime endDt) _shiftBoundsOnDay(
    DateTime entryDate,
    String startHHmm,
    String endHHmm,
  ) {
    final sp = startHHmm.split(':');
    final ep = endHHmm.split(':');
    final sh = int.tryParse(sp.first.trim()) ?? 8;
    final sm = sp.length > 1 ? (int.tryParse(sp[1].trim()) ?? 0) : 0;
    final eh = int.tryParse(ep.first.trim()) ?? 18;
    final em = ep.length > 1 ? (int.tryParse(ep[1].trim()) ?? 0) : 0;
    final startDt =
        DateTime(entryDate.year, entryDate.month, entryDate.day, sh, sm);
    var endDt = DateTime(entryDate.year, entryDate.month, entryDate.day, eh, em);
    if (endDt.isBefore(startDt) || endDt.isAtSameMomentAs(startDt)) {
      endDt = endDt.add(const Duration(days: 1));
    }
    return (startDt, endDt);
  }

  /// Mesma regra de «Incluir plantão»: último dia do mês + turno passa da meia-noite.
  bool _plantaoGeraViradaMes(ShiftLocation loc, DateTime entryDate) {
    if (!loc.financialEnabled) return false;
    if (!_isLastDayOfMonth(entryDate)) return false;
    final (startDt, endDt) =
        _shiftBoundsOnDay(entryDate, loc.startTime, loc.endTime);
    return _isCrossingToNextDay(startDt, endDt);
  }

  Future<void> _removeAutoLancamentoBySourceId(
    CollectionReference<Map<String, dynamic>> scalesRef,
    String sourceId,
  ) async {
    Future<QuerySnapshot<Map<String, dynamic>>> getPreferCache(
        Query<Map<String, dynamic>> q) async {
      try {
        return await q.get(const GetOptions(source: Source.cache));
      } catch (_) {
        return await q.get();
      }
    }

    final bySource = await getPreferCache(
        scalesRef.where('autoViradaSourceId', isEqualTo: sourceId));
    for (final doc in bySource.docs) {
      await scalesRef.doc(doc.id).delete();
    }
    // Compatibilidade com lançamentos antigos.
    final note = _autoViradaNote(sourceId);
    final legacy = await getPreferCache(scalesRef.where('notes', isEqualTo: note));
    for (final doc in legacy.docs) {
      await scalesRef.doc(doc.id).delete();
    }
  }

  static Timestamp _firestoreDateNoonUtc(DateTime day) => Timestamp.fromDate(
        DateTime.utc(day.year, day.month, day.day, 12, 0, 0),
      );

  Future<List<ScaleEntry>> _listScaleEntriesOnDay(
    CollectionReference<Map<String, dynamic>> scalesRef,
    DateTime day,
  ) async {
    try {
      final snap = await scalesRef
          .where('date', isEqualTo: _firestoreDateNoonUtc(_normDay(day)))
          .get();
      return snap.docs.map((d) => ScaleEntry.fromDoc(d)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Remove plantão/compromisso antigo (virada automática + espelho Agenda quando aplicável).
  Future<void> _deleteScaleEntryForTroca(
    CollectionReference<Map<String, dynamic>> scalesRef,
    ScaleEntry e,
  ) async {
    final id = e.id?.trim();
    if (id == null || id.isEmpty) return;
    await _removeAutoLancamentoBySourceId(scalesRef, id);
    await ExpressCompromissoAgendaSync.deleteScaleWithAgendaSync(
      userDocId: _userDocId,
      entry: e,
    );
  }

  /// Na troca: apaga o(s) lançamento(s) antigo(s) do dia antes de gravar o plantão novo.
  Future<void> _removerEntradasAntesDaTroca(
    CollectionReference<Map<String, dynamic>> scalesRef,
  ) async {
    final dia = _normDay(widget.day);
    final onDay = await _listScaleEntriesOnDay(scalesRef, dia);
    final idsVistos = <String>{};
    final paraApagar = <ScaleEntry>[];

    void registrar(ScaleEntry e) {
      final id = e.id?.trim();
      if (id == null || id.isEmpty || !idsVistos.add(id)) return;
      paraApagar.add(e);
    }

    final existentes = widget.entriesExistentes;
    final trocarApenasUm = existentes.length == 1;

    for (final e in existentes) {
      registrar(e);
    }
    if (!trocarApenasUm) {
      for (final e in onDay) {
        registrar(e);
      }
    }
    if (paraApagar.isEmpty) {
      for (final e in onDay) {
        registrar(e);
      }
    }

    for (final e in paraApagar) {
      await _deleteScaleEntryForTroca(scalesRef, e);
    }
    ExpressCompromissoAgendaSync.refreshNotifications(_userDocId);
  }

  Future<void> _syncAutoViradaMesFromLocation({
    required CollectionReference<Map<String, dynamic>> scalesRef,
    required String sourceId,
    required ShiftLocation loc,
    required String colorHex,
    required String labelComHorario,
    required String? abbreviation,
    required DateTime entryDate,
    ScaleRates? rates,
  }) async {
    await _removeAutoLancamentoBySourceId(scalesRef, sourceId);
    if (!_plantaoGeraViradaMes(loc, entryDate)) return;

    final (startDt, endDt) =
        _shiftBoundsOnDay(entryDate, loc.startTime, loc.endTime);
    final carryDate =
        DateTime(entryDate.year, entryDate.month, entryDate.day)
            .add(const Duration(days: 1));
    final nextStart = DateTime(carryDate.year, carryDate.month, carryDate.day, 0, 0);
    final ratesResolved = rates ?? await ScaleRatesService().getEffectiveRates(_userDocId);
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

    final hoje = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final autoEntry = ScaleEntry(
      date: carryDate,
      start: '00:00',
      end: '${endDt.hour.toString().padLeft(2, '0')}:${endDt.minute.toString().padLeft(2, '0')}',
      dayRate: ratesCarry.diurnoForWeekday(ScaleRates.weekdayToIndex(carryDate.weekday)),
      nightRate: ratesResolved.noturnoForWeekday(ScaleRates.weekdayToIndex(entryDate.weekday)),
      hoursDay: (res['hoursDay'] ?? 0).toDouble(),
      hoursNight: (res['hoursNight'] ?? 0).toDouble(),
      totalValue: total,
      label: labelComHorario,
      abbreviation: abbreviation,
      colorHex: colorHex,
      paid: carryDate.isBefore(hoje),
      isCompromisso: false,
      employerType: loc.employerType.name,
      notes: _autoViradaNote(sourceId),
    );
    final autoMap = autoEntry.toMap();
    autoMap['autoViradaMes'] = true;
    autoMap['autoViradaSourceId'] = sourceId;
    await scalesRef.add(autoMap);
  }

  @override
  void initState() {
    super.initState();
    _ratesListener = () {
      final nUid = ScaleRatesCacheNotifier.instance.lastUid;
      if (nUid != null && nUid.isNotEmpty && nUid != _userDocId) return;
      _ratesMemo = null;
      if (mounted) setState(() {});
    };
    ScaleRatesCacheNotifier.instance.addListener(_ratesListener!);
    _locationsCache = List<ShiftLocation>.from(widget.locations);
    _days = [_normDay(widget.day)];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _getRatesCached();
    });
  }

  @override
  void dispose() {
    if (_ratesListener != null) {
      ScaleRatesCacheNotifier.instance.removeListener(_ratesListener!);
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SelecaoPlantaoSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.locations != oldWidget.locations) {
      _locationsCache = List<ShiftLocation>.from(widget.locations);
    }
  }

  Future<void> _recarregarLocationsDoFirestore() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_userDocId)
          .collection('locations')
          .get();
      final list = snap.docs
          .map((d) => ShiftLocation.fromMap(d.id, d.data()))
          .where((l) => l.name.isNotEmpty || l.abbreviation.isNotEmpty)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (mounted) setState(() => _locationsCache = list);
    } catch (_) {}
  }

  Future<Map<String, double>?> _computeValorMap(
    ShiftLocation loc,
    DateTime forDay, {
    ScaleRates? rates,
  }) async {
    if (!loc.financialEnabled) {
      return {'hoursDay': 0.0, 'hoursNight': 0.0, 'total': 0.0};
    }
    if (loc.paymentType == PaymentType.fixed) {
      final total = loc.baseValue + loc.bonus - loc.discount;
      return {'hoursDay': 0.0, 'hoursNight': 0.0, 'total': total.clamp(0, double.infinity)};
    }
    final partsStart = loc.startTime.split(':');
    final partsEnd = loc.endTime.split(':');
    final startH = int.tryParse(partsStart.first) ?? 8;
    final startM = partsStart.length > 1 ? int.tryParse(partsStart[1]) ?? 0 : 0;
    final endH = int.tryParse(partsEnd.first) ?? 18;
    final endM = partsEnd.length > 1 ? int.tryParse(partsEnd[1]) ?? 0 : 0;

    var startDt = DateTime(forDay.year, forDay.month, forDay.day, startH, startM);
    var endDt = DateTime(forDay.year, forDay.month, forDay.day, endH, endM);
    if (endDt.isBefore(startDt) || endDt.isAtSameMomentAs(startDt)) {
      endDt = endDt.add(const Duration(days: 1));
    }
    return ScaleRatesService().computeShiftForUid(
      uid: _userDocId,
      start: startDt,
      end: endDt,
      entryDate: forDay,
    );
  }

  Future<void> _onLocationTap(ShiftLocation loc) async {
    final key = _keyForLoc(loc);
    final wasSelected = _selectedKeys.contains(key);

    setState(() {
      if (widget.trocar) {
        _selectedKeys
          ..clear()
          ..add(key);
        _valorByKey.clear();
      } else {
        if (wasSelected) {
          _selectedKeys.remove(key);
          _valorByKey.remove(key);
        } else {
          _selectedKeys.add(key);
        }
      }
    });

    if (!widget.trocar && wasSelected) return;

    final rates = await _getRatesCached();
    if (!mounted) return;

    final v = await _computeValorMap(loc, _dayParaResumo, rates: rates);
    if (mounted) setState(() => _valorByKey[key] = v);
  }

  Future<void> _refreshValoresSelecionados() async {
    final rates = await _getRatesCached();
    if (!mounted) return;
    final keys = _selectedKeys.toList();
    final entries = await Future.wait(
      keys.map((k) async {
        final l = _findLocByKey(k);
        if (l == null) return MapEntry<String, Map<String, double>?>(k, null);
        final v = await _computeValorMap(l, _dayParaResumo, rates: rates);
        return MapEntry(k, v);
      }),
    );
    if (!mounted) return;
    setState(() {
      for (final e in entries) {
        if (e.value != null) _valorByKey[e.key] = e.value;
      }
    });
  }

  String _labelBotaoDatas() {
    final ds = _daysSorted;
    if (ds.isEmpty) return DateFormat('EEEE, d \'de\' MMMM', 'pt_BR').format(widget.day);
    if (widget.trocar || ds.length == 1) {
      return DateFormat('EEEE, d \'de\' MMMM', 'pt_BR').format(ds.first);
    }
    final mes = DateFormat('MMMM yyyy', 'pt_BR').format(ds.first);
    final nums = ds.map((d) => '${d.day}').join(', ');
    return '${ds.length} dias em $mes ($nums)';
  }

  /// Normaliza cor do plantão (0xFF..., #..., ou 6 hex) para formato da escala: #RRGGBB.
  static String _normalizeColorHexForScale(String? colorHex) {
    if (colorHex == null || colorHex.isEmpty) return '#2D5BFF';
    String hex = colorHex.replaceFirst(RegExp(r'^#'), '').replaceFirst(RegExp(r'^0x', caseSensitive: false), '');
    if (hex.length > 6) hex = hex.substring(hex.length - 6);
    if (hex.length < 6) return '#2D5BFF';
    return '#${hex.toUpperCase()}';
  }

  Future<void> _salvarNaEscala() async {
    if (_selectedKeys.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione ao menos um plantão ou compromisso.')),
      );
      return;
    }
    if (widget.trocar && _selectedKeys.length != 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Na troca, selecione apenas um item do pré-cadastro.')),
      );
      return;
    }

    final locs = <ShiftLocation>[];
    for (final loc in _locationsCache) {
      if (_selectedKeys.contains(_keyForLoc(loc))) locs.add(loc);
    }
    if (locs.isEmpty) return;

    setState(() => _loading = true);

    final scalesRef = FirebaseFirestore.instance.collection('users').doc(_userDocId).collection('scales');

    try {
      if (widget.trocar) {
        await _removerEntradasAntesDaTroca(scalesRef);
      }

      final hoje = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      // Troca sempre no dia aberto no calendário (evita apagar num dia e lançar noutro).
      final dias = widget.trocar ? [_normDay(widget.day)] : _daysSorted;
      if (dias.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      var totalInclusoes = 0;
      final rates = await _getRatesCached();

      String dayLocKey(DateTime d, ShiftLocation loc) =>
          '${d.year}-${d.month}-${d.day}\t${_keyForLoc(loc)}';

      final pairs = <(DateTime, ShiftLocation)>[];
      for (final dayNorm in dias) {
        for (final loc in locs) {
          if (loc.financialEnabled && loc.paymentType != PaymentType.fixed) {
            pairs.add((dayNorm, loc));
          }
        }
      }
      final valorByDayLoc = <String, Map<String, double>?>{};
      if (pairs.isNotEmpty) {
        final valores = await Future.wait(
          pairs.map((p) => _computeValorMap(p.$2, p.$1, rates: rates)),
        );
        for (var i = 0; i < pairs.length; i++) {
          valorByDayLoc[dayLocKey(pairs[i].$1, pairs[i].$2)] = valores[i];
        }
      }

      final List<({
        DocumentReference<Map<String, dynamic>> ref,
        Map<String, dynamic> data,
        ShiftLocation loc,
        String colorHex,
        String labelComHorario,
        String? abbreviation,
        DateTime entryDate
      })> pendentes = [];
      for (final dayNorm in dias) {
        final isRetroativo = dayNorm.isBefore(hoje);

        for (final loc in locs) {
          Map<String, double>? valor;
          if (loc.financialEnabled && loc.paymentType != PaymentType.fixed) {
            valor = valorByDayLoc[dayLocKey(dayNorm, loc)];
          }

          final colorHex = _normalizeColorHexForScale(loc.colorHex);
          final start = loc.startTime;
          final end = loc.endTime;

          double totalValue = 0;
          double hoursDay = 0;
          double hoursNight = 0;
          double dayRate = 0;
          double nightRate = 0;

          if (loc.financialEnabled) {
            if (loc.paymentType == PaymentType.fixed) {
              totalValue = (loc.baseValue + loc.bonus - loc.discount).clamp(0, double.infinity);
            } else if (valor != null) {
              totalValue = valor['total'] ?? 0;
              hoursDay = valor['hoursDay'] ?? 0;
              hoursNight = valor['hoursNight'] ?? 0;
              dayRate = rates.diurnoForWeekday(ScaleRates.weekdayToIndex(dayNorm.weekday));
              nightRate = rates.noturnoForWeekday(ScaleRates.weekdayToIndex(dayNorm.weekday));
            }
          }

          final labelComHorario = ShiftLocation.fullNameWithSchedule(loc.name, start, end);
          final abbrev = loc.abbreviation.trim().isNotEmpty
              ? loc.abbreviation.trim().toUpperCase().substring(0, (loc.abbreviation.trim().length).clamp(1, 6))
              : ShiftLocation.abbreviationFromName(loc.name);
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
            abbreviation: abbrev.isNotEmpty ? abbrev : null,
            colorHex: colorHex,
            paid: isRetroativo,
            isCompromisso: !loc.financialEnabled,
            employerType: loc.employerType.name,
          );

          final ref = scalesRef.doc();
          pendentes.add((
            ref: ref,
            data: entry.toMap(),
            loc: loc,
            colorHex: colorHex,
            labelComHorario: labelComHorario,
            abbreviation: abbrev.isNotEmpty ? abbrev : null,
            entryDate: dayNorm,
          ));
          totalInclusoes++;
        }
      }

      // Escrita em lote (rápido para múltiplos dias/tipos), respeitando limite do Firestore.
      const batchLimit = 400;
      for (var i = 0; i < pendentes.length; i += batchLimit) {
        final chunk = pendentes.sublist(
          i,
          (i + batchLimit) > pendentes.length ? pendentes.length : (i + batchLimit),
        );
        final batch = FirebaseFirestore.instance.batch();
        for (final p in chunk) {
          batch.set(p.ref, p.data);
        }
        await batch.commit();
      }

      // Virada de mês (00:00 do dia seguinte / 1º do mês seguinte) — mesma regra de «Incluir plantão».
      var gerouViradaMes = false;
      if (pendentes.isNotEmpty) {
        Future<void> syncViradas() async {
          for (final p in pendentes) {
            if (!_plantaoGeraViradaMes(p.loc, p.entryDate)) continue;
            await _syncAutoViradaMesFromLocation(
              scalesRef: scalesRef,
              sourceId: p.ref.id,
              loc: p.loc,
              colorHex: p.colorHex,
              labelComHorario: p.labelComHorario,
              abbreviation: p.abbreviation,
              entryDate: p.entryDate,
              rates: rates,
            );
            gerouViradaMes = true;
          }
        }

        if (widget.trocar) {
          await syncViradas();
        } else {
          unawaited(syncViradas().catchError((_) {}));
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
        final n = locs.length;
        final dCount = dias.length;
        String msg;
        if (widget.trocar && dCount == 1 && n == 1) {
          final loc = locs.first;
          final diaTroca = dias.first;
          double valorNovo = 0;
          if (loc.financialEnabled) {
            if (loc.paymentType == PaymentType.fixed) {
              valorNovo = (loc.baseValue + loc.bonus - loc.discount)
                  .clamp(0, double.infinity)
                  .toDouble();
            } else {
              valorNovo =
                  (_valorByKey[_keyForLoc(loc)]?['total'] ?? 0).toDouble();
            }
          }
          final carryDia = diaTroca.add(const Duration(days: 1));
          final viradaTxt = gerouViradaMes || _plantaoGeraViradaMes(loc, diaTroca)
              ? ' · Lançamento automático em ${DateFormat('dd/MM').format(carryDia)} (após 00:00).'
              : '';
          msg =
              'Plantão trocado em ${DateFormat('dd/MM').format(diaTroca)}: '
              '${ShiftLocation.fullNameWithSchedule(loc.name, loc.startTime, loc.endTime)}'
              '${loc.financialEnabled ? ' — ${CurrencyFormats.formatBRL(valorNovo)}' : ''}'
              '$viradaTxt';
        } else if (dCount == 1 && n == 1) {
          msg =
              '${ShiftLocation.fullNameWithSchedule(locs.first.name, locs.first.startTime, locs.first.endTime)} adicionado em ${DateFormat('dd/MM').format(dias.first)}';
        } else if (dCount == 1) {
          msg = '$n itens adicionados em ${DateFormat('dd/MM').format(dias.first)}';
        } else {
          msg =
              '$totalInclusoes lançamentos ($n tipo(s) × $dCount dia(s) em ${DateFormat('MMMM yyyy', 'pt_BR').format(dias.first)}).';
        }
        final offline =
            isConnectivityOffline(await Connectivity().checkConnectivity());
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(offline
                ? '$msg Guardado no aparelho; sincroniza quando houver internet.'
                : msg)));
        widget.onSalvar();
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().split('\n').first;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $msg')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _totalFinanceiroSelecionado() {
    var sum = 0.0;
    for (final k in _selectedKeys) {
      final loc = _findLocByKey(k);
      if (loc == null || !loc.financialEnabled) continue;
      final v = _valorByKey[k];
      if (v != null) sum += (v['total'] ?? 0).toDouble();
    }
    return sum;
  }

  /// Valor exibido à direita da linha quando o item está marcado.
  String? _valorTextoParaLinha(ShiftLocation loc) {
    final key = _keyForLoc(loc);
    if (!_selectedKeys.contains(key)) return null;
    if (!loc.financialEnabled) return 'Sem valor';
    final v = _valorByKey[key];
    if (v == null) return 'Calculando…';
    return CurrencyFormats.formatBRL(v['total'] ?? 0);
  }

  Future<void> _abrirListaPlantoesRecorrentes() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LocationsScreen(uid: _userDocId),
      ),
    );
    if (!mounted) return;
    widget.onSalvar();
    await _recarregarLocationsDoFirestore();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final w = mq.size.width;
    final hPad = w < 400 ? 16.0 : (w < 600 ? 18.0 : 22.0);
    final sumFooter = _totalFinanceiroSelecionado();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F9),
      resizeToAvoidBottomInset: scaffoldKeyboardResizeToAvoidBottomInset(),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: 'Retornar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context, false),
          style: IconButton.styleFrom(
            foregroundColor: Colors.white,
            minimumSize: const Size(48, 48),
          ),
        ),
        title: Text(
          widget.trocar ? 'Trocar plantão' : 'Escalas',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!widget.trocar)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Marque um ou vários plantões; o valor com financeiro ativo aparece na linha e no total. Toque em INSERIR para lançar.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade800, height: 1.35),
                      ),
                    ),
                  _premiumExpressoButton(
                    icon: Icons.calendar_today_rounded,
                    label: _labelBotaoDatas(),
                    titleFontSize: 16,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    gradient: const [
                      Color(0xFF5B21B6),
                      Color(0xFF7C3AED),
                      Color(0xFF9333EA),
                    ],
                    onTap: () async {
                      final res = await showMultiDateMonthPickerDialog(
                        context: context,
                        month: DateTime(_dayParaResumo.year, _dayParaResumo.month, 1),
                        initialSelected: _days,
                        maxSelection: widget.trocar ? 1 : null,
                      );
                      if (res != null && res.isNotEmpty) {
                        setState(() => _days = res.map(_normDay).toList());
                        await _refreshValoresSelecionados();
                      }
                    },
                  ),
                  if (!widget.trocar)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'No calendário: marque um dia ou vários no mês; os itens abaixo serão lançados em todas as datas selecionadas.',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.3),
                      ),
                    ),
                  if (!widget.trocar && widget.onPeriodoAutomatico != null) ...[
                    const SizedBox(height: 12),
                    _premiumExpressoButton(
                      icon: Icons.auto_awesome_rounded,
                      label: 'Período automático',
                      subtitle: 'Ordinárias · extras · compromissos',
                      titleFontSize: 15,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      gradient: const [
                        Color(0xFF5B21B6),
                        Color(0xFF7C3AED),
                        Color(0xFFD97706),
                      ],
                      onTap: widget.onPeriodoAutomatico!,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _premiumExpressoButton(
                        icon: Icons.bolt_rounded,
                        label: 'Plantão expresso',
                        subtitle: 'Com valor financeiro',
                        gradient: const [
                          Color(0xFFF97316),
                          Color(0xFFFFB648),
                        ],
                        onTap: () {
                          showLancamentoExpressoPlantaoSheet(
                            context: context,
                            uid: _userDocId,
                            day: _dayParaResumo,
                            days: widget.trocar ? null : _daysSorted,
                            initialFinanceiro: true,
                            initialEmployer: EmployerType.state,
                            onSalvar: () {
                              if (context.mounted) Navigator.of(context).pop(true);
                              widget.onSalvar();
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      _premiumExpressoButton(
                        icon: Icons.event_note_rounded,
                        label: 'Compromisso particular',
                        subtitle: 'Sem valor financeiro',
                        gradient: const [
                          Color(0xFF00897B),
                          Color(0xFF004D40),
                        ],
                        onTap: () {
                          showLancamentoExpressoPlantaoSheet(
                            context: context,
                            uid: _userDocId,
                            day: _dayParaResumo,
                            days: widget.trocar ? null : _daysSorted,
                            initialFinanceiro: false,
                            initialEmployer: EmployerType.state,
                            onSalvar: () {
                              if (context.mounted) Navigator.of(context).pop(true);
                              widget.onSalvar();
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      _premiumExpressoButton(
                        icon: Icons.playlist_add_check_rounded,
                        label: 'Lista de plantões recorrentes',
                        subtitle: 'Cadastre aqui',
                        gradient: const [
                          Color(0xFF5B21B6),
                          Color(0xFF7C3AED),
                          Color(0xFF9333EA),
                        ],
                        onTap: _abrirListaPlantoesRecorrentes,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (_locationsCache.isNotEmpty) ...[
                    Text(
                      'Filtrar por vínculo',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: Colors.grey.shade800),
                    ),
                    const SizedBox(height: 8),
                    EmployerVinculoChips.filterRow(
                      filter: _filtroVinculo,
                      onChanged: _setFiltroVinculo,
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (_locationsCache.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        children: [
                          Icon(Icons.event_note_rounded, size: 44, color: Colors.grey.shade400),
                          const SizedBox(height: 10),
                          Text(
                            'Nenhum plantão no pré-cadastro. Use «Lista de plantões recorrentes» acima para cadastrar. O lançamento expresso não grava no pré-cadastro.',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.35),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else if (_locationsFiltradas.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Column(
                        children: [
                          Icon(Icons.filter_alt_off_rounded, size: 40, color: Colors.grey.shade400),
                          const SizedBox(height: 10),
                          Text(
                            'Nenhum plantão com este vínculo. Escolha outro filtro ou cadastre em «Lista de plantões recorrentes».',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13.5, height: 1.35),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else
                    ..._locationsFiltradas.map((loc) => _LocationTile(
                          location: loc,
                          selected: _selectedKeys.contains(_keyForLoc(loc)),
                          multiSelect: !widget.trocar,
                          narrow: w < 400,
                          valorLinha: _valorTextoParaLinha(loc),
                          onTap: () => _onLocationTap(loc),
                        )),
                ],
              ),
            ),
          ),
          if (_selectedKeys.isNotEmpty)
            Material(
              elevation: 12,
              shadowColor: Colors.black38,
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Total selecionado (financeiro ativo)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                                if (_daysSorted.length > 1)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '${_daysSorted.length} dias no calendário — cada data usa horas/valor conforme o dia da semana.',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                        height: 1.25,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            CurrencyFormats.formatBRL(sumFooter),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                              color: Color(0xFF1A237E),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _loading ? null : _salvarNaEscala,
                        icon: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.task_alt_rounded),
                        label: Text(_loading
                            ? 'Salvando…'
                            : (widget.trocar ? 'TROCAR PLANTÃO' : 'INSERIR')),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _loading ? null : () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1A237E),
                            side: BorderSide(
                              color: const Color(0xFF1A237E).withValues(alpha: 0.45),
                              width: 1.5,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text(
                            'Cancelar',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LocationTile extends StatelessWidget {
  final ShiftLocation location;
  final bool selected;
  final bool multiSelect;
  final bool narrow;
  /// Valor por linha quando marcado (financeiro ou «Sem valor»).
  final String? valorLinha;
  final VoidCallback onTap;

  const _LocationTile({
    required this.location,
    required this.selected,
    required this.multiSelect,
    this.narrow = false,
    this.valorLinha,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: location.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: location.color.withValues(alpha: 0.95)),
        boxShadow: [
          BoxShadow(
            color: location.color.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? location.color : Colors.transparent, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: narrow ? 2 : 4),
          child: ListTile(
            dense: narrow,
            contentPadding: EdgeInsets.symmetric(horizontal: narrow ? 8 : 12),
            leading: multiSelect
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 40,
                        child: Checkbox(
                          value: selected,
                          onChanged: (_) => onTap(),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          fillColor: WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.selected)) return location.color;
                            return null;
                          }),
                        ),
                      ),
                      badge,
                    ],
                  )
                : badge,
            title: Text(
              location.name,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: narrow ? 14 : 15),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${location.startTime} – ${location.endTime}${location.financialEnabled ? '' : ' · compromisso'}',
              style: TextStyle(fontSize: narrow ? 11 : 12, color: Colors.grey.shade600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: multiSelect && valorLinha != null
                ? Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          valorLinha!,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: narrow ? 11.5 : 13,
                            color: location.financialEnabled ? const Color(0xFF1A237E) : Colors.grey.shade700,
                          ),
                          textAlign: TextAlign.end,
                        ),
                      ],
                    ),
                  )
                : (!multiSelect && selected ? Icon(Icons.check_circle_rounded, color: location.color) : null),
          ),
        ),
      ),
    );
  }
}

