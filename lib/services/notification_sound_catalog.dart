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
    description: 'Triplo pulso + glissando — audiência crítica.',
  ),
];

/// Devolve o item pelo `id` (null se removido do catálogo).
NotificationSoundCatalogItem? findCatalogItemById(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final i in kNotificationSoundCatalog) {
    if (i.id == id) return i;
  }
  return null;
}
