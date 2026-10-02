import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Histórico de um lançamento: de onde veio, quando nasceu, se foi editado.
///
/// O que existia antes: uma auditoria global em `activity_logs` que grava
/// «Criou receita», sem o id do documento. Ou seja, era impossível olhar um
/// lançamento e saber a história dele — e é justamente aí que a dúvida
/// aparece («isso veio do banco ou eu digitei?», «quem mudou a categoria?»).
///
/// Nada de coleção nova: o documento já guarda `createdAt`, `updatedAt`,
/// `source`, `categoriaOrigem` e os carimbos da conciliação. O que faltava era
/// **ler isso e contar a história em português**.
class FinanceHistoricoItem {
  const FinanceHistoricoItem({
    required this.quando,
    required this.titulo,
    required this.detalhe,
    required this.icone,
    required this.cor,
  });

  /// `null` quando o evento existe mas não tem data (registro antigo).
  final DateTime? quando;
  final String titulo;
  final String detalhe;
  final IconData icone;
  final Color cor;
}

const _kVerde = Color(0xFF059669);
const _kAzul = Color(0xFF2563EB);
const _kRoxo = Color(0xFF7C3AED);
const _kAmbar = Color(0xFFB45309);
const _kCinza = Color(0xFF64748B);

DateTime? _data(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  final t = DateTime.tryParse('$v');
  return t;
}

String _t(dynamic v) => (v ?? '').toString().trim();

/// Como o lançamento nasceu, em português.
({String titulo, String detalhe, IconData icone, Color cor}) _origem(
    Map<String, dynamic> d) {
  final source = _t(d['source']);
  final externo = _t(d['openFinanceExternalId']);

  if (externo.isNotEmpty || source == 'open_finance') {
    return (
      titulo: 'Veio do banco',
      detalhe: 'Importado pelo Open Finance — você não precisou digitar.',
      icone: Icons.account_balance_rounded,
      cor: _kAzul,
    );
  }
  if (_t(d['vendaId']).isNotEmpty) {
    final quem = _t(d['vendaParceiroNome']);
    return (
      titulo: 'Nasceu de uma venda',
      detalhe: quem.isEmpty ? 'Lançado pelo módulo Vendas.' : 'Venda para $quem.',
      icone: Icons.shopping_bag_rounded,
      cor: _kVerde,
    );
  }
  if (_t(d['vehicleId']).isNotEmpty) {
    final v = _t(d['vehicleLabel']);
    return (
      titulo: 'Nasceu na frota',
      detalhe: v.isEmpty ? 'Lançado pelo módulo Veículos.' : 'Veículo $v.',
      icone: Icons.local_shipping_rounded,
      cor: _kAmbar,
    );
  }
  if (_t(d['juridicoProcessoId']).isNotEmpty || _t(d['juridicoDespesaId']).isNotEmpty) {
    return (
      titulo: 'Nasceu na advocacia',
      detalhe: 'Despesa ou honorário de processo.',
      icone: Icons.gavel_rounded,
      cor: _kRoxo,
    );
  }
  if (_t(d['scaleId']).isNotEmpty) {
    return (
      titulo: 'Nasceu na escala',
      detalhe: 'Valor do plantão.',
      icone: Icons.local_police_rounded,
      cor: _kAzul,
    );
  }
  if (_t(d['fixedExpenseId']).isNotEmpty || _t(d['fixedIncomeId']).isNotEmpty) {
    return (
      titulo: 'Conta fixa',
      detalhe: 'Gerado a partir de uma despesa ou receita fixa.',
      icone: Icons.repeat_rounded,
      cor: _kRoxo,
    );
  }
  if (source == 'telegram') {
    return (
      titulo: 'Lançado pelo Telegram',
      detalhe: 'Você mandou por texto ou áudio no bot.',
      icone: Icons.send_rounded,
      cor: _kAzul,
    );
  }
  if (d['createdByMagic'] == true) {
    return (
      titulo: 'Lançamento expresso',
      detalhe: 'Criado pelo atalho rápido do app.',
      icone: Icons.bolt_rounded,
      cor: _kAmbar,
    );
  }
  return (
    titulo: 'Você lançou',
    detalhe: 'Digitado no app.',
    icone: Icons.edit_rounded,
    cor: _kCinza,
  );
}

/// Monta a linha do tempo do lançamento, do mais antigo para o mais novo.
List<FinanceHistoricoItem> financeHistoricoDoLancamento(Map<String, dynamic> d) {
  final itens = <FinanceHistoricoItem>[];

  final o = _origem(d);
  itens.add(FinanceHistoricoItem(
    quando: _data(d['createdAt']),
    titulo: o.titulo,
    detalhe: o.detalhe,
    icone: o.icone,
    cor: o.cor,
  ));

  // Conciliação: o app reconheceu que o lançamento dele e o crédito do banco
  // são a mesma coisa — e por isso não criou um segundo igual.
  final conciliado = _data(d['conciliadoEm']) ?? _data(d['conciliadoComVendaEm']);
  if (conciliado != null || d['conciliadoAutomaticamente'] == true) {
    itens.add(FinanceHistoricoItem(
      quando: conciliado,
      titulo: 'Conferido no banco',
      detalhe: 'O extrato confirmou este lançamento — nada foi duplicado.',
      icone: Icons.verified_rounded,
      cor: _kVerde,
    ));
  }

  if (_t(d['categoriaOrigem']) == 'manual') {
    itens.add(FinanceHistoricoItem(
      quando: _data(d['updatedAt']),
      titulo: 'Categoria trocada por você',
      detalhe: 'Vale mais que o palpite do sistema: o histórico passa a usar '
          'a sua escolha nos próximos lançamentos desta mesma pessoa.',
      icone: Icons.touch_app_rounded,
      cor: _kCinza,
    ));
  } else if (_t(d['categoriaOrigem']) == 'historico') {
    itens.add(FinanceHistoricoItem(
      quando: _data(d['updatedAt']),
      titulo: 'Categoria como das outras vezes',
      detalhe: 'Repetiu o que você já tinha feito com o dinheiro desta mesma '
          'pessoa ou empresa.',
      icone: Icons.history_rounded,
      cor: const Color(0xFF0D9488),
    ));
  }

  final pago = _data(d['paidAt']);
  if (pago != null) {
    final baixa = _t(d['baixaAutomatica']);
    itens.add(FinanceHistoricoItem(
      quando: pago,
      titulo: _t(d['type']) == 'income' ? 'Recebido' : 'Pago',
      detalhe: switch (baixa) {
        'open_finance' => 'Baixa automática: o crédito apareceu no extrato.',
        'quitacao_automatica' => 'Baixa automática: o Pix do banco casou com esta venda.',
        'quitacao_escolhida' || 'vinculo_manual' => 'Baixa pelo crédito do banco escolhido.',
        'comprovante' => 'Baixa com comprovante.',
        'mercadopago' => 'Baixa automática pelo Mercado Pago.',
        _ => 'Marcado como quitado.',
      },
      icone: Icons.check_circle_rounded,
      cor: _kVerde,
    ));
  }

  // Edição só vira linha própria quando é depois da criação — senão todo
  // lançamento mostraria «editado» no segundo em que nasceu.
  final criado = _data(d['createdAt']);
  final alterado = _data(d['updatedAt']);
  if (alterado != null &&
      (criado == null || alterado.difference(criado).inSeconds > 90) &&
      _t(d['categoriaOrigem']) != 'manual') {
    itens.add(FinanceHistoricoItem(
      quando: alterado,
      titulo: 'Editado',
      detalhe: 'Algum campo foi alterado depois de criado.',
      icone: Icons.edit_note_rounded,
      cor: _kAmbar,
    ));
  }

  itens.sort((a, b) {
    final x = a.quando;
    final y = b.quando;
    if (x == null && y == null) return 0;
    if (x == null) return -1;
    if (y == null) return 1;
    return x.compareTo(y);
  });
  return itens;
}
