import '../constants/promo_site_urls.dart';
import '../services/version_check_service.dart';
import 'app_update_launcher.dart';

/// URLs e visibilidade dos botões «Atualizar app» em avisos de manutenção/melhorias.
class MaintenanceAppUpdateLinks {
  final String androidUrl;
  final String iosUrl;
  final bool showAndroidButton;
  final bool showIosButton;

  const MaintenanceAppUpdateLinks({
    required this.androidUrl,
    required this.iosUrl,
    required this.showAndroidButton,
    required this.showIosButton,
  });

  bool get hasAnyButton => showAndroidButton || showIosButton;
}

/// Resolve links a partir de `system/config` (manutenção / melhorias).
MaintenanceAppUpdateLinks resolveMaintenanceAppUpdateLinks(
  Map<String, dynamic>? data,
) {
  final includeButtons = data?['maintenanceIncludeAppUpdateButtons'] != false;
  final useOfficial = data?['maintenancePromoUseOfficialSite'] == true;

  final rawAndroid =
      (data?['maintenancePromoUrlAndroid'] ?? '').toString().trim();
  final rawIos = (data?['maintenancePromoUrlIos'] ?? '').toString().trim();
  final legacy = (data?['maintenancePromoUrl'] ?? '').toString().trim();
  final promoId = (data?['maintenancePromoFirestoreId'] ?? '').toString().trim();

  String androidUrl;
  String iosUrl;

  if (useOfficial) {
    androidUrl = resolveMaintenancePromoLaunchUrl(
      useOfficialPromoSite: true,
      customUrl: '',
      promoFirestoreId: promoId,
    );
    iosUrl = resolveMaintenancePromoLaunchUrl(
      useOfficialPromoSite: true,
      customUrl: '',
      promoFirestoreId: promoId,
    );
  } else {
    androidUrl = resolveMaintenancePromoLaunchUrl(
      useOfficialPromoSite: false,
      customUrl: rawAndroid.isNotEmpty ? rawAndroid : legacy,
      promoFirestoreId: promoId,
    );
    iosUrl = resolveMaintenancePromoLaunchUrl(
      useOfficialPromoSite: false,
      customUrl: rawIos,
      promoFirestoreId: promoId,
    );
    if (includeButtons) {
      if (!_isHttp(androidUrl)) {
        androidUrl = VersionCheckService.playStoreAppUrl;
      }
      if (!_isHttp(iosUrl)) {
        iosUrl = VersionCheckService.effectiveTestFlightUrl;
      }
    }
  }

  final storeStyle = includeButtons && !useOfficial;
  final showAndroid =
      storeStyle && _isHttp(androidUrl) && showAndroidStoreUi;
  final showIos = storeStyle && _isHttp(iosUrl) && showIosStoreUi;

  return MaintenanceAppUpdateLinks(
    androidUrl: androidUrl,
    iosUrl: iosUrl,
    showAndroidButton: showAndroid,
    showIosButton: showIos,
  );
}

bool _isHttp(String u) => u.startsWith('http://') || u.startsWith('https://');

/// Preenche controladores do admin com links oficiais de atualização.
void applyDefaultMaintenanceAppUpdateUrls({
  required void Function(String android) setAndroid,
  required void Function(String ios) setIos,
}) {
  setAndroid(VersionCheckService.playStoreAppUrl);
  setIos(VersionCheckService.effectiveTestFlightUrl);
}

/// Texto sugerido para campanhas de melhoria com botões de atualização.
const String kMaintenanceImprovementsMessageDefault =
    'Temos melhorias e correções na nova versão do app. '
    'Toque no botão abaixo para atualizar e continuar com a melhor experiência.';
