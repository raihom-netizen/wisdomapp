/// Configurações do Controle Total por usuário: padrão de horas, tipo de servidor, adicionais (empresa), teto mensal.
/// Configuração global do app é do Estado de Goiás (AC4); o usuário pode padronizar os dele ou manter Goiás.
class ControleTotalConfig {
  /// 'global_goias' = usar valores do Estado (Goiás) | 'personal' = usar meus valores
  final String hoursSource;

  /// 'estadual' | 'municipal' | 'privado' (empresa)
  final String serverType;

  /// Adicional em % sobre o valor calculado (ex: 10 = 10%). Para empresa/privado.
  final double companyBonusPercent;

  /// Adicional fixo por hora (R$/h) para empresa/privado.
  final double companyBonusFixedPerHour;

  /// Teto de horas mensais para previsões e alertas (ex.: 192 para padrão GO). Qualquer usuário pode configurar.
  final double tetoHorasMensal;

  const ControleTotalConfig({
    this.hoursSource = 'global_goias',
    this.serverType = 'estadual',
    this.companyBonusPercent = 0,
    this.companyBonusFixedPerHour = 0,
    this.tetoHorasMensal = 192,
  });

  /// Valor padrão do teto (Estado de Goiás / Município).
  static const double tetoHorasMensalPadrao = 192;

  static const String hoursSourceGlobalGoias = 'global_goias';
  static const String hoursSourcePersonal = 'personal';
  static const String hoursSourceClt = 'clt';

  static const String serverTypeEstadual = 'estadual';
  static const String serverTypeMunicipal = 'municipal';
  static const String serverTypePrivado = 'privado';

  bool get useGlobalGoias => hoursSource == hoursSourceGlobalGoias;
  bool get usePersonalRates => hoursSource == hoursSourcePersonal;
  bool get useClt => hoursSource == hoursSourceClt;
  bool get isEmpresa => serverType == serverTypePrivado;

  Map<String, dynamic> toMap() => {
        'hoursSource': hoursSource,
        'serverType': serverType,
        'companyBonusPercent': companyBonusPercent,
        'companyBonusFixedPerHour': companyBonusFixedPerHour,
        'tetoHorasMensal': tetoHorasMensal,
      };

  static ControleTotalConfig fromMap(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return const ControleTotalConfig();
    return ControleTotalConfig(
      hoursSource: _str(data['hoursSource'], hoursSourceGlobalGoias),
      serverType: _str(data['serverType'], serverTypeEstadual),
      companyBonusPercent: _double(data['companyBonusPercent'], 0),
      companyBonusFixedPerHour: _double(data['companyBonusFixedPerHour'], 0),
      tetoHorasMensal: _double(data['tetoHorasMensal'], tetoHorasMensalPadrao),
    );
  }

  static String _str(dynamic v, String def) =>
      (v != null && v.toString().trim().isNotEmpty) ? v.toString().trim() : def;

  static double _double(dynamic v, double def) {
    if (v == null) return def;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? def;
  }

  ControleTotalConfig copyWith({
    String? hoursSource,
    String? serverType,
    double? companyBonusPercent,
    double? companyBonusFixedPerHour,
    double? tetoHorasMensal,
  }) =>
      ControleTotalConfig(
        hoursSource: hoursSource ?? this.hoursSource,
        serverType: serverType ?? this.serverType,
        companyBonusPercent: companyBonusPercent ?? this.companyBonusPercent,
        companyBonusFixedPerHour: companyBonusFixedPerHour ?? this.companyBonusFixedPerHour,
        tetoHorasMensal: tetoHorasMensal ?? this.tetoHorasMensal,
      );

  /// Aplica adicionais/bônus ao valor base (para empresa/privado).
  double applyBonus(double baseValue, double totalHours) {
    if (!isEmpresa) return baseValue;
    var v = baseValue;
    if (companyBonusPercent > 0) v += v * (companyBonusPercent / 100);
    if (companyBonusFixedPerHour > 0) v += companyBonusFixedPerHour * totalHours;
    return v;
  }
}
