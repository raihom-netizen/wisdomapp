import 'package:shared_preferences/shared_preferences.dart';

/// Preferências de notificações apenas em dispositivo (local).
/// Usado em Configurações: Financeiro, Cursos e antecedência de lembretes.
class LocalNotificationPreferences {
  static const _keyFinanceiro = 'notif_local_financeiro';
  static const _keyEscalas = 'notif_local_escalas';
  static const _keyCompromissosAudiencias = 'notif_local_compromissos_audiencias';
  static const _keyAntecedenciaMinutos = 'notif_local_antecedencia_minutos';
  static const _keyAntecedenciaPersonalizado = 'notif_local_antecedencia_personalizado';
  static const _keyAntecedenciaList = 'notif_local_antecedencia_list';
  static const _keyCursos = 'notif_local_cursos';
  static const _keyShowAsPopupOnPhone = 'notif_show_as_popup_on_phone';

  static const int k1Hora = 60;
  static const int k1Dia = 1440;
  static const int k30Min = 30;
  static const int k15Min = 15;

  /// Padrão oficial do sistema: **1 dia + 60 min** (30, 15 e personalizado desligados).
  static const List<int> kDefaultLeads = [k1Dia, k1Hora];

  /// Fallback quando a lista salva está vazia ou inválida.
  static List<int> effectiveLeads(Iterable<int>? raw) {
    final parsed = (raw ?? const <int>[])
        .where((m) => m > 0)
        .toSet()
        .toList()
      ..sort();
    if (parsed.isNotEmpty) return parsed;
    return List<int>.from(kDefaultLeads);
  }

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  /// Lê todas as prefs locais num único acesso (evita vários `getInstance` na abertura).
  Future<LocalNotificationPrefsBundle> loadBundle() async {
    final p = await _prefs;
    final rawList = p.getString(_keyAntecedenciaList);
    List<int> leads;
    if (rawList != null && rawList.isNotEmpty) {
      leads = rawList
          .split(',')
          .map((e) => int.tryParse(e.trim()) ?? 0)
          .where((e) => e > 0)
          .toSet()
          .toList()
        ..sort();
      if (leads.isEmpty) {
        leads = List<int>.from(kDefaultLeads);
      }
    } else {
      final v = p.getInt(_keyAntecedenciaMinutos);
      if (v != null && v > 0) {
        leads = [v];
      } else {
        final custom = p.getInt(_keyAntecedenciaPersonalizado);
        if (custom != null && custom > 0) {
          leads = [custom];
        } else {
          leads = List<int>.from(kDefaultLeads);
        }
      }
    }
    return LocalNotificationPrefsBundle(
      showAsPopupOnPhone: p.getBool(_keyShowAsPopupOnPhone) ?? true,
      financeiro: p.getBool(_keyFinanceiro) ?? true,
      cursos: p.getBool(_keyCursos) ?? true,
      escalas: p.getBool(_keyEscalas) ?? true,
      compromissosAudiencias:
          p.getBool(_keyCompromissosAudiencias) ?? true,
      antecedenciaMinutosList: leads,
      personalizadoValor: p.getInt(_keyAntecedenciaPersonalizado),
    );
  }

  /// Mostrar notificações em pop-up no celular (heads-up). Padrão true.
  Future<bool> get showAsPopupOnPhone async => (await _prefs).getBool(_keyShowAsPopupOnPhone) ?? true;
  Future<void> setShowAsPopupOnPhone(bool value) async {
    await (await _prefs).setBool(_keyShowAsPopupOnPhone, value);
  }

  Future<bool> get financeiro async => (await _prefs).getBool(_keyFinanceiro) ?? true;
  Future<bool> get cursos async => (await _prefs).getBool(_keyCursos) ?? true;
  Future<bool> get escalas async => (await _prefs).getBool(_keyEscalas) ?? true;
  Future<bool> get compromissosAudiencias async => (await _prefs).getBool(_keyCompromissosAudiencias) ?? true;

  /// Lista de minutos de antecedência selecionados (ex.: [60, 1440, 90]). Pode marcar 60 min, 1 dia e personalizado ao mesmo tempo.
  ///
  /// Padrão (quando usuário nunca configurou): [kDefaultLeads] = **1 dia + 60 min**.
  Future<List<int>> get antecedenciaMinutosList async {
    final p = await _prefs;
    final raw = p.getString(_keyAntecedenciaList);
    if (raw != null && raw.isNotEmpty) {
      final list = raw
          .split(',')
          .map((e) => int.tryParse(e.trim()) ?? 0)
          .where((e) => e > 0)
          .toSet()
          .toList()
        ..sort();
      if (list.isNotEmpty) return list;
    }
    final v = p.getInt(_keyAntecedenciaMinutos);
    if (v != null && v > 0) return [v];
    final custom = p.getInt(_keyAntecedenciaPersonalizado);
    if (custom != null && custom > 0) return [custom];
    return List<int>.from(kDefaultLeads);
  }

  /// Minutos de antecedência efetivos (primeiro da lista, compatibilidade).
  Future<int> get antecedenciaMinutos async {
    final list = await antecedenciaMinutosList;
    return list.isNotEmpty ? list.first : k1Hora;
  }

  Future<int?> get antecedenciaPersonalizadoValor async {
    final p = await _prefs;
    return p.getInt(_keyAntecedenciaPersonalizado);
  }

  Future<void> setFinanceiro(bool value) async {
    (await _prefs).setBool(_keyFinanceiro, value);
  }

  Future<void> setCursos(bool value) async {
    (await _prefs).setBool(_keyCursos, value);
  }

  Future<void> setEscalas(bool value) async {
    (await _prefs).setBool(_keyEscalas, value);
  }

  Future<void> setCompromissosAudiencias(bool value) async {
    (await _prefs).setBool(_keyCompromissosAudiencias, value);
  }

  /// Salva a lista de antecedências (ex.: [60, 1440] ou [60, 1440, 90] com personalizado).
  Future<void> setAntecedenciaList(List<int> minutesList, {int? personalizadoMinutos}) async {
    final p = await _prefs;
    final list = minutesList.where((m) => m > 0).toSet().toList()..sort();
    await p.setString(_keyAntecedenciaList, list.join(','));
    if (personalizadoMinutos != null && personalizadoMinutos > 0) {
      await p.setInt(_keyAntecedenciaPersonalizado, personalizadoMinutos);
    }
  }

  Future<void> setAntecedenciaPreset(int minutes) async {
    final p = await _prefs;
    await p.setInt(_keyAntecedenciaMinutos, minutes);
  }

  Future<void> setAntecedenciaPersonalizado(int minutes) async {
    final p = await _prefs;
    await p.setInt(_keyAntecedenciaMinutos, -1);
    await p.setInt(_keyAntecedenciaPersonalizado, minutes);
  }
}

/// Snapshot das prefs locais de notificação (leitura única).
class LocalNotificationPrefsBundle {
  const LocalNotificationPrefsBundle({
    required this.showAsPopupOnPhone,
    required this.financeiro,
    required this.cursos,
    required this.escalas,
    required this.compromissosAudiencias,
    required this.antecedenciaMinutosList,
    this.personalizadoValor,
  });

  final bool showAsPopupOnPhone;
  final bool financeiro;
  final bool cursos;
  final bool escalas;
  final bool compromissosAudiencias;
  final List<int> antecedenciaMinutosList;
  final int? personalizadoValor;
}
