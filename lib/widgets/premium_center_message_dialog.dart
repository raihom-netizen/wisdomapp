import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/url_launcher_helper.dart';

/// Diálogo central estilo “push” premium: cantos amplos, sombra, hierarquia clara.
/// O corpo fica em área rolável com altura máxima para o botão inferior e ações sempre visíveis.
/// [onLater] é chamado **antes** do fechamento; não é necessário chamar [Navigator.pop] dentro dele.
Future<T?> showPremiumCenterMessageDialog<T>({
  required BuildContext context,
  required IconData headerIcon,
  required String title,
  String? subtitle,
  required String bodyText,
  String signature = 'Atenciosamente, equipe WISDOMAPP',
  /// Quando preenchido, substitui o corpo de texto (ex.: resumo semanal em cartões).
  Widget? customBody,
  List<Widget> extraActions = const [],
  Widget? primaryButton,
  String laterLabel = 'Depois',
  VoidCallback? onLater,
  /// Se true, não mostra o segundo botão «Depois/OK» no rodapé (usa só o do cabeçalho).
  bool hideFooterLaterButton = false,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: 0.48),
    builder: (ctx) {
      final mq = MediaQuery.of(ctx);
      final maxW = mq.size.width.clamp(0.0, 420.0);
      final maxDialogH = (mq.size.height - mq.padding.vertical) * 0.88;

      void dismiss() {
        onLater?.call();
        if (!ctx.mounted) return;
        Navigator.of(ctx, rootNavigator: true).maybePop();
      }

      return Center(
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxDialogH),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.deepBlueDark.withValues(alpha: 0.22),
                    blurRadius: 32,
                    offset: const Offset(0, 16),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: 5,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.deepBlueDark,
                            AppColors.deepBlue,
                            AppColors.accent,
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(10, 10, 8, 0),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFEFF6FF),
                            Colors.white,
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.12),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Icon(
                              headerIcon,
                              color: AppColors.primary,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                    height: 1.25,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                                if (subtitle != null && subtitle.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    subtitle,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textMuted,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: dismiss,
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              laterLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(22, 8, 22, hideFooterLaterButton ? 18 : 8),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: constraints.maxWidth),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (customBody != null)
                                    customBody
                                  else
                                    _SelectableLinkBody(
                                      text: bodyText,
                                      baseStyle: TextStyle(
                                        fontSize: 14.5,
                                        height: 1.45,
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      linkStyle: TextStyle(
                                        fontSize: 14.5,
                                        height: 1.45,
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w700,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  if (customBody == null && signature.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      signature,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontStyle: FontStyle.italic,
                                        color: AppColors.textMuted,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                  if (extraActions.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: extraActions,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (primaryButton != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                        child: primaryButton,
                      ),
                    if (!hideFooterLaterButton)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14, top: 2),
                        child: Center(
                          child: TextButton(
                            onPressed: dismiss,
                            child: Text(
                              laterLabel,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Corpo com URLs tocáveis (abre no handler externo via [UrlLauncher]).
class _SelectableLinkBody extends StatelessWidget {
  final String text;
  final TextStyle baseStyle;
  final TextStyle linkStyle;

  const _SelectableLinkBody({
    required this.text,
    required this.baseStyle,
    required this.linkStyle,
  });

  static final _urlRe = RegExp(r'https?://[^\s]+', caseSensitive: false);

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    var start = 0;
    for (final m in _urlRe.allMatches(text)) {
      if (m.start > start) {
        spans.add(TextSpan(text: text.substring(start, m.start), style: baseStyle));
      }
      final url = m.group(0)!;
      spans.add(
        TextSpan(
          text: url,
          style: linkStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              try {
                await openPromoMaintenanceLink(url);
              } catch (_) {}
            },
        ),
      );
      start = m.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: baseStyle));
    }
    if (spans.isEmpty) {
      return SelectableText(text, style: baseStyle);
    }
    return SelectableText.rich(
      TextSpan(children: spans),
    );
  }
}
