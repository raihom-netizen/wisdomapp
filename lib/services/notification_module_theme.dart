/// Tema visual unificado por módulo — push local, FCM foreground e paridade com Cloud Functions.
class NotificationModuleTheme {
  const NotificationModuleTheme({
    required this.kind,
    required this.label,
    required this.emoji,
    required this.channelId,
    required this.channelName,
    required this.channelDescription,
    required this.colorArgb,
    required this.threadId,
    this.bannerAsset,
    this.webBannerPath,
  });

  final String kind;
  final String label;

  /// Emoji no título/canal — padrão bancário (iOS + Web; Android canal).
  final String emoji;
  final String channelId;
  final String channelName;
  final String channelDescription;
  final int colorArgb;
  final String threadId;

  /// Asset Flutter (rich push local Android).
  final String? bannerAsset;

  /// Caminho no hosting (`/icons/push-banner-*.png`).
  final String? webBannerPath;

  static String normalizeKind(String? raw) {
    final k = (raw ?? 'escala').toLowerCase().trim();
    if (k == 'audiencia' ||
        k == 'compromisso' ||
        k == 'financeiro' ||
        k == 'folga' ||
        k == 'escala') {
      return k;
    }
    return 'escala';
  }

  /// Servidor pode enviar `category` ou `channelKind` (paridade manual bancário).
  static String resolveKindFromData(Map<String, dynamic> data) {
    final raw =
        (data['category'] ?? data['channelKind'] ?? 'escala').toString();
    return normalizeKind(raw);
  }

  static NotificationModuleTheme forKind(String? raw) {
    switch (normalizeKind(raw)) {
      case 'audiencia':
        return const NotificationModuleTheme(
          kind: 'audiencia',
          label: 'Audiência',
          emoji: '⚖️',
          channelId: 'controletotal_audiencia',
          channelName: '⚖️ Audiências e Processos',
          channelDescription:
              'Alertas críticos de prazos processuais e audiências',
          colorArgb: 0xFF5B21B6,
          threadId: 'controletotal_audiencia',
          bannerAsset: 'assets/images/push_banners/push-banner-audiencia.png',
          webBannerPath: '/icons/push-banner-audiencia.png',
        );
      case 'compromisso':
        return const NotificationModuleTheme(
          kind: 'compromisso',
          label: 'Compromisso',
          emoji: '📅',
          channelId: 'controletotal_compromisso',
          channelName: '📅 Compromissos e Reuniões',
          channelDescription: 'Lembretes de reuniões e compromissos agendados',
          colorArgb: 0xFF2563EB,
          threadId: 'controletotal_compromisso',
          bannerAsset: 'assets/images/push_banners/push-banner-compromisso.png',
          webBannerPath: '/icons/push-banner-compromisso.png',
        );
      case 'financeiro':
        return const NotificationModuleTheme(
          kind: 'financeiro',
          label: 'Financeiro',
          emoji: '💰',
          channelId: 'controletotal_financeiro',
          channelName: '💰 Financeiro e Contas a Pagar',
          channelDescription:
              'Vencimentos de boletos, faturas e alertas financeiros',
          colorArgb: 0xFF0D9488,
          threadId: 'controletotal_financeiro',
          bannerAsset: 'assets/images/push_banners/push-banner-financeiro.png',
          webBannerPath: '/icons/push-banner-financeiro.png',
        );
      case 'folga':
        return const NotificationModuleTheme(
          kind: 'folga',
          label: 'Folga',
          emoji: '🌴',
          channelId: 'controletotal_folga',
          channelName: '🌴 Folgas (Produtividade)',
          channelDescription: 'Folgas e produtividade — WISDOMAPP',
          colorArgb: 0xFF7C3AED,
          threadId: 'controletotal_folga',
          bannerAsset: 'assets/images/push_banners/push-banner-folga.png',
          webBannerPath: '/icons/push-banner-folga.png',
        );
      default:
        return const NotificationModuleTheme(
          kind: 'escala',
          label: 'Escala',
          emoji: '⏰',
          channelId: 'controletotal_escala',
          channelName: '⏰ Escalas e Plantões',
          channelDescription: 'Plantões, escalas e banco de horas — WISDOMAPP',
          colorArgb: 0xFFEA580C,
          threadId: 'controletotal_escala',
          bannerAsset: 'assets/images/push_banners/push-banner-escala.png',
          webBannerPath: '/icons/push-banner-escala.png',
        );
    }
  }

  static const allKinds = [
    'escala',
    'compromisso',
    'audiencia',
    'financeiro',
    'folga',
  ];
}
