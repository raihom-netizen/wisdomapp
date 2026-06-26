import 'package:flutter_test/flutter_test.dart';

import 'package:controle_total_premium/models/user_profile.dart';

void main() {
  final baseActive = UserProfile(
    uid: 'u1',
    cpf: '',
    cpfMasked: '',
    email: 'user@exemplo.com',
    name: 'User',
    role: 'user',
    plan: 'premium',
    planStatus: 'active',
    licenseExpiresAt: _licenseOk,
    createdAt: _created,
  );

  group('Compatibilidade Premium (plano legado no Firestore)', () {
    test('plano premium sem flags PRO: continua premium; Open Finance desligado', () {
      expect(baseActive.isPremium, isTrue);
      expect(baseActive.hasPremiumProEntitlement, isFalse);
      expect(baseActive.canUseOpenFinanceBanks, isFalse);
      expect(baseActive.isPartnershipOrAssegoRetailTier, isFalse);
    });

    test('plano premium_pro: continua premium; rótulo UI = Premium; Open Finance desligado', () {
      final p = UserProfile(
        uid: 'u1',
        cpf: '',
        cpfMasked: '',
        email: 'user@exemplo.com',
        name: 'User',
        role: 'user',
        plan: 'premium_pro',
        planStatus: 'active',
        licenseExpiresAt: _licenseOk,
        createdAt: _created,
      );
      expect(p.isPremium, isTrue);
      expect(p.hasPremiumProEntitlement, isFalse);
      expect(p.canUseOpenFinanceBanks, isFalse);
      expect(UserProfile.planDisplayLabelForFirestorePlan('premium_pro'), 'Premium');
      expect(UserProfile.planDisplayLabelForPublicAppUi('premium_pro'), 'Premium');
    });

    test('app/divulgação: convênios mostram só «Premium»; Admin mantém rótulo detalhado', () {
      expect(UserProfile.planDisplayLabelForPublicAppUi('premium_assego'), 'Premium');
      expect(UserProfile.planDisplayLabelForPublicAppUi('premium_unimil'), 'Premium');
      expect(UserProfile.planDisplayLabelForPublicAppUi('premium_foo_bar'), 'Premium');
      expect(UserProfile.planDisplayLabelForFirestorePlan('premium_assego'), 'Premium ASSEGO');
      expect(UserProfile.planDisplayLabelForFirestorePlan('premium_unimil'), 'Premium Unimil');
    });

    test('convênio com plano premium: sem open finance até migrar a plan', () {
      final p = UserProfile(
        uid: 'u1',
        cpf: '',
        cpfMasked: '',
        email: 'user@exemplo.com',
        name: 'User',
        role: 'user',
        plan: 'premium',
        planStatus: 'active',
        licenseExpiresAt: _licenseOk,
        createdAt: _created,
        partnershipId: 'p1',
      );
      expect(p.isPartnershipOrAssegoRetailTier, isTrue);
      expect(p.hasPremiumProEntitlement, isFalse);
      expect(p.canUseOpenFinanceBanks, isFalse);
    });

    test('convênio com premium_pro: convênio reconhecido; Open Finance desligado', () {
      final p = UserProfile(
        uid: 'u1',
        cpf: '',
        cpfMasked: '',
        email: 'user@exemplo.com',
        name: 'User',
        role: 'user',
        plan: 'premium_pro',
        planStatus: 'active',
        licenseExpiresAt: _licenseOk,
        createdAt: _created,
        partnershipId: 'p1',
      );
      expect(p.isPartnershipOrAssegoRetailTier, isTrue);
      expect(p.canUseOpenFinanceBanks, isFalse);
    });
  });
}

final _licenseOk = DateTime(2035, 6, 1);
final _created = DateTime(2020, 1, 1);
