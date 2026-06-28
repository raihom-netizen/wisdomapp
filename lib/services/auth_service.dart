import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'delegate_access_service.dart';
import 'push_notification_service.dart';
import 'offline_credentials_store.dart';
import 'login_preferences.dart';
import '../models/user_profile.dart';
import '../utils/firestore_retry.dart';
import '../utils/firestore_web_guard.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  /// Callable `ctResolveCpfEmail` e demais funções estão em us-central1.
  final FirebaseFunctions _fn =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Web client ID (Firebase / google-services.json) — WISDOMAPP `wisdomapp-b9e98`.
  static const String _googleServerClientId =
      '766524666378-ce9albkkvn01si77s6ofcqvoaatn29s0.apps.googleusercontent.com';

  GoogleSignIn? _googleSignInLazy;

  /// Instância única — reaproveita credenciais Google no dispositivo (login expresso mais rápido).
  GoogleSignIn _googleSignInInstance() {
    _googleSignInLazy ??= GoogleSignIn(
      scopes: const ['email', 'profile'],
      // Web client ID (tipo 3) — obrigatório no Android para idToken Firebase.
      serverClientId: kIsWeb ? null : _googleServerClientId,
      // Conta nativa no app (picker Google), não browser externo.
      forceCodeForRefreshToken: false,
    );
    return _googleSignInLazy!;
  }

  bool _isPermissionLikeError(Object error) {
    if (error is FirebaseException) {
      final code = error.code.toLowerCase();
      final msg = '${error.message ?? ''} ${error.toString()}'.toLowerCase();
      if (code == 'permission-denied' || code == 'unauthenticated') return true;
      if (msg.contains('permission-denied') ||
          msg.contains('permission_denied') ||
          msg.contains('insufficient permissions') ||
          msg.contains('unauthenticated')) {
        return true;
      }
    }
    final text = error.toString().toLowerCase();
    return text.contains('permission-denied') ||
        text.contains('permission_denied') ||
        text.contains('unauthenticated');
  }

  Future<void> _refreshWriteSession([User? user]) async {
    final current = user ?? _auth.currentUser;
    if (current == null) return;
    try {
      await current.getIdToken(true);
    } catch (_) {
      // Ignora: vamos tentar novamente a escrita para validar se a sessão recuperou.
    }
    try {
      await current.reload();
    } catch (_) {
      // Ignora erro de reload: em web/safari pode falhar intermitente.
    }
  }

  Future<void> _runFirestoreWriteWithRetry(
    Future<void> Function() action, {
    User? user,
  }) async {
    try {
      await action();
    } catch (e) {
      if (!_isPermissionLikeError(e)) rethrow;
      await _refreshWriteSession(user);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await action();
    }
  }

  Stream<User?> authStateChanges() => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  /// Força o Firebase a atualizar o token de acesso. Use após pagamento aprovado ou alteração de licença no admin.
  /// Ajuda a limpar cache de autenticação que pode causar permission-denied nas Security Rules.
  Future<void> refreshToken() async {
    final user = _auth.currentUser;
    if (user != null) {
      await user.getIdToken(true);
    }
  }

  String normalizeCpf(String v) => v.replaceAll(RegExp(r'[^0-9]'), '');
  String maskCpf(String cpfDigits) {
    final c = normalizeCpf(cpfDigits);
    if (c.length != 11) return cpfDigits;
    return '${c.substring(0,3)}.${c.substring(3,6)}.${c.substring(6,9)}-${c.substring(9,11)}';
  }

  Future<String> cpfToEmail(String cpfOrEmail) async {
    final input = cpfOrEmail.trim();
    if (input.contains('@')) return input;
    final cpf = normalizeCpf(input);
    if (cpf.length != 11) throw Exception('CPF inválido');
    try {
      final res =
          await _fn.httpsCallable('ctResolveCpfEmail').call({'cpf': cpf});
      final data = Map<String, dynamic>.from(res.data as Map);
      final email = (data['email'] ?? '').toString();
      if (email.isEmpty) throw Exception('CPF não cadastrado');
      return email;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found') {
        throw Exception('CPF não cadastrado');
      }
      if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
        throw Exception(
          'Sem conexão com o servidor. Verifique a internet e tente de novo.',
        );
      }
      final msg = (e.message ?? '').trim();
      if (msg.isNotEmpty) throw Exception(msg);
      rethrow;
    }
  }

  Future<UserCredential> signInWithCpf(String cpfOrEmail, String password) async {
    final email = await cpfToEmail(cpfOrEmail);
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  /// Envia e-mail para redefinir senha (Firebase Auth). Aceita CPF ou e-mail.
  Future<void> sendPasswordResetEmail(String cpfOrEmail) async {
    final email = await cpfToEmail(cpfOrEmail.trim());
    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<UserCredential> signUpWithCpf({
    required String cpf,
    required String name,
    required String email,
    required String password,
  }) async {
    final cpfDigits = normalizeCpf(cpf);
    if (cpfDigits.length != 11) throw Exception('CPF inválido');

    final emailTrim = email.trim();
    if (emailTrim.isEmpty) throw Exception('E-mail é obrigatório para identificação.');
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(emailTrim)) {
      throw Exception('Informe um e-mail válido (ex.: nome@dominio.com).');
    }

    final idx = await _db.collection('cpf_index').doc(cpfDigits).get();
    if (idx.exists) throw Exception('CPF já cadastrado');

    final cred = await _auth.createUserWithEmailAndPassword(
      email: emailTrim,
      password: password,
    );
    final uid = cred.user!.uid;
    final now = FieldValue.serverTimestamp();
    await _refreshWriteSession(cred.user);

    final trialEnd = DateTime.now().add(Duration(days: UserProfile.newUserTrialDays));
    await _runFirestoreWriteWithRetry(() async {
      await _db.collection('users').doc(uid).set({
        'cpf': cpfDigits,
        'cpfMasked': maskCpf(cpfDigits),
        'email': emailTrim,
        'name': name.trim(),
        'role': 'user',
        'plan': 'premium',
        'planStatus': 'active',
        'licenseExpiresAt': Timestamp.fromDate(trialEnd),
        'createdAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));

      await _db.collection('cpf_index').doc(cpfDigits).set({
        'uid': uid,
        'email': emailTrim,
        'createdAt': now,
      }, SetOptions(merge: true));

      await _db.collection('users').doc(uid).collection('settings').doc('general').set({
        'nightStart': '22:00',
        'nightEnd': '05:00',
        'regionDefault': 'GO',
        'updatedAt': now,
        'createdAt': now,
      }, SetOptions(merge: true));
    }, user: cred.user);

    return cred;
  }

  /// Marca perfil como completo (ex.: após cadastro rápido). Opcionalmente preenche CPF e atualiza cpf_index para login por CPF.
  Future<void> completeProfile(String uid, {String? cpf, String? email}) async {
    final ref = _db.collection('users').doc(uid);
    final data = <String, dynamic>{
      'profileComplete': true,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final emailTrim = email?.trim().toLowerCase() ?? '';
    if (emailTrim.isNotEmpty && emailTrim.contains('@')) {
      data['email'] = emailTrim;
    }
    String? emailToUse = emailTrim.isNotEmpty ? emailTrim : null;
    if (cpf != null && cpf.trim().isNotEmpty) {
      final cpfDigits = normalizeCpf(cpf.trim());
      if (cpfDigits.length == 11) {
        data['cpf'] = cpfDigits;
        data['cpfMasked'] = maskCpf(cpfDigits);
        final userSnap = await ref.get();
        emailToUse ??= (userSnap.data()?['email'] ?? '').toString().trim().toLowerCase();
        if (emailToUse != null && emailToUse.isNotEmpty) {
          await _db.collection('cpf_index').doc(cpfDigits).set({
            'uid': uid,
            'email': emailToUse,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }
    }
    await _runFirestoreWriteWithRetry(
      () => ref.set(data, SetOptions(merge: true)),
      user: _auth.currentUser,
    );
  }

  Future<void> resetPasswordByCpf(String cpfOrEmail) async {
    final email = await cpfToEmail(cpfOrEmail);
    await _auth.sendPasswordResetEmail(email: email);
  }

  /// Na web, retorna o Web Client ID da config do Firebase (getPublicConfig). Vazio se não configurado.
  Future<String> getGoogleWebClientIdForWeb() async {
    if (!kIsWeb) return '';
    try {
      final res = await _fn.httpsCallable('getPublicConfig').call();
      final map = Map<String, dynamic>.from(res.data as Map);
      final id = (map['googleWebClientId'] ?? '').toString().trim();
      if (id.isNotEmpty) return id;
    } catch (_) {}
    return '';
  }

  /// Login com Google. Retorna null se o usuário cancelar.
  /// Web: popup do Firebase.
  /// Android/iOS: google_sign_in + signInWithCredential.
  /// [forceAccountPicker]: após «trocar de conta», obriga escolher outra conta Google.
  Future<UserCredential?> signInWithGoogle({bool forceAccountPicker = false}) async {
    if (kIsWeb) {
      final GoogleAuthProvider googleProvider = GoogleAuthProvider();
      if (forceAccountPicker) {
        googleProvider.setCustomParameters({'prompt': 'select_account'});
      }
      try {
        return await FirestoreWebGuard.runWebGoogleSignInFlow(() async {
          final userCred = await _auth.signInWithPopup(googleProvider);
          await FirestoreWebGuard.stabilizeAfterWebSignIn();
          await FirestoreWebGuard.runWithWebRecovery(
            () => _ensureUserProfile(userCred.user),
          );
          return userCred;
        });
      } catch (e) {
        if (e.toString().contains('popup_closed_by_user') ||
            e.toString().contains('cancelled-popup')) {
          return null;
        }
        rethrow;
      }
    }
    try {
      final gsi = _googleSignInInstance();
      GoogleSignInAccount? googleUser;
      if (forceAccountPicker) {
        try {
          await gsi.signOut();
        } catch (_) {}
        googleUser = await gsi.signIn();
      } else {
        try {
          googleUser = await gsi.signInSilently();
        } catch (_) {
          googleUser = null;
        }
        googleUser ??= await gsi.signIn();
      }
      if (googleUser == null) return null;
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCred = await _auth.signInWithCredential(credential);
      await _ensureUserProfile(userCred.user);
      return userCred;
    } catch (e) {
      rethrow;
    }
  }

  /// Login expresso com Google sem abrir o picker (mobile), quando já há conta no dispositivo.
  /// Retorna null quando não há sessão Google disponível no dispositivo.
  Future<UserCredential?> signInWithGoogleSilently() async {
    if (kIsWeb) return null;
    try {
      final gsi = _googleSignInInstance();
      final GoogleSignInAccount? googleUser = await gsi.signInSilently();
      if (googleUser == null) return null;
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCred = await _auth.signInWithCredential(credential);
      await _ensureUserProfile(userCred.user);
      return userCred;
    } catch (_) {
      return null;
    }
  }

  static bool get isSignInWithAppleAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  static String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Login com Apple (iOS). Obrigatório para App Store guideline 4.8 quando há login social.
  /// Retorna null se o usuário cancelar. Configure o provedor Apple no Firebase Console.
  Future<UserCredential?> signInWithApple() async {
    if (!isSignInWithAppleAvailable) return null;

    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);

    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );
      final idToken = appleCredential.identityToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception(
          'A Apple não retornou o token de identidade. Tente novamente.',
        );
      }
      // authorizationCode como accessToken ajuda o Firebase a validar o fluxo em alguns casos (revisão App Store / iCloud).
      final authCode = appleCredential.authorizationCode;
      final accessToken = authCode.isNotEmpty ? authCode : null;
      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: idToken,
        rawNonce: rawNonce,
        accessToken: accessToken,
      );
      final userCred = await _auth.signInWithCredential(oauthCredential);
      final u = userCred.user;
      if (u != null) {
        final given = appleCredential.givenName?.trim();
        final family = appleCredential.familyName?.trim();
        final nameParts = <String>[];
        if (given != null && given.isNotEmpty) nameParts.add(given);
        if (family != null && family.isNotEmpty) nameParts.add(family);
        final combined = nameParts.join(' ');
        if (combined.isNotEmpty &&
            (u.displayName == null || u.displayName!.trim().isEmpty)) {
          try {
            await u.updateDisplayName(combined);
          } catch (_) {
            // Não falhar o login se só a atualização do nome falhar (rede / estado Firebase).
          }
        }
      }
      await _ensureUserProfile(userCred.user);
      return userCred;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    } on FirebaseAuthException {
      rethrow;
    }
  }

  /// Após restaurar sessão (cold start / sub-login): garante `users/{uid}.email`.
  ///
  /// [skipDelegateIndexProbe]: evita 2ª leitura de `delegate_email_index` no login
  /// (já tratada por [DelegateAccessService]).
  Future<void> ensureUserProfileFromSession({
    bool skipDelegateIndexProbe = false,
  }) async {
    await _ensureUserProfile(
      _auth.currentUser,
      skipDelegateIndexProbe: skipDelegateIndexProbe,
    );
  }

  /// E-mail da sessão Firebase (reload + providers). Vazio = conta não identificável.
  Future<String> _resolveSessionEmail(
    User user, {
    bool tryReload = true,
  }) async {
    var email = (user.email ?? '').trim();
    if (email.isEmpty && tryReload) {
      try {
        await user.reload();
      } catch (_) {}
    }
    final u = _auth.currentUser ?? user;
    email = (u.email ?? '').trim();
    if (email.isEmpty) {
      for (final p in u.providerData) {
        final e = (p.email ?? '').trim();
        if (e.isNotEmpty) {
          email = e;
          break;
        }
      }
    }
    return email.trim().toLowerCase();
  }

  /// Grava e-mail (e nome se faltar) quando o documento foi criado sem identificação.
  Future<void> _patchUserIdentityIfMissing({
    required String uid,
    required String email,
    String? displayName,
  }) async {
    final norm = email.trim().toLowerCase();
    if (norm.isEmpty || !norm.contains('@')) return;
    final ref = _db.collection('users').doc(uid);
    final snap = await runFirestoreWithRetry(() => ref.get());
    final data = snap.data() ?? {};
    final existingEmail = (data['email'] ?? '').toString().trim().toLowerCase();
    final existingName = (data['name'] ?? '').toString().trim();
    final patch = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (existingEmail.isEmpty) {
      patch['email'] = norm;
    }
    if (existingName.isEmpty) {
      final dn = (displayName ?? '').trim();
      patch['name'] = dn.isNotEmpty ? dn : norm.split('@').first;
    }
    if (patch.length <= 1) return;
    await _runFirestoreWriteWithRetry(
      () => ref.set(patch, SetOptions(merge: true)),
      user: _auth.currentUser,
    );
  }

  Future<void> _alignDelegateProfileIfAuthorized({
    required User u,
    required String email,
    required DocumentReference<Map<String, dynamic>> ref,
  }) async {
    if (DelegateAccessService.isActingAsDelegate) return;
    final delegateKey = email.trim().toLowerCase();
    if (delegateKey.isEmpty) return;
    try {
      final idx = await _db
          .collection('delegate_email_index')
          .doc(delegateKey)
          .get(const GetOptions(source: Source.serverAndCache));
      if (idx.exists && idx.data()?['active'] == true) {
        final principalUid =
            (idx.data()?['principalUid'] as String?)?.trim() ?? '';
        if (principalUid.isNotEmpty && principalUid != u.uid) {
          await _refreshWriteSession(u);
          await _runFirestoreWriteWithRetry(() {
            return ref.set({
              'email': delegateKey,
              'name': u.displayName?.trim().isNotEmpty == true
                  ? u.displayName!.trim()
                  : delegateKey.split('@').first,
              'role': 'user',
              'accountType': 'delegate',
              'plan': 'delegate',
              'linkedPrincipalUid': principalUid,
              'planStatus': 'active',
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }, user: u);
        }
      }
    } catch (_) {}
  }

  /// Exige e-mail para identificar todos os usuários. Não cria perfil sem e-mail.
  ///
  /// Sign in with Apple: o Firebase às vezes só preenche [User.email] após [reload] ou o e-mail
  /// vem em [UserInfo.email] do provider `apple.com` (relay @privaterelay.appleid.com). Sem isso,
  /// a revisão da App Store via de ver erro após credencial válida (Diretriz 2.1).
  Future<void> _ensureUserProfile(
    User? user, {
    bool skipDelegateIndexProbe = false,
  }) async {
    if (user == null) return;
    final u = _auth.currentUser ?? user;
    final email = await _resolveSessionEmail(
      u,
      tryReload: (u.email ?? '').trim().isEmpty,
    );
    if (email.isEmpty) {
      await _auth.signOut();
      throw Exception(
        'Não recebemos um e-mail para identificar sua conta. '
        'Tente de novo; na primeira vez com Apple, confirme o acesso na janela da Apple. '
        'Você também pode entrar com Google ou com e-mail e senha.',
      );
    }
    final ref = _db.collection('users').doc(u.uid);

    // Cache rápido só se o doc local já tem e-mail (evita doc “delegate” sem email).
    if (!kIsWeb) {
      try {
        final cached = await ref.get(const GetOptions(source: Source.cache));
        if (cached.exists) {
          final cachedEmail =
              (cached.data()?['email'] ?? '').toString().trim().toLowerCase();
          if (cachedEmail.isNotEmpty) {
            if (!skipDelegateIndexProbe) {
              await _alignDelegateProfileIfAuthorized(
                u: u,
                email: email,
                ref: ref,
              );
            }
            return;
          }
        }
      } catch (_) {}
    }

    final snap = await runFirestoreWithRetry(
      () => ref.get(
        GetOptions(source: kIsWeb ? Source.server : Source.serverAndCache),
      ),
    );

    if (snap.exists) {
      await _patchUserIdentityIfMissing(
        uid: u.uid,
        email: email,
        displayName: u.displayName,
      );
      if (!skipDelegateIndexProbe) {
        await _alignDelegateProfileIfAuthorized(u: u, email: email, ref: ref);
      }
      return;
    }

    // Sub-login (1º acesso): perfil delegate — só se compartilhamento ativo no índice.
    if (!skipDelegateIndexProbe) {
      try {
        final delegateKey = email.trim().toLowerCase();
        if (delegateKey.isNotEmpty) {
          final idx = await _db
              .collection('delegate_email_index')
              .doc(delegateKey)
              .get(const GetOptions(source: Source.serverAndCache))
              .timeout(const Duration(seconds: 2));
          if (idx.exists && idx.data()?['active'] == true) {
            final principalUid =
                (idx.data()?['principalUid'] as String?)?.trim() ?? '';
            if (principalUid.isNotEmpty && principalUid != u.uid) {
              await _refreshWriteSession(u);
              await _runFirestoreWriteWithRetry(() {
                return ref.set({
                  'email': email,
                  'name': u.displayName?.trim() ?? email.split('@').first,
                  'role': 'user',
                  'accountType': 'delegate',
                  'linkedPrincipalUid': principalUid,
                  'plan': 'delegate',
                  'planStatus': 'active',
                  'profileComplete': true,
                  'createdAt': FieldValue.serverTimestamp(),
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
              }, user: u);
              return;
            }
          }
        }
      } catch (_) {}
    }

    final now = FieldValue.serverTimestamp();
    final trialEnd = DateTime.now().add(Duration(days: UserProfile.newUserTrialDays));
    await _refreshWriteSession(u);
    await _runFirestoreWriteWithRetry(() {
      return ref.set({
        'email': email,
        'name': u.displayName?.trim() ?? email.split('@').first,
        'role': 'user',
        'plan': 'premium',
        'planStatus': 'active',
        'licenseExpiresAt': Timestamp.fromDate(trialEnd),
        'createdAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));
    }, user: u);
  }

  /// Cadastro rápido: nome completo + e-mail + senha. Apenas criação por e-mail/senha (sem Google).
  /// No botão "CRIAR CONTA" use apenas este método — não chame signInWithPopup.
  Future<UserCredential> signUpSimple({
    required String name,
    required String email,
    required String password,
  }) async {
    final emailTrim = email.trim();
    final nameTrim = name.trim();
    if (nameTrim.isEmpty) throw Exception('Informe o nome completo.');
    if (emailTrim.isEmpty) throw Exception('E-mail é obrigatório para identificação. Informe um e-mail válido.');
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(emailTrim)) {
      throw Exception('Informe um e-mail válido (ex.: nome@dominio.com).');
    }
    if (password.length < 6) throw Exception('A senha deve ter no mínimo 6 caracteres.');

    final cred = await _auth.createUserWithEmailAndPassword(
      email: emailTrim,
      password: password,
    );
    await cred.user?.updateDisplayName(nameTrim);
    final uid = cred.user!.uid;
    final now = FieldValue.serverTimestamp();
    await _refreshWriteSession(cred.user);

    final trialEnd = DateTime.now().add(Duration(days: UserProfile.newUserTrialDays));
    await _runFirestoreWriteWithRetry(() async {
      await _db.collection('users').doc(uid).set({
        'name': nameTrim,
        'email': emailTrim,
        'role': 'user',
        'plan': 'premium',
        'planStatus': 'active',
        'profileComplete': false,
        'licenseExpiresAt': Timestamp.fromDate(trialEnd),
        'createdAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));

      await _db.collection('users').doc(uid).collection('settings').doc('notifications').set({
        'scaleReminderEnabled': true,
        'scaleReminderMinutes': 60,
        'emailReminderEnabled': true,
        'dailyDigestEnabled': true,
        'notifCompromissos': true,
        'notifAudiencias': true,
        'notifCompromissosAudiencias': true,
        'deliveryEscala': 'both',
        'deliveryCompromisso': 'both',
        'deliveryAudiencia': 'both',
        'updatedAt': now,
      }, SetOptions(merge: true));
    }, user: cred.user);

    return cred;
  }

  /// Encerra sessão Firebase. O app permanece logado até «Entrar com outra conta» nas Configurações.
  /// [forAccountSwitch]: único fluxo de saída — limpa hints OAuth, credenciais offline e força novo login.
  Future<void> signOut({bool forAccountSwitch = false}) async {
    if (!forAccountSwitch) {
      // Mantém sessão/hints no aparelho — não deslogar por engano (menu antigo «Sair»).
      return;
    }
    await OfflineCredentialsStore.instance.clear().catchError((_) {});
    PushNotificationService.removeToken().catchError((_) {});
    if (!kIsWeb) {
      try {
        final gsi = _googleSignInInstance();
        await gsi.signOut();
        await gsi.disconnect();
      } catch (_) {}
    }
    if (kIsWeb) {
      await FirestoreWebGuard.recoverFirestoreWebSession().catchError((_) {});
    }
    await _auth.signOut();
  }

  /// Mensagem amigável para erros de login com Google (ex.: ApiException 10 = SHA-1 não configurado).
  /// Quem criou conta só com Google não tem senha — deve entrar com Google; o admin precisa configurar SHA-1 no Firebase.
  static String friendlyGoogleSignInError(Object e) {
    final s = e.toString();
    if (FirestoreWebGuard.isInternalAssertionError(e)) {
      return 'Conexão com o servidor instável neste navegador. '
          'Aguarde alguns segundos e toque em «Entrar com Google» de novo. '
          'Se persistir, atualize a página (F5) ou abra em uma aba anônima.';
    }
    if (s.contains('ApiException: 10') || s.contains('sign_in_failed')) {
      return 'Quem criou conta com Google deve entrar com Google. '
          'O administrador precisa adicionar a impressão digital SHA-1/SHA-256 do app no Firebase '
          '(incluindo a chave de Assinatura do app no Google Play). '
          'Se você tiver senha cadastrada, pode usar "Entrar com e-mail e senha".';
    }
    return s.replaceFirst(RegExp(r'^Exception:?\s*'), '');
  }

  /// Mensagem amigável para erros de login com Apple (Firebase / configuração).
  static String friendlyAppleSignInError(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'operation-not-allowed':
          return 'Login com a Apple não está ativado no Firebase. Em Authentication > Sign-in method, '
              'ative Apple e salve (Team ID, Key ID, chave .p8 e Services ID da Apple Developer).';
        case 'invalid-credential':
          return 'A Apple autenticou, mas o Firebase recusou a credencial. Confira no Firebase o provedor Apple: '
              'mesmo Team ID e Key que em developer.apple.com; chave .p8 válida; Services ID com domínios e '
              'Return URLs exatamente como o Firebase mostra. No Apple Developer, o App ID do app deve ter '
              '"Sign In with Apple" ativado.';
        case 'account-exists-with-different-credential':
          return 'Já existe conta com este e-mail usando outro login. Use Google ou e-mail e senha, ou entre '
              'com o mesmo método que usou ao cadastrar.';
        case 'user-disabled':
          return 'Esta conta foi desativada. Entre em contato com o suporte.';
        default:
          final m = (e.message ?? '').trim();
          if (m.isNotEmpty) return m;
          return 'Erro de autenticação (${e.code}). Tente novamente ou use outro método de login.';
      }
    }
    final s = e.toString();
    if (s.contains('invalid-credential') || s.contains('ERROR_INVALID_CREDENTIAL')) {
      return 'Credencial inválida ou expirada. No Firebase Console, confira o provedor Apple (chave .p8, '
          'Service ID e domínios). Na Apple Developer, confira Sign In with Apple no App ID e no Services ID.';
    }
    return s.replaceFirst(RegExp(r'^Exception:?\s*'), '');
  }

  /// Mensagem amigável para login e-mail/CPF + senha (conta de revisão, senha errada, etc.).
  static String friendlyEmailPasswordSignInError(Object e) {
    if (e is FirebaseFunctionsException) {
      switch (e.code) {
        case 'not-found':
          return 'CPF não cadastrado. Verifique o número ou crie uma conta.';
        case 'invalid-argument':
          return 'CPF inválido. Informe os 11 dígitos.';
        case 'unavailable':
        case 'deadline-exceeded':
          return 'Sem conexão com o servidor. Verifique a internet e tente de novo.';
        default:
          final m = (e.message ?? '').trim();
          if (m.isNotEmpty) return m;
          return 'Não foi possível validar o CPF (${e.code}).';
      }
    }
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-credential':
        case 'wrong-password':
          return 'E-mail/CPF ou senha incorretos. Quem criou conta só com Google ou com a Apple deve usar '
              'esses botões. Para senha: use "Esqueci minha senha" ou confira no Firebase Auth se o usuário existe.';
        case 'user-not-found':
          return 'Não encontramos conta com estes dados. Verifique e-mail/CPF ou crie uma conta.';
        case 'user-disabled':
          return 'Esta conta foi desativada. Entre em contato com o suporte.';
        case 'invalid-email':
          return 'E-mail inválido. Verifique o formato.';
        case 'too-many-requests':
          return 'Muitas tentativas. Aguarde alguns minutos e tente de novo.';
        default:
          final m = (e.message ?? '').trim();
          if (m.isNotEmpty) return m;
          return 'Não foi possível entrar (${e.code}).';
      }
    }
    return e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), '');
  }
}

