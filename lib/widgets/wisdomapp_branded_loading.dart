import 'package:flutter/material.dart';

import 'wisdomapp_hero_brand.dart';

/// Splash de carregamento WISDOMAPP — Android, iOS e web (AuthWrapper).
class WisdomappBrandedLoading extends StatelessWidget {
  const WisdomappBrandedLoading({
    super.key,
    this.message,
    this.submessage,
    this.showProgress = true,
  });

  final String? message;
  final String? submessage;
  final bool showProgress;

  static const _bg = Color(0xFF061428);
  static const _bg2 = Color(0xFF0A1F56);
  static const _bg3 = Color(0xFF132D6B);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_bg, _bg2, _bg3],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const WisdomappHeroBrand(
                    compact: true,
                    showMicroTagline: true,
                    showIdealizer: true,
                  ),
                  if (showProgress) ...[
                    const SizedBox(height: 28),
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.95),
                      ),
                    ),
                  ],
                  if (message != null && message!.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (submessage != null && submessage!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      submessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
