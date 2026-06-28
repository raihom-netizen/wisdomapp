import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';
import '../utils/url_launcher_helper.dart';
import '../services/version_check_service.dart';
import '../constants/app_strings.dart';
import '../constants/app_version.dart';

/// Tela bloqueante quando há atualização obrigatória (forceUpdate).
/// Web: não bloqueia mais a sessão (banner flutuante). Mobile: abre loja/TestFlight.
class ForceUpdateScreen extends StatefulWidget {
  const ForceUpdateScreen({super.key});

  @override
  State<ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends State<ForceUpdateScreen> {
  Timer? _autoReloadTimer;
  int _secondsLeft = 3;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _startWebCountdown();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openUpdate(auto: true);
      });
    }
  }

  void _startWebCountdown() {
    _autoReloadTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) {
          t.cancel();
          _reloadWeb();
        }
      });
    });
  }

  void _reloadWeb() {
    if (_opening) return;
    setState(() => _opening = true);
    VersionCheckService.reloadWebPageNow(force: true);
  }

  @override
  void dispose() {
    _autoReloadTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final version = VersionCheckService.pendingUpdateVersion ?? AppVersion.current;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.system_update_rounded,
                  size: 80,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Atualização obrigatória',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Uma nova versão ($version) está disponível. Atualize o app para continuar usando o WISDOMAPP.',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (!kIsWeb) ...[
                  const SizedBox(height: 8),
                  Text(
                    defaultTargetPlatform == TargetPlatform.iOS
                        ? 'Toque em "Atualizar agora" para abrir o TestFlight e instalar a nova versão beta (link público).'
                        : 'Toque em "Atualizar agora" para abrir a Google Play Store e instalar a versão mais recente.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary.withOpacity(0.9),
                      height: 1.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (kIsWeb) ...[
                  const SizedBox(height: 20),
                  Text(
                    _secondsLeft > 0
                        ? 'Recarregando automaticamente em $_secondsLeft segundo(s)...'
                        : 'Recarregando...',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 32),
                Semantics(
                  label: AppStrings.semanticsUpdateNow,
                  button: true,
                  child: FilledButton.icon(
                    onPressed: _opening ? null : () => _openUpdate(auto: false),
                    icon: _opening
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.open_in_new_rounded, size: 24),
                    label: Text(kIsWeb ? 'Recarregar agora' : 'Atualizar agora'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                if (kIsWeb) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _opening
                        ? null
                        : () {
                            final v =
                                VersionCheckService.pendingUpdateVersion ?? '42.0';
                            final url =
                                'https://wisdomapp-b9e98.web.app/?v=$v&_=${DateTime.now().millisecondsSinceEpoch}';
                            launchUrl(
                              Uri.parse(url),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                    child: const Text('Abrir em nova aba (evita cache)'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openUpdate({required bool auto}) async {
    if (_opening) return;
    if (kIsWeb) {
      _reloadWeb();
      return;
    }
    setState(() => _opening = true);
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final url = VersionCheckService.effectiveTestFlightUrl;
        await openUrlPreferChrome(url);
        return;
      }
      const fallbackStore =
          'https://play.google.com/store/apps/details?id=com.wisdomapp.app';
      final directUrl = VersionCheckService.apkDownloadUrl?.trim();
      var url = fallbackStore;
      if (directUrl != null &&
          directUrl.isNotEmpty &&
          (directUrl.startsWith('http://') || directUrl.startsWith('https://'))) {
        final lower = directUrl.toLowerCase();
        url = lower.contains('play.google.com') ? directUrl : fallbackStore;
      }
      await openUrlPreferChrome(url);
    } catch (_) {
      if (mounted && !auto) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              defaultTargetPlatform == TargetPlatform.iOS
                  ? 'Não foi possível abrir o TestFlight.'
                  : 'Não foi possível abrir a Play Store. Verifique sua conexão.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }
}
