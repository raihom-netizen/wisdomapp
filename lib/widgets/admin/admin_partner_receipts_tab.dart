import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide showDatePicker;
import 'package:intl/intl.dart';

import '../../constants/app_brand.dart';
import '../../constants/app_business_rules.dart';
import '../../constants/currency_formats.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_picker_a11y.dart';
import '../../widgets/fast_text_field.dart';
import '../../widgets/module_header_premium.dart';
import 'admin_page_shell.dart';

/// Recebimentos Mercado Pago — somente a parte do sócio (read-only).
class AdminPartnerReceiptsTab extends StatefulWidget {
  const AdminPartnerReceiptsTab({super.key});

  @override
  State<AdminPartnerReceiptsTab> createState() =>
      _AdminPartnerReceiptsTabState();
}

class _AdminPartnerReceiptsTabState extends State<AdminPartnerReceiptsTab> {
  final _searchFilterCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _searchQuery = '';
  String _filterStatus = 'all';
  bool _orderByUser = false;
  DateTime _filterStart = DateTime.now().subtract(const Duration(days: 30));
  DateTime _filterEnd = DateTime.now();

  Map<String, String> _uidDisplayCache = {};
  String _uidDisplayCacheKey = '';
  Future<Map<String, String>>? _uidDisplayFuture;

  double _periodGross = 0;
  double _periodNet = 0;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchFilterCtrl.dispose();
    super.dispose();
  }

  void _ensureUserDisplayFuture(List<String> uids) {
    final key = uids.join('|');
    if (key == _uidDisplayCacheKey && _uidDisplayFuture != null) return;
    _uidDisplayCacheKey = key;
    if (uids.isEmpty) {
      _uidDisplayCache = {};
      _uidDisplayFuture = Future.value(_uidDisplayCache);
      return;
    }
    _uidDisplayFuture = _loadUserDisplayMap(uids).then((m) {
      _uidDisplayCache = m;
      return m;
    });
  }

  Future<Map<String, String>> _loadUserDisplayMap(List<String> uids) async {
    final unique = uids.where((s) => s.isNotEmpty).toSet().toList();
    if (unique.isEmpty) return {};
    final result = <String, String>{};
    const batchSize = 30;
    for (var i = 0; i < unique.length; i += batchSize) {
      final batch = unique.skip(i).take(batchSize).toList();
      final refs = batch
          .map((uid) => FirebaseFirestore.instance.collection('users').doc(uid))
          .toList();
      final snaps = await Future.wait(refs.map((r) => r.get()));
      for (var j = 0; j < batch.length; j++) {
        final d = snaps[j].data();
        if (d == null) continue;
        final name = (d['name'] ?? '').toString().trim();
        final email = (d['email'] ?? '').toString().trim();
        if (email.isNotEmpty) {
          result[batch[j]] = name.isNotEmpty ? '$name ($email)' : email;
        } else if (name.isNotEmpty) {
          result[batch[j]] = name;
        }
      }
    }
    return result;
  }

  static DateTime? _parseApprovedDate(Map<String, dynamic> d) {
    final raw = d['raw'];
    if (raw is! Map) return null;
    final v =
        raw['date_approved'] ?? raw['date_created'] ?? raw['date_last_updated'];
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  static String? _parseUserDisplay(Map<String, dynamic> d) {
    final raw = d['raw'];
    if (raw is! Map) return null;
    final payer = raw['payer'];
    if (payer is! Map) return null;
    final email = (payer['email'] ?? '').toString().trim();
    final name = (payer['first_name'] ?? payer['name'] ?? '').toString().trim();
    if (email.isNotEmpty) return name.isNotEmpty ? '$name ($email)' : email;
    return null;
  }

  static bool _isPartnerPayment(Map<String, dynamic> data) {
    final ownerLabel = (data['splitOwnerLabel'] ?? '').toString().toLowerCase();
    return ownerLabel.contains('johnathan') ||
        ownerLabel.contains('jhonathan') ||
        data['splitPartnerShareGross'] != null;
  }

  static double _partnerGross(Map<String, dynamic> data, double total) {
    final g = data['splitPartnerShareGross'];
    if (g is num && g > 0) return g.toDouble();
    final pct = data['splitPartnerSharePercent'];
    if (pct is num && pct > 0) return total * (pct / 100);
    return total * 0.5;
  }

  static double _partnerNet(Map<String, dynamic> data, double totalNet, double total) {
    final n = data['splitPartnerShareNet'];
    if (n is num && n > 0) return n.toDouble();
    final gross = _partnerGross(data, total);
    if (total <= 0) return gross;
    return totalNet * (gross / total);
  }

  void _recalcTotals(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    const taxaPix = 0.0099;
    const taxaCartao = 0.0499;
    var gross = 0.0;
    var net = 0.0;
    for (final d in docs) {
      final data = d.data();
      final raw = data['raw'];
      if (raw is! Map) continue;
      final amt = raw['transaction_amount'];
      final total = amt is num ? amt.toDouble() : 0.0;
      if (total <= 0) continue;
      final method =
          (raw['payment_method_id'] ?? '').toString().toLowerCase();
      final taxa = method == 'pix' ? taxaPix : taxaCartao;
      final totalNet = total * (1 - taxa);
      gross += _partnerGross(data, total);
      net += _partnerNet(data, totalNet, total);
    }
    if (mounted) {
      setState(() {
        _periodGross = gross;
        _periodNet = net;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: AdminPageShell.listPadding(context, top: 8),
      children: [
        ModuleHeaderPremium(
          title: 'Recebimentos · ${AppBrand.idealizerName}',
          icon: Icons.receipt_long_rounded,
          subtitle:
              'Somente sua parte (bruto e líquido). Visualização — sem edição de credenciais.',
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.accent.withValues(alpha: 0.15),
                AppColors.primary.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bruto no período',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700)),
                    Text(fmt.format(_periodGross),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
              Container(width: 1, height: 40, color: Colors.grey.shade300),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Líquido no período',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700)),
                    Text(fmt.format(_periodNet),
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: AppColors.success)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildPeriodRow(context),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FastTextField(
                controller: _searchFilterCtrl,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Buscar por e-mail ou nome',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: (_) {
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(
                    Duration(milliseconds: AppBusinessRules.searchDebounceMs),
                    () {
                      if (mounted) {
                        setState(
                            () => _searchQuery = _searchFilterCtrl.text.trim());
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _filterStatus,
              isDense: true,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Todos')),
                DropdownMenuItem(value: 'approved', child: Text('Aprovado')),
                DropdownMenuItem(value: 'cancelled', child: Text('Cancelado')),
              ],
              onChanged: (v) => setState(() => _filterStatus = v ?? 'all'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ChoiceChip(
              label: const Text('Mais recente'),
              selected: !_orderByUser,
              onSelected: (_) => setState(() => _orderByUser = false),
            ),
            const SizedBox(width: 6),
            ChoiceChip(
              label: const Text('Por usuário'),
              selected: _orderByUser,
              onSelected: (_) => setState(() => _orderByUser = true),
            ),
          ],
        ),
        const SizedBox(height: 16),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('mp_payments')
              .limit(500)
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Erro ao carregar pagamentos.',
                      style: TextStyle(color: Colors.grey.shade700)),
                ),
              );
            }
            if (!snap.hasData) {
              return const Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator()));
            }
            final startDay = DateTime(
                _filterStart.year, _filterStart.month, _filterStart.day);
            final endDay = DateTime(_filterEnd.year, _filterEnd.month,
                _filterEnd.day, 23, 59, 59);

            var docs = snap.data!.docs.where((d) {
              final data = d.data();
              if (data['isOutgoing'] == true) return false;
              if (!_isPartnerPayment(data)) return false;
              final dt = _parseApprovedDate(data);
              if (dt == null) return true;
              final day = DateTime(dt.year, dt.month, dt.day);
              if (day.isBefore(startDay) || day.isAfter(endDay)) return false;
              if (_filterStatus == 'approved' &&
                  (data['status'] ?? '') != 'approved') {
                return false;
              }
              if (_filterStatus == 'cancelled' &&
                  (data['status'] ?? '') != 'cancelled') {
                return false;
              }
              return true;
            }).toList();

            WidgetsBinding.instance.addPostFrameCallback((_) {
              _recalcTotals(docs);
            });

            final uniqueUids = docs
                .map((d) => (d.data()['uid'] ?? '').toString())
                .where((s) => s.isNotEmpty)
                .toSet()
                .toList();
            _ensureUserDisplayFuture(uniqueUids);

            return FutureBuilder<Map<String, String>>(
              future: _uidDisplayFuture,
              builder: (context, userSnap) {
                final uidToDisplay = userSnap.data ?? _uidDisplayCache;
                if (_searchQuery.isNotEmpty) {
                  final q = _searchQuery.toLowerCase();
                  docs = docs.where((d) {
                    final data = d.data();
                    final uid = (data['uid'] ?? '').toString();
                    final combined =
                        '${_parseUserDisplay(data) ?? ''} ${uidToDisplay[uid] ?? ''} $uid'
                            .toLowerCase();
                    return combined.contains(q);
                  }).toList();
                }
                docs.sort((a, b) {
                  if (_orderByUser) {
                    final uidA = (a.data()['uid'] ?? '').toString();
                    final uidB = (b.data()['uid'] ?? '').toString();
                    final da = (_parseUserDisplay(a.data()) ??
                            uidToDisplay[uidA] ??
                            uidA)
                        .toLowerCase();
                    final db = (_parseUserDisplay(b.data()) ??
                            uidToDisplay[uidB] ??
                            uidB)
                        .toLowerCase();
                    final cmp = da.compareTo(db);
                    if (cmp != 0) return cmp;
                  }
                  final ta = a.data()['updatedAt'] is Timestamp
                      ? (a.data()['updatedAt'] as Timestamp).millisecondsSinceEpoch
                      : 0;
                  final tb = b.data()['updatedAt'] is Timestamp
                      ? (b.data()['updatedAt'] as Timestamp).millisecondsSinceEpoch
                      : 0;
                  return tb.compareTo(ta);
                });

                if (docs.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Nenhum recebimento da sua parte no período.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  );
                }

                return Column(
                  children: docs.map((d) => _paymentTile(d, uidToDisplay)).toList(),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildPeriodRow(BuildContext context) {
    return Row(
      children: [
        Text('Período:',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: Colors.grey.shade700)),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _filterStart,
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
            );
            if (d != null) setState(() => _filterStart = d);
          },
          child: Text(DateFormat('dd/MM/yyyy').format(_filterStart)),
        ),
        const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4), child: Text('até')),
        OutlinedButton(
          onPressed: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _filterEnd,
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
            );
            if (d != null) setState(() => _filterEnd = d);
          },
          child: Text(DateFormat('dd/MM/yyyy').format(_filterEnd)),
        ),
      ],
    );
  }

  Widget _paymentTile(
      QueryDocumentSnapshot<Map<String, dynamic>> d,
      Map<String, String> uidToDisplay) {
    const taxaPix = 0.0099;
    const taxaCartao = 0.0499;
    final data = d.data();
    final uid = (data['uid'] ?? '').toString();
    final plan = (data['plan'] ?? '').toString();
    final status = (data['status'] ?? '').toString();
    final raw = data['raw'] as Map<String, dynamic>?;
    final amount = raw?['transaction_amount'] ?? 0;
    final total = amount is num ? amount.toDouble() : 0.0;
    final method = (raw?['payment_method_id'] ?? '').toString().toLowerCase();
    final taxa = method == 'pix' ? taxaPix : taxaCartao;
    final totalNet = total * (1 - taxa);
    final pGross = _partnerGross(data, total);
    final pNet = _partnerNet(data, totalNet, total);
    final isApproved = status == 'approved';
    final userDisplay = _parseUserDisplay(data) ??
        uidToDisplay[uid] ??
        (uid.isNotEmpty ? uid : '—');
    final dt = _parseApprovedDate(data);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isApproved
            ? AppColors.success.withValues(alpha: 0.07)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isApproved
              ? AppColors.success.withValues(alpha: 0.3)
              : Colors.grey.shade200,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isApproved ? Icons.check_circle_rounded : Icons.schedule_rounded,
            color: isApproved ? AppColors.success : Colors.orange,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(userDisplay,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text('Plano: $plan',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade700)),
                if (dt != null)
                  Text(
                    DateFormat('dd/MM/yyyy HH:mm').format(dt),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                CurrencyFormats.formatBRL(pGross),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: isApproved ? AppColors.success : Colors.grey.shade700,
                ),
              ),
              Text(
                'Líq. ${CurrencyFormats.formatBRL(pNet)}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
