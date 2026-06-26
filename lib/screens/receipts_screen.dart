import 'dart:async';

import 'package:flutter/material.dart' hide showDatePicker;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import '../models/user_profile.dart';
import '../utils/url_launcher_helper.dart';
import '../theme/app_colors.dart';
import '../utils/date_picker_a11y.dart';
import '../utils/firestore_user_doc_id.dart';

class ReceiptsScreen extends StatefulWidget {
  final String uid;
  final UserProfile profile;
  const ReceiptsScreen({super.key, required this.uid, required this.profile});

  @override
  State<ReceiptsScreen> createState() => _ReceiptsScreenState();
}

class _ReceiptsScreenState extends State<ReceiptsScreen> {
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day - 30);
  DateTime _to = DateTime.now();
  StreamSubscription<fa.User?>? _authUidSub;

  @override
  void initState() {
    super.initState();
    _authUidSub = fa.FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _authUidSub?.cancel();
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>> _txRef() =>
      FirebaseFirestore.instance.collection('users').doc(firestoreUserDocIdForAppShell(widget.uid)).collection('transactions');

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _from = picked);
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _to = picked);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.profile.temAcessoPremium && !widget.profile.isAdmin) {
      return const Scaffold(
        body: SafeArea(child: Center(child: Text('Assine o plano para acessar os comprovantes.'))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Voltar',
              )
            : null,
        title: const Text('Comprovantes'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [AppColors.deepBlueDark, AppColors.deepBlue, AppColors.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(color: AppColors.deepBlueDark.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 10)),
              ],
            ),
            child: Row(
              children: [
                Image.asset('assets/images/icon.png', height: 32, width: 32, errorBuilder: (_, __, ___) => const Icon(Icons.apps_rounded, color: Colors.white, size: 32)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Comprovantes Premium',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                ),
                const Icon(Icons.receipt_long, color: Colors.white),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: OutlinedButton.icon(onPressed: _pickFrom, icon: const Icon(Icons.date_range), label: const Text('De'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: _pickTo, icon: const Icon(Icons.event), label: const Text('Até'))),
            ],
          ),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _txRef()
                .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(_from))
                .where('date', isLessThanOrEqualTo: Timestamp.fromDate(_to))
                .orderBy('date', descending: true)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs.where((d) {
                final m = d.data();
                return m['hasReceipt'] == true || m.containsKey('receipt');
              }).toList();
              if (docs.isEmpty) return const Center(child: Text('Nenhum comprovante no período.'));

              return Column(
                children: docs.map((doc) {
                      if (doc == docs.first) {
                        return Column(
                          children: [
                            Card(
                              child: ListTile(
                                leading: const Icon(Icons.analytics),
                                title: Text('Total de comprovantes: ${docs.length}'),
                                subtitle: const Text('Arquivos enviados no período selecionado.'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _ReceiptItem(doc: doc),
                          ],
                        );
                      }
                      return _ReceiptItem(doc: doc);
                }).toList(),
              );
            },
          ),
        ],
        ),
      ),
    );
  }
}

class _ReceiptItem extends StatelessWidget {
  final DocumentSnapshot<Map<String, dynamic>> doc;
  const _ReceiptItem({required this.doc});

  @override
  Widget build(BuildContext context) {
    final data = doc.data() ?? {};
    final receipt = Map<String, dynamic>.from(data['receipt'] ?? {});
    final name = (receipt['name'] ?? receipt['originalName'] ?? 'Comprovante').toString();
    final link = (receipt['downloadUrl'] ?? receipt['webViewLink'] ?? receipt['webContentLink'] ?? '').toString();
    final date = (data['date'] as Timestamp?)?.toDate();

    return Card(
      child: ListTile(
        leading: const Icon(Icons.receipt_long),
        title: Text(name),
        subtitle: Text(date == null ? '' : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}'),
        trailing: link.isEmpty
            ? const Icon(Icons.link_off)
            : IconButton(
                icon: const Icon(Icons.open_in_new),
                onPressed: () async {
                  if (link.isEmpty) return;
                  try {
                    await openUrlPreferChrome(link);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível abrir o link.')));
                    }
                  }
                },
              ),
      ),
    );
  }
}
