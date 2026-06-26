import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/controle_total_config.dart';
import '../models/scale_rates.dart';
import '../utils/firestore_user_doc_id.dart';
import 'controle_total_config_service.dart';
import 'scale_rates_cache_notifier.dart';
import 'clt_labor_config_service.dart';
import 'scale_rates_period_service.dart';
import 'user_scale_rates_period_service.dart';

/// Valores de hora extra (diurno/noturno por dia): padrão AC4 GO, editável no admin e pelo usuário.
/// Use [getEffectiveRates] na Calculadora e inclusão de plantão (respeita `hoursSource`).
class ScaleRatesService {
  ScaleRatesService._();
  factory ScaleRatesService() => _instance;
  static final ScaleRatesService _instance = ScaleRatesService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final Map<String, ScaleRates> _memoryByKey = {};
  final Map<String, ControleTotalConfig> _configMemoryByUid = {};

  DocumentReference<Map<String, dynamic>> _userRatesDoc(String uid) => _db
      .collection('users')
      .doc(firestoreUserDocIdForAppShell(uid))
      .collection('settings')
      .doc('scale_rates');

  DocumentReference<Map<String, dynamic>> get _globalRatesDoc =>
      _db.collection('config').doc('scale_rates');

  static String _memoryKey(String uid, ControleTotalConfig config) =>
      '${firestoreUserDocIdForAppShell(uid)}|${config.hoursSource}';

  /// Limpa cache em memória. [notify] = false evita recálculo em telas inativas (ex.: reconexão).
  void invalidateMemory([String? uid, bool notify = true]) {
    if (uid == null || uid.isEmpty) {
      _memoryByKey.clear();
      _configMemoryByUid.clear();
    } else {
      final docId = firestoreUserDocIdForAppShell(uid);
      final prefix = '$docId|';
      _memoryByKey.removeWhere((k, _) => k.startsWith(prefix));
      _configMemoryByUid.remove(docId);
    }
    if (notify) {
      ScaleRatesCacheNotifier.instance.notifyRatesChanged(uid);
    }
    CltLaborConfigService().invalidate(uid);
  }

  Future<ControleTotalConfig> _configForUid(String uid) async {
    final docId = firestoreUserDocIdForAppShell(uid);
    final hit = _configMemoryByUid[docId];
    if (hit != null) return hit;
    final config = await ControleTotalConfigService().getConfigCacheFirst(uid);
    _configMemoryByUid[docId] = config;
    return config;
  }

  /// Preferência pelo cache local (rápido sem rede); se não existir doc em cache, tenta rede+cache.
  Future<DocumentSnapshot<Map<String, dynamic>>> _getDocCacheFirst(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      final cached = await ref.get(const GetOptions(source: Source.cache));
      if (cached.exists) return cached;
    } catch (_) {}
    try {
      return await ref.get();
    } catch (_) {
      return await ref.get(const GetOptions(source: Source.cache));
    }
  }

  Future<ScaleRates?> _ratesFromRef(DocumentReference<Map<String, dynamic>> ref) async {
    try {
      final snap = await _getDocCacheFirst(ref);
      if (snap.exists && snap.data() != null) {
        return ScaleRates.fromMap(snap.data());
      }
    } catch (_) {}
    return null;
  }

  /// Lê as taxas para o usuário (ou padrão do sistema).
  /// Para "Padrão Particular": usa personalização do usuário se existir, senão global.
  /// Offline: usa cache persistente do Firestore; sem cache, AC4 padrão embutido no app.
  Future<ScaleRates> getRates({String? uid}) async {
    if (uid != null && uid.isNotEmpty) {
      final user = await _ratesFromRef(_userRatesDoc(uid));
      if (user != null) return user;
    }
    final global = await _ratesFromRef(_globalRatesDoc);
    if (global != null) return global;
    return ScaleRates.defaultRates;
  }

  /// Taxas conforme Configurações (Goiás global vs personalizado do usuário).
  Future<ScaleRates> getEffectiveRates(String uid) async {
    if (uid.isEmpty) return ScaleRates.defaultRates;
    final config = await _configForUid(uid);
    return getEffectiveRatesForConfig(uid, config);
  }

  Future<ScaleRates> getEffectiveRatesForConfig(
    String uid,
    ControleTotalConfig config,
  ) async {
    final key = _memoryKey(uid, config);
    final hit = _memoryByKey[key];
    if (hit != null) return hit;

    final rates = config.useGlobalGoias
        ? await getGlobalRatesOnly()
        : config.useClt
            ? (await CltLaborConfigService().getConfig(uid)).toScaleRates()
            : await getRates(uid: uid);
    _memoryByKey[key] = rates;
    return rates;
  }

  /// Apenas tabela global (Estado de Goiás / admin). Ignora personalização do usuário.
  Future<ScaleRates> getGlobalRatesOnly() async {
    await ScaleRatesPeriodService().ensureLoaded();
    return ScaleRatesPeriodService().currentDisplayRates();
  }

  /// Usuário no padrão Goiás global?
  Future<bool> usesGlobalGoiasRates(String uid) async {
    if (uid.isEmpty) return true;
    final config = await _configForUid(uid);
    return config.useGlobalGoias;
  }

  /// Tabela para exibição/cadastro conforme a **data civil do serviço** (retroativo ok).
  Future<ScaleRates> getRatesForServiceDay(String uid, DateTime serviceDay) async {
    await ScaleRatesPeriodService().ensureLoaded();
    if (uid.isEmpty) {
      return ScaleRatesPeriodService().ratesForServiceDay(serviceDay);
    }
    final config = await _configForUid(uid);
    if (config.useGlobalGoias) {
      return ScaleRatesPeriodService().ratesForServiceDay(serviceDay);
    }
    if (config.useClt) {
      return (await CltLaborConfigService().getConfig(uid)).toScaleRates();
    }
    final userPeriods = await UserScaleRatesPeriodService().getPeriods(uid);
    if (userPeriods.isNotEmpty) {
      return UserScaleRatesPeriodService().ratesForServiceDay(uid, serviceDay);
    }
    return getEffectiveRatesForConfig(uid, config);
  }

  /// Cálculo de plantão respeitando histórico de períodos GO (global) ou tabela pessoal.
  Future<Map<String, double>> computeShiftForUid({
    required String uid,
    required DateTime start,
    required DateTime end,
    DateTime? entryDate,
  }) async {
    await ScaleRatesPeriodService().ensureLoaded();
    final periodSvc = ScaleRatesPeriodService();
    if (uid.isEmpty) {
      if (entryDate != null && ScaleRates.isLastDayOfMonth(entryDate)) {
        return periodSvc.computeShiftMainEntryLastDayOfMonth(
          start: start,
          end: end,
          entryDate: entryDate,
        );
      }
      return periodSvc.computeShift(start: start, end: end);
    }
    final config = await _configForUid(uid);
    if (config.useGlobalGoias) {
      if (entryDate != null && ScaleRates.isLastDayOfMonth(entryDate)) {
        return periodSvc.computeShiftMainEntryLastDayOfMonth(
          start: start,
          end: end,
          entryDate: entryDate,
        );
      }
      return periodSvc.computeShift(start: start, end: end);
    }
    final rates = config.useClt
        ? (await CltLaborConfigService().getConfig(uid)).toScaleRates()
        : await _ratesForPersonalShift(uid, config, serviceDay: start);
    if (entryDate != null && ScaleRates.isLastDayOfMonth(entryDate)) {
      return rates.computeShiftMainEntryLastDayOfMonth(
        start: start,
        end: end,
        entryDate: entryDate,
      );
    }
    return rates.computeShift(start: start, end: end);
  }

  Future<ScaleRates> _ratesForPersonalShift(
    String uid,
    ControleTotalConfig config, {
    required DateTime serviceDay,
  }) async {
    final userPeriods = await UserScaleRatesPeriodService().getPeriods(uid);
    if (userPeriods.isNotEmpty) {
      return UserScaleRatesPeriodService().ratesForServiceDay(uid, serviceDay);
    }
    return getEffectiveRatesForConfig(uid, config);
  }

  Stream<ScaleRates> watchGlobalRates() {
    return ScaleRatesPeriodService().watchPeriods().map(
          (_) => ScaleRatesPeriodService().currentDisplayRates(),
        );
  }

  Future<void> setGlobalRates(ScaleRates rates) async {
    final map = rates.toMap();
    map['updatedAt'] = FieldValue.serverTimestamp();
    await _globalRatesDoc.set(map, SetOptions(merge: true));
    invalidateMemory();
  }

  Future<void> ensureGlobalDefaults() async {
    await ScaleRatesPeriodService().seedBootstrapIfEmpty();
  }

  Future<void> setUserRates(String uid, ScaleRates rates) async {
    if (uid.isEmpty) return;
    final map = rates.toMap();
    map['updatedAt'] = FieldValue.serverTimestamp();
    await _userRatesDoc(uid).set(map, SetOptions(merge: true));
    invalidateMemory(uid);
  }
}
