/// Versão única do app: Web, painel ADM, painel usuário — tudo na mesma linha.
///
/// Controle sequencial (6.01, 6.02, …): use o script na raiz do projeto:
///   npm run version:bump -- "Descrição da melhoria"
/// ou: .\bump_version.ps1 "Descrição"
/// O script atualiza [current], pubspec.yaml, package.json, functions/package.json e CHANGELOG.md.
/// O `deploy.ps1` publica web + `version.json` mas **não** grava `app_config/version` nem força atualização.
/// No painel Admin > Versão no servidor, use **"Subir versão e forçar atualização"** quando quiser obrigar
/// web, Android e iOS a atualizar.
///
/// **Release interno (web / Android / iOS alinhados — mesmo build sempre):**
/// - [current] = marketing (ex.: 10.04), igual para todos.
/// - [buildNumber] = número do `+` no pubspec (10.04.0+**16**). Igual em web/version.json e CFBundleVersion iOS.
/// - [versionCode] = mesmo valor que `versionCode` no `android/app/build.gradle`.
///
/// **Subir build iOS só (TestFlight à frente de web/Android):**
///   .\scripts\bump_ios_build.ps1
/// **Subir build (todas as plataformas juntas):**
///   .\scripts\bump_build.ps1
/// **Sincronizar arquivos após editar manualmente:**
///   .\scripts\sync_app_version.ps1
/// **Deploy:** .\deploy.ps1 (já chama sync antes de web + AAB + CodeMagic).
class AppVersion {
  AppVersion._();

  /// Versão atual do app — 10.04 (marketing; usuário vê no rodapé como principal).
  static const String current = '10.04';

  /// Build do pubspec (`10.04.0+12` → **12**). Web + Android; iOS usa [iosBuildNumber] quando maior.
  static const int buildNumber = 21;

  /// CFBundleVersion iOS (App Store / TestFlight). Pode ficar à frente de [buildNumber] (hotfix só Apple).
  static const int iosBuildNumber = 23;

  /// Mesmo inteiro que `versionCode` no Android (Play). Atualizar junto com build.gradle em cada release.
  static const int versionCode = 21;

  /// Identificador único do release web/Android (iOS pode estar em `10.04+$iosBuildNumber`).
  static String get releaseTag => '$current+$buildNumber';

  /// Tag iOS para suporte / TestFlight.
  static String get iosReleaseTag => '$current+$iosBuildNumber';

  /// Texto para conferência (admin / suporte): marketing, build pubspec e código Android.
  static String get internalLabel => '$releaseTag · #$versionCode';

  /// Retorna true se [serverVersion] é mais nova que [clientVersion].
  /// Ex: isNewer("5.01", "5.0") => true; isNewer("5.0", "5.0") => false.
  static bool isNewer(String serverVersion, String clientVersion) {
    final s = _parse(serverVersion);
    final c = _parse(clientVersion);
    for (int i = 0; i < s.length || i < c.length; i++) {
      final sv = i < s.length ? s[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (sv > cv) return true;
      if (sv < cv) return false;
    }
    return false;
  }

  static List<int> _parse(String v) {
    return v
        .split(RegExp(r'[.\-]'))
        .map((e) => int.tryParse(e.trim()) ?? 0)
        .toList();
  }
}
