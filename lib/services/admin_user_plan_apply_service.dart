import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_profile.dart';
import 'admin_audit_service.dart';
import 'admin_partnership_plan_catalog.dart';
import 'billing_service.dart';
import 'logs_service.dart';

/// Aplica mudança de plano no Admin (inclui vínculo de convênio para `premium_*`).
class AdminUserPlanApplyService {
  AdminUserPlanApplyService._();

  static Future<void> apply({
    required DocumentReference<Map<String, dynamic>> ref,
    required String uid,
    required String name,
    required String email,
    required String currentPlan,
    required String currentPartnershipId,
    required String currentPartnershipName,
    required String newPlan,
    required List<AdminPartnershipPlanOption> conveniosCatalog,
  }) async {
    final np = newPlan.trim().toLowerCase();
    final cp = currentPlan.trim().toLowerCase();
    if (np == cp) return;

    final beforeMap = <String, dynamic>{'plan': cp};
    if (currentPartnershipId.isNotEmpty) {
      beforeMap['partnershipId'] = currentPartnershipId;
    }
    if (currentPartnershipName.isNotEmpty) {
      beforeMap['partnershipName'] = currentPartnershipName;
    }

    if (np == 'free') {
      await BillingService().setUserToFree(uid);
    } else {
      final updates = <String, dynamic>{
        'plan': np,
        'planStatus': 'active',
        'updatedAt': FieldValue.serverTimestamp(),
        'removedByAdminAt': FieldValue.delete(),
      };

      void clearPartnership() {
        updates['partnershipId'] = FieldValue.delete();
        updates['partnershipName'] = FieldValue.delete();
      }

      final isRetailPremium = np == 'premium' ||
          np == 'premium_monthly' ||
          np == 'premium_annual';
      final isLegacy = np == 'basic' ||
          np == 'basico' ||
          np == 'master' ||
          np == 'master_monthly' ||
          np == 'master_annual';

      if (isRetailPremium ||
          isLegacy ||
          UserProfile.planIndicatesPremiumPro(np)) {
        clearPartnership();
      } else if (np.startsWith('premium_')) {
        AdminPartnershipPlanOption? match;
        for (final o in conveniosCatalog) {
          if (o.planCode == np) {
            match = o;
            break;
          }
        }
        if (match != null) {
          updates['partnershipId'] = match.partnershipDocId;
          updates['partnershipName'] = match.partnershipName;
        } else {
          clearPartnership();
        }
      } else {
        clearPartnership();
      }
      await ref.update(updates);
    }

    final afterMap = <String, dynamic>{'plan': np};
    await AdminAuditService().logAdminAction(
      action: alterarPlano,
      targetUserId: uid,
      targetUserEmail: email.isNotEmpty ? email : null,
      before: beforeMap,
      after: afterMap,
    );
    await LogsService().saveLog(
      modulo: 'Admin',
      acao: 'Alterou plano de usuário',
      detalhes: '${name.isEmpty ? uid : name} • $np',
    );
  }
}
