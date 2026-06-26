import 'package:flutter/material.dart';

/// Faixa exibida no app (score 0–100).
enum FinanceHealthTier {
  saudavel,
  atencao,
  risco,
}

/// Score simples baseado no saldo do período (entrada − saída).
/// Referência: saldo alto → melhor nota; saldo negativo → risco.
int calcularScoreFinanceiro(double entrada, double saida) {
  final saldo = entrada - saida;
  if (saldo > 1000) return 90;
  if (saldo > 500) return 75;
  if (saldo > 0) return 60;
  return 30;
}

FinanceHealthTier tierFromScore(int score) {
  if (score >= 80) return FinanceHealthTier.saudavel;
  if (score >= 50) return FinanceHealthTier.atencao;
  return FinanceHealthTier.risco;
}

String labelFinanceHealthTier(FinanceHealthTier t) {
  switch (t) {
    case FinanceHealthTier.saudavel:
      return 'Saudável';
    case FinanceHealthTier.atencao:
      return 'Atenção';
    case FinanceHealthTier.risco:
      return 'Risco';
  }
}

String hintFinanceHealthTier(FinanceHealthTier t) {
  switch (t) {
    case FinanceHealthTier.saudavel:
      return 'Caixa do período favorável — mantenha hábito e reserva.';
    case FinanceHealthTier.atencao:
      return 'Monitore gastos fixos e categorias no topo.';
    case FinanceHealthTier.risco:
      return 'Despesas pressionam o período — revise prioridades.';
  }
}

Color colorFinanceHealthTier(FinanceHealthTier t) {
  switch (t) {
    case FinanceHealthTier.saudavel:
      return const Color(0xFF16A34A);
    case FinanceHealthTier.atencao:
      return const Color(0xFFD97706);
    case FinanceHealthTier.risco:
      return const Color(0xFFDC2626);
  }
}
