/// «Despertar» POR ITEM — compromisso, audiência, escala/plantão e plantão
/// recorrente (pré-cadastro em `users/{uid}/locations`).
///
/// Gravado no próprio documento do item:
///
/// ```
/// despertar: { ativo: bool, modo: 'som' | 'vibrar', som: '<id do catálogo>' | '' }
/// ```
///
/// PADRÃO DESLIGADO: o ITEM decide se desperta. O servidor
/// (`functions/agenda_despertar_item.js`): ligado → o aviso chega como
/// despertador (Adiar/Encerrar + repetições) com o toque escolhido ou só
/// vibrando; desligado OU campo ausente (itens antigos, bot do Telegram) →
/// aviso normal, mesmo com o despertador do módulo ligado. O módulo
/// (Notificações › Despertador e sons) define só COMO toca: vezes/intervalo
/// (sem escolha: 3 × 3 min) e o toque padrão («Padrão do despertador»).
///
/// Plantão lançado de um pré-cadastro recorrente sem o campo herda o do
/// pré-cadastro no servidor.
class DespertarItem {
  const DespertarItem({
    this.ativo = false,
    this.modo = modoSom,
    this.som = '',
  });

  static const String campo = 'despertar';
  static const String modoSom = 'som';
  static const String modoVibrar = 'vibrar';

  /// Nasce desligado.
  static const DespertarItem desligado = DespertarItem();

  final bool ativo;

  /// `som` | `vibrar`.
  final String modo;

  /// Id do catálogo (`notification_sound_catalog.dart`); vazio = toque longo
  /// do módulo ou o padrão de despertar.
  final String som;

  bool get soVibrar => modo == modoVibrar;

  static final RegExp _reSom = RegExp(r'^[a-z0-9_]{2,40}$');

  /// Lê do documento; `null` quando o item não tem o campo (= desligado).
  static DespertarItem? fromData(Map<String, dynamic>? data) {
    final raw = data?[campo];
    if (raw is! Map || raw['ativo'] is! bool) return null;
    final modo = raw['modo'] == modoVibrar ? modoVibrar : modoSom;
    final som = (raw['som'] ?? '').toString().trim();
    return DespertarItem(
      ativo: raw['ativo'] as bool,
      modo: modo,
      som: _reSom.hasMatch(som) ? som : '',
    );
  }

  /// Valor do formulário: o do item, senão desligado.
  static DespertarItem doDocumento(Map<String, dynamic>? data) =>
      fromData(data) ?? desligado;

  DespertarItem copyWith({bool? ativo, String? modo, String? som}) =>
      DespertarItem(
        ativo: ativo ?? this.ativo,
        modo: modo ?? this.modo,
        som: som ?? this.som,
      );

  /// Sempre as 3 chaves: com `set(merge)` um mapa é mesclado campo a campo,
  /// então omitir `som` deixaria o toque antigo lá.
  Map<String, dynamic> toMap() => {
        'ativo': ativo,
        'modo': modo == modoVibrar ? modoVibrar : modoSom,
        'som': som,
      };

  /// `{ despertar: {...} }` para espalhar no payload de gravação.
  Map<String, dynamic> get campos => {campo: toMap()};

  @override
  bool operator ==(Object other) =>
      other is DespertarItem &&
      other.ativo == ativo &&
      other.modo == modo &&
      other.som == som;

  @override
  int get hashCode => Object.hash(ativo, modo, som);
}
