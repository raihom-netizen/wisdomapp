import 'package:cloud_firestore/cloud_firestore.dart';

/// Entrada de histórico administrativo para um utilizador.
class AdminAuditEntry {
  final String id;
  final String action;
  final String adminEmail;
  final String details;
  final DateTime? at;

  const AdminAuditEntry({
    required this.id,
    required this.action,
    required this.adminEmail,
    required this.details,
    this.at,
  });
}

/// Consulta `admin_audit_log` filtrado por utilizador alvo.
class AdminAuditQueryService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<AdminAuditEntry>> watchForUser(String targetUserId, {int limit = 50}) {
    if (targetUserId.trim().isEmpty) {
      return Stream.value(const []);
    }
    return _db
        .collection('admin_audit_log')
        .where('targetUserId', isEqualTo: targetUserId)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) {
        final data = d.data();
        final ts = data['timestamp'];
        DateTime? at;
        if (ts is Timestamp) at = ts.toDate();
        return AdminAuditEntry(
          id: d.id,
          action: (data['action'] ?? '').toString(),
          adminEmail: (data['adminEmail'] ?? '').toString(),
          details: (data['details'] ?? '').toString(),
          at: at,
        );
      }).toList();
      list.sort((a, b) {
        final ta = a.at ?? DateTime.fromMillisecondsSinceEpoch(0);
        final tb = b.at ?? DateTime.fromMillisecondsSinceEpoch(0);
        return tb.compareTo(ta);
      });
      return list;
    });
  }
}
