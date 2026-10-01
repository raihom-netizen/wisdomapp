import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:controle_total_premium/services/admin_painel_geral_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final agora = DateTime(2026, 10, 1, 10);

  Map<String, dynamic> user({
    required String email,
    String plan = 'premium',
    DateTime? criado,
    DateTime? vence,
    String? partnership,
  }) =>
      {
        'email': email,
        'name': email.split('@').first,
        'plan': plan,
        'planStatus': 'active',
        'createdAt': Timestamp.fromDate(criado ?? DateTime(2025, 1, 1)),
        if (vence != null) 'licenseExpiresAt': Timestamp.fromDate(vence),
        if (partnership != null) 'partnershipId': partnership,
      };

  test('pagantes, cortesia, teste, previsão só de pagantes e P&L', () {
    final usuarios = [
      MapEntry('pagante', user(email: 'a@x.com', vence: DateTime(2026, 10, 20))),
      MapEntry('cortesia', user(email: 'b@x.com', vence: DateTime(2027, 1, 1))),
      MapEntry('teste', user(email: 'c@x.com', criado: DateTime(2026, 9, 28))),
      MapEntry('convenio',
          user(email: 'd@x.com', vence: DateTime(2027, 1, 1), partnership: 'p1')),
      MapEntry('vencido', user(email: 'e@x.com', vence: DateTime(2026, 9, 20))),
      MapEntry('fantasma', {'plan': 'premium'}), // sem e-mail: ignorado
    ];
    final pagamentos = [
      AdminPagamento(
          valor: 30, data: DateTime(2026, 9, 20), pix: true, uid: 'pagante'),
      AdminPagamento(
          valor: 30, data: DateTime(2025, 12, 1), pix: false, email: 'e@x.com'),
    ];
    final d = AdminPainelGeralData.calcular(
      usuarios: usuarios,
      pagamentos: pagamentos,
      custos: const [AdminCusto(nome: 'Firebase', valorMensal: 40)],
      agora: agora,
    );

    expect(d.totalUsuarios, 5);
    expect(d.pagantes, 1);
    expect(d.cortesia, 1);
    expect(d.emTeste, 1);
    expect(d.convenio, 1);
    expect(d.naoRenovaram, 1); // vencido pagou antes e não renovou
    expect(d.novos7, 1);
    expect(d.mrr, 30);
    expect(d.previsao30, 30); // pagante vence em 20/10
    expect(d.receita30, 30);
    expect(d.receitaPorMes.length, 12);
    expect(d.receitaPorMes[10], 30); // setembro
    expect(d.custoMensal, 40);
    expect(d.resultadoUsuarios.single.uid, 'pagante');
    expect(d.resultadoUsuarios.single.liquido12m, closeTo(30 * (1 - kAdminTaxaPix), 0.001));
  });

  test('plano anual divide a receita recorrente por 12', () {
    final d = AdminPainelGeralData.calcular(
      usuarios: [
        MapEntry('u', user(email: 'a@x.com', vence: DateTime(2027, 9, 1))),
      ],
      pagamentos: [
        AdminPagamento(
            valor: 120,
            data: DateTime(2026, 9, 1),
            pix: true,
            uid: 'u',
            plano: 'premium_annual'),
      ],
      custos: const [],
      agora: agora,
    );
    expect(d.mrr, 10);
    expect(d.previsao30, 0);
  });
}
