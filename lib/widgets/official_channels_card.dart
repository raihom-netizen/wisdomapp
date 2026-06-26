import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../utils/url_launcher_helper.dart';

/// Faixa premium de canais oficiais — YouTube, Instagram, WhatsApp.
class OfficialChannelsCard extends StatelessWidget {
  const OfficialChannelsCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.youtubeUrl,
    required this.instagramUrl,
    required this.whatsappUrl,
    this.youtubeLabel = 'YouTube',
    this.instagramLabel = 'Instagram',
    this.whatsappLabel = 'WhatsApp',
    this.compact = false,
    this.includeYoutubeInstagram = true,
    this.forDarkBackground = false,
  });

  final String title;
  final String subtitle;
  final String youtubeUrl;
  final String instagramUrl;
  final String whatsappUrl;
  final String youtubeLabel;
  final String instagramLabel;
  final String whatsappLabel;
  final bool compact;
  final bool includeYoutubeInstagram;
  final bool forDarkBackground;

  bool get _hasAny {
    final w = whatsappUrl.trim().isNotEmpty;
    if (!includeYoutubeInstagram) return w;
    return youtubeUrl.trim().isNotEmpty ||
        instagramUrl.trim().isNotEmpty ||
        w;
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasAny) return const SizedBox.shrink();

    final pad = compact ? 12.0 : 18.0;
    final radius = compact ? 16.0 : 22.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: forDarkBackground ? 14 : 0,
          sigmaY: forDarkBackground ? 14 : 0,
        ),
        child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: forDarkBackground
            ? LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.16),
                  Colors.white.withValues(alpha: 0.06),
                  const Color(0xFF6366F1).withValues(alpha: 0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Color(0xFFFFFFFF), Color(0xFFF0F4FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        border: Border.all(
          color: forDarkBackground
              ? Colors.white.withValues(alpha: 0.22)
              : const Color(0xFFCBD5E1),
        ),
        boxShadow: [
          BoxShadow(
            color: forDarkBackground
                ? Colors.black.withValues(alpha: 0.22)
                : AppColors.deepBlue.withValues(alpha: compact ? 0.06 : 0.12),
            blurRadius: compact ? 10 : 24,
            offset: Offset(0, compact ? 4 : 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            Positioned(
              right: -24,
              top: -24,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFD4AF37).withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(pad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: compact ? 40 : 48,
                        height: compact ? 40 : 48,
                        child: Image.asset(
                          'assets/images/icon_no_bg.png',
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.verified_rounded,
                            color: AppColors.deepBlueDark,
                            size: compact ? 16 : 20,
                          ),
                        ),
                      ),
                      SizedBox(width: compact ? 10 : 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title.trim().isEmpty ? 'Canais oficiais' : title,
                              style: GoogleFonts.inter(
                                fontSize: compact ? 13 : 16,
                                fontWeight: FontWeight.w800,
                                color: forDarkBackground
                                    ? Colors.white.withValues(alpha: 0.98)
                                    : const Color(0xFF0F172A),
                                height: 1.2,
                              ),
                            ),
                            if (subtitle.trim().isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: GoogleFonts.inter(
                                  fontSize: compact ? 11 : 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: forDarkBackground
                                      ? Colors.white.withValues(alpha: 0.72)
                                      : AppColors.textMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: compact ? 10 : 14),
                  LayoutBuilder(
                    builder: (context, c) {
                      final narrow = c.maxWidth < 340;
                      final tiles = <Widget>[
                        if (includeYoutubeInstagram && youtubeUrl.trim().isNotEmpty)
                          _channelTile(
                            icon: FontAwesomeIcons.youtube,
                            label: youtubeLabel,
                            subtitle: 'Vídeos e aulas',
                            colors: const [Color(0xFFFF0000), Color(0xFFCC0000)],
                            onTap: () => openUrlPreferChrome(youtubeUrl),
                            compact: compact,
                            expanded: !narrow,
                          ),
                        if (includeYoutubeInstagram && instagramUrl.trim().isNotEmpty)
                          _channelTile(
                            icon: FontAwesomeIcons.instagram,
                            label: instagramLabel,
                            subtitle: 'Novidades',
                            colors: const [Color(0xFFE1306C), Color(0xFF833AB4), Color(0xFF405DE6)],
                            onTap: () => openUrlPreferChrome(instagramUrl),
                            compact: compact,
                            expanded: !narrow,
                          ),
                        if (whatsappUrl.trim().isNotEmpty)
                          _channelTile(
                            icon: FontAwesomeIcons.whatsapp,
                            label: whatsappLabel,
                            subtitle: 'Fale conosco',
                            colors: const [Color(0xFF25D366), Color(0xFF128C7E)],
                            onTap: () => openUrlPreferChrome(whatsappUrl),
                            compact: compact,
                            expanded: !narrow,
                          ),
                      ];
                      if (narrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < tiles.length; i++) ...[
                              if (i > 0) SizedBox(height: compact ? 8 : 10),
                              tiles[i],
                            ],
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < tiles.length; i++) ...[
                            if (i > 0) SizedBox(width: compact ? 8 : 10),
                            Expanded(child: tiles[i]),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
        ),
      ),
    );
  }

  Widget _channelTile({
    required FaIconData icon,
    required String label,
    required String subtitle,
    required List<Color> colors,
    required VoidCallback onTap,
    required bool compact,
    required bool expanded,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 10 : 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [
                colors.first.withValues(alpha: forDarkBackground ? 0.28 : 0.12),
                colors.last.withValues(alpha: forDarkBackground ? 0.14 : 0.06),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: colors.first.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                width: compact ? 36 : 42,
                height: compact ? 36 : 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(colors: colors),
                  boxShadow: [
                    BoxShadow(
                      color: colors.first.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: FaIcon(icon, color: Colors.white, size: compact ? 16 : 18),
                ),
              ),
              SizedBox(width: compact ? 8 : 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: compact ? 12 : 13.5,
                        fontWeight: FontWeight.w800,
                        color: forDarkBackground
                            ? Colors.white.withValues(alpha: 0.96)
                            : const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: compact ? 10 : 11,
                        fontWeight: FontWeight.w600,
                        color: forDarkBackground
                            ? Colors.white.withValues(alpha: 0.65)
                            : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_outward_rounded,
                size: compact ? 14 : 16,
                color: forDarkBackground
                    ? Colors.white.withValues(alpha: 0.55)
                    : colors.first.withValues(alpha: 0.85),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
