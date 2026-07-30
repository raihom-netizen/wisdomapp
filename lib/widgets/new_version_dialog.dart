import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import '../constants/app_brand.dart';
import '../constants/app_version.dart';
import '../services/version_check_service.dart';
import '../theme/app_colors.dart';
import '../utils/app_update_launcher.dart';

/// Diálogo de nova versão (não bloqueante) — igual Controle Total.
///
/// Só aparece quando o admin toca em "Subir versão e avisar usuários" no
/// Painel Admin. O usuário escolhe entre "Atualizar agora" e "Mais tarde":
/// não é obrigatório atualizar, mas o aviso lembra que sem atualizar ele pode
/// ficar sem as novas melhorias. "Mais tarde" dispensa o aviso até o admin
/// subir um release mais novo.
class NewVersionDialog extends StatelessWidget {
  const NewVersionDialog({super.key});

  static bool _isOpen = false;

  /// Abre o diálogo de forma segura a partir de qualquer ponto.
  /// Evita abrir múltiplas instâncias sobrepostas.
  static Future<void> show(BuildContext context) async {
    if (_isOpen) return;
    _isOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const NewVersionDialog(),
    );
    _isOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final version =
        VersionCheckService.pendingUpdateVersion ?? AppVersion.current;
    final isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFFFFF), Color(0xFFF0F7FF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: AppColors.deepBlueDark.withValues(alpha: 0.18),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: AppColors.logoGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Nova versão disponível',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'A versão $version já está no ar com melhorias e correções para o ${AppBrand.displayName}.',
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFFFB300).withValues(alpha: 0.5),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xFFF57C00),
                        size: 22,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'A atualização não é obrigatória, mas sem ela você pode ficar sem as novas melhorias e correções de segurança.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF795548),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!kIsWeb) ...[
                  const SizedBox(height: 12),
                  Text(
                    isIos
                        ? 'Toque em "Atualizar agora" para abrir o TestFlight e instalar a nova versão.'
                        : 'Toque em "Atualizar agora" para abrir a Play Store e baixar a nova versão.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary.withValues(alpha: 0.9),
                      height: 1.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          VersionCheckService.dismissUpdateNotice();
                          Navigator.of(context).pop();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: BorderSide(
                              color: AppColors.primary.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Mais tarde',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _openUpdate(context),
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        label: Text(
                            kIsWeb ? 'Recarregar agora' : 'Atualizar agora'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openUpdate(BuildContext context) async {
    // Web: recarrega a página; mobile: abre Play Store / TestFlight e limpa o aviso.
    await launchControleTotalAppUpdate(context);
    if (!kIsWeb && context.mounted) {
      Navigator.of(context).pop();
    }
  }
}
