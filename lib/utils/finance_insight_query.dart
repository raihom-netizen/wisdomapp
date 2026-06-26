import 'package:cloud_firestore/cloud_firestore.dart';

import 'finance_transactions_realtime.dart';

/// Consulta leve para gráficos/preview (limite de docs — ultra rápido).
class FinanceInsightQuery {
  FinanceInsightQuery._();

  static const int kMaxDocsForCharts = 8000;

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> fetchPeriodDocs({
    required String uid,
    required DateTime from,
    required DateTime to,
    String statusFilter = 'all',
    String? financeAccountId,
  }) {
    return financePeriodMergedDocumentsCollect(
      uid: uid,
      from: from,
      to: to,
      statusFilter: statusFilter,
      financeAccountId: financeAccountId,
      pageSize: 400,
      maxDocuments: kMaxDocsForCharts,
    );
  }
}
