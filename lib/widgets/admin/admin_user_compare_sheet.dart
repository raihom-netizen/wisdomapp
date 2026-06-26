import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Compara dois utilizadores lado a lado.
Future<void> showAdminUserCompareSheet(
  BuildContext context, {
  required String uidA,
  required String uidB,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scroll) => _CompareBody(
        scrollController: scroll,
        uidA: uidA,
        uidB: uidB,
      ),
    ),
  );
}

class _CompareBody extends StatelessWidget {
  final ScrollController scrollController;
  final String uidA;
  final String uidB;

  const _CompareBody({
    required this.scrollController,
    required this.uidA,
    required this.uidB,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: FutureBuilder<List<Map<String, dynamic>?>>(
        future: Future.wait([
          _load(uidA),
          _load(uidB),
        ]),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final a = snap.data![0];
          final b = snap.data![1];
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Comparar utilizadores',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              _row('Nome', _v(a, 'name'), _v(b, 'name')),
              _row('E-mail', _v(a, 'email'), _v(b, 'email')),
              _row('Plano', _plan(a), _plan(b)),
              _row('Vencimento', _exp(a), _exp(b)),
              _row('Convênio', _v(a, 'partnershipId'), _v(b, 'partnershipId')),
              _row('App', _v(a, 'app'), _v(b, 'app')),
              _row('Status', _v(a, 'status'), _v(b, 'status')),
              _row('UID', uidA, uidB),
            ],
          );
        },
      ),
    );
  }

  Future<Map<String, dynamic>?> _load(String uid) async {
    final snap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    return snap.data();
  }

  String _v(Map<String, dynamic>? m, String key) =>
      (m?[key] ?? '—').toString().trim().isEmpty ? '—' : (m![key]).toString();

  String _plan(Map<String, dynamic>? m) =>
      _v(m, 'plan').replaceAll('—', '') == ''
          ? _v(m, 'licensePlan')
          : _v(m, 'plan');

  String _exp(Map<String, dynamic>? m) {
    final ts = m?['licenseExpiresAt'];
    if (ts is Timestamp) {
      return DateFormat('dd/MM/yyyy').format(ts.toDate());
    }
    return '—';
  }

  Widget _row(String label, String left, String right) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _cell(left)),
              const SizedBox(width: 8),
              Expanded(child: _cell(right)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cell(String text) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(text, style: const TextStyle(fontSize: 13)),
    );
  }
}
