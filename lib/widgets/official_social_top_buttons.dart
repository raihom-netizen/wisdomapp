import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../models/landing_public_content.dart';
import '../utils/url_launcher_helper.dart';

/// Botões Instagram, YouTube e WhatsApp — barra superior (estilo Johnathan Tarley).
/// URLs e rótulos vêm de `landing_content/main` (Admin / Gestor → Landing).
class OfficialSocialTopButtons extends StatelessWidget {
  const OfficialSocialTopButtons({
    super.key,
    required this.instagramUrl,
    required this.youtubeUrl,
    required this.whatsappUrl,
    this.instagramLabel = 'Instagram',
    this.youtubeLabel = 'YouTube',
    this.whatsappLabel = 'WhatsApp',
    this.goldAccent = const Color(0xFFD4AF37),
    this.showLabels = false,
  });

  factory OfficialSocialTopButtons.fromLanding(LandingPublicContent c) {
    return OfficialSocialTopButtons(
      instagramUrl: c.divInstagramUrl,
      youtubeUrl: c.divYoutubeUrl,
      whatsappUrl: c.divWhatsappUrl,
      instagramLabel: c.divInstagramLabel,
      youtubeLabel: c.divYoutubeLabel,
      whatsappLabel: c.divWhatsappLabel,
    );
  }

  final String instagramUrl;
  final String youtubeUrl;
  final String whatsappUrl;
  final String instagramLabel;
  final String youtubeLabel;
  final String whatsappLabel;
  final Color goldAccent;
  final bool showLabels;

  bool _valid(String url) {
    final t = url.trim();
    return t.isNotEmpty &&
        (t.startsWith('http://') ||
            t.startsWith('https://') ||
            t.startsWith('wa.me/'));
  }

  bool get _hasAny =>
      _valid(instagramUrl) || _valid(youtubeUrl) || _valid(whatsappUrl);

  @override
  Widget build(BuildContext context) {
    if (!_hasAny) return const SizedBox.shrink();

    final chips = <Widget>[
      if (_valid(instagramUrl))
        _SocialChip(
          icon: FontAwesomeIcons.instagram,
          label: instagramLabel,
          tooltip: instagramLabel,
          url: instagramUrl,
          colors: const [Color(0xFFE1306C), Color(0xFF833AB4), Color(0xFF405DE6)],
          goldAccent: goldAccent,
          showLabel: showLabels,
        ),
      if (_valid(youtubeUrl))
        _SocialChip(
          icon: FontAwesomeIcons.youtube,
          label: youtubeLabel,
          tooltip: youtubeLabel,
          url: youtubeUrl,
          colors: const [Color(0xFFFF0000), Color(0xFFCC0000)],
          goldAccent: goldAccent,
          showLabel: showLabels,
        ),
      if (_valid(whatsappUrl))
        _SocialChip(
          icon: FontAwesomeIcons.whatsapp,
          label: whatsappLabel,
          tooltip: whatsappLabel,
          url: whatsappUrl,
          colors: const [Color(0xFF25D366), Color(0xFF128C7E)],
          goldAccent: goldAccent,
          showLabel: showLabels,
        ),
    ];

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: chips,
    );
  }
}

class _SocialChip extends StatelessWidget {
  const _SocialChip({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.url,
    required this.colors,
    required this.goldAccent,
    required this.showLabel,
  });

  final FaIconData icon;
  final String label;
  final String tooltip;
  final String url;
  final List<Color> colors;
  final Color goldAccent;
  final bool showLabel;

  Future<void> _open() async {
    var target = url.trim();
    if (!target.startsWith('http')) {
      target = 'https://$target';
    }
    try {
      await openUrlPreferChrome(target);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _open,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: EdgeInsets.symmetric(
              horizontal: showLabel ? 14 : 0,
              vertical: showLabel ? 8 : 0,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                colors: [
                  colors.first.withValues(alpha: 0.22),
                  colors.last.withValues(alpha: 0.10),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: goldAccent.withValues(alpha: 0.42),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: colors.first.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: showLabel
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _iconBadge(),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.94),
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  )
                : SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(child: _iconBadge(size: 18)),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _iconBadge({double size = 16}) {
    return Container(
      width: showLabel ? 32 : 36,
      height: showLabel ? 32 : 36,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(showLabel ? 10 : 12),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: FaIcon(icon, color: Colors.white, size: size),
      ),
    );
  }
}
