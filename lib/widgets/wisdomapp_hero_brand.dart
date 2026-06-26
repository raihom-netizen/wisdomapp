import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_brand.dart';
import 'wisdomapp_emblem.dart';

/// Marca WISDOMAPP no hero — ícone oficial em alta resolução.
class WisdomappHeroBrand extends StatelessWidget {
  const WisdomappHeroBrand({
    super.key,
    this.emblemSize,
    this.showMicroTagline = true,
    this.showIdealizer = false,
    this.compact = false,
  });

  final double? emblemSize;
  final bool showMicroTagline;
  final bool showIdealizer;
  final bool compact;

  static const Color _gold = Color(0xFFD4AF37);
  static const Color _goldLight = Color(0xFFF0D878);
  static const Color _goldDeep = Color(0xFFB8941F);

  double _resolveEmblemSize(BuildContext context) {
    if (emblemSize != null) return emblemSize!;
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    final compactCap = h < 700 ? 88.0 : 104.0;
    if (compact) return w > 600 ? 112.0 : compactCap;
    if (kIsWeb) {
      if (w > 900) return 168.0;
      if (w > 520) return 140.0;
      return h < 680 ? 108.0 : 124.0;
    }
    return w > 400 ? 128.0 : 108.0;
  }

  @override
  Widget build(BuildContext context) {
    final size = _resolveEmblemSize(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        WisdomappEmblem(size: size, showGlow: false, showWordmark: false),
        if (showIdealizer) ...[
          SizedBox(height: compact ? 10 : 14),
          WisdomappHeroTitle(
            text: AppBrand.name,
            fontSize: compact ? 28 : null,
          ),
          const SizedBox(height: 6),
          Text(
            AppBrand.idealizerName.toUpperCase(),
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: compact ? 10 : 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: compact ? 1.8 : 2.2,
              color: _goldLight.withValues(alpha: 0.92),
            ),
          ),
        ],
        if (showMicroTagline) ...[
          SizedBox(height: compact ? 10 : (showIdealizer ? 12 : 14)),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_goldLight, _gold, _goldDeep],
            ).createShader(bounds),
            child: Text(
              'SABEDORIA FINANCEIRA',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w800,
                letterSpacing: compact ? 2.4 : 3.2,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Título hero premium — gradiente dourado sobre o fundo navy.
class WisdomappHeroTitle extends StatelessWidget {
  const WisdomappHeroTitle({
    super.key,
    required this.text,
    this.fontSize,
  });

  final String text;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final fs = fontSize ?? (w > 600 ? 38.0 : 34.0);
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFFFFF),
          Color(0xFFF0D878),
          Color(0xFFD4AF37),
        ],
        stops: [0.0, 0.55, 1.0],
      ).createShader(bounds),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: fs,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.8,
          height: 1.05,
        ),
      ),
    );
  }
}
