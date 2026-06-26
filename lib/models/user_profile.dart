import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

import '../constants/admin_gestor_config.dart';
import '../constants/admin_partner_config.dart';

class UserProfile {
  final String uid;
  final String cpf;
  final String cpfMasked;
  final String email;
  final String name;
  final String role; // admin / master (acesso painel) / user
  final String plan; // free | premium | premium_assego | premium_pro (+ legados basic/master só leitura)
  final String planStatus; // active/canceled/past_due
  /// Data de validade da licença (trial ou paga). null = sem limite (ex.: free sem trial).
  final DateTime? licenseExpiresAt;
  /// Data de criação da conta. Alinhado a [newUserTrialDays] (fallback de acesso).
  final DateTime? createdAt;

  /// Dias de teste grátis a partir do cadastro (APK, AAB, iOS, web). Textos de divulgação (landing, planos, etc.) e `licenseExpiresAt` na criação devem seguir este valor (site: meta em `web/index.html`).
  static const int newUserTrialDays = 30;
  /// false = cadastro rápido; usuário pode completar dados depois (ex.: CPF).
  final bool profileComplete;

  /// Leitura legada do Firestore (Open Finance desativado no app).
  final bool premiumPro;
  final bool isPremiumPro;

  /// Convênio / cadastro por parceria (`users.partnershipId`).
  final String? partnershipId;

  /// Legado admin (conexões OF) — sem efeito enquanto Open Finance estiver desligado.
  final int? premiumProIncludedBankConnections;

  /// E-mail autorizado a acessar os dados desta licença (sub-login — um único e-mail).
  final String? authorizedDelegateEmail;

  const UserProfile({
    required this.uid,
    required this.cpf,
    required this.cpfMasked,
    required this.email,
    required this.name,
    required this.role,
    required this.plan,
    required this.planStatus,
    this.licenseExpiresAt,
    this.createdAt,
    this.profileComplete = true,
    this.premiumPro = false,
    this.isPremiumPro = false,
    this.partnershipId,
    this.premiumProIncludedBankConnections,
    this.authorizedDelegateEmail,
  });

  /// Normaliza o campo vindo do Firestore para [planStatus] interno: `active` | `canceled` | `past_due`.
  /// Dados de importação/Console às vezes têm `ativo` ou string vazia; sem isto o app trata como bloqueado.
  static String normalizePlanStatusFromFirestore(Object? value) {
    if (value == null) return 'active';
    final s = value.toString().trim().toLowerCase();
    if (s.isEmpty) return 'active';
    if (s == 'active' ||
        s == 'ativo' ||
        s == 'ativa' ||
        s == 'trialing' ||
        s == 'em_teste' ||
        s == 'em teste' ||
        s == 'paid' ||
        s == 'pago' ||
        s == 'paga' ||
        s == 'ok' ||
        s == 'valid' ||
        s == 'válido' ||
        s == 'valida' ||
        s == 'válida' ||
        s == 'on' ||
        s == 'enabled' ||
        s == 'habilitado' ||
        s == 'habilitada' ||
        s == 'succeeded' ||
        s == 'complete' ||
        s == 'concluido' ||
        s == 'concluído' ||
        s == 'em dia') {
      return 'active';
    }
    if (s == 'canceled' ||
        s == 'cancelled' ||
        s == 'cancelado' ||
        s == 'cancelada' ||
        s == 'churn' ||
        s == 'ended') {
      return 'canceled';
    }
    if (s == 'past_due' ||
        s == 'past due' ||
        s == 'pastdue' ||
        s == 'vencido' ||
        s == 'vencida' ||
        s == 'overdue' ||
        s == 'inadimplente' ||
        s == 'suspended' ||
        s == 'suspenso' ||
        s == 'suspensa') {
      return 'past_due';
    }
    return s;
  }

  /// Leitura única do documento `users/{uid}` — **mesma regra** que [FirestoreService.watchProfile]
  /// (evita duplicar parse e bugs entre streams e checagens de Open Finance).
  factory UserProfile.fromFirestoreMap(String uid, Map<String, dynamic> d) {
    DateTime? licenseExpiresAt;
    final exp = d['licenseExpiresAt'];
    if (exp is Timestamp) {
      licenseExpiresAt = exp.toDate();
    } else if (exp is String) {
      licenseExpiresAt = DateTime.tryParse(exp);
    }
    final createdAt =
        d['createdAt'] is Timestamp ? (d['createdAt'] as Timestamp).toDate() : null;
    final rawPid = d['partnershipId'];
    final partnershipId = rawPid == null || rawPid.toString().trim().isEmpty
        ? null
        : rawPid.toString().trim();
    int? proSlots;
    final rawSlots = d['premiumProIncludedBankConnections'];
    if (rawSlots is int) {
      proSlots = rawSlots;
    } else if (rawSlots is num) {
      proSlots = rawSlots.round();
    }
    final rawDelegate = d['authorizedDelegateEmail'];
    final authorizedDelegateEmail =
        rawDelegate == null || rawDelegate.toString().trim().isEmpty
            ? null
            : rawDelegate.toString().trim().toLowerCase();
    return UserProfile(
      uid: uid,
      cpf: (d['cpf'] ?? '') as String,
      cpfMasked: (d['cpfMasked'] ?? '') as String,
      email: (d['email'] ?? '') as String,
      name: (d['name'] ?? '') as String,
      role: (d['role'] ?? 'user') as String,
      plan: (d['plan'] ?? 'premium').toString().trim().toLowerCase(),
      planStatus: normalizePlanStatusFromFirestore(d['planStatus'] ?? d['statusAssinatura'] ?? d['status']),
      licenseExpiresAt: licenseExpiresAt,
      createdAt: createdAt,
      profileComplete: d['profileComplete'] != false,
      premiumPro: d['premiumPro'] == true,
      isPremiumPro: d['isPremiumPro'] == true,
      partnershipId: partnershipId,
      premiumProIncludedBankConnections: proSlots,
      authorizedDelegateEmail: authorizedDelegateEmail,
    );
  }

  /// `premium_pro` ou códigos de checkout `premium_pro_*` no Firestore.
  static bool planIndicatesPremiumPro(String plan) {
    final p = plan.trim().toLowerCase();
    if (p.isEmpty) return false;
    if (p == 'premium_pro') return true;
    return p.startsWith('premium_pro_');
  }

  /// Plano legado no Firestore; integração automática a bancos descontinuada no app (sempre false).
  bool get hasPremiumProEntitlement => false;

  /// Convênio ativo ou plano ASSEGO laboratorial — mesmo pacote comercial do Premium.
  bool get isPartnershipOrAssegoRetailTier {
    final pid = partnershipId?.trim();
    if (pid != null && pid.isNotEmpty) return true;
    return plan.trim().toLowerCase() == 'premium_assego';
  }

  /// Open Finance (Pluggy) desativado: não exibir nem usar conexões bancárias automáticas.
  bool get canUseOpenFinanceBanks => false;

  /// Acesso total ao painel admin: role admin ou master.
  bool get isAdmin => role == 'admin' || role == 'master';

  /// Gestor de conteúdo — menu limitado (dicas, cursos, landing/divulgação).
  bool get isGestor =>
      AdminGestorConfig.isGestorAccount(role: role, email: email);

  /// Sócio — painel financeiro/usuários somente leitura.
  bool get isPartner =>
      AdminPartnerConfig.isPartnerAccount(role: role, email: email);

  /// Pode abrir o Painel Admin (admin completo, gestor ou sócio).
  bool get canAccessAdminPanel => isAdmin || isGestor || isPartner;

  /// Novo usuário: criado há menos de [newUserTrialDays] dias — recebe acesso total (trial / rede de segurança).
  bool get isNewUserTrial {
    if (createdAt == null) return false;
    return DateTime.now().difference(createdAt!).inDays < newUserTrialDays;
  }
  /// Quem adquire o plano tem acesso total (app, web e comprovantes). Inclui convênio ASSEGO (`premium_assego`).
  /// [plan] do Firestore pode variar em maiúsculas (import CSV, Console).
  bool get isPremium {
    final p = plan.trim().toLowerCase();
    if (UserProfile.planIndicatesPremiumPro(p)) return true;
    if (p == 'premium' ||
        p == 'premium_monthly' ||
        p == 'premium_annual') {
      return true;
    }
    if (p == 'premium_assego') return true;
    // Convênios com código próprio (ex.: premium_unimil) — não confundir com premium_pro*.
    if (p.startsWith('premium_') && !p.startsWith('premium_pro')) return true;
    return false;
  }

  bool get isFree => plan.trim().toLowerCase() == 'free';

  /// Plano pago unificado para **app** e **site de divulgação**: sempre «Premium», sem expor código de convênio.
  /// Painel Admin usa [planDisplayLabelForFirestorePlan].
  static bool _planIndicatesPublicPremiumTier(String plan) {
    final p = plan.trim().toLowerCase();
    if (planIndicatesPremiumPro(p)) return true;
    if (p == 'premium' ||
        p == 'premium_monthly' ||
        p == 'premium_annual') {
      return true;
    }
    if (p == 'premium_assego') return true;
    if (p.startsWith('premium_') && !p.startsWith('premium_pro')) return true;
    return false;
  }

  /// Rótulo para menu do app, configurações e divulgação: **só** «Premium» para qualquer tier pago;
  /// convênios (ASSEGO, Unimil, etc.) aparecem detalhados só no Admin.
  static String planDisplayLabelForPublicAppUi(String plan) {
    final p = plan.trim().toLowerCase();
    if (p.isEmpty || p == 'free') return 'Grátis';
    if (_planIndicatesPublicPremiumTier(plan)) return 'Premium';
    return planDisplayLabelForFirestorePlan(plan);
  }

  /// Rótulo detalhado (painel Admin, auditoria): inclui convênio quando aplicável.
  static String planDisplayLabelForFirestorePlan(String plan) {
    final p = plan.trim().toLowerCase();
    if (p.isEmpty || p == 'free') return 'Grátis';
    if (UserProfile.planIndicatesPremiumPro(p)) return 'Premium';
    if (p == 'premium_assego') return 'Premium ASSEGO';
    if (p == 'premium_unimil') return 'Premium Unimil';
    switch (p) {
      case 'premium':
      case 'premium_monthly':
      case 'premium_annual':
        return 'Premium';
      default:
        if (p.startsWith('premium_pro')) return 'Premium';
        if (p.startsWith('premium_')) {
          final rest = p.substring('premium_'.length);
          if (rest.isEmpty) return 'Premium';
          final pretty = rest
              .split('_')
              .where((s) => s.isNotEmpty)
              .map((s) {
                if (s.length == 1) return s.toUpperCase();
                return '${s[0].toUpperCase()}${s.substring(1).toLowerCase()}';
              })
              .join(' ');
          return 'Premium $pretty';
        }
        return plan.isEmpty ? 'Plano' : plan;
    }
  }

  /// Rótulo no app para o utilizador: [planDisplayLabelForPublicAppUi] (sem nome de convênio).
  String get planDisplayLabelForUi =>
      UserProfile.planDisplayLabelForPublicAppUi(plan);

  /// Dias de carência após o vencimento para o usuário renovar (acesso total durante esse período).
  static const int licenseGracePeriodDays = 3;

  /// Compara apenas a data (dia) — licença vence ao fim do dia de vencimento.
  static bool isLicenseExpiredByDate(DateTime? expiresAt) {
    if (expiresAt == null) return false;
    final now = DateTime.now();
    final expDay = DateTime(expiresAt.year, expiresAt.month, expiresAt.day);
    final today = DateTime(now.year, now.month, now.day);
    return expDay.isBefore(today);
  }

  /// Licença ainda válida no dia de vencimento (válida o dia todo).
  static bool _isLicenseValidByDate(DateTime? expiresAt) {
    if (expiresAt == null) return true;
    final now = DateTime.now();
    final expDay = DateTime(expiresAt.year, expiresAt.month, expiresAt.day);
    final today = DateTime(now.year, now.month, now.day);
    return !expDay.isBefore(today);
  }

  /// Último dia da carência (dia do vencimento + 3 dias). Durante esse período o usuário ainda tem acesso.
  DateTime? get _graceEndDate {
    if (licenseExpiresAt == null) return null;
    final expDay = DateTime(licenseExpiresAt!.year, licenseExpiresAt!.month, licenseExpiresAt!.day);
    return expDay.add(const Duration(days: licenseGracePeriodDays));
  }

  /// True quando a licença venceu e já passou dos 3 dias de carência — bloqueio total (tela "Sistema vencido").
  bool get isPastGracePeriod {
    if (licenseExpiresAt == null || isAdmin) return false;
    final graceEnd = _graceEndDate!;
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    return today.isAfter(graceEnd);
  }

  /// True se está dentro dos 3 dias de carência (venceu mas ainda pode usar para renovar).
  bool get isInGracePeriod {
    if (licenseExpiresAt == null) return false;
    if (_isLicenseValidByDate(licenseExpiresAt)) return false;
    return !isPastGracePeriod;
  }

  /// Estado do acesso: ATIVO (dentro da validade), CARENCIA (3 dias após vencimento), BLOQUEADO (após carência).
  /// Usado para definir se os botões "Lançar", "Configurar" etc. aparecem ou não em Escalas, Plantões, Configurações.
  String get licenseAccessState {
    if (isAdmin) return 'ATIVO';
    if (isNewUserTrial) return 'ATIVO';
    if (isFree || planStatus != 'active') return 'BLOQUEADO';
    if (licenseExpiresAt == null) return 'ATIVO';
    if (isPastGracePeriod) return 'BLOQUEADO';
    if (isInGracePeriod) return 'CARENCIA';
    return 'ATIVO';
  }

  /// true = pode lançar/escalas/configurar. false = bloquear ações.
  bool get canLaunchOrConfigure => licenseAccessState != 'BLOQUEADO';

  /// Acesso completo: escalas, calculadora, lançamentos, app, web e comprovantes.
  /// Inclui trial [newUserTrialDays] dias, plano com licença ativa e os 3 dias de carência após o vencimento.
  bool get hasActiveLicense {
    if (isNewUserTrial) return true;
    if (isFree || planStatus != 'active') return false;
    if (licenseExpiresAt == null) return true;
    if (_isLicenseValidByDate(licenseExpiresAt)) return true;
    if (isInGracePeriod) return true;
    return false;
  }

  /// Em período de teste ([newUserTrialDays] dias) ou licença paga ainda válida.
  bool get isInTrialOrValidLicense => licenseExpiresAt != null && _isLicenseValidByDate(licenseExpiresAt);

  /// Licença existia mas já venceu (data no passado), sem considerar carência.
  bool get isLicenseExpired => isLicenseExpiredByDate(licenseExpiresAt);

  /// Acesso total (app, web e comprovantes): quem tem licença ativa (trial, plano pago dentro da validade ou em carência).
  /// Regras mantidas: vencimento, 3 dias de carência, bloqueio total após carência.
  bool get temAcessoPremium => hasActiveLicense;

  /// Verifica acesso total a partir de um mapa (ex.: Firestore). Quem tem licença ativa tem acesso total.
  static bool temAcessoPremiumFromMap(Map<String, dynamic> userData) {
    final p = (userData['plan'] ?? userData['plano'] ?? 'trial').toString().toLowerCase();
    final status = (userData['planStatus'] ?? userData['statusAssinatura'] ?? '').toString().toLowerCase();
    if (p == 'free') return false;
    if (status != 'active' && status != 'ativo') return false;
    final exp = userData['licenseExpiresAt'] ?? userData['dataExpiracao'];
    if (exp == null) return true;
    DateTime? dt;
    if (exp is DateTime) dt = exp;
    else if (exp is String) dt = DateTime.tryParse(exp);
    if (dt == null) return true;
    if (_isLicenseValidByDate(dt)) return true;
    // Dentro dos 3 dias de carência
    final expDay = DateTime(dt.year, dt.month, dt.day);
    final graceEnd = expDay.add(const Duration(days: licenseGracePeriodDays));
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    return !today.isAfter(graceEnd);
  }

  /// Serialização leve para [UserProfileStartupCache] (reabertura instantânea).
  Map<String, dynamic> toStartupCacheMap() {
    return {
      'cpf': cpf,
      'cpfMasked': cpfMasked,
      'email': email,
      'name': name,
      'role': role,
      'plan': plan,
      'planStatus': planStatus,
      'licenseExpiresAt': licenseExpiresAt?.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
      'profileComplete': profileComplete,
      'premiumPro': premiumPro,
      'isPremiumPro': isPremiumPro,
      'partnershipId': partnershipId,
      'premiumProIncludedBankConnections':
          premiumProIncludedBankConnections,
      'authorizedDelegateEmail': authorizedDelegateEmail,
    };
  }

  static DateTime? _dateFromStartupCache(Object? v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  factory UserProfile.fromStartupCacheMap(String uid, Map<String, dynamic> d) {
    final rawSlots = d['premiumProIncludedBankConnections'];
    int? proSlots;
    if (rawSlots is int) {
      proSlots = rawSlots;
    } else if (rawSlots is num) {
      proSlots = rawSlots.round();
    }
    final rawDelegate = d['authorizedDelegateEmail'];
    final authorizedDelegateEmail =
        rawDelegate == null || rawDelegate.toString().trim().isEmpty
            ? null
            : rawDelegate.toString().trim().toLowerCase();
    final rawPid = d['partnershipId'];
    final partnershipId = rawPid == null || rawPid.toString().trim().isEmpty
        ? null
        : rawPid.toString().trim();
    return UserProfile(
      uid: uid,
      cpf: (d['cpf'] ?? '') as String,
      cpfMasked: (d['cpfMasked'] ?? '') as String,
      email: (d['email'] ?? '') as String,
      name: (d['name'] ?? '') as String,
      role: (d['role'] ?? 'user') as String,
      plan: (d['plan'] ?? 'premium').toString().trim().toLowerCase(),
      planStatus: normalizePlanStatusFromFirestore(d['planStatus']),
      licenseExpiresAt: _dateFromStartupCache(d['licenseExpiresAt']),
      createdAt: _dateFromStartupCache(d['createdAt']),
      profileComplete: d['profileComplete'] != false,
      premiumPro: d['premiumPro'] == true,
      isPremiumPro: d['isPremiumPro'] == true,
      partnershipId: partnershipId,
      premiumProIncludedBankConnections: proSlots,
      authorizedDelegateEmail: authorizedDelegateEmail,
    );
  }
}
