import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/promo_site_urls.dart';
import '../services/in_app_floating_message_service.dart';
import '../services/version_check_service.dart';
import '../theme/app_colors.dart';
import '../utils/app_update_launcher.dart';
import '../utils/maintenance_app_update_links.dart';
import '../utils/url_launcher_helper.dart';
import 'maintenance_app_update_buttons.dart';
import 'premium_center_message_dialog.dart';
import 'weekly_summary_premium_body.dart';

/// Preferências: último aviso manutenção/promo dispensado pelo diálogo central (alinha com banner do Início).
const String kMaintenanceDismissedFingerprintPrefsKey =
    'premium_center_maintenance_fp';

/// Disparado após gravar o fingerprint em prefs (diálogo central ou banner) para o Início atualizar na hora.
final ValueNotifier<int> maintenanceDismissSync = ValueNotifier<int>(0);

bool _maintenanceAppliesToUser(Map<String, dynamic>? data, String uid) {
  if (data == null) return false;
  final raw = data['maintenanceTargetUids'];
  if (raw is! List || raw.isEmpty) return true;
  final set = raw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toSet();
  if (set.isEmpty) return true;
  return set.contains(uid);
}

/// Mesma assinatura usada ao dispensar o diálogo global e o cartão do Início.
String fingerprintForMaintenanceConfig(Map<String, dynamic> data) {
  return [
    (data['maintenanceMessage'] ?? '').toString(),
    (data['maintenanceDate'] ?? '').toString(),
    (data['maintenanceTime'] ?? '').toString(),
    (data['maintenancePromoUrlAndroid'] ?? '').toString(),
    (data['maintenancePromoUrlIos'] ?? '').toString(),
    (data['maintenancePromoUrl'] ?? '').toString(),
    (data['maintenancePromoFirestoreId'] ?? '').toString(),
    (data['maintenancePromoUseOfficialSite'] ?? false).toString(),
    (data['maintenanceIncludeAppUpdateButtons'] ?? true).toString(),
  ].join('\u001f');
}

bool _gMaintenanceExpiredCleared = false;

void _clearExpiredMaintenanceOnce() {
  if (_gMaintenanceExpiredCleared) return;
  _gMaintenanceExpiredCleared = true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    FirebaseFirestore.instance.doc('system/config').set({
      'maintenanceMessage': '',
      'maintenanceDate': '',
      'maintenanceTime': '',
      'maintenancePromoUrl': '',
      'maintenancePromoUrlAndroid': '',
      'maintenancePromoUrlIos': '',
      'maintenancePromoLabel': '',
      'maintenancePromoUseOfficialSite': false,
      'maintenancePromoFirestoreId': '',
      'maintenanceTargetUids': [],
    }, SetOptions(merge: true));
  });
}

/// Escuta manutenção (Firestore), nova versão e mensagens in-app — mostra **um** diálogo central premium de cada vez, em qualquer módulo.
class PremiumGlobalMessageHost extends StatefulWidget {
  final String uid;

  const PremiumGlobalMessageHost({super.key, required this.uid});

  @override
  State<PremiumGlobalMessageHost> createState() => PremiumGlobalMessageHostState();
}

class PremiumGlobalMessageHostState extends State<PremiumGlobalMessageHost> {
  bool _dialogOpen = false;
  String? _maintenanceDismissedFp;
  DateTime? _lastPumpAt;

  @override
  void initState() {
    super.initState();
    InAppFloatingMessageService.notifier.addListener(_schedulePump);
    VersionCheckService.forceUpdateNotifier.addListener(_schedulePump);
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      _maintenanceDismissedFp =
          p.getString(kMaintenanceDismissedFingerprintPrefsKey);
      if (mounted) _schedulePump();
    } catch (_) {}
  }

  @override
  void dispose() {
    InAppFloatingMessageService.notifier.removeListener(_schedulePump);
    VersionCheckService.forceUpdateNotifier.removeListener(_schedulePump);
    super.dispose();
  }

  void _schedulePump() {
    final now = DateTime.now();
    if (_lastPumpAt != null && now.difference(_lastPumpAt!).inMilliseconds < 500) {
      return;
    }
    _lastPumpAt = now;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tryPumpQueue();
    });
  }

  Future<void> _persistMaintenanceDismiss(String fp) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(kMaintenanceDismissedFingerprintPrefsKey, fp);
      _maintenanceDismissedFp = fp;
      maintenanceDismissSync.value++;
    } catch (_) {}
  }

  Future<void> _tryPumpQueue([Map<String, dynamic>? configData]) async {
    if (!mounted || _dialogOpen) return;

    final ctx = context;
    if (!ctx.mounted) return;

    Map<String, dynamic>? data = configData;
    data ??= (await FirebaseFirestore.instance.doc('system/config').get()).data();

    // 1) Manutenção / promo admin
    if (data != null && _maintenanceAppliesToUser(data, widget.uid)) {
      final parsed = _parseMaintenance(data);
      if (parsed != null) {
        final fp = fingerprintForMaintenanceConfig(data);
        if (fp != _maintenanceDismissedFp) {
          await _showMaintenanceDialog(ctx, data, parsed, fp);
          return;
        }
      }
    }

    // 2) Nova versão — só faixa no painel (Play / TestFlight); sem diálogo bloqueante.

    // 3) In-app (resumo / push)
    final floating = InAppFloatingMessageService.notifier.value;
    if (floating != null) {
      await _showFloatingDialog(ctx, floating);
    }
  }

  _MaintenanceParsed? _parseMaintenance(Map<String, dynamic> data) {
    final msg = (data['maintenanceMessage'] ?? '').toString().trim();
    final dateStr = (data['maintenanceDate'] ?? '').toString();
    final timeStr = (data['maintenanceTime'] ?? '').toString();
    final promoUrlRawAndroid = (data['maintenancePromoUrlAndroid'] ?? '').toString().trim();
    final promoUrlRawIos = (data['maintenancePromoUrlIos'] ?? '').toString().trim();
    final promoUrlLegacy = (data['maintenancePromoUrl'] ?? '').toString().trim();
    final promoFirestoreId = (data['maintenancePromoFirestoreId'] ?? '').toString().trim();
    final promoLabel = (data['maintenancePromoLabel'] ?? '').toString().trim();
    final useOfficialPromoSite = data['maintenancePromoUseOfficialSite'] == true;
    final appUpdateLinks = resolveMaintenanceAppUpdateLinks(data);
    final effectivePromoUrlAndroid = resolveMaintenancePromoLaunchUrl(
      useOfficialPromoSite: useOfficialPromoSite,
      customUrl: promoUrlRawAndroid.isNotEmpty ? promoUrlRawAndroid : promoUrlLegacy,
      promoFirestoreId: promoFirestoreId,
    );
    final effectivePromoUrlIos = resolveMaintenancePromoLaunchUrl(
      useOfficialPromoSite: useOfficialPromoSite,
      customUrl: promoUrlRawIos,
      promoFirestoreId: promoFirestoreId,
    );
    final showPromoAndroid =
        !appUpdateLinks.hasAnyButton && effectivePromoUrlAndroid.isNotEmpty;
    final showPromoIos =
        !appUpdateLinks.hasAnyButton && effectivePromoUrlIos.isNotEmpty;
    final showPromo = showPromoAndroid || showPromoIos;

    if (msg.isEmpty &&
        (dateStr.isEmpty || timeStr.isEmpty) &&
        !showPromo &&
        !appUpdateLinks.hasAnyButton) {
      return null;
    }

    if (dateStr.isNotEmpty) {
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        final y = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        final d = int.tryParse(parts[2]) ?? 0;
        if (y > 0 && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
          final maintenanceDate = DateTime(y, m, d);
          final today = DateTime.now();
          final todayDate = DateTime(today.year, today.month, today.day);
          if (todayDate.isAfter(maintenanceDate)) {
            _clearExpiredMaintenanceOnce();
            return null;
          }
        }
      }
    }

    var texto = msg.isNotEmpty
        ? msg
        : (appUpdateLinks.hasAnyButton
            ? kMaintenanceImprovementsMessageDefault
            : (showPromo
                ? 'Acesse o site oficial pelo botão abaixo para ver a promoção, entrar com Google ou criar conta e concluir o pagamento.'
                : 'Manutenção programada.'));
    if (dateStr.isNotEmpty && timeStr.isNotEmpty) {
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        final d = int.tryParse(parts[2]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        final y = int.tryParse(parts[0]) ?? 0;
        texto =
            'Manutenção programada para ${d.toString().padLeft(2, '0')}/${m.toString().padLeft(2, '0')}/$y às $timeStr.${msg.isNotEmpty ? '\n\n$msg' : ''}';
      }
    }
    final promoButtonLabel =
        promoLabel.isNotEmpty ? promoLabel : 'Abrir site — promoção / pagamento';

    return _MaintenanceParsed(
      body: texto,
      appUpdateLinks: appUpdateLinks,
      showAndroid: showPromoAndroid,
      showIos: showPromoIos,
      effectiveAndroid: effectivePromoUrlAndroid,
      effectiveIos: effectivePromoUrlIos,
      promoButtonLabel: promoButtonLabel,
    );
  }

  Future<void> _showMaintenanceDialog(
    BuildContext ctx,
    Map<String, dynamic> raw,
    _MaintenanceParsed p,
    String fp,
  ) async {
    _dialogOpen = true;
    final isAppUpdate = p.appUpdateLinks.hasAnyButton;
    final subtitle = isAppUpdate
        ? 'Atualize o app para receber as melhorias'
        : 'WISDOMAPP · links oficiais · toque para abrir com segurança';

    final extras = <Widget>[];
    if (isAppUpdate) {
      extras.add(
        MaintenanceAppUpdateButtons(links: p.appUpdateLinks),
      );
    }
    final showAndroid = !isAppUpdate && p.showAndroid && showAndroidStoreUi;
    final showIos = !isAppUpdate && p.showIos && showIosStoreUi;
    if (showAndroid) {
      extras.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: FilledButton.icon(
            onPressed: () async {
              try {
                await openPromoMaintenanceLink(p.effectiveAndroid);
              } catch (_) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Não foi possível abrir o link do Android.')),
                  );
                }
              }
            },
            icon: const Icon(Icons.android_rounded, size: 22),
            label: Text(showIos ? 'Android — ${p.promoButtonLabel}' : p.promoButtonLabel),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      );
    }
    if (showIos) {
      extras.add(
        FilledButton.icon(
          onPressed: () async {
            try {
              await openPromoMaintenanceLink(p.effectiveIos);
            } catch (_) {
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Não foi possível abrir o link do iPhone.')),
                );
              }
            }
          },
          icon: const Icon(Icons.apple_rounded, size: 22),
          label: Text(showAndroid ? 'iPhone — ${p.promoButtonLabel}' : p.promoButtonLabel),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      );
    }

    await showPremiumCenterMessageDialog<void>(
      context: ctx,
      headerIcon: Icons.workspace_premium_rounded,
      title: isAppUpdate ? 'Nova versão com melhorias' : 'Manutenção e promoção',
      subtitle: subtitle,
      bodyText: p.body,
      extraActions: extras,
      primaryButton: null,
      laterLabel: 'OK',
      barrierDismissible: true,
    ).whenComplete(() async {
      await _persistMaintenanceDismiss(fp);
    });
    _dialogOpen = false;
    if (mounted) _schedulePump();
  }

  Future<void> _showFloatingDialog(BuildContext ctx, InAppFloatingPayload payload) async {
    _dialogOpen = true;
    final url = (payload.openUrl ?? '').trim();
    final isWeekly = payload.kind == InAppFloatingKind.weeklySummary;
    final hasStruct = payload.weeklyStructured != null;
    void popDialog() {
      if (!ctx.mounted) return;
      final nav = Navigator.of(ctx, rootNavigator: true);
      if (nav.canPop()) nav.pop();
    }

    try {
      await showPremiumCenterMessageDialog<void>(
        context: ctx,
        headerIcon: isWeekly ? Icons.summarize_rounded : Icons.notifications_active_rounded,
        title: payload.title,
        subtitle: isWeekly ? 'Super premium · WISDOMAPP' : 'Mensagem para você',
        bodyText: hasStruct ? '' : payload.body,
        customBody: hasStruct ? WeeklySummaryPremiumBody(data: payload.weeklyStructured!) : null,
        signature: '',
        laterLabel: isWeekly ? 'OK' : 'Ver depois',
        hideFooterLaterButton: isWeekly && hasStruct,
        primaryButton: (!isWeekly && url.isNotEmpty)
            ? FilledButton.icon(
                onPressed: () async {
                  try {
                    await openPromoMaintenanceLink(url);
                  } catch (_) {}
                },
                icon: const Icon(Icons.open_in_new_rounded, color: Colors.white),
                label: const Text('Abrir link', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              )
            : (!isWeekly && url.isEmpty)
                ? FilledButton(
                    onPressed: popDialog,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Entendi', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  )
                : null,
        barrierDismissible: true,
      );
    } finally {
      await InAppFloatingMessageService.dismissCurrent();
      _dialogOpen = false;
      if (mounted) _schedulePump();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.doc('system/config').snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _tryPumpQueue(data);
        });
        return const SizedBox.shrink();
      },
    );
  }
}

class _MaintenanceParsed {
  final String body;
  final MaintenanceAppUpdateLinks appUpdateLinks;
  final bool showAndroid;
  final bool showIos;
  final String effectiveAndroid;
  final String effectiveIos;
  final String promoButtonLabel;

  _MaintenanceParsed({
    required this.body,
    required this.appUpdateLinks,
    required this.showAndroid,
    required this.showIos,
    required this.effectiveAndroid,
    required this.effectiveIos,
    required this.promoButtonLabel,
  });
}
