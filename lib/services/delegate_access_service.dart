import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/firestore_user_doc_id.dart';

/// Acesso delegado: e-mail autorizado pelo titular usa os dados do UID principal.
class DelegateAccessService {
  DelegateAccessService._();

  static const _kDataOwnerUid = 'delegate_data_owner_uid';
  static const _kPrincipalEmail = 'delegate_principal_email';
  static const _kPrincipalName = 'delegate_principal_name';
  static const _kDelegateAuthEmail = 'delegate_auth_email';
  static const _kDelegateSessionPinned = 'delegate_session_pinned_v1';
  /// SnackBar de revogação já visto (OK), por e-mail do sub-login removido.
  static const _kRevokedSnackAckForEmail = 'delegate_revoked_snack_ack_email_v1';
  /// Aviso fixo em Configurações (perto de Compartilhar).
  static const _kRevokedBannerActive = 'delegate_revoked_banner_active_v1';
  static const _kRevokedPrincipalEmail = 'delegate_revoked_principal_email_v1';
  /// E-mail do usuário que foi removido (sub-login) — nunca o titular que removeu.
  static const _kRevokedBannerForAuthEmail = 'delegate_revoked_banner_auth_email_v1';

  static String? _cachedDataOwnerUid;
  static String? _cachedPrincipalEmail;
  static String? _cachedPrincipalName;

  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _indexListener;
  static DateTime? _lastPinnedServerCheck;

  /// UI: aviso quando titular revogou o sub-login (registar no [main.dart]).
  static void Function(String message)? onDelegateAccessRevoked;

  /// Dispara rebuild quando delegação é confirmada ou revogada.
  static final ValueNotifier<int> sessionRevision = ValueNotifier<int>(0);

  /// Evita SnackBar repetido na mesma sessão do app.
  static bool _revokedMessageShownThisSession = false;

  static bool _revokedBannerActive = false;
  static String? _revokedPrincipalEmailCache;
  static String? _revokedBannerForAuthEmailCache;

  static String? _currentAuthEmail() {
    return FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase();
  }

  static String? get dataOwnerUid => _cachedDataOwnerUid;
  static String? get principalEmail => _cachedPrincipalEmail;
  static String? get principalName => _cachedPrincipalName;

  static bool get isActingAsDelegate {
    final session = firestoreSessionUid();
    if (session == null || session.isEmpty) return false;
    final owner = _cachedDataOwnerUid;
    return owner != null && owner.isNotEmpty && owner != session;
  }

  static bool canManageDelegateSharing() {
    final session = firestoreSessionUid();
    return session != null && session.isNotEmpty && !isActingAsDelegate;
  }

  /// Aviso permanente em Configurações — só para o e-mail do sub-login removido.
  static bool get showRevokedBannerInSettings {
    if (!_revokedBannerActive) return false;
    final current = _currentAuthEmail() ?? '';
    if (current.isEmpty) return false;
    final forDelegate = (_revokedBannerForAuthEmailCache ?? '').trim().toLowerCase();
    if (forDelegate.isEmpty || forDelegate != current) return false;
    final principal = (_revokedPrincipalEmailCache ?? '').trim().toLowerCase();
    // Titular (e-mail da licença principal) nunca vê este aviso.
    if (principal.isNotEmpty && principal == current) return false;
    return true;
  }

  static String? get revokedPrincipalEmail => _revokedPrincipalEmailCache;

  static const String revokedNoticeMessage =
      'O titular removeu ou alterou seu acesso compartilhado. '
      'Você continua na sua conta, com licença própria, sem os dados da licença principal.';

  /// Utilizador confirmou o pop-up (OK) — não mostrar SnackBar de novo (este e-mail).
  static Future<void> markRevokedSnackAcknowledged() async {
    final current = _currentAuthEmail();
    if (current == null || current.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRevokedSnackAckForEmail, current);
  }

  static Future<bool> wasRevokedSnackAcknowledged() async {
    final current = _currentAuthEmail();
    if (current == null || current.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    final acked = (prefs.getString(_kRevokedSnackAckForEmail) ?? '').trim().toLowerCase();
    return acked.isNotEmpty && acked == current;
  }

  /// Só o sub-login removido (não o titular que removeu o e-mail autorizado).
  static bool _shouldShowRevokedNoticeToRemovedUser({
    required bool wasActingAsDelegate,
    required bool hadPinned,
    required String? delegateAuthEmail,
    required String? dataOwnerUid,
    required String? sessionUid,
    required String? principalLicenseEmail,
  }) {
    if (!wasActingAsDelegate || !hadPinned) return false;
    final current = _currentAuthEmail() ?? '';
    final auth = delegateAuthEmail?.trim().toLowerCase() ?? '';
    if (current.isEmpty || auth.isEmpty || auth != current) return false;
    final owner = dataOwnerUid?.trim() ?? '';
    final session = sessionUid?.trim() ?? '';
    if (owner.isEmpty || session.isEmpty || owner == session) return false;
    final principal = principalLicenseEmail?.trim().toLowerCase() ?? '';
    if (principal.isNotEmpty && principal == current) return false;
    return true;
  }

  static Future<void> _recordDelegateRevoked({
    required String delegateAuthEmail,
    String? principalEmail,
  }) async {
    final auth = delegateAuthEmail.trim().toLowerCase();
    if (auth.isEmpty) return;
    _revokedBannerActive = true;
    _revokedBannerForAuthEmailCache = auth;
    final pe = principalEmail?.trim().toLowerCase();
    if (pe != null && pe.isNotEmpty) {
      _revokedPrincipalEmailCache = pe;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRevokedBannerActive, true);
    await prefs.setString(_kRevokedBannerForAuthEmail, auth);
    if (pe != null && pe.isNotEmpty) {
      await prefs.setString(_kRevokedPrincipalEmail, pe);
    }
    _notifyRevision();
  }

  static Future<void> _clearRevokedNoticeState() async {
    _revokedBannerActive = false;
    _revokedPrincipalEmailCache = null;
    _revokedBannerForAuthEmailCache = null;
    _revokedMessageShownThisSession = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRevokedBannerActive);
    await prefs.remove(_kRevokedPrincipalEmail);
    await prefs.remove(_kRevokedBannerForAuthEmail);
    await prefs.remove(_kRevokedSnackAckForEmail);
    _notifyRevision();
  }

  static String emailDocKey(String email) => email.trim().toLowerCase();

  static bool isValidEmail(String email) {
    final e = email.trim();
    return e.isNotEmpty && RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(e);
  }

  static void _notifyRevision() {
    sessionRevision.value++;
  }

  static bool _prefsLoaded = false;

  static Future<void> loadFromPrefs() async {
    if (_prefsLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _cachedDataOwnerUid = prefs.getString(_kDataOwnerUid);
    _cachedPrincipalEmail = prefs.getString(_kPrincipalEmail);
    _cachedPrincipalName = prefs.getString(_kPrincipalName);
    _revokedBannerActive = prefs.getBool(_kRevokedBannerActive) ?? false;
    _revokedPrincipalEmailCache = prefs.getString(_kRevokedPrincipalEmail);
    _revokedBannerForAuthEmailCache = prefs.getString(_kRevokedBannerForAuthEmail);
    _prefsLoaded = true;
  }

  static Future<bool> isDelegatePinned() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kDelegateSessionPinned) ?? false;
  }

  static Future<void> _pinDelegateSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDelegateSessionPinned, true);
  }

  static Future<void> _unpinDelegateSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kDelegateSessionPinned);
  }

  static Future<void> _persist({
    required String principalUid,
    required String authEmail,
    String? principalEmail,
    String? principalName,
  }) async {
    _cachedDataOwnerUid = principalUid;
    _cachedPrincipalEmail = principalEmail;
    if (principalName != null && principalName.isNotEmpty) {
      _cachedPrincipalName = principalName;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDataOwnerUid, principalUid);
    await prefs.setString(_kDelegateAuthEmail, authEmail);
    if (principalEmail != null && principalEmail.isNotEmpty) {
      await prefs.setString(_kPrincipalEmail, principalEmail);
    } else {
      await prefs.remove(_kPrincipalEmail);
    }
    if (principalName != null && principalName.isNotEmpty) {
      await prefs.setString(_kPrincipalName, principalName);
    }
    _revokedMessageShownThisSession = false;
    await _clearRevokedNoticeState();
    _notifyRevision();
  }

  static Future<void> clear({bool notifyRevoked = false}) async {
    _stopDelegateIndexListener();
    final wasActingAsDelegate = isActingAsDelegate;
    final hadPinned = await isDelegatePinned();
    final revokedPrincipalEmail = _cachedPrincipalEmail;
    final dataOwnerUid = _cachedDataOwnerUid;
    final sessionUid = FirebaseAuth.instance.currentUser?.uid;
    final hadOwnerCache = _cachedDataOwnerUid != null;
    final prefs = await SharedPreferences.getInstance();
    final delegateAuthEmail = prefs.getString(_kDelegateAuthEmail);
    _cachedDataOwnerUid = null;
    _cachedPrincipalEmail = null;
    _cachedPrincipalName = null;
    _prefsLoaded = false;
    _lastPinnedServerCheck = null;
    await prefs.remove(_kDataOwnerUid);
    await prefs.remove(_kPrincipalEmail);
    await prefs.remove(_kPrincipalName);
    await prefs.remove(_kDelegateAuthEmail);
    await _unpinDelegateSession();
    if (wasActingAsDelegate || hadOwnerCache) _notifyRevision();
    // Só o sub-login removido (e-mail autorizado), nunca o titular que removeu.
    final showToRemoved = notifyRevoked &&
        _shouldShowRevokedNoticeToRemovedUser(
          wasActingAsDelegate: wasActingAsDelegate,
          hadPinned: hadPinned,
          delegateAuthEmail: delegateAuthEmail,
          dataOwnerUid: dataOwnerUid,
          sessionUid: sessionUid,
          principalLicenseEmail: revokedPrincipalEmail,
        );
    if (showToRemoved) {
      final auth = delegateAuthEmail!.trim().toLowerCase();
      final bannerForCurrent = (_revokedBannerForAuthEmailCache ?? '').trim().toLowerCase();
      if (!_revokedBannerActive || bannerForCurrent != auth) {
        await _recordDelegateRevoked(
          delegateAuthEmail: auth,
          principalEmail: revokedPrincipalEmail,
        );
      }
      final snackAcked = await wasRevokedSnackAcknowledged();
      if (!snackAcked && !_revokedMessageShownThisSession) {
        _revokedMessageShownThisSession = true;
        onDelegateAccessRevoked?.call(revokedNoticeMessage);
      }
    }
  }

  static void _stopDelegateIndexListener() {
    unawaited(_indexListener?.cancel());
    _indexListener = null;
  }

  /// Escuta revogação/alteração no Firestore (automático, sem bloquear login).
  static void ensureDelegateIndexListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _stopDelegateIndexListener();
      return;
    }
    unawaited(() async {
      await loadFromPrefs();
      if (!isActingAsDelegate) {
        _stopDelegateIndexListener();
        return;
      }
      final email = user.email?.trim().toLowerCase() ?? '';
      if (email.isEmpty) return;

      _stopDelegateIndexListener();
      _indexListener = FirebaseFirestore.instance
          .collection('delegate_email_index')
          .doc(emailDocKey(email))
          .snapshots()
          .listen(
        (snap) {
          unawaited(_onDelegateIndexSnapshot(snap, user));
        },
        onError: (_) {},
      );
    }());
  }

  static Future<void> _onDelegateIndexSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap,
    User user,
  ) async {
    if (!snap.exists || snap.data()?['active'] != true) {
      if (!isActingAsDelegate) return;
      await clear(notifyRevoked: true);
      return;
    }
    final principalUid = (snap.data()?['principalUid'] as String?)?.trim() ?? '';
    if (principalUid.isEmpty ||
        principalUid == user.uid ||
        principalUid != _cachedDataOwnerUid) {
      if (!isActingAsDelegate) return;
      await clear(notifyRevoked: true);
      return;
    }
  }

  static Future<void> _handleDelegateRevoked() async {
    if (!isActingAsDelegate && _cachedDataOwnerUid == null) return;
    await clear(notifyRevoked: isActingAsDelegate);
  }

  /// Titular ativou compartilhamento (tem e-mail autorizado cadastrado).
  static bool principalHasSharingEnabled(Map<String, dynamic>? userData) {
    // Vale qualquer um da lista: quem removeu o primeiro e manteve os outros
    // continua compartilhando.
    return authorizedEmailsFrom(userData).isNotEmpty;
  }

  /// Bloqueia painel antes do 1º vínculo? Não — sub-login fixo em cache + listener.
  static Future<bool> shouldBlockLoginForDelegateResolve() async {
    await loadFromPrefs();
    if (await isDelegatePinned()) {
      if (isActingAsDelegate) return false;
      await _unpinDelegateSession();
    }
    return false;
  }

  /// Startup: sub-login já vinculado neste aparelho.
  static Future<bool> prepareSessionForStartup() async {
    if (!_prefsLoaded) await loadFromPrefs();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await clear();
      return false;
    }
    final authEmail = user.email?.trim().toLowerCase() ?? '';
    if (authEmail.isEmpty) {
      await clear();
      return false;
    }
    if (!isActingAsDelegate) {
      if (_cachedDataOwnerUid != null) await clear();
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    final cachedAuth = (prefs.getString(_kDelegateAuthEmail) ?? '').trim();
    if (cachedAuth != authEmail) {
      await clear();
      return false;
    }
    return true;
  }

  /// Após login: [blocking] ignorado se sessão delegada já fixada (pinned).
  static Future<void> resolveAfterLogin({bool blocking = true}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await clear();
      return;
    }

    final authEmail = user.email?.trim().toLowerCase() ?? '';
    if (authEmail.isEmpty) {
      await clear();
      return;
    }

    await loadFromPrefs();
    if (_cachedDataOwnerUid != null && !isActingAsDelegate) {
      await clear();
    }
    if (await isDelegatePinned() && isActingAsDelegate) {
      ensureDelegateIndexListener();
      return;
    }

    final useBlocking = blocking && !await isDelegatePinned();
    if (!useBlocking) {
      unawaited(_resolveInternal(authEmail, user, blocking: false));
      return;
    }
    await _resolveInternal(authEmail, user, blocking: true);
  }

  static Future<void> _resolveInternal(
    String authEmail,
    User user, {
    required bool blocking,
  }) async {
    try {
      final indexRef = FirebaseFirestore.instance
          .collection('delegate_email_index')
          .doc(emailDocKey(authEmail));

      DocumentSnapshot<Map<String, dynamic>>? doc;
      if (blocking) {
        try {
          doc = await indexRef
              .get(const GetOptions(source: Source.serverAndCache))
              .timeout(const Duration(seconds: 2));
        } catch (_) {
          try {
            doc = await indexRef
                .get(const GetOptions(source: Source.cache))
                .timeout(const Duration(milliseconds: 400));
          } catch (_) {}
        }
      } else {
        try {
          doc = await indexRef
              .get(const GetOptions(source: Source.cache))
              .timeout(const Duration(milliseconds: 80));
        } catch (_) {}

        if (doc == null || !doc.exists) {
          if (await isDelegatePinned() && isActingAsDelegate) {
            ensureDelegateIndexListener();
            return;
          }
          try {
            doc = await indexRef
                .get(const GetOptions(source: Source.serverAndCache))
                .timeout(const Duration(milliseconds: 1200));
          } catch (_) {
            return;
          }
        }
      }

      if (doc == null || !doc.exists || doc.data()?['active'] != true) {
        // Titular (sem vínculo delegado) — índice inexistente é normal; não avisar.
        if (!isActingAsDelegate && _cachedDataOwnerUid == null) return;
        await _handleDelegateRevoked();
        return;
      }

      final data = doc.data()!;
      final principalUid = (data['principalUid'] as String?)?.trim() ?? '';
      if (principalUid.isEmpty || principalUid == user.uid) {
        await clear();
        return;
      }

      final principalEmail =
          (data['principalEmail'] as String?)?.trim().toLowerCase() ?? '';
      await _persist(
        principalUid: principalUid,
        authEmail: authEmail,
        principalEmail: principalEmail.isNotEmpty ? principalEmail : null,
      );
      await _pinDelegateSession();
      ensureDelegateIndexListener();
      unawaited(_loadPrincipalNameLazy(principalUid));
      unawaited(_syncDelegateSessionProfile(user.uid, principalUid));
      unawaited(_markInviteAccepted(authEmail, user.uid));
    } catch (_) {
      if (await isDelegatePinned() && isActingAsDelegate) {
        ensureDelegateIndexListener();
        return;
      }
      if (_cachedDataOwnerUid == null) await clear();
    }
  }

  /// Revalidação leve ao voltar do app (não bloqueia UI se pinned).
  static Future<void> revalidateSession({bool blocking = false}) async {
    await loadFromPrefs();
    if (_cachedDataOwnerUid != null && !isActingAsDelegate) {
      await clear();
    }
    if (await isDelegatePinned() && isActingAsDelegate) {
      final now = DateTime.now();
      if (_lastPinnedServerCheck != null &&
          now.difference(_lastPinnedServerCheck!) <
              const Duration(hours: 4)) {
        ensureDelegateIndexListener();
        return;
      }
      _lastPinnedServerCheck = now;
      await resolveAfterLogin(blocking: false);
      ensureDelegateIndexListener();
      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email?.trim().toLowerCase() ?? '';
      if (user != null && email.isNotEmpty) {
        unawaited(_markInviteAccepted(email, user.uid));
      }
      return;
    }
    await resolveAfterLogin(blocking: blocking);
  }

  static Future<void> _syncDelegateSessionProfile(
    String sessionUid,
    String principalUid,
  ) async {
    try {
      final authEmail =
          FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase() ?? '';
      // Sem 'plan': é campo protegido do perfil (só admin/servidor muda —
      // firestore.rules camposProtegidosPerfil); com ele a gravação inteira
      // era recusada.
      final patch = <String, dynamic>{
        'accountType': 'delegate',
        'linkedPrincipalUid': principalUid,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (authEmail.isNotEmpty && authEmail.contains('@')) {
        patch['email'] = authEmail;
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(sessionUid)
          .set(patch, SetOptions(merge: true));
    } catch (_) {}
  }

  static Future<void> _loadPrincipalNameLazy(String principalUid) async {
    if (_cachedPrincipalName != null &&
        _cachedPrincipalName!.isNotEmpty &&
        _cachedPrincipalEmail != null &&
        _cachedPrincipalEmail!.isNotEmpty) {
      return;
    }
    try {
      final principalDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(principalUid)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 3));
      final data = principalDoc.data();
      final name = (data?['name'] as String?)?.trim();
      final email = (data?['email'] as String?)?.trim().toLowerCase();
      var changed = false;
      if (name != null && name.isNotEmpty) {
        _cachedPrincipalName = name;
        changed = true;
      }
      if ((_cachedPrincipalEmail == null || _cachedPrincipalEmail!.isEmpty) &&
          email != null &&
          email.isNotEmpty) {
        _cachedPrincipalEmail = email;
        changed = true;
      }
      if (changed) {
        final prefs = await SharedPreferences.getInstance();
        if (name != null && name.isNotEmpty) {
          await prefs.setString(_kPrincipalName, name);
        }
        if (email != null && email.isNotEmpty) {
          await prefs.setString(_kPrincipalEmail, email);
        }
        _notifyRevision();
      }
    } catch (_) {}
  }

  /// Sub-login: marca no índice que o convite foi aceito (e quando foi o
  /// último acesso). É o que o titular vê como «Ativo» × «Convite pendente».
  /// As regras só deixam o próprio e-mail gravar estes 3 campos.
  static DateTime? _lastInviteMarkAt;

  static Future<void> _markInviteAccepted(String authEmail, String uid) async {
    final key = emailDocKey(authEmail);
    if (key.isEmpty || uid.isEmpty) return;
    final now = DateTime.now();
    if (_lastInviteMarkAt != null &&
        now.difference(_lastInviteMarkAt!) < const Duration(hours: 6)) {
      return;
    }
    try {
      final ref =
          FirebaseFirestore.instance.collection('delegate_email_index').doc(key);
      final snap = await ref.get();
      final data = snap.data();
      if (!snap.exists || data == null || data['active'] != true) return;
      final principal = (data['principalUid'] as String?)?.trim() ?? '';
      if (principal.isEmpty || principal == uid) return;
      final patch = <String, dynamic>{
        'delegateUid': uid,
        'lastSeenAt': FieldValue.serverTimestamp(),
      };
      if (data['acceptedAt'] == null) {
        patch['acceptedAt'] = FieldValue.serverTimestamp();
      }
      await ref.update(patch);
      _lastInviteMarkAt = now;
    } catch (_) {}
  }

  /// Quantas pessoas a licença pode autorizar ao mesmo tempo (igual ao
  /// Controle Total). Cada uma entra com o próprio Google/Apple e continua sem
  /// licença própria — o vínculo é com quem cadastrou.
  static const int maxAuthorizedEmails = 4;

  /// E-mails autorizados da licença, em ordem de cadastro.
  ///
  /// Lê o campo novo (`authorizedDelegateEmails`) e, quando ele ainda não
  /// existe, o campo antigo de um e-mail só — nenhuma licença precisa ser
  /// migrada para continuar funcionando.
  static List<String> authorizedEmailsFrom(Map<String, dynamic>? userData) {
    final lista = userData?['authorizedDelegateEmails'];
    final out = <String>[];
    if (lista is List) {
      for (final e in lista) {
        final k = emailDocKey(e.toString());
        if (k.isNotEmpty && !out.contains(k)) out.add(k);
      }
    }
    final antigo =
        emailDocKey((userData?['authorizedDelegateEmail'] ?? '').toString());
    if (antigo.isNotEmpty && !out.contains(antigo)) out.insert(0, antigo);
    return out;
  }

  /// Lê os e-mails autorizados direto do Firestore.
  static Future<List<String>> loadAuthorizedEmails(String principalUid) async {
    final uid = principalUid.trim();
    if (uid.isEmpty) return const [];
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      return authorizedEmailsFrom(snap.data());
    } catch (_) {
      return const [];
    }
  }

  /// Lista com a situação de cada pessoa (pendente / ativo / sem acesso).
  static Future<List<DelegateInvite>> loadInvites(String principalUid) async {
    final uid = principalUid.trim();
    final emails = await loadAuthorizedEmails(uid);
    if (emails.isEmpty) return const [];
    final db = FirebaseFirestore.instance;
    final out = await Future.wait(emails.map((email) async {
      try {
        final snap =
            await db.collection('delegate_email_index').doc(email).get();
        final d = snap.data();
        if (!snap.exists ||
            d == null ||
            d['active'] != true ||
            (d['principalUid'] ?? '').toString().trim() != uid) {
          return DelegateInvite(
              email: email, status: DelegateInviteStatus.semAcesso);
        }
        final aceito = d['acceptedAt'];
        final visto = d['lastSeenAt'];
        return DelegateInvite(
          email: email,
          status: aceito == null
              ? DelegateInviteStatus.pendente
              : DelegateInviteStatus.ativo,
          acceptedAt: aceito is Timestamp ? aceito.toDate() : null,
          lastSeenAt: visto is Timestamp ? visto.toDate() : null,
        );
      } catch (_) {
        return DelegateInvite(
            email: email, status: DelegateInviteStatus.semAcesso);
      }
    }));
    return out;
  }

  /// Adiciona (ou troca) um e-mail autorizado na lista.
  ///
  /// `substituindo` é o e-mail que está sendo editado — ele sai da lista e do
  /// índice no mesmo lote, para não sobrar acesso de quem foi trocado.
  /// Passar o MESMO e-mail em `substituindo` e `newEmail` reativa o índice.
  static Future<String?> saveAuthorizedEmailInList({
    required String principalUid,
    required String principalEmail,
    required String newEmail,
    String substituindo = '',
  }) async {
    final uid = principalUid.trim();
    if (uid.isEmpty) return 'Sessão inválida. Saia e entre novamente no app.';
    final clean = emailDocKey(newEmail);
    if (!isValidEmail(clean)) return 'Informe um e-mail válido.';
    final own = emailDocKey(principalEmail);
    if (clean == own) {
      return 'O e-mail autorizado não pode ser o mesmo da licença principal.';
    }
    final antigo = emailDocKey(substituindo);

    try {
      final db = FirebaseFirestore.instance;
      final userRef = db.collection('users').doc(uid);
      final userSnap = await userRef.get();
      final atuais = authorizedEmailsFrom(userSnap.data());
      if (atuais.contains(clean) && clean != antigo) {
        return 'Esse e-mail já está autorizado nesta licença.';
      }
      final restantes = atuais.where((e) => e != antigo && e != clean).toList();
      if (restantes.length >= maxAuthorizedEmails) {
        return 'Você já tem $maxAuthorizedEmails pessoas autorizadas. '
            'Remova uma para adicionar outra.';
      }

      final indexRef = db.collection('delegate_email_index').doc(clean);
      final existing = await indexRef.get();
      if (existing.exists) {
        final otherUid =
            (existing.data()?['principalUid'] as String?)?.trim() ?? '';
        if (otherUid.isNotEmpty && otherUid != uid) {
          return 'Este e-mail já está autorizado em outra conta.';
        }
      }

      String? delegateUidAntigo;
      if (antigo.isNotEmpty && antigo != clean) {
        delegateUidAntigo = await _delegateUidOf(antigo);
      }

      final novos = [...restantes, clean];
      final batch = db.batch();
      batch.set(userRef, {
        'authorizedDelegateEmails': novos,
        // O campo antigo continua com o primeiro da lista: o painel admin, as
        // functions e as versões antigas do app leem ele.
        'authorizedDelegateEmail': novos.first,
        'delegateSharingEnabled': true,
        'authorizedDelegateUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      batch.set(indexRef, {
        'principalUid': uid,
        'principalEmail': own,
        'active': true,
        'invitedAt': existing.exists
            ? (existing.data()?['invitedAt'] ?? FieldValue.serverTimestamp())
            : FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (antigo.isNotEmpty && antigo != clean) {
        // Só apagar: marcar `active: false` e apagar o mesmo documento no
        // mesmo lote é escrita dupla no mesmo caminho e derrubava o lote
        // inteiro (o e-mail NOVO ia junto).
        batch.delete(db.collection('delegate_email_index').doc(antigo));
      }
      await batch.commit();
      if (delegateUidAntigo != null) {
        unawaited(_removeDelegatePushTokens(uid, delegateUidAntigo));
      }
      return null;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return 'Sem permissão para salvar agora. Saia e entre de novo no app; '
            'se continuar, o e-mail pode já estar autorizado em outra conta.';
      }
      if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
        return 'Sem conexão com o servidor. Tente de novo em instantes.';
      }
      return 'Não consegui salvar o e-mail autorizado (${e.code}). Tente de novo.';
    } catch (_) {
      return 'Não foi possível salvar o e-mail autorizado. Tente de novo.';
    }
  }

  /// Tira UM e-mail da lista (e o acesso dele), mantendo os outros.
  static Future<String?> removeAuthorizedEmailFromList({
    required String principalUid,
    required String email,
  }) async {
    final uid = principalUid.trim();
    final alvo = emailDocKey(email);
    if (uid.isEmpty || alvo.isEmpty) return 'Sessão inválida.';
    try {
      final db = FirebaseFirestore.instance;
      final userRef = db.collection('users').doc(uid);
      final userSnap = await userRef.get();
      final restantes =
          authorizedEmailsFrom(userSnap.data()).where((e) => e != alvo).toList();
      final delegateUid = await _delegateUidOf(alvo);

      final batch = db.batch();
      batch.set(userRef, {
        'authorizedDelegateEmails': restantes,
        'authorizedDelegateEmail': restantes.isEmpty ? '' : restantes.first,
        'delegateSharingEnabled': restantes.isNotEmpty,
        'authorizedDelegateUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      batch.delete(db.collection('delegate_email_index').doc(alvo));
      await batch.commit();
      if (delegateUid != null) {
        unawaited(_removeDelegatePushTokens(uid, delegateUid));
      }
      return null;
    } on FirebaseException catch (e) {
      return 'Não consegui remover agora (${e.code}). Tente de novo.';
    } catch (_) {
      return 'Não foi possível remover. Tente de novo.';
    }
  }

  /// Painel admin: troca o primeiro e-mail (ou cadastra, se não houver).
  static Future<String?> saveAuthorizedEmail({
    required String principalUid,
    required String principalEmail,
    required String newEmail,
  }) async {
    final atuais = await loadAuthorizedEmails(principalUid);
    return saveAuthorizedEmailInList(
      principalUid: principalUid,
      principalEmail: principalEmail,
      newEmail: newEmail,
      substituindo: atuais.isEmpty ? '' : atuais.first,
    );
  }

  static Future<String?> _delegateUidOf(String email) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('delegate_email_index')
          .doc(emailDocKey(email))
          .get();
      final v = (snap.data()?['delegateUid'] ?? '').toString().trim();
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  /// O aparelho do sub-login grava o token de push na pasta do titular (é
  /// onde ele trabalha). Ao tirar o acesso, o push do titular não pode
  /// continuar chegando no celular de quem saiu.
  static Future<void> _removeDelegatePushTokens(
    String principalUid,
    String delegateUid,
  ) async {
    if (principalUid == delegateUid) return;
    final userRef =
        FirebaseFirestore.instance.collection('users').doc(principalUid);
    for (final sub in const ['fcmTokens', 'deviceTokens']) {
      try {
        final q = await userRef
            .collection(sub)
            .where('authUid', isEqualTo: delegateUid)
            .limit(20)
            .get();
        for (final d in q.docs) {
          await d.reference.delete();
        }
      } catch (_) {}
    }
  }

  /// Tira TODOS os e-mails autorizados (painel admin «Remover»).
  static Future<void> removeAuthorizedEmail(String principalUid) async {
    final emails = await loadAuthorizedEmails(principalUid);
    if (emails.isEmpty) {
      // Pode ter sobrado só o campo antigo vazio/inconsistente: limpa o perfil.
      await FirebaseFirestore.instance.collection('users').doc(principalUid).set({
        'authorizedDelegateEmails': <String>[],
        'authorizedDelegateEmail': '',
        'delegateSharingEnabled': false,
        'authorizedDelegateUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }
    for (final e in emails) {
      final erro = await removeAuthorizedEmailFromList(
        principalUid: principalUid,
        email: e,
      );
      if (erro != null) throw Exception(erro);
    }
  }
}

/// Situação de uma pessoa autorizada, vista pelo titular.
enum DelegateInviteStatus {
  /// Autorizado, mas a pessoa ainda não entrou no app com esse e-mail.
  pendente,

  /// Já entrou com o e-mail autorizado e está usando os dados da licença.
  ativo,

  /// Está na lista do titular, mas o índice de acesso não existe (gravação
  /// antiga que falhou pela metade). Reativar resolve.
  semAcesso,
}

class DelegateInvite {
  const DelegateInvite({
    required this.email,
    required this.status,
    this.acceptedAt,
    this.lastSeenAt,
  });

  final String email;
  final DelegateInviteStatus status;
  final DateTime? acceptedAt;
  final DateTime? lastSeenAt;
}
