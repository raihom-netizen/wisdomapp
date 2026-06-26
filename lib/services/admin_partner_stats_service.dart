import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

/// Indicadores do painel sócio (Johnathan Tarley) — somente leitura.
class AdminPartnerStats {
  final int totalUsers;
  final int totalPremiums;
  final int licensesExpired;
  final int licensesExpiring7d;
  final double partnerGross;
  final double partnerNet;
  final double partnerPixNet;
  final double partnerCardNet;
  final List<double> partnerGrossByBucket;
  final List<String> bucketLabels;
  final double partnerSharePercent;

  const AdminPartnerStats({
    required this.totalUsers,
    required this.totalPremiums,
    required this.licensesExpired,
    required this.licensesExpiring7d,
    required this.partnerGross,
    required this.partnerNet,
    this.partnerPixNet = 0,
    this.partnerCardNet = 0,
    this.partnerGrossByBucket = const [],
    this.bucketLabels = const [],
    this.partnerSharePercent = 50,
  });
}

class AdminPartnerStatsService {
  const AdminPartnerStatsService();

  static double _partnerGrossFromPayment(Map<String, dynamic> data, double total) {
    final splitGross = data['splitPartnerShareGross'];
    if (splitGross is num && splitGross > 0) return splitGross.toDouble();
    final pct = data['splitPartnerSharePercent'];
    if (pct is num && pct > 0) return total * (pct / 100);
    return total * 0.5;
  }

  static double _partnerNetFromPayment(
    Map<String, dynamic> data,
    double totalGross,
    double totalNet,
  ) {
    final splitNet = data['splitPartnerShareNet'];
    if (splitNet is num && splitNet > 0) return splitNet.toDouble();
    final gross = _partnerGrossFromPayment(data, totalGross);
    if (totalGross <= 0) return gross;
    return totalNet * (gross / totalGross);
  }

  Future<double> _loadPartnerSharePercent() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('mp_project_config')
          .doc('default')
          .get();
      final split = snap.data()?['split'];
      if (split is Map) {
        final pct = split['partnerSharePercent'] ?? split['partner_share_percent'];
        if (pct is num && pct > 0) return pct.toDouble().clamp(0, 100);
      }
    } catch (_) {}
    return 50;
  }

  Future<AdminPartnerStats> load({required int periodDays}) async {
    final now = DateTime.now();
    final periodStart = DateTime(
      now.subtract(Duration(days: periodDays)).year,
      now.subtract(Duration(days: periodDays)).month,
      now.subtract(Duration(days: periodDays)).day,
    );
    final startOfToday = DateTime(now.year, now.month, now.day);
    final end7Eod = startOfToday.add(const Duration(days: 7, hours: 23, minutes: 59));

    const taxaPix = 0.0099;
    const taxaCartao = 0.0499;

    int totalUsers = 0;
    int totalPremiums = 0;
    int licensesExpired = 0;
    int licensesExpiring7d = 0;

    try {
      final users = FirebaseFirestore.instance.collection('users');
      final counts = await Future.wait<AggregateQuerySnapshot>([
        users.count().get(),
        users
            .where('plan', whereIn: [
              'premium',
              'premium_pro',
              'premium_assego',
              'premium_monthly',
              'premium_annual',
            ])
            .count()
            .get(),
        users
            .where('licenseExpiresAt', isLessThan: Timestamp.fromDate(startOfToday))
            .count()
            .get(),
        users
            .where('licenseExpiresAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
            .where('licenseExpiresAt',
                isLessThanOrEqualTo: Timestamp.fromDate(end7Eod))
            .count()
            .get(),
      ]);
      totalUsers = counts[0].count ?? 0;
      totalPremiums = counts[1].count ?? 0;
      licensesExpired = counts[2].count ?? 0;
      licensesExpiring7d = counts[3].count ?? 0;
    } catch (_) {}

    final partnerSharePercent = await _loadPartnerSharePercent();

    final bucketSize = periodDays <= 14
        ? 1
        : periodDays <= 31
            ? 2
            : periodDays <= 90
                ? 5
                : 7;
    final nBuckets =
        math.min(28, math.max(1, (periodDays / bucketSize).ceil()));
    final partnerGrossByBucket = List<double>.filled(nBuckets, 0);
    final bucketLabels = List<String>.generate(nBuckets, (i) {
      final d = periodStart.add(Duration(days: i * bucketSize));
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    });

    double partnerGross = 0;
    double partnerNet = 0;
    double partnerPixNet = 0;
    double partnerCardNet = 0;

    try {
      QuerySnapshot<Map<String, dynamic>> mpSnap;
      try {
        mpSnap = await FirebaseFirestore.instance
            .collection('mp_payments')
            .where('status', isEqualTo: 'approved')
            .where('dateApprovedAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(periodStart))
            .orderBy('dateApprovedAt', descending: true)
            .limit(800)
            .get();
      } catch (_) {
        mpSnap = await FirebaseFirestore.instance
            .collection('mp_payments')
            .where('status', isEqualTo: 'approved')
            .limit(2000)
            .get();
      }

      for (final d in mpSnap.docs) {
        final data = d.data();
        if (data['isOutgoing'] == true) continue;
        final raw = data['raw'];
        if (raw is! Map) continue;
        final amt = raw['transaction_amount'];
        final total = amt is num ? amt.toDouble() : 0.0;
        if (total <= 0) continue;

        DateTime? dt;
        final topTs = data['dateApprovedAt'];
        if (topTs is Timestamp) {
          dt = topTs.toDate();
        } else {
          final dateApproved = raw['date_approved'];
          if (dateApproved is String) {
            dt = DateTime.tryParse(dateApproved);
          } else if (dateApproved is Timestamp) {
            dt = dateApproved.toDate();
          }
        }
        if (dt == null) continue;
        final dtDay = DateTime(dt.year, dt.month, dt.day);
        if (dtDay.isBefore(periodStart)) continue;

        final method =
            (raw['payment_method_id'] ?? '').toString().toLowerCase();
        final isPix = method == 'pix';
        final taxa = isPix ? taxaPix : taxaCartao;
        final totalNet = total * (1 - taxa);

        final pGross = _partnerGrossFromPayment(data, total);
        final pNet = _partnerNetFromPayment(data, total, totalNet);
        partnerGross += pGross;
        partnerNet += pNet;
        if (isPix) {
          partnerPixNet += pNet;
        } else {
          partnerCardNet += pNet;
        }

        final dayFromStart = dtDay.difference(periodStart).inDays;
        if (dayFromStart >= 0 && dayFromStart < periodDays) {
          final bi = dayFromStart ~/ bucketSize;
          if (bi >= 0 && bi < nBuckets) {
            partnerGrossByBucket[bi] += pGross;
          }
        }
      }
    } catch (_) {}

    return AdminPartnerStats(
      totalUsers: totalUsers,
      totalPremiums: totalPremiums,
      licensesExpired: licensesExpired,
      licensesExpiring7d: licensesExpiring7d,
      partnerGross: partnerGross,
      partnerNet: partnerNet,
      partnerPixNet: partnerPixNet,
      partnerCardNet: partnerCardNet,
      partnerGrossByBucket: partnerGrossByBucket,
      bucketLabels: bucketLabels,
      partnerSharePercent: partnerSharePercent,
    );
  }
}
