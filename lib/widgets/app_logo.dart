import 'package:flutter/material.dart';

import 'wisdomapp_hero_brand.dart';

/// Logo WISDOMAPP — emblema transparente integrado ao tema (sem caixa de fundo).
class AppLogo extends StatelessWidget {
  final double height;
  final double? width;
  final BoxFit fit;
  final bool showMicroTagline;

  const AppLogo({
    super.key,
    this.height = 48,
    this.width,
    this.fit = BoxFit.contain,
    this.showMicroTagline = false,
  });

  @override
  Widget build(BuildContext context) {
    if (showMicroTagline) {
      return WisdomappHeroBrand(
        emblemSize: height,
        showMicroTagline: true,
        compact: height < 80,
      );
    }
    return WisdomappHeroBrand(
      emblemSize: height,
      showMicroTagline: false,
      compact: height < 80,
    );
  }
}
