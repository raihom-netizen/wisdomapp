import 'package:shared_preferences/shared_preferences.dart';



import 'app_session_cache.dart';
import 'home_start_module_cache.dart';
import 'offline_credentials_store.dart';
import 'user_profile_startup_cache.dart';



const String _kPreferEmailPassword = 'prefer_email_password_login';

const String _kLastLoginIdentifier = 'last_login_identifier';

const String _kLastOAuthProvider = 'last_oauth_provider';

/// Após «Entrar com outra conta»: não refazer login Google/Apple silencioso.

const String _kAccountSwitchPending = 'account_switch_pending';



/// Preferência: mostrar formulário de e-mail/senha na próxima abertura do login.

class LoginPreferences {

  static SharedPreferences? _prefs;

  static bool? _startupAccountSwitchPending;

  static bool? _startupReturningUser;



  /// Resultado síncrono após [warmUpForStartup] (cold start).

  static bool? get startupAccountSwitchPending => _startupAccountSwitchPending;

  static bool? get startupReturningUser => _startupReturningUser;



  static Future<SharedPreferences> _prefsOrLoad() async {

    return _prefs ??= await SharedPreferences.getInstance();

  }



  /// Pré-carrega prefs + flag «returning user» antes do primeiro frame autenticado.

  static Future<void> warmUpForStartup() async {

    if (_startupReturningUser != null) return;

    final prefs = await _prefsOrLoad();

    _startupAccountSwitchPending =

        prefs.getBool(_kAccountSwitchPending) ?? false;

    if (_startupAccountSwitchPending!) {

      _startupReturningUser = false;

      return;

    }

    final id = (prefs.getString(_kLastLoginIdentifier) ?? '').trim();

    if (id.isNotEmpty) {

      _startupReturningUser = true;

      return;

    }

    final oauth = (prefs.getString(_kLastOAuthProvider) ?? '').trim();

    if (oauth.isNotEmpty) {

      _startupReturningUser = true;

      return;

    }

    _startupReturningUser = await OfflineCredentialsStore.instance.hasStored();

  }



  static Future<bool> getPreferEmailPassword() async {

    final prefs = await _prefsOrLoad();

    return prefs.getBool(_kPreferEmailPassword) ?? false;

  }



  static Future<void> setPreferEmailPassword(bool value) async {

    final prefs = await _prefsOrLoad();

    await prefs.setBool(_kPreferEmailPassword, value);

  }



  static Future<String> getLastLoginIdentifier() async {

    final prefs = await _prefsOrLoad();

    return (prefs.getString(_kLastLoginIdentifier) ?? '').trim();

  }



  static Future<void> setLastLoginIdentifier(String value) async {

    final prefs = await _prefsOrLoad();

    final clean = value.trim();

    if (clean.isEmpty) {

      await prefs.remove(_kLastLoginIdentifier);

      return;

    }

    await prefs.setString(_kLastLoginIdentifier, clean);

    _startupReturningUser = true;

  }



  /// Último método usado com sucesso: `google` | `apple` | `email` — para login expresso (ex.: Google silencioso).

  static Future<String?> getLastOAuthProvider() async {

    final prefs = await _prefsOrLoad();

    final s = (prefs.getString(_kLastOAuthProvider) ?? '').trim();

    if (s.isEmpty) return null;

    return s;

  }



  static Future<void> setLastOAuthProvider(String value) async {

    final prefs = await _prefsOrLoad();

    final v = value.trim().toLowerCase();

    if (v.isEmpty || (v != 'google' && v != 'apple' && v != 'email')) {

      await prefs.remove(_kLastOAuthProvider);

      return;

    }

    await prefs.setString(_kLastOAuthProvider, v);

    _startupReturningUser = true;

  }



  /// Chamado no [AuthService.signOut] para não tentar Google silencioso com a conta errada após "Sair".

  static Future<void> clearOAuthHints() async {

    final prefs = await _prefsOrLoad();

    await prefs.remove(_kLastOAuthProvider);

  }



  /// «Sair» / «Entrar com outra conta»: limpa hints e bloqueia reconnect silencioso até login expresso.

  static Future<void> prepareForAccountSwitch({bool preferEmailForm = false}) async {

    final prefs = await _prefsOrLoad();

    await prefs.remove(_kLastOAuthProvider);

    await prefs.remove(_kLastLoginIdentifier);

    await prefs.setBool(_kPreferEmailPassword, preferEmailForm);

    await prefs.setBool(_kAccountSwitchPending, true);

    await AppSessionCache.clear();
    await UserProfileStartupCache.clear();
    await HomeStartModuleCache.clear();

    _startupAccountSwitchPending = true;

    _startupReturningUser = false;

  }



  static Future<bool> isAccountSwitchPending() async {

    if (_startupAccountSwitchPending != null) {

      return _startupAccountSwitchPending!;

    }

    final prefs = await _prefsOrLoad();

    return prefs.getBool(_kAccountSwitchPending) ?? false;

  }



  /// Chamado ao abrir [LoginScreen] após «Entrar com outra conta».

  static Future<bool> consumeAccountSwitchPending() async {

    final prefs = await _prefsOrLoad();

    final v = prefs.getBool(_kAccountSwitchPending) ?? false;

    if (v) await prefs.remove(_kAccountSwitchPending);

    _startupAccountSwitchPending = false;

    return v;

  }



  /// Login bem-sucedido: libera auto-restore e não trata como «troca de conta».

  static Future<void> markSuccessfulLogin() async {

    final prefs = await _prefsOrLoad();

    await prefs.remove(_kAccountSwitchPending);

    _startupAccountSwitchPending = false;

    _startupReturningUser = true;

  }



  /// Já houve login bem-sucedido neste aparelho (não é primeira instalação).

  static Future<bool> hasReturningLoginOnDevice() async {

    if (_startupReturningUser != null) {

      if (_startupAccountSwitchPending == true) return false;

      return _startupReturningUser!;

    }

    final id = await getLastLoginIdentifier();

    if (id.isNotEmpty) return true;

    final oauth = await getLastOAuthProvider();

    if (oauth != null) return true;

    return OfflineCredentialsStore.instance.hasStored();

  }

}


