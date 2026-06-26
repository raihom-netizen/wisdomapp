import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
/// Emblema WISDOMAPP — mesmo ícone dos apps (Android/iOS/PWA).
class WisdomappEmblem extends StatelessWidget {
  const WisdomappEmblem({
    super.key,
    required this.size,
    this.showGlow = true,
    this.showWordmark = true,
  });

  final double size;
  final bool showGlow;
  final bool showWordmark;

  static const Color gold = Color(0xFFD4AF37);
  static const Color goldLight = Color(0xFFF0D878);
  static const Color goldDeep = Color(0xFFB8941F);

  static String? get _webIconUrl {
    if (!kIsWeb) return null;
    try {
      return Uri.base.resolve('icons/wisdomapp_emblem.png').toString();
    } catch (_) {
      return null;
    }
  }

  Widget _buildIconImage(double side) {
    final asset = Image.asset(
      'assets/images/icon_no_bg.png',
      width: side,
      height: side,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) =>
          Icon(Icons.account_balance_wallet_rounded, size: side, color: gold),
    );
    final webUrl = _webIconUrl;
    if (webUrl == null) return asset;
    return Image.network(
      webUrl,
      width: side,
      height: side,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => asset,
    );
  }

  @override
  Widget build(BuildContext context) {
    final glowSize = size * 1.12;
    final wordmarkFs = size * 0.14;
    final emblem = _buildIconImage(size);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: glowSize,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (showGlow)
                Container(
                  width: glowSize * 0.92,
                  height: glowSize * 0.92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: size * 0.18,
                        offset: Offset(0, size * 0.06),
                      ),
                    ],
                  ),
                ),
              emblem,
            ],
          ),
        ),
        if (showWordmark) ...[
          SizedBox(height: size * 0.04),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [goldLight, gold, goldDeep],
            ).createShader(bounds),
            child: Text(
              'WISDOM',
              style: GoogleFonts.playfairDisplay(
                fontSize: wordmarkFs,
                fontWeight: FontWeight.w800,
                letterSpacing: size * 0.008,
                height: 1.0,
              ),
            ),
          ),
          Text(
            'APP',
            style: GoogleFonts.inter(
              fontSize: wordmarkFs * 0.42,
              fontWeight: FontWeight.w800,
              letterSpacing: wordmarkFs * 0.35,
              color: goldLight.withValues(alpha: 0.88),
              height: 1.0,
            ),
          ),
        ],
      ],
    );
  }
}
