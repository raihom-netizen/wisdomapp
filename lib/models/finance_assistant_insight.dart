import 'package:flutter/material.dart';

/// Insight visual do assistente financeiro (alerta ou análise automática).
class FinanceAssistantInsight {
  const FinanceAssistantInsight({
    required this.title,
    required this.body,
    required this.icon,
    required this.accentColor,
    this.kind = FinanceAssistantInsightKind.info,
  });

  final String title;
  final String body;
  final IconData icon;
  final Color accentColor;
  final FinanceAssistantInsightKind kind;
}

enum FinanceAssistantInsightKind { warning, success, info, trend }
