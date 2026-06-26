import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../services/auth_service.dart';

/// Botões padrão: Google (sempre) + Apple (somente iOS nativo).
class OAuthLoginButtons extends StatelessWidget {
  const OAuthLoginButtons({
    super.key,
    required this.loading,
    required this.onGoogle,
    this.onApple,
    this.googleLabel = 'Continuar com Google',
    this.appleLabel = 'Continuar com a Apple',
    this.googleForeground,
    this.googleBackground = Colors.white,
    this.googleBorderColor,
    this.compact = false,
  });

  final bool loading;
  final VoidCallback? onGoogle;
  final VoidCallback? onApple;
  final String googleLabel;
  final String appleLabel;
  final Color? googleForeground;
  final Color googleBackground;
  final Color? googleBorderColor;
  final bool compact;

  bool get _showApple =>
      AuthService.isSignInWithAppleAvailable && onApple != null;

  @override
  Widget build(BuildContext context) {
    final fg = googleForeground ?? const Color(0xFF1F1F1F);
    final border = googleBorderColor ?? const Color(0xFF747775);
    final gap = compact ? 8.0 : 12.0;
    final height = compact ? 48.0 : 54.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: OutlinedButton(
            onPressed: loading ? null : onGoogle,
            style: OutlinedButton.styleFrom(
              backgroundColor: googleBackground,
              foregroundColor: fg,
              side: BorderSide(color: border, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(compact ? 14 : 16),
              ),
            ),
            child: loading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FaIcon(FontAwesomeIcons.google, size: 20, color: fg),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          googleLabel,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: fg,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        if (_showApple) ...[
          SizedBox(height: gap),
          SizedBox(
            height: height,
            child: FilledButton(
              onPressed: loading ? null : onApple,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(compact ? 14 : 16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const FaIcon(FontAwesomeIcons.apple, size: 22, color: Colors.white),
                  const SizedBox(width: 10),
                  Text(
                    appleLabel,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
