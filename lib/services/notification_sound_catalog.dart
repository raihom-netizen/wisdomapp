/// Banco offline de áudios de notificação que vem **embutido** no app
/// (estilo WhatsApp: o usuário escolhe entre vários toques pré-instalados).
///
/// Os arquivos ficam em `flutter_app/assets/sounds/notifications/` e são
/// carregados via `AssetSource(...)` (sem internet, sem permissão extra).
///
/// **Como adicionar / substituir tom**
///   1. Coloque o arquivo `.wav` (recomendado), `.mp3` ou `.m4a` em
///      `assets/sounds/notifications/` (já está listado no `pubspec.yaml`).
///   2. Inclua uma entrada nova em [kNotificationSoundCatalog] com `id`
///      único, `assetPath` apontando para o arquivo e `displayName` curto.
///   3. Rode `flutter pub get` e o tom passa a aparecer em
///      «Preferências → Sons das notificações» e no formulário de cada
///      evento (Escala, Compromisso, Audiência).
///
/// **Importante:** todos os toques são gerados em ~1.0–2.3 s (padrão *premium*)
/// com harmônicas, envelopes ADSR e reverb sintético — quando o usuário dá play
/// no preview, ouve um trecho longo o suficiente para escolher com calma.
class NotificationSoundCatalogItem {
  const NotificationSoundCatalogItem({
    required this.id,
    required this.assetPath,
    required this.displayName,
    this.description,
    this.longo = false,
    this.extraLongo = false,
    this.duracaoSeg,
  });

  /// Identificador estável guardado em `users/{uid}/...` e no payload da
  /// notificação. **Não renomear** depois que estiver em produção, pois
  /// quebra escolhas antigas dos usuários.
  final String id;

  /// Caminho do asset (`assets/sounds/notifications/<file>.wav`).
  final String assetPath;

  /// Nome curto exibido na UI (chip/lista).
  final String displayName;

  /// Linha auxiliar opcional (ex.: «pim curto», «sino triplo»).
  final String? description;

  /// Toque longo (5–10 s) do despertador — aparece em grupo próprio.
  final bool longo;

  /// Toque EXTRA longo (~25 s, abaixo do limite de 30 s do iPhone). Também é
  /// [longo] (canal «Despertador»), mas aparece num grupo próprio.
  final bool extraLongo;

  /// Duração aproximada, mostrada no card («8 s»).
  final int? duracaoSeg;
}

/// Catálogo fixo. Reflete os arquivos em
/// `flutter_app/assets/sounds/notifications/` (`.wav` gerados por
/// `dart run tool/generate_notification_wavs.dart` no pacote Flutter).
const List<NotificationSoundCatalogItem> kNotificationSoundCatalog = [
  NotificationSoundCatalogItem(
    id: 'pop_curto',
    assetPath: 'assets/sounds/notifications/pop_curto.wav',
    displayName: 'Bolha moderna',
    description: 'Pop suave com eco — agradável e rápido.',
  ),
  NotificationSoundCatalogItem(
    id: 'aviso_suave',
    assetPath: 'assets/sounds/notifications/aviso_suave.wav',
    displayName: 'Aviso premium',
    description: 'Acorde C/E sustentado, leve e elegante.',
  ),
  NotificationSoundCatalogItem(
    id: 'sino_curto',
    assetPath: 'assets/sounds/notifications/sino_curto.wav',
    displayName: 'Cristal premium',
    description: 'Sino C6 com longa cauda harmônica.',
  ),
  NotificationSoundCatalogItem(
    id: 'sino_triplo',
    assetPath: 'assets/sounds/notifications/sino_triplo.wav',
    displayName: 'Sino triplo',
    description: 'Três sinos C-E-G em cascata.',
  ),
  NotificationSoundCatalogItem(
    id: 'alerta',
    assetPath: 'assets/sounds/notifications/alerta.wav',
    displayName: 'Alerta moderno',
    description: 'Glissandos descendentes — prioridade alta.',
  ),
  NotificationSoundCatalogItem(
    id: 'beep_classico',
    assetPath: 'assets/sounds/notifications/beep_classico.wav',
    displayName: 'Trio digital',
    description: 'Três beeps modernos em sequência.',
  ),
  NotificationSoundCatalogItem(
    id: 'duo_curto',
    assetPath: 'assets/sounds/notifications/duo_curto.wav',
    displayName: 'Arpejo curto',
    description: 'Dois tons ascendentes (C → G).',
  ),
  NotificationSoundCatalogItem(
    id: 'plim',
    assetPath: 'assets/sounds/notifications/plim.wav',
    displayName: 'Plim brilhante',
    description: 'Toque A6 cristalino com decay rápido.',
  ),
  NotificationSoundCatalogItem(
    id: 'whatsapp_like',
    assetPath: 'assets/sounds/notifications/whatsapp_like.wav',
    displayName: 'Notificação moderna',
    description: 'Duo curto B-E com brilho.',
  ),
  NotificationSoundCatalogItem(
    id: 'sino_grave',
    assetPath: 'assets/sounds/notifications/sino_grave.wav',
    displayName: 'Sino grave premium',
    description: 'G3 com reverb longo — discreto.',
  ),
  NotificationSoundCatalogItem(
    id: 'chime',
    assetPath: 'assets/sounds/notifications/chime.wav',
    displayName: 'Chime Cmaj',
    description: 'Arpejo C5-E5-G5-C6 ascendente.',
  ),
  NotificationSoundCatalogItem(
    id: 'urgente',
    assetPath: 'assets/sounds/notifications/urgente.wav',
    displayName: 'Urgente premium',
    description: 'Triplo pulso + glissando — alerta crítico.',
  ),
  // ── Despertador: toques longos (5–10 s), gerados pelo mesmo script ──
  NotificationSoundCatalogItem(
    id: 'longo_despertar',
    assetPath: 'assets/sounds/notifications/longo_despertar.wav',
    displayName: 'Despertar suave',
    description: 'Arpejo de marimba que cresce aos poucos.',
    longo: true,
    duracaoSeg: 8,
  ),
  NotificationSoundCatalogItem(
    id: 'longo_alarme_digital',
    assetPath: 'assets/sounds/notifications/longo_alarme_digital.wav',
    displayName: 'Alarme digital',
    description: 'Bipes de despertador de cabeceira.',
    longo: true,
    duracaoSeg: 6,
  ),
  NotificationSoundCatalogItem(
    id: 'longo_carrilhao',
    assetPath: 'assets/sounds/notifications/longo_carrilhao.wav',
    displayName: 'Carrilhão',
    description: 'Melodia de relógio de torre em sinos.',
    longo: true,
    duracaoSeg: 9,
  ),
  NotificationSoundCatalogItem(
    id: 'longo_sirene',
    assetPath: 'assets/sounds/notifications/longo_sirene.wav',
    displayName: 'Sirene suave',
    description: 'Sobe e desce sem assustar.',
    longo: true,
    duracaoSeg: 6,
  ),
  NotificationSoundCatalogItem(
    id: 'longo_radar',
    assetPath: 'assets/sounds/notifications/longo_radar.wav',
    displayName: 'Radar',
    description: 'Pings agudos com eco.',
    longo: true,
    duracaoSeg: 6,
  ),
  NotificationSoundCatalogItem(
    id: 'longo_harpa',
    assetPath: 'assets/sounds/notifications/longo_harpa.wav',
    displayName: 'Harpa',
    description: 'Arpejo de duas oitavas com acorde final.',
    longo: true,
    duracaoSeg: 7,
  ),
  NotificationSoundCatalogItem(
    id: 'longo_urgente',
    assetPath: 'assets/sounds/notifications/longo_urgente.wav',
    displayName: 'Urgente contínuo',
    description: 'Pulsos triplos — para não perder a hora.',
    longo: true,
    duracaoSeg: 5,
  ),
  NotificationSoundCatalogItem(
    id: 'longo_melodia',
    assetPath: 'assets/sounds/notifications/longo_melodia.wav',
    displayName: 'Melodia da manhã',
    description: 'Melodia leve sobre acorde de fundo.',
    longo: true,
    duracaoSeg: 10,
  ),
  NotificationSoundCatalogItem(
    id: 'longo_toque_classico',
    assetPath: 'assets/sounds/notifications/longo_toque_classico.wav',
    displayName: 'Toque clássico',
    description: 'Telefone fixo tocando.',
    longo: true,
    duracaoSeg: 6,
  ),
  NotificationSoundCatalogItem(
    id: 'extra_despertar_crescente',
    assetPath: 'assets/sounds/notifications/extra_despertar_crescente.wav',
    displayName: 'Despertar crescente',
    description: 'Vai ficando mais alto e mais rápido.',
    longo: true,
    extraLongo: true,
    duracaoSeg: 25,
  ),
  NotificationSoundCatalogItem(
    id: 'extra_alarme_digital',
    assetPath: 'assets/sounds/notifications/extra_alarme_digital.wav',
    displayName: 'Alarme digital longo',
    description: 'Bipes de cabeceira sem parar.',
    longo: true,
    extraLongo: true,
    duracaoSeg: 25,
  ),
  NotificationSoundCatalogItem(
    id: 'extra_sirene',
    assetPath: 'assets/sounds/notifications/extra_sirene.wav',
    displayName: 'Sirene longa',
    description: 'Sobe e desce, sem ser estridente.',
    longo: true,
    extraLongo: true,
    duracaoSeg: 25,
  ),
  NotificationSoundCatalogItem(
    id: 'extra_toque_classico',
    assetPath: 'assets/sounds/notifications/extra_toque_classico.wav',
    displayName: 'Telefone tocando',
    description: 'Toque de telefone fixo, 8 vezes.',
    longo: true,
    extraLongo: true,
    duracaoSeg: 24,
  ),
  NotificationSoundCatalogItem(
    id: 'extra_carrilhao',
    assetPath: 'assets/sounds/notifications/extra_carrilhao.wav',
    displayName: 'Carrilhão longo',
    description: 'Relógio de torre, três vezes.',
    longo: true,
    extraLongo: true,
    duracaoSeg: 25,
  ),
  NotificationSoundCatalogItem(
    id: 'extra_urgente',
    assetPath: 'assets/sounds/notifications/extra_urgente.wav',
    displayName: 'Urgente longo',
    description: 'Rajadas de dois tons, para não perder.',
    longo: true,
    extraLongo: true,
    duracaoSeg: 25,
  ),
];

/// Toques curtos (notificação comum).
List<NotificationSoundCatalogItem> get kToquesCurtos =>
    kNotificationSoundCatalog.where((i) => !i.longo).toList();

/// Toques longos do despertador (5–10 s).
List<NotificationSoundCatalogItem> get kToquesLongos =>
    kNotificationSoundCatalog.where((i) => i.longo && !i.extraLongo).toList();

/// Toques extra longos do despertador (~25 s).
List<NotificationSoundCatalogItem> get kToquesExtraLongos =>
    kNotificationSoundCatalog.where((i) => i.extraLongo).toList();

/// Devolve o item pelo `id` (null se removido do catálogo).
NotificationSoundCatalogItem? findCatalogItemById(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final i in kNotificationSoundCatalog) {
    if (i.id == id) return i;
  }
  return null;
}
