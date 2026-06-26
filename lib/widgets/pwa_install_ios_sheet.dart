import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../theme/app_colors.dart';
import '../utils/pwa_install_helper.dart';

/// URL da imagem ou GIF que mostra onde tocar no Safari (Compartilhar → Adicionar à Tela de Início).
/// Coloque o arquivo em web/assets/images/ para o servidor servir. Ex.: ios-adicionar-tela-inicio.png ou .gif
String get _iosInstallImageUrl {
  if (!kIsWeb) return '';
  try {
    final origin = Uri.base.origin;
    return '$origin/assets/images/ios-adicionar-tela-inicio.png';
  } catch (_) {
    return '';
  }
}

String get _iosInstallImageUrlGif {
  if (!kIsWeb) return '';
  try {
    final origin = Uri.base.origin;
    return '$origin/assets/images/ios-adicionar-tela-inicio.gif';
  } catch (_) {
    return '';
  }
}

/// Modal (janela interna) com imagem/GIF mostrando onde clicar no Safari para adicionar à tela inicial.
/// No iOS, ao tocar no banner "Instalar", abre este modal.
class PwaInstallIosSheet extends StatelessWidget {
  const PwaInstallIosSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const Dialog(
        child: PwaInstallIosSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 400, maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.add_to_home_screen_rounded, size: 32, color: AppColors.primary),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Instalar no iPhone',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.notifications_active_rounded, color: AppColors.primary, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Instale o app (Adicionar à Tela de Início) primeiro, senão a notificação não chega.',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Toque no Safari onde indicado na imagem abaixo:',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    _IosInstallImage(urlPng: _iosInstallImageUrl, urlGif: _iosInstallImageUrlGif),
                    const SizedBox(height: 20),
                    Text(
                      'Se não aparecer a imagem:',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade800),
                    ),
                    const SizedBox(height: 8),
                    _Step(number: 1, text: 'Toque no ícone Compartilhar (quadrado com seta para cima) na barra inferior do Safari.'),
                    const SizedBox(height: 8),
                    _Step(number: 2, text: 'Role o menu e toque em "Adicionar à Tela de Início".'),
                    const SizedBox(height: 8),
                    _Step(number: 3, text: 'Toque em "Adicionar" no canto superior direito.'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Entendi'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tenta exibir imagem PNG ou GIF; se falhar, mostra apenas o texto dos passos (já está abaixo).
class _IosInstallImage extends StatelessWidget {
  final String urlPng;
  final String urlGif;

  const _IosInstallImage({required this.urlPng, required this.urlGif});

  @override
  Widget build(BuildContext context) {
    if (urlPng.isEmpty && urlGif.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        urlGif.isNotEmpty ? urlGif : urlPng,
        fit: BoxFit.contain,
        width: double.infinity,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            height: 200,
            alignment: Alignment.center,
            child: CircularProgressIndicator(value: loadingProgress.expectedTotalBytes != null ? loadingProgress.cumulativeBytesLoaded / (loadingProgress.expectedTotalBytes ?? 1) : null),
          );
        },
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String text;

  const _Step({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text('$number', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.35))),
        ],
      ),
    );
  }
}

/// Um único ponto de entrada: ao tocar em "Instalar", Android abre o diálogo nativo;
/// iPhone abre o modal com imagem/instruções. Chamar de qualquer lugar (Dashboard, banner, etc.).
Future<void> handlePwaInstallTap(BuildContext context) async {
  if (!kIsWeb) return;
  if (hasPwaDeferredPrompt) {
    await triggerPwaInstall();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Toque em "Instalar" no diálogo para adicionar à tela inicial.'),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return;
  }
  if (isPwaIos) {
    await PwaInstallIosSheet.show(context);
    return;
  }
  if (!context.mounted) return;
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.add_to_home_screen_rounded, color: AppColors.primary),
          SizedBox(width: 10),
          Text('Instalar na tela inicial'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Neste navegador a instalação é manual. Siga os passos abaixo:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 14),
            Text('iPhone (Safari):', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
            const SizedBox(height: 6),
            const Text(
              'Toque no ícone Compartilhar (quadrado com seta para cima) na barra do Safari e depois em "Adicionar à Tela de Início".',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            Text('Chrome:', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
            const SizedBox(height: 6),
            const Text(
              'Toque no menu (⋮) do Chrome e selecione "Instalar app" ou "Adicionar à tela inicial".',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Entendi'),
        ),
      ],
    ),
  );
}
