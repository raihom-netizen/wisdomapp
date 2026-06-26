import 'package:cloud_firestore/cloud_firestore.dart';

/// Lista principal do Financeiro com menos tráfego: consulta só com [where] em
/// [date], [type] e [status] (sem pesquisa livre, sem categoria, sem conta).
bool financeMainPeriodCanServerPage({
  required String searchLowerTrim,
  required String statusFilter,
  required String? categoryFilter,
  required String? financeAccountFilterId,
}) {
  if (searchLowerTrim.isNotEmpty) return false;
  final cat = categoryFilter?.trim() ?? '';
  if (cat.isNotEmpty) return false;
  final acc = financeAccountFilterId?.trim() ?? '';
  if (acc.isNotEmpty) return false;
  return statusFilter == 'all' || statusFilter == 'pending' || statusFilter == 'paid';
}

/// Query alinhada aos índices `transactions`: [type]+[date], [type]+[status]+[date], [status]+[date].
Query<Map<String, dynamic>> financeMainPeriodFirestoreQuery({
  required String sessionUid,
  required DateTime from,
  required DateTime to,
  required String statusFilter,
  required String typeFilter,
}) {
  final col = FirebaseFirestore.instance.collection('users').doc(sessionUid).collection('transactions');
  final start = Timestamp.fromDate(DateTime(from.year, from.month, from.day));
  final end = Timestamp.fromDate(DateTime(to.year, to.month, to.day, 23, 59, 59));
  Query<Map<String, dynamic>> q = col
      .where('date', isGreaterThanOrEqualTo: start)
      .where('date', isLessThanOrEqualTo: end);
  if (typeFilter == 'income') {
    q = q.where('type', isEqualTo: 'income');
  } else if (typeFilter == 'expense') {
    q = q.where('type', isEqualTo: 'expense');
  }
  if (statusFilter == 'pending') {
    q = q.where('status', isEqualTo: 'pending');
  } else if (statusFilter == 'paid') {
    q = q.where('status', isEqualTo: 'paid');
  }
  return q.orderBy('date', descending: false);
}
