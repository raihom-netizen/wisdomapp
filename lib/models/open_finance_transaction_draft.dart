import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/category_matcher.dart';
import '../utils/transaction_name_cleaner.dart';

/// Rascunho de lançamento a partir de JSON de agregador (Pluggy, Belvo, etc.) → `users/{uid}/transactions`.
class OpenFinanceTransactionDraft {
  final double amount;
  final DateTime date;
  final String description;
  final String category;
  final String type;
  final String? externalId;

  const OpenFinanceTransactionDraft({
    required this.amount,
    required this.date,
    required this.description,
    required this.category,
    this.type = 'expense',
    this.externalId,
  });

  /// Interpreta payload comum de APIs de transação (campos podem variar por provedor).
  factory OpenFinanceTransactionDraft.fromAggregatorJson(
    Map<String, dynamic> json, {
    String fallbackCategory = 'Outros',
  }) {
    final rawDesc = (json['description'] ??
            json['name'] ??
            json['title'] ??
            json['merchant']?['name'] ??
            '')
        .toString()
        .trim();
    final desc = TransactionNameCleaner.clean(rawDesc.isEmpty ? '' : rawDesc).trim();
    final descForCategory = desc.isEmpty ? rawDesc : desc;
    final cat = CategoryMatcher.autoCategorize(descForCategory, fallback: fallbackCategory);

    double amt = 0;
    final raw = json['amount'] ?? json['value'] ?? json['transactionAmount'];
    if (raw is num) {
      amt = raw.toDouble().abs();
    } else if (raw is String) {
      amt = double.tryParse(raw.replaceAll(',', '.'))?.abs() ?? 0;
    }

    DateTime dt = DateTime.now();
    final dateRaw = json['date'] ?? json['createdAt'] ?? json['postedAt'];
    if (dateRaw is String) {
      dt = DateTime.tryParse(dateRaw) ?? dt;
    } else if (dateRaw is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(dateRaw);
    }

    final tRaw = (json['type'] ?? json['operationType'] ?? 'DEBIT').toString().toLowerCase();
    final type = tRaw.contains('credit') || tRaw.contains('income') || tRaw.contains('deposit')
        ? 'income'
        : 'expense';

    final ext = (json['id'] ?? json['transactionId'] ?? json['pluggyTransactionId'])?.toString();

    return OpenFinanceTransactionDraft(
      amount: amt,
      date: dt,
      description: desc.isNotEmpty ? desc : (rawDesc.isNotEmpty ? rawDesc : 'Lançamento Open Finance'),
      category: cat,
      type: type,
      externalId: ext,
    );
  }

  Map<String, dynamic> toFirestoreMap({
    String? financeAccountId,
  }) {
    final ext = externalId?.trim() ?? '';
    return {
      'type': type,
      'amount': amount,
      'category': category,
      'description': description,
      'status': 'paid',
      'date': Timestamp.fromDate(date),
      'recurrence': 'none',
      'installmentCount': 1,
      'installmentIndex': 1,
      if (financeAccountId != null && financeAccountId.trim().isNotEmpty) 'financeAccountId': financeAccountId.trim(),
      if (ext.isNotEmpty) 'openFinanceExternalId': ext,
      'source': 'open_finance',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
