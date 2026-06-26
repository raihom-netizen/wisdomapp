import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Carrega/salva configuração dual Mercado Pago (admin).
class MpAdminConfigService {
  MpAdminConfigService._();
  static final instance = MpAdminConfigService._();

  static const defaultWebhookUrl =
      'https://us-central1-wisdomapp-b9e98.cloudfunctions.net/mpWebhook';

  final _fn = FirebaseFunctions.instanceFor(region: 'us-central1');

  Future<MpAdminConfigSnapshot> load() async {
    try {
      final res = await _fn.httpsCallable('ctGetMpAdminConfig').call();
      final data = Map<String, dynamic>.from(res.data as Map);
      if (data['ok'] == true) {
        return _fromCallable(data);
      }
    } catch (e, st) {
      debugPrint('MpAdminConfigService ctGetMpAdminConfig: $e\n$st');
    }
    return _loadFromFirestore();
  }

  Future<MpAdminConfigSnapshot> _loadFromFirestore() async {
    final ownerSnap = await FirebaseFirestore.instance
        .collection('settings')
        .doc('mercadopago')
        .get();
    final partnerSnap = await FirebaseFirestore.instance
        .collection('settings')
        .doc('mercadopago_partner')
        .get();
    final projectSnap = await FirebaseFirestore.instance
        .collection('mp_project_config')
        .doc('main')
        .get();
    final pricesSnap = await FirebaseFirestore.instance
        .collection('app_config')
        .doc('mp_checkout_prices')
        .get();

    final owner = ownerSnap.data() ?? {};
    final partner = partnerSnap.data() ?? {};
    final project = projectSnap.data() ?? {};
    final prices = pricesSnap.data() ?? {};

    final ownerToken = _s(owner, 'access_token', 'accessToken');
    final partnerToken = _s(partner, 'access_token', 'accessToken');
    final partnerCollector = _s(partner, 'collector_id', 'collectorId');

    return MpAdminConfigSnapshot(
      ownerPublicKey: _s(owner, 'public_key', 'publicKey'),
      ownerAccessToken: ownerToken,
      ownerClientId: _s(owner, 'client_id', 'clientId'),
      ownerClientSecret: _s(owner, 'client_secret', 'clientSecret'),
      ownerWebhookUrl: _s(owner, 'webhook_url', 'webhookUrl', defaultWebhookUrl),
      ownerWebhookSecret: _s(owner, 'webhook_secret', 'webhookSecret'),
      ownerCollectorId: _s(owner, 'collector_id', 'collectorId'),
      ownerConfigured: ownerToken.isNotEmpty,
      partnerPublicKey: _s(partner, 'public_key', 'publicKey'),
      partnerAccessToken: partnerToken,
      partnerClientId: _s(partner, 'client_id', 'clientId'),
      partnerCollectorId: partnerCollector,
      partnerConfigured: partnerToken.isNotEmpty && partnerCollector.isNotEmpty,
      splitEnabled: project['splitEnabled'] == true,
      splitModeFixed: (project['splitMode'] ?? '').toString() == 'fixed',
      ownerSharePercent: _d(project['ownerSharePercent'], 29.86),
      partnerSharePercent: _d(project['partnerSharePercent'], 70.14),
      ownerShareFixed: _d(project['ownerShareFixed'], 14.90),
      partnerShareFixed: _d(project['partnerShareFixed'], 35.00),
      referenceGross: _d(project['referenceGross'], _d(prices['premium_monthly'], 49.90)),
      premiumMonthly: _d(prices['premium_monthly'], 49.90),
      premiumAnnual: _d(prices['premium_annual'], 478.80),
      webhookDefaultUrl: defaultWebhookUrl,
    );
  }

  MpAdminConfigSnapshot _fromCallable(Map<String, dynamic> data) {
    final owner = Map<String, dynamic>.from(data['owner'] as Map? ?? {});
    final partner = Map<String, dynamic>.from(data['partner'] as Map? ?? {});
    final split = Map<String, dynamic>.from(data['split'] as Map? ?? {});
    final prices = Map<String, dynamic>.from(data['prices'] as Map? ?? {});

    return MpAdminConfigSnapshot(
      ownerPublicKey: _s(owner, 'publicKey', 'public_key'),
      ownerAccessToken: _s(owner, 'accessToken', 'access_token'),
      ownerClientId: _s(owner, 'clientId', 'client_id'),
      ownerClientSecret: _s(owner, 'clientSecret', 'client_secret'),
      ownerWebhookUrl: _s(
        owner,
        'webhookUrl',
        'webhook_url',
        data['webhookDefaultUrl']?.toString() ?? defaultWebhookUrl,
      ),
      ownerWebhookSecret: _s(owner, 'webhookSecret', 'webhook_secret'),
      ownerCollectorId: _s(owner, 'collectorId', 'collector_id'),
      ownerConfigured: owner['configured'] == true ||
          _s(owner, 'accessToken', 'access_token').isNotEmpty,
      partnerPublicKey: _s(partner, 'publicKey', 'public_key'),
      partnerAccessToken: _s(partner, 'accessToken', 'access_token'),
      partnerClientId: _s(partner, 'clientId', 'client_id'),
      partnerCollectorId: _s(partner, 'collectorId', 'collector_id'),
      partnerConfigured: partner['configured'] == true ||
          (_s(partner, 'accessToken', 'access_token').isNotEmpty &&
              _s(partner, 'collectorId', 'collector_id').isNotEmpty),
      splitEnabled: split['enabled'] == true,
      splitModeFixed: (split['mode'] ?? '').toString() == 'fixed',
      ownerSharePercent: _d(split['ownerSharePercent'], 29.86),
      partnerSharePercent: _d(split['partnerSharePercent'], 70.14),
      ownerShareFixed: _d(split['ownerShareFixed'], 14.90),
      partnerShareFixed: _d(split['partnerShareFixed'], 35.00),
      referenceGross: _d(split['referenceGross'], _d(prices['premium_monthly'], 49.90)),
      premiumMonthly: _d(prices['premium_monthly'], 49.90),
      premiumAnnual: _d(prices['premium_annual'], 478.80),
      webhookDefaultUrl:
          (data['webhookDefaultUrl'] ?? defaultWebhookUrl).toString(),
    );
  }

  Future<Map<String, dynamic>> save({
    required MpAdminConfigSnapshot config,
    required bool syncLandingTexts,
  }) async {
    final res = await _fn.httpsCallable('ctSaveMpAdminConfig').call<Map<String, dynamic>>({
      'owner': {
        'publicKey': config.ownerPublicKey,
        'accessToken': config.ownerAccessToken,
        'clientId': config.ownerClientId,
        'clientSecret': config.ownerClientSecret,
        'webhookUrl': config.ownerWebhookUrl,
        'webhookSecret': config.ownerWebhookSecret,
        'collectorId': config.ownerCollectorId,
      },
      'partner': {
        'publicKey': config.partnerPublicKey,
        'accessToken': config.partnerAccessToken,
        'clientId': config.partnerClientId,
        'collectorId': config.partnerCollectorId,
      },
      'split': {
        'enabled': config.splitEnabled,
        'mode': config.splitModeFixed ? 'fixed' : 'percent',
        'ownerSharePercent': config.ownerSharePercent,
        'partnerSharePercent': config.partnerSharePercent,
        'ownerShareFixed': config.ownerShareFixed,
        'partnerShareFixed': config.partnerShareFixed,
        'referenceGross': config.referenceGross,
        'partnerCollectorId': config.partnerCollectorId,
      },
      'prices': {
        'premium_monthly': config.premiumMonthly,
        'premium_annual': config.premiumAnnual,
        'premium_pro_monthly': config.premiumMonthly,
        'premium_pro_annual': config.premiumAnnual,
      },
      'syncLandingTexts': syncLandingTexts,
    });
    return Map<String, dynamic>.from(res.data);
  }

  static String _s(Map<String, dynamic> m, String a, String b, [String fallback = '']) {
    final v = (m[a] ?? m[b] ?? fallback).toString().trim();
    return v;
  }

  static double _d(dynamic v, double fallback) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString().replaceAll(',', '.') ?? '') ?? fallback;
  }
}

class MpAdminConfigSnapshot {
  MpAdminConfigSnapshot({
    required this.ownerPublicKey,
    required this.ownerAccessToken,
    required this.ownerClientId,
    required this.ownerClientSecret,
    required this.ownerWebhookUrl,
    required this.ownerWebhookSecret,
    required this.ownerCollectorId,
    required this.ownerConfigured,
    required this.partnerPublicKey,
    required this.partnerAccessToken,
    required this.partnerClientId,
    required this.partnerCollectorId,
    required this.partnerConfigured,
    required this.splitEnabled,
    required this.splitModeFixed,
    required this.ownerSharePercent,
    required this.partnerSharePercent,
    required this.ownerShareFixed,
    required this.partnerShareFixed,
    required this.referenceGross,
    required this.premiumMonthly,
    required this.premiumAnnual,
    required this.webhookDefaultUrl,
  });

  final String ownerPublicKey;
  final String ownerAccessToken;
  final String ownerClientId;
  final String ownerClientSecret;
  final String ownerWebhookUrl;
  final String ownerWebhookSecret;
  final String ownerCollectorId;
  final bool ownerConfigured;
  final String partnerPublicKey;
  final String partnerAccessToken;
  final String partnerClientId;
  final String partnerCollectorId;
  final bool partnerConfigured;
  final bool splitEnabled;
  final bool splitModeFixed;
  final double ownerSharePercent;
  final double partnerSharePercent;
  final double ownerShareFixed;
  final double partnerShareFixed;
  final double referenceGross;
  final double premiumMonthly;
  final double premiumAnnual;
  final String webhookDefaultUrl;

  MpAdminConfigSnapshot copyWith({
    String? ownerPublicKey,
    String? ownerAccessToken,
    String? ownerClientId,
    String? ownerClientSecret,
    String? ownerWebhookUrl,
    String? ownerWebhookSecret,
    String? ownerCollectorId,
    bool? ownerConfigured,
    String? partnerPublicKey,
    String? partnerAccessToken,
    String? partnerClientId,
    String? partnerCollectorId,
    bool? partnerConfigured,
    bool? splitEnabled,
    bool? splitModeFixed,
    double? ownerSharePercent,
    double? partnerSharePercent,
    double? ownerShareFixed,
    double? partnerShareFixed,
    double? referenceGross,
    double? premiumMonthly,
    double? premiumAnnual,
    String? webhookDefaultUrl,
  }) {
    return MpAdminConfigSnapshot(
      ownerPublicKey: ownerPublicKey ?? this.ownerPublicKey,
      ownerAccessToken: ownerAccessToken ?? this.ownerAccessToken,
      ownerClientId: ownerClientId ?? this.ownerClientId,
      ownerClientSecret: ownerClientSecret ?? this.ownerClientSecret,
      ownerWebhookUrl: ownerWebhookUrl ?? this.ownerWebhookUrl,
      ownerWebhookSecret: ownerWebhookSecret ?? this.ownerWebhookSecret,
      ownerCollectorId: ownerCollectorId ?? this.ownerCollectorId,
      ownerConfigured: ownerConfigured ?? this.ownerConfigured,
      partnerPublicKey: partnerPublicKey ?? this.partnerPublicKey,
      partnerAccessToken: partnerAccessToken ?? this.partnerAccessToken,
      partnerClientId: partnerClientId ?? this.partnerClientId,
      partnerCollectorId: partnerCollectorId ?? this.partnerCollectorId,
      partnerConfigured: partnerConfigured ?? this.partnerConfigured,
      splitEnabled: splitEnabled ?? this.splitEnabled,
      splitModeFixed: splitModeFixed ?? this.splitModeFixed,
      ownerSharePercent: ownerSharePercent ?? this.ownerSharePercent,
      partnerSharePercent: partnerSharePercent ?? this.partnerSharePercent,
      ownerShareFixed: ownerShareFixed ?? this.ownerShareFixed,
      partnerShareFixed: partnerShareFixed ?? this.partnerShareFixed,
      referenceGross: referenceGross ?? this.referenceGross,
      premiumMonthly: premiumMonthly ?? this.premiumMonthly,
      premiumAnnual: premiumAnnual ?? this.premiumAnnual,
      webhookDefaultUrl: webhookDefaultUrl ?? this.webhookDefaultUrl,
    );
  }
}
