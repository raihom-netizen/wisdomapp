import 'package:flutter_test/flutter_test.dart';
import 'package:controle_total_premium/models/landing_public_content.dart';
import 'package:controle_total_premium/services/mp_checkout_pricing_service.dart';

void main() {
  group('landing_defaults — fonte única', () {
    test('toda chave das seções do editor tem campo com padrão', () {
      for (final s in kLandingEditorSections) {
        for (final k in s.keys) {
          expect(kLandingAllFieldsByKey.containsKey(k), isTrue,
              reason: 'seção ${s.id}: chave $k sem LandingFieldDef');
        }
      }
    });

    test('nenhuma chave aparece em duas seções', () {
      final seen = <String, String>{};
      for (final s in kLandingEditorSections) {
        for (final k in s.keys) {
          expect(seen.containsKey(k), isFalse,
              reason: '$k está em ${seen[k]} e em ${s.id}');
          seen[k] = s.id;
        }
      }
    });

    test('todo campo editável aparece em alguma seção do editor', () {
      final inSections = <String>{
        for (final s in kLandingEditorSections) ...s.keys,
      };
      final missing = kLandingAllFieldsByKey.keys
          .where((k) => !inSections.contains(k))
          .toList();
      expect(missing, isEmpty, reason: 'fora do editor: $missing');
    });

    test('página sem Firestore mostra exatamente o padrão do editor', () {
      final c = LandingPublicContent.initial();
      expect(c.t('homeModulesTitle'), landingDefaultFor('homeModulesTitle'));
      expect(c.t('siteExpressTitle'), 'Login expresso');
      expect(c.heroSubtitle, landingDefaultFor('heroSubtitle'));
      expect(c.divHeroBadge, landingDefaultFor('divHeroBadge'));
    });

    test('Firestore vazio/branco cai no padrão; preenchido vale', () {
      final c = LandingPublicContent.fromMap({
        'homeModulesTitle': '   ',
        'homeQuoteAuthor': '— Autor novo',
      }).applyPremiumTextsFromCheckoutPricing(
          MpCheckoutPricingSnapshot.defaults());
      expect(c.t('homeModulesTitle'), landingDefaultFor('homeModulesTitle'));
      expect(c.t('homeQuoteAuthor'), '— Autor novo');
    });
  });

  group('preços — mesmo doc em tudo', () {
    final p =
        MpCheckoutPricingSnapshot(premiumMonthly: 59.9, premiumAnnual: 599.0);

    test('marcadores trocam pelo preço atual', () {
      expect(
        landingFillPlaceholders('{premium_mensal} ou {premium_anual}', p),
        r'R$ 59,90 ou R$ 599,00',
      );
      expect(landingFillPlaceholders('{premium_anual_mes}', p), r'R$ 49,91');
    });

    test('linhas de valor e parágrafos seguem o preço do checkout', () {
      final c = LandingPublicContent.fromMap({
        'divPremiumMensal': r'R$ 1,00/mês',
        'landingPremiumDetail': 'Só {premium_mensal} por mês',
        'landingPremiumCardPeriod': r'Antigo R$ 49,90',
        'divPlanosSubtitle': 'Sem preço aqui',
        'divPremiumBeneficios': 'A, B, C',
      }).applyPremiumTextsFromCheckoutPricing(p);
      expect(c.divPremiumMensal, r'R$ 59,90/mês');
      expect(c.landingPremiumDetail, r'Só R$ 59,90 por mês');
      expect(c.landingPremiumCardPeriod, contains(r'R$ 49,91'));
      expect(c.divPlanosSubtitle, 'Sem preço aqui');
      expect(c.divPremiumBeneficiosList, ['A', 'B', 'C']);
    });

    test('padrão da home usa o preço (não fica preso em texto fixo)', () {
      final c = LandingPublicContent.fromMap(null)
          .applyPremiumTextsFromCheckoutPricing(p);
      expect(c.landingPremiumDetail, contains(r'R$ 59,90'));
      expect(c.homePremiumCombinedPriceLine, contains(r'R$ 599,00'));
    });
  });
}
