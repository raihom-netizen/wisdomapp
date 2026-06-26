import '../constants/app_brand.dart';

/// Textos do módulo Cursos (`app_config/wisdom_courses_module`) — editáveis no Painel Admin.
class WisdomCoursesModuleConfig {
  const WisdomCoursesModuleConfig({
    required this.heroTitle,
    required this.heroMessage,
    required this.sectionTitle,
    required this.emptyMessage,
    required this.showTipsSection,
  });

  final String heroTitle;
  final String heroMessage;
  final String sectionTitle;
  final String emptyMessage;
  final bool showTipsSection;

  static final defaults = WisdomCoursesModuleConfig(
    heroTitle: 'Método Wisdom de Organização Financeira',
    heroMessage: AppBrand.idealizerName,
    sectionTitle: 'Vídeos publicados',
    emptyMessage:
        'Nenhum vídeo disponível no momento. Volte em breve!',
    showTipsSection: true,
  );

  factory WisdomCoursesModuleConfig.fromMap(Map<String, dynamic>? raw) {
    final d = defaults;
    String pick(String k, String def) {
      final v = raw?[k];
      if (v == null) return def;
      final t = v.toString().trim();
      return t.isEmpty ? def : t;
    }

    return WisdomCoursesModuleConfig(
      heroTitle: _normalizeHeroTitle(pick('heroTitle', d.heroTitle)),
      heroMessage: _normalizeHeroMessage(pick('heroMessage', d.heroMessage)),
      sectionTitle: pick('sectionTitle', d.sectionTitle),
      emptyMessage: pick('emptyMessage', d.emptyMessage),
      showTipsSection: raw?['showTipsSection'] != false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'heroTitle': heroTitle,
        'heroMessage': heroMessage,
        'sectionTitle': sectionTitle,
        'emptyMessage': emptyMessage,
        'showTipsSection': showTipsSection,
      };

  /// Substitui títulos legados pelo método Wisdom atual.
  static String _normalizeHeroTitle(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return defaults.heroTitle;
    const legacy = {
      'Cursos Financeiros',
      'Cursos em vídeo',
      'Cursos em Vídeo',
    };
    if (legacy.contains(t)) return defaults.heroTitle;
    return t;
  }

  /// Remove instruções de admin legadas no texto exibido ao usuário.
  static String _normalizeHeroMessage(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return defaults.heroMessage;
    const legacyMessages = {
      'Aulas em vídeo com princípios bíblicos.',
      'Aulas em vídeo com princípios bíblicos',
    };
    if (legacyMessages.contains(t)) return defaults.heroMessage;
    final lower = t.toLowerCase();
    if (lower.contains('painel admin') ||
        lower.contains('publique links') ||
        lower.contains('youtube no painel')) {
      return defaults.heroMessage;
    }
    for (final sep in [' — ', ' - ', ' – ']) {
      if (t.contains(sep)) {
        final before = t.split(sep).first.trim();
        if (before.isNotEmpty) {
          return before.endsWith('.') ? before : '$before.';
        }
      }
    }
    return t;
  }
}
