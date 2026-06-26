import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/promo_site_urls.dart';
import '../screens/payment_status_screen.dart';
import '../utils/pwa_install_helper.dart';
import '../utils/url_launcher_helper.dart';

/// Promoção exibida no site (divulgação / landing): só aparece se o admin marcar
/// [showOnDivulgacaoWeb] e a promoção estiver ativa, em vigência e com estoque.
class PublicDivulgacaoPromo {
  PublicDivulgacaoPromo({
    required this.id,
    required this.title,
    required this.durationDays,
    required this.planCode,
    this.priceBrl,
    required this.quantityTotal,
    required this.quantitySold,
    this.quantityMarketingDisplay,
    this.validUntil,
  });

  final String id;
  final String title;
  final int durationDays;
  final String planCode;
  final double? priceBrl;
  final int quantityTotal;
  final int quantitySold;
  final int? quantityMarketingDisplay;
  /// Fim da vigência configurado no Firestore (fim do dia local do timestamp).
  final DateTime? validUntil;

  int get remaining => (quantityTotal - quantitySold).clamp(0, quantityTotal);

  String get priceLabel {
    if (priceBrl != null) {
      final s = priceBrl!.toStringAsFixed(2).replaceAll('.', ',');
      return 'R\$ $s';
    }
    return 'Consulte o valor no checkout';
  }

  String get urgencyLine {
    final parts = <String>[];
    final m = quantityMarketingDisplay;
    if (m != null && m > 0) {
      parts.add('Restam $m vagas na divulgação (número da campanha).');
    }
    if (remaining <= 10 && remaining > 0) {
      parts.add('Limite real de vendas: $remaining vaga(s).');
    }
    final vu = validUntil;
    if (vu != null) {
      final d = vu;
      parts.add(
        'Válida até ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}.',
      );
    }
    if (parts.isEmpty) return 'Oferta por tempo limitado.';
    return parts.join(' ');
  }

  static bool _isEligible(Map<String, dynamic> m) {
    if (m['showOnDivulgacaoWeb'] != true) return false;
    if (m['active'] == false) return false;
    final total = (m['quantityTotal'] as num?)?.toInt() ?? 0;
    final sold = (m['quantitySold'] as num?)?.toInt() ?? 0;
    if (total < 1 || sold >= total) return false;
    final now = DateTime.now();
    final vf = m['validFrom'] as Timestamp?;
    final vu = m['validUntil'] as Timestamp?;
    if (vf != null) {
      final from = DateTime(vf.toDate().year, vf.toDate().month, vf.toDate().day);
      if (now.isBefore(from)) return false;
    }
    if (vu != null) {
      final until = vu.toDate();
      if (now.isAfter(until)) return false;
    }
    return true;
  }

  static PublicDivulgacaoPromo? _fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    if (m == null || !_isEligible(m)) return null;
    final mkt = (m['quantityMarketingDisplay'] as num?)?.toInt();
    final vu = m['validUntil'] as Timestamp?;
    return PublicDivulgacaoPromo(
      id: d.id,
      title: (m['title'] ?? 'Promoção').toString(),
      durationDays: (m['durationDays'] as num?)?.toInt() ?? 30,
      planCode: (m['planCode'] ?? 'premium_monthly').toString(),
      priceBrl: (m['priceBrl'] as num?)?.toDouble(),
      quantityTotal: (m['quantityTotal'] as num?)?.toInt() ?? 0,
      quantitySold: (m['quantitySold'] as num?)?.toInt() ?? 0,
      quantityMarketingDisplay: (mkt != null && mkt > 0) ? mkt : null,
      validUntil: vu?.toDate(),
    );
  }

  /// Após validar o documento em [EscolhaPlanoPage] — mesmo shape do cartão público.
  factory PublicDivulgacaoPromo.fromLoadedPromotionDoc(String id, Map<String, dynamic> m) {
    final mkt = (m['quantityMarketingDisplay'] as num?)?.toInt();
    final vu = m['validUntil'] as Timestamp?;
    return PublicDivulgacaoPromo(
      id: id,
      title: (m['title'] ?? 'Promoção').toString(),
      durationDays: (m['durationDays'] as num?)?.toInt() ?? 30,
      planCode: (m['planCode'] ?? 'premium_monthly').toString(),
      priceBrl: (m['priceBrl'] as num?)?.toDouble(),
      quantityTotal: (m['quantityTotal'] as num?)?.toInt() ?? 0,
      quantitySold: (m['quantitySold'] as num?)?.toInt() ?? 0,
      quantityMarketingDisplay: (mkt != null && mkt > 0) ? mkt : null,
      validUntil: vu?.toDate(),
    );
  }

  /// Uma promoção pública: a mais recente por [createdAt] entre as elegíveis.
  static Stream<PublicDivulgacaoPromo?> watchFeatured() {
    return FirebaseFirestore.instance.collection('promotions').snapshots().map((snap) {
      PublicDivulgacaoPromo? best;
      Timestamp? bestTs;
      for (final d in snap.docs) {
        final p = _fromDoc(d);
        if (p == null) continue;
        final ca = d.data()?['createdAt'] as Timestamp?;
        if (best == null) {
          best = p;
          bestTs = ca;
          continue;
        }
        final cur = ca ?? Timestamp.fromMillisecondsSinceEpoch(0);
        final prev = bestTs ?? Timestamp.fromMillisecondsSinceEpoch(0);
        if (cur.compareTo(prev) > 0) {
          best = p;
          bestTs = ca;
        }
      }
      return best;
    });
  }
}

/// Cartão premium para landing, `/divulgacao`, app e web (PIX/cartão no app quando aplicável).
class DivulgacaoPublicPromoCard extends StatelessWidget {
  const DivulgacaoPublicPromoCard({super.key});

  static const Color _deep = Color(0xFF0B1220);
  static const Color _violet = Color(0xFF6366F1);
  static const Color _gold = Color(0xFFE8C547);

  void _onCta(BuildContext context, PublicDivulgacaoPromo promo) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final args = <String, dynamic>{
      'promoId': promo.id,
      'afterLoginRoute': '/escolha-plano',
      'openMpCheckoutAfterPromoLoad': true,
    };
    if (uid != null) {
      openPublicPromoMercadoPagoCheckout(context, promo);
      return;
    }
    Navigator.of(context).pushNamed('/login', arguments: args);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PublicDivulgacaoPromo?>(
      stream: PublicDivulgacaoPromo.watchFeatured(),
      builder: (context, snap) {
        final promo = snap.data;
        if (promo == null) return const SizedBox.shrink();
        // Safari iPhone/iPad: só mensagem + site (sem checkout MP na web móvel Apple).
        if (kIsWeb && isPwaIos) {
          final url = buildMaintenancePromoSiteUrl(
            promoFirestoreId: promo.id,
            source: 'safari_ios_landing_promo',
          );
          return Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  openPromoMaintenanceLink(url).catchError((_) {});
                },
                borderRadius: BorderRadius.circular(16),
                child: Ink(
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.deepPurple.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Promoção limitada',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.deepPurple.shade900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Toque para abrir o site oficial e ver os detalhes desta campanha.',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade800,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'wisdomapp-b9e98.web.app',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.underline,
                            color: Colors.indigo.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                colors: [_violet, const Color(0xFF7C3AED), _gold.withValues(alpha: 0.85)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(color: _violet.withValues(alpha: 0.35), blurRadius: 28, offset: const Offset(0, 14)),
              ],
            ),
            padding: const EdgeInsets.all(2),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: Colors.white.withValues(alpha: 0.98),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _gold.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'PROMO ATIVA',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                            color: _deep,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.bolt_rounded, color: _violet, size: 28),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    promo.title,
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      color: _deep,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${promo.priceLabel} · +${promo.durationDays} dias de licença após pagamento aprovado',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    promo.urgencyLine,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _violet,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: () => _onCta(context, promo),
                      style: FilledButton.styleFrom(
                        backgroundColor: _deep,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: Text(
                        FirebaseAuth.instance.currentUser != null
                            ? 'Pagar com esta promoção'
                            : 'Entrar e aproveitar — PIX ou cartão',
                        style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Novos e clientes: mesma conta. PIX ou cartão com Mercado Pago no app ou na web — a licença fica na sua conta.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600, height: 1.35),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

String normalizePlanCodeForMpCheckout(String? raw) {
  final s = (raw ?? 'premium_monthly').toLowerCase().trim();
  const valid = {'premium_monthly', 'premium_annual'};
  if (valid.contains(s)) return s;
  if (s.contains('annual') || s.contains('yearly') || s.contains('anual')) {
    return 'premium_annual';
  }
  return 'premium_monthly';
}

/// Escolhe PIX ou cartão e abre [CheckoutScreen] (Mercado Pago + webhook → licença).
void openPublicPromoMercadoPagoCheckout(BuildContext context, PublicDivulgacaoPromo promo) {
  final plan = normalizePlanCodeForMpCheckout(promo.planCode);
  final bottomPadding = MediaQuery.paddingOf(context).bottom;
  const slate800 = Color(0xFF1e293b);
  const blue600 = Color(0xFF2563eb);
  const slate400 = Color(0xFF94a3b8);

  void pushCheckout(String method) {
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CheckoutScreen(
          initialPlanCode: plan,
          initialPromoId: promo.id,
          paymentMethod: method,
        ),
      ),
    );
  }

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF0f172a),
    isDismissible: true,
    enableDrag: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      top: false,
      bottom: true,
      left: true,
      right: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Pagamento — Mercado Pago',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              promo.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            Material(
              color: slate800,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    pushCheckout('pix');
                  });
                },
                borderRadius: BorderRadius.circular(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Row(
                      children: [
                        Icon(Icons.qr_code_2_rounded, color: blue600, size: 28),
                        SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'PIX',
                            style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded, size: 14, color: slate400),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Material(
              color: slate800,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    pushCheckout('cartao');
                  });
                },
                borderRadius: BorderRadius.circular(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Row(
                      children: [
                        Icon(Icons.credit_card_rounded, color: blue600, size: 28),
                        SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'Cartão de crédito',
                            style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded, size: 14, color: slate400),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Agora não',
                style: TextStyle(color: slate400, fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    ),
  ).whenComplete(() {
    // Web/Safari: às vezes o foco ou hit-test ficam presos após fechar o sheet sem pagar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
    });
  });
}
