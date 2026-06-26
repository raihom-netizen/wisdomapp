import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../widgets/light_filter_picker.dart';

/// Métrica de um convênio no resumo Admin (contagem de usuários vinculados).
class AdminPartnershipMetric {
  const AdminPartnershipMetric({
    required this.partnershipDocId,
    required this.planCode,
    required this.partnershipName,
    required this.userCount,
  });

  final String partnershipDocId;
  final String planCode;
  final String partnershipName;
  final int userCount;
}

/// Uma linha do catálogo de planos de convênio (coleção `partnerships`) para o
/// painel Admin — alimenta o dropdown «Plano» ao editar usuário.
class AdminPartnershipPlanOption {
  const AdminPartnershipPlanOption({
    required this.partnershipDocId,
    required this.planCode,
    required this.partnershipName,
  });

  /// ID do documento em `partnerships/{id}`.
  final String partnershipDocId;

  /// Código gravado em `users.plan` e no convênio (`planCode`).
  final String planCode;

  /// Nome amigável do convênio.
  final String partnershipName;
}

/// Monta a lista a partir do snapshot de `partnerships` (um item por
/// [planCode] distinto — se dois convênios partilharem o mesmo código, fica
/// o primeiro encontrado para vínculo ao mudar plano no Admin).
List<AdminPartnershipPlanOption> parsePartnershipPlansSnapshot(
  QuerySnapshot<Map<String, dynamic>> snap,
) {
  final byPlan = <String, AdminPartnershipPlanOption>{};
  for (final doc in snap.docs) {
    final m = doc.data();
    if (m['active'] == false) continue;
    var planCode = (m['planCode'] ?? '').toString().trim().toLowerCase();
    planCode = planCode.replaceAll(RegExp(r'[^a-z0-9_]'), '');
    if (planCode.isEmpty) continue;
    if (planCode == 'free') continue;
    // Varejo puro — não entra como «convênio» na lista (já existe opção Premium).
    if (planCode == 'premium' ||
        planCode == 'premium_monthly' ||
        planCode == 'premium_annual') {
      continue;
    }
    if (UserProfile.planIndicatesPremiumPro(planCode)) continue;
    final name = (m['name'] ?? doc.id).toString().trim();
    if (name.isEmpty) continue;
    byPlan.putIfAbsent(
      planCode,
      () => AdminPartnershipPlanOption(
        partnershipDocId: doc.id,
        planCode: planCode,
        partnershipName: name,
      ),
    );
  }
  final list = byPlan.values.toList()
    ..sort((a, b) => a.partnershipName
        .toLowerCase()
        .compareTo(b.partnershipName.toLowerCase()));
  return list;
}

/// Valor exibido no `DropdownButton` de plano — deve coincidir com um dos
/// `value` dos itens (incluindo códigos `premium_*` dos convênios).
String adminUserPlanDropdownValue(String plan) {
  final p = plan.trim().toLowerCase();
  if (p.isEmpty || p == 'free') return 'free';
  if (UserProfile.planIndicatesPremiumPro(p)) return 'premium';
  if (p == 'basic' || p == 'basico') return 'basic';
  if (p == 'master' ||
      p == 'master_monthly' ||
      p == 'master_annual') {
    return 'master';
  }
  if (p == 'premium' ||
      p == 'premium_monthly' ||
      p == 'premium_annual') {
    return 'premium';
  }
  // Convênios: premium_assego, premium_unimil, premium_xyz…
  if (p.startsWith('premium_')) return p;
  return 'premium';
}

List<DropdownMenuItem<String>> adminUserPlanDropdownItems({
  required String currentPlan,
  required List<AdminPartnershipPlanOption> convenios,
}) {
  final p = currentPlan.trim().toLowerCase();
  final items = <DropdownMenuItem<String>>[
    const DropdownMenuItem(value: 'free', child: Text('Free')),
    const DropdownMenuItem(
      value: 'premium',
      child: Text('Premium (particular / varejo)'),
    ),
  ];
  final seen = <String>{'free', 'premium'};
  for (final c in convenios) {
    if (seen.contains(c.planCode)) continue;
    seen.add(c.planCode);
    final label = '${c.partnershipName} — ${c.planCode}';
    items.add(
      DropdownMenuItem(
        value: c.planCode,
        child: Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  if (p == 'basic' || p == 'basico') {
    items.insert(
      1,
      const DropdownMenuItem(
        value: 'basic',
        child: Text('Básico (legado — migrar)'),
      ),
    );
  }
  if (p == 'master' ||
      p == 'master_monthly' ||
      p == 'master_annual') {
    items.insert(
      2,
      const DropdownMenuItem(
        value: 'master',
        child: Text('Master plano (legado — migrar)'),
      ),
    );
  }

  // Plano atual ainda não listado (sync em curso ou código antigo / manual).
  final curVal = adminUserPlanDropdownValue(currentPlan);
  final existing = items.map((e) => e.value).whereType<String>().toSet();
  if (!existing.contains(curVal) &&
      curVal != 'free' &&
      curVal != 'premium' &&
      curVal != 'basic' &&
      curVal != 'master') {
    items.add(
      DropdownMenuItem(
        value: curVal,
        child: Text(
          UserProfile.planDisplayLabelForFirestorePlan(curVal),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
  return items;
}

/// Itens do filtro «Plano» na lista de usuários (Todos + Free + Premium + cada convênio).
List<DropdownMenuItem<String>> adminUserFilterPlanDropdownItems(
  List<AdminPartnershipPlanOption> convenios,
) {
  final items = <DropdownMenuItem<String>>[
    const DropdownMenuItem(value: 'todos', child: Text('Todos')),
    const DropdownMenuItem(value: 'free', child: Text('Free')),
    const DropdownMenuItem(
      value: 'premium',
      child: Text('Premium (varejo)'),
    ),
  ];
  final seen = <String>{'todos', 'free', 'premium'};
  for (final c in convenios) {
    if (seen.contains(c.planCode)) continue;
    seen.add(c.planCode);
    items.add(
      DropdownMenuItem(
        value: c.planCode,
        child: Text(
          '${c.partnershipName} (${c.planCode})',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
  // Filtro legado: `premium_assego` costuma existir mesmo sem doc em `partnerships`.
  const legacyPlanFilterCodes = <String>['premium_assego'];
  for (final code in legacyPlanFilterCodes) {
    if (seen.contains(code)) continue;
    seen.add(code);
    items.add(
      DropdownMenuItem(
        value: code,
        child: Text(UserProfile.planDisplayLabelForFirestorePlan(code)),
      ),
    );
  }
  return items;
}

/// Mesmas opções de [adminUserFilterPlanDropdownItems], sem [DropdownMenuItem].
List<LightFilterOption<String>> adminUserFilterPlanLightOptions(
  List<AdminPartnershipPlanOption> convenios,
) {
  final items = <LightFilterOption<String>>[
    const LightFilterOption(value: 'todos', label: 'Todos'),
    const LightFilterOption(value: 'free', label: 'Free'),
    const LightFilterOption(value: 'premium', label: 'Premium (varejo)'),
  ];
  final seen = <String>{'todos', 'free', 'premium'};
  for (final c in convenios) {
    if (seen.contains(c.planCode)) continue;
    seen.add(c.planCode);
    items.add(
      LightFilterOption(
        value: c.planCode,
        label: '${c.partnershipName} (${c.planCode})',
      ),
    );
  }
  const legacyPlanFilterCodes = <String>['premium_assego'];
  for (final code in legacyPlanFilterCodes) {
    if (seen.contains(code)) continue;
    seen.add(code);
    items.add(
      LightFilterOption(
        value: code,
        label: UserProfile.planDisplayLabelForFirestorePlan(code),
      ),
    );
  }
  return items;
}
