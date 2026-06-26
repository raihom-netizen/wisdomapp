import 'package:flutter/material.dart';

import '../constants/finance_bank_brand_hosts.dart';

import '../constants/finance_bank_presets.dart';



/// Miniatura da marca: PNG offline em `assets/images/bank_brands/` ou iniciais do preset.

class FinanceBankBrandThumb extends StatelessWidget {

  final FinanceBankPreset? preset;

  final double size;

  /// `true`: fundo translúcido para ler bem sobre gradiente escuro/colorido.

  final bool onBrandGradient;

  final IconData fallbackIcon;



  const FinanceBankBrandThumb({

    super.key,

    required this.preset,

    this.size = 28,

    this.onBrandGradient = true,

    this.fallbackIcon = Icons.account_balance_wallet_rounded,

  });



  @override

  Widget build(BuildContext context) {

    final p = preset;

    if (p == null) {

      return Icon(

        fallbackIcon,

        size: size * 0.82,

        color: onBrandGradient ? Colors.white : const Color(0xFF475569),

      );

    }



    final radius = BorderRadius.circular(size * 0.28);

    final assetPath = financeBankBrandAssetPath(p.id);

    final pad = size * 0.14;

    if (assetPath == null) {
      return _InitialsBadge(preset: p, size: size, radius: radius, onBrandGradient: onBrandGradient);
    }



    final bg = onBrandGradient

        ? Colors.white.withValues(alpha: 0.22)

        : Colors.white;

    final borderColor = onBrandGradient

        ? Colors.white.withValues(alpha: 0.42)

        : p.color1.withValues(alpha: 0.35);



    return Container(

      width: size,

      height: size,

      decoration: BoxDecoration(

        color: bg,

        borderRadius: radius,

        border: Border.all(color: borderColor, width: onBrandGradient ? 1 : 1.2),

        boxShadow: onBrandGradient

            ? null

            : [

                BoxShadow(

                  color: Colors.black.withValues(alpha: 0.06),

                  blurRadius: 6,

                  offset: const Offset(0, 2),

                ),

              ],

      ),

      clipBehavior: Clip.antiAlias,

      child: Padding(

        padding: EdgeInsets.all(pad),

        child: Image.asset(

          assetPath,

          fit: BoxFit.contain,

          filterQuality: FilterQuality.high,

          gaplessPlayback: true,

          errorBuilder: (_, __, ___) =>

              _InitialsInner(preset: p, fontSize: size * 0.34, onBrandGradient: onBrandGradient),

        ),

      ),

    );

  }

}

class _InitialsBadge extends StatelessWidget {

  final FinanceBankPreset preset;

  final double size;

  final BorderRadius radius;

  final bool onBrandGradient;



  const _InitialsBadge({

    required this.preset,

    required this.size,

    required this.radius,

    required this.onBrandGradient,

  });



  @override

  Widget build(BuildContext context) {

    return Container(

      width: size,

      height: size,

      decoration: BoxDecoration(

        borderRadius: radius,

        gradient: LinearGradient(

          colors: [preset.color1, preset.color2],

          begin: Alignment.topLeft,

          end: Alignment.bottomRight,

        ),

        border: onBrandGradient ? Border.all(color: Colors.white.withValues(alpha: 0.35)) : null,

        boxShadow: onBrandGradient

            ? [BoxShadow(color: preset.color1.withValues(alpha: 0.35), blurRadius: 6, offset: const Offset(0, 2))]

            : null,

      ),

      alignment: Alignment.center,

      child: _InitialsInner(preset: preset, fontSize: size * 0.34, onBrandGradient: true),

    );

  }

}



class _InitialsInner extends StatelessWidget {

  final FinanceBankPreset preset;

  final double fontSize;

  final bool onBrandGradient;



  const _InitialsInner({

    required this.preset,

    required this.fontSize,

    required this.onBrandGradient,

  });



  @override

  Widget build(BuildContext context) {

    final raw = preset.initials;

    final label = raw.length > 2 ? raw.substring(0, 2) : raw;

    return FittedBox(

      fit: BoxFit.scaleDown,

      child: Text(

        label,

        maxLines: 1,

        style: TextStyle(

          color: onBrandGradient ? Colors.white : preset.color1,

          fontSize: fontSize,

          fontWeight: FontWeight.w900,

          letterSpacing: -0.5,

        ),

      ),

    );

  }

}

