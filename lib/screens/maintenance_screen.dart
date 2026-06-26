import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../constants/promo_site_urls.dart';
import '../utils/app_update_launcher.dart';
import '../utils/maintenance_app_update_links.dart';
import '../utils/url_launcher_helper.dart';
import '../widgets/maintenance_app_update_buttons.dart';

bool _maintenanceFullScreenAppliesToUser(
    Map<String, dynamic>? data, String? uid) {
  if (uid == null || uid.isEmpty) return true;
  final raw = data?['maintenanceTargetUids'];
  if (raw is! List || raw.isEmpty) return true;
  final set = raw
      .map((e) => e.toString().trim())
      .where((s) => s.isNotEmpty)
      .toSet();
  if (set.isEmpty) return true;
  return set.contains(uid);
}

/// Tela exibida quando system/config.manutencao == true.
/// Mostra mensagem personalizada definida no Admin > Manutenção.
/// Admin pode desativar a manutenção.
class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.doc('system/config').snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final myUid = FirebaseAuth.instance.currentUser?.uid;
        if (!_maintenanceFullScreenAppliesToUser(data, myUid)) {
          return Scaffold(
            backgroundColor: const Color(0xFFF4F7FA),
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 56, color: Colors.blue.shade700),
                      const SizedBox(height: 16),
                      Text(
                        'Este aviso de manutenção é direcionado a outros usuários. Sua conta segue normalmente.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade800,
                            height: 1.35),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        final msg = (data?['maintenanceMessage'] ?? '').toString().trim();
        final dateStr = (data?['maintenanceDate'] ?? '').toString();
        final timeStr = (data?['maintenanceTime'] ?? '').toString();
        final configMap = data ?? <String, dynamic>{};
        final appUpdateLinks = resolveMaintenanceAppUpdateLinks(configMap);
        final useOfficialPromoSite =
            data?['maintenancePromoUseOfficialSite'] == true;
        final promoUrlRawAndroid =
            (data?['maintenancePromoUrlAndroid'] ?? '').toString().trim();
        final promoUrlRawIos =
            (data?['maintenancePromoUrlIos'] ?? '').toString().trim();
        final promoUrlLegacy =
            (data?['maintenancePromoUrl'] ?? '').toString().trim();
        final promoFirestoreId =
            (data?['maintenancePromoFirestoreId'] ?? '').toString().trim();
        final promoLabel = (data?['maintenancePromoLabel'] ?? '')
            .toString()
            .trim();
        final effectivePromoUrlAndroid = resolveMaintenancePromoLaunchUrl(
          useOfficialPromoSite: useOfficialPromoSite,
          customUrl: promoUrlRawAndroid.isNotEmpty
              ? promoUrlRawAndroid
              : promoUrlLegacy,
          promoFirestoreId: promoFirestoreId,
        );
        final effectivePromoUrlIos = resolveMaintenancePromoLaunchUrl(
          useOfficialPromoSite: useOfficialPromoSite,
          customUrl: promoUrlRawIos,
          promoFirestoreId: promoFirestoreId,
        );
        final showPromoButtonAndroid = !appUpdateLinks.hasAnyButton &&
            effectivePromoUrlAndroid.isNotEmpty &&
            showAndroidStoreUi;
        final showPromoButtonIos = !appUpdateLinks.hasAnyButton &&
            effectivePromoUrlIos.isNotEmpty &&
            showIosStoreUi;
        final showPromoButton = appUpdateLinks.hasAnyButton ||
            showPromoButtonAndroid ||
            showPromoButtonIos;
        final promoButtonLabel = promoLabel.isNotEmpty
            ? promoLabel
            : 'Abrir site — promoção / pagamento';
        String subtext = msg.isNotEmpty ? msg : 'Estamos realizando melhorias. Voltamos em breve.';
        if (dateStr.isNotEmpty && timeStr.isNotEmpty) {
          final parts = dateStr.split('-');
          if (parts.length == 3) {
            final d = int.tryParse(parts[2]) ?? 0;
            final m = int.tryParse(parts[1]) ?? 0;
            final y = int.tryParse(parts[0]) ?? 0;
            subtext = 'Manutenção programada para ${d.toString().padLeft(2, '0')}/${m.toString().padLeft(2, '0')}/$y às $timeStr.\n\n$subtext';
          }
        }
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.construction_rounded, size: 80, color: Colors.orange.shade700),
                    const SizedBox(height: 24),
                    Text(
                      'Sistema em Manutenção',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      subtext,
                      style: TextStyle(fontSize: 16, color: Colors.grey.shade700, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                    if (appUpdateLinks.hasAnyButton) ...[
                      const SizedBox(height: 20),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: MaintenanceAppUpdateButtons(
                          links: appUpdateLinks,
                        ),
                      ),
                    ] else if (showPromoButton) ...[
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.center,
                        children: [
                          if (showPromoButtonAndroid)
                            FilledButton.icon(
                              onPressed: () async {
                                try {
                                  await openPromoMaintenanceLink(
                                      effectivePromoUrlAndroid);
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Não foi possível abrir o link do Android.'),
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.android_rounded, size: 20),
                              label: Text(showPromoButtonIos
                                  ? 'Android'
                                  : promoButtonLabel),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 14),
                              ),
                            ),
                          if (showPromoButtonIos)
                            FilledButton.icon(
                              onPressed: () async {
                                try {
                                  await openPromoMaintenanceLink(
                                      effectivePromoUrlIos);
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Não foi possível abrir o link do iPhone.'),
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.apple_rounded, size: 20),
                              label: Text(showPromoButtonAndroid
                                  ? 'iPhone'
                                  : promoButtonLabel),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 14),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 32),
                    _AdminDesativarButton(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AdminDesativarButton extends StatefulWidget {
  @override
  State<_AdminDesativarButton> createState() => _AdminDesativarButtonState();
}

class _AdminDesativarButtonState extends State<_AdminDesativarButton> {
  bool _loading = false;
  bool _isAdmin = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  Future<void> _checkAdmin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _isAdmin = false;
        _checking = false;
      });
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance.doc('users/$uid').get();
      final data = snap.data() ?? {};
      final role = (data['role'] ?? '').toString();
      final admin = role == 'admin' || role == 'master';
      if (mounted) {
        setState(() {
          _isAdmin = admin;
          _checking = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _desativarManutencao() async {
    setState(() => _loading = true);
    try {
      await FirebaseFirestore.instance.doc('system/config').set({
        'manutencao': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Manutenção desativada.'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) return const SizedBox.shrink();
    if (!_isAdmin) return const SizedBox.shrink();

    return FilledButton.icon(
      onPressed: _loading ? null : _desativarManutencao,
      icon: _loading
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.power_settings_new_rounded),
      label: Text(_loading ? 'Desativando...' : 'Desativar manutenção (Admin)'),
      style: FilledButton.styleFrom(
        backgroundColor: Colors.orange.shade700,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    );
  }
}
