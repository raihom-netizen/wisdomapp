import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'fast_text_field.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../constants/currency_formats.dart';
import '../widgets/shell_keyboard_bottom_pad.dart';
import '../services/admin_partnership_plan_catalog.dart';
import '../services/admin_user_plan_apply_service.dart';
import '../services/admin_audit_service.dart';
import '../services/billing_service.dart';
import '../services/logs_service.dart';
import '../models/user_profile.dart';
import '../utils/admin_responsive.dart';
import '../services/functions_service.dart';
import '../theme/app_colors.dart';
import '../utils/debounced_text_controller.dart';
import '../utils/keyboard_form_scaffold.dart';
import '../utils/url_launcher_helper.dart' as url_helper;
import 'admin_delegate_email_section.dart';
import 'brl_amount_text_field.dart';
import 'app_bar_chart.dart';
import 'admin/admin_page_shell.dart';
import 'module_header_premium.dart';

String _formatPartnershipVigenciaSubtitle(Map<String, dynamic> m) {
  final cs = m['contractStartsAt'];
  final ce = m['contractEndsAt'];
  String? a;
  String? b;
  if (cs is Timestamp) {
    a = DateFormat('dd/MM/yyyy').format(cs.toDate());
  }
  if (ce is Timestamp) {
    b = DateFormat('dd/MM/yyyy').format(ce.toDate());
  }
  if (a == null && b == null) return '';
  if (a != null && b != null) return 'Vigência contrato: $a — $b';
  if (a != null) return 'Início contrato: $a';
  return 'Fim contrato: $b';
}

String _normalizePartnershipPlanCode(String? raw) {
  return (raw ?? '').trim().toLowerCase();
}

/// Planos “varejo” padrão — não ampliar contagem pelo campo `plan` (evita incluir todos os premium do MP).
bool _isRetailPremiumPlanNorm(String planNorm) {
  return planNorm == 'premium' ||
      planNorm == 'premium_monthly' ||
      planNorm == 'premium_annual';
}

/// Só por [partnershipId] — mesmo comportamento antigo (rápido com aggregate count).
Future<int> _countUsersPartnershipIdOnly(
  FirebaseFirestore fs,
  String partnershipId,
  int periodDays,
) async {
  final col = fs.collection('users').where('partnershipId', isEqualTo: partnershipId);
  if (periodDays <= 0) {
    final r = await col.count().get();
    return r.count ?? 0;
  }
  final since = DateTime.now().subtract(Duration(days: periodDays));
  final ts = Timestamp.fromDate(since);
  try {
    final r = await col.where('createdAt', isGreaterThanOrEqualTo: ts).count().get();
    return r.count ?? 0;
  } catch (_) {
    final snap = await col.limit(3000).get();
    var n = 0;
    for (final d in snap.docs) {
      final c = d.data()['createdAt'];
      if (c is Timestamp && !c.toDate().isBefore(since)) n++;
    }
    return n;
  }
}

/// União de usuários: [partnershipId] igual ao convênio OU [plan] igual ao [planCode] do convênio
/// (ex.: premium_assego), para quando o plano é alterado manualmente no painel sem preencher partnershipId.
Future<Set<String>> _unionUserIdsPartnershipOrPlan(
  FirebaseFirestore fs,
  String partnershipId,
  String planCode,
  int periodDays,
) async {
  final since = DateTime.now().subtract(Duration(days: periodDays > 0 ? periodDays : 0));
  final ts = Timestamp.fromDate(since);

  Future<Set<String>> loadByPartnershipId() async {
    if (periodDays > 0) {
      try {
        final snap = await fs
            .collection('users')
            .where('partnershipId', isEqualTo: partnershipId)
            .where('createdAt', isGreaterThanOrEqualTo: ts)
            .limit(5000)
            .get();
        return snap.docs.map((d) => d.id).toSet();
      } catch (_) {
        final snap = await fs
            .collection('users')
            .where('partnershipId', isEqualTo: partnershipId)
            .limit(5000)
            .get();
        final set = <String>{};
        for (final d in snap.docs) {
          final c = d.data()['createdAt'];
          if (c is Timestamp && !c.toDate().isBefore(since)) set.add(d.id);
        }
        return set;
      }
    }
    final snap =
        await fs.collection('users').where('partnershipId', isEqualTo: partnershipId).limit(5000).get();
    return snap.docs.map((d) => d.id).toSet();
  }

  Future<Set<String>> loadByPlan() async {
    if (periodDays > 0) {
      try {
        final snap = await fs
            .collection('users')
            .where('plan', isEqualTo: planCode)
            .where('createdAt', isGreaterThanOrEqualTo: ts)
            .limit(5000)
            .get();
        return snap.docs.map((d) => d.id).toSet();
      } catch (_) {
        final snap =
            await fs.collection('users').where('plan', isEqualTo: planCode).limit(5000).get();
        final set = <String>{};
        for (final d in snap.docs) {
          final c = d.data()['createdAt'];
          if (c is Timestamp && !c.toDate().isBefore(since)) set.add(d.id);
        }
        return set;
      }
    }
    final snap =
        await fs.collection('users').where('plan', isEqualTo: planCode).limit(5000).get();
    return snap.docs.map((d) => d.id).toSet();
  }

  final a = await loadByPartnershipId();
  final b = await loadByPlan();
  return {...a, ...b};
}

/// Usuários vinculados ao convênio; opcionalmente só com [createdAt] nos últimos [periodDays] (0 = todo o período).
/// [partnershipPlanCode]: quando não é plano varejo (ex.: premium_assego), conta também usuários com o mesmo
/// [plan] no documento, além de [partnershipId] — alinhado a alterações manuais no painel Usuários.
Future<int> countUsersPartnershipInPeriod(
  FirebaseFirestore fs,
  String partnershipId,
  int periodDays, {
  String? partnershipPlanCode,
}) async {
  final raw = _normalizePartnershipPlanCode(partnershipPlanCode);
  final effective = raw.isEmpty ? 'premium_assego' : raw;
  if (_isRetailPremiumPlanNorm(effective)) {
    return _countUsersPartnershipIdOnly(fs, partnershipId, periodDays);
  }
  final ids = await _unionUserIdsPartnershipOrPlan(fs, partnershipId, effective, periodDays);
  return ids.length;
}

/// Meses “de cobrança” aproximados (30 dias) entre duas datas inclusivas.
double _billingMonthsBetween(DateTime start, DateTime end) {
  final a = DateTime(start.year, start.month, start.day);
  final b = DateTime(end.year, end.month, end.day);
  if (b.isBefore(a)) return 0;
  final days = b.difference(a).inDays + 1;
  return (days / 30.0).clamp(1 / 30, 5000.0);
}

Future<Set<String>> _unionUserIdsPartnershipDateRange(
  FirebaseFirestore fs,
  String partnershipId,
  String planCode,
  DateTime start,
  DateTime end,
) async {
  final startTs = Timestamp.fromDate(DateTime(start.year, start.month, start.day));
  final endTs = Timestamp.fromDate(DateTime(end.year, end.month, end.day, 23, 59, 59));

  Future<Set<String>> loadByPartnershipId() async {
    try {
      final snap = await fs
          .collection('users')
          .where('partnershipId', isEqualTo: partnershipId)
          .where('createdAt', isGreaterThanOrEqualTo: startTs)
          .where('createdAt', isLessThanOrEqualTo: endTs)
          .limit(5000)
          .get();
      return snap.docs.map((e) => e.id).toSet();
    } catch (_) {
      final snap = await fs
          .collection('users')
          .where('partnershipId', isEqualTo: partnershipId)
          .limit(5000)
          .get();
      final set = <String>{};
      final startD = DateTime(start.year, start.month, start.day);
      final endD = DateTime(end.year, end.month, end.day);
      for (final d in snap.docs) {
        final c = d.data()['createdAt'];
        if (c is Timestamp) {
          final dt = c.toDate();
          final day = DateTime(dt.year, dt.month, dt.day);
          if (!day.isBefore(startD) && !day.isAfter(endD)) set.add(d.id);
        }
      }
      return set;
    }
  }

  Future<Set<String>> loadByPlan() async {
    final raw = _normalizePartnershipPlanCode(planCode);
    final effective = raw.isEmpty ? 'premium_assego' : raw;
    if (_isRetailPremiumPlanNorm(effective)) return {};
    try {
      final snap = await fs
          .collection('users')
          .where('plan', isEqualTo: effective)
          .where('createdAt', isGreaterThanOrEqualTo: startTs)
          .where('createdAt', isLessThanOrEqualTo: endTs)
          .limit(5000)
          .get();
      return snap.docs.map((e) => e.id).toSet();
    } catch (_) {
      final snap =
          await fs.collection('users').where('plan', isEqualTo: effective).limit(5000).get();
      final set = <String>{};
      final startD = DateTime(start.year, start.month, start.day);
      final endD = DateTime(end.year, end.month, end.day);
      for (final d in snap.docs) {
        final c = d.data()['createdAt'];
        if (c is Timestamp) {
          final dt = c.toDate();
          final day = DateTime(dt.year, dt.month, dt.day);
          if (!day.isBefore(startD) && !day.isAfter(endD)) set.add(d.id);
        }
      }
      return set;
    }
  }

  final raw = _normalizePartnershipPlanCode(planCode);
  final effective = raw.isEmpty ? 'premium_assego' : raw;
  if (_isRetailPremiumPlanNorm(effective)) {
    return loadByPartnershipId();
  }
  final a = await loadByPartnershipId();
  final b = await loadByPlan();
  return {...a, ...b};
}

Future<int> _countUsersPartnershipDateRange(
  FirebaseFirestore fs,
  String partnershipId,
  String? partnershipPlanCode,
  DateTime start,
  DateTime end,
) async {
  final raw = _normalizePartnershipPlanCode(partnershipPlanCode);
  final effective = raw.isEmpty ? 'premium_assego' : raw;
  final ids = await _unionUserIdsPartnershipDateRange(fs, partnershipId, effective, start, end);
  return ids.length;
}

Future<List<DocumentSnapshot<Map<String, dynamic>>>> _listUserDocsPartnershipDateRange(
  FirebaseFirestore fs,
  String partnershipId,
  String? partnershipPlanCode,
  DateTime start,
  DateTime end,
  int limit,
) async {
  final raw = _normalizePartnershipPlanCode(partnershipPlanCode);
  final effective = raw.isEmpty ? 'premium_assego' : raw;
  final ids = await _unionUserIdsPartnershipDateRange(fs, partnershipId, effective, start, end);
  final sorted = ids.toList()..sort();
  final out = <DocumentSnapshot<Map<String, dynamic>>>[];
  for (final id in sorted.take(limit)) {
    final doc = await fs.collection('users').doc(id).get();
    if (doc.exists) out.add(doc);
  }
  return out;
}

/// Membros ativos do convênio; opcionalmente só entradas recentes por [createdAt].
Future<int> _countMembersPartnershipInPeriod(
  FirebaseFirestore fs,
  String partnershipId,
  int periodDays,
) async {
  final col = fs
      .collection('partnerships')
      .doc(partnershipId)
      .collection('members')
      .where('active', isEqualTo: true);
  if (periodDays <= 0) {
    final r = await col.count().get();
    return r.count ?? 0;
  }
  final since = DateTime.now().subtract(Duration(days: periodDays));
  final ts = Timestamp.fromDate(since);
  try {
    final r = await col.where('createdAt', isGreaterThanOrEqualTo: ts).count().get();
    return r.count ?? 0;
  } catch (_) {
    final snap = await col.limit(3000).get();
    var n = 0;
    for (final d in snap.docs) {
      final c = d.data()['createdAt'];
      if (c is Timestamp && !c.toDate().isBefore(since)) n++;
    }
    return n;
  }
}

class _PartnershipPickResult {
  final bool all;
  final String? id;

  const _PartnershipPickResult.all() : all = true, id = null;

  const _PartnershipPickResult.one(this.id) : all = false;
}

/// Lista de usuários do convênio em cards (painel) ou tabela (grade UNIMIL).
enum PartnershipUsersPanelLayout { cards, dataTable }

/// Escopo da lista de usuários no preview / painel convênio.
enum PartnershipUsersPreviewScope {
  /// Um convênio específico (partnershipId + planCode).
  byPartnership,

  /// Todos com `partnershipId` preenchido.
  allWithPartnershipLink,
}

/// Aba Admin — Convênios: cadastro, link público, métricas, gráfico de cadastros,
/// lista de novos envios, CSV por URL e relatórios rápidos (copiar CSV).
class PartnershipsAdminModule extends StatefulWidget {
  final Color brandBlue;
  final Color brandTeal;

  const PartnershipsAdminModule({
    super.key,
    required this.brandBlue,
    required this.brandTeal,
  });

  @override
  State<PartnershipsAdminModule> createState() => _PartnershipsAdminModuleState();
}

class _PartnershipsAdminModuleState extends State<PartnershipsAdminModule> {
  final _idCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _daysCtrl = TextEditingController(text: '365');
  /// Plano Firestore aplicado ao convênio (mesmas permissões de premium no app).
  final _newPlanCodeCtrl = TextEditingController(text: 'premium_assego');
  /// Vigência opcional na criação (gravada no mesmo doc do convênio).
  DateTime? _novoContratoInicio;
  DateTime? _novoContratoFim;
  final _novoTetoUsuariosCtrl = TextEditingController(text: '4000');
  final _novoValorExcedenteCtrl = TextEditingController();
  bool _saving = false;

  /// 0 = todo o período; senão últimos N dias (cadastro `createdAt`).
  int _filtroFinancePeriodoDias = 30;
  /// null = todas as associações.
  String? _filtroPartnershipId;
  /// null = todos os planos; senão filtra `planCode` do documento do convênio.
  String? _filtroPlanCode;

  @override
  void dispose() {
    _idCtrl.dispose();
    _nameCtrl.dispose();
    _daysCtrl.dispose();
    _newPlanCodeCtrl.dispose();
    _novoTetoUsuariosCtrl.dispose();
    _novoValorExcedenteCtrl.dispose();
    super.dispose();
  }

  double _parseMoneyNovoConvenio(String raw) {
    final normalized = raw.replaceAll('.', '').replaceAll(',', '.').trim();
    return double.tryParse(normalized) ?? 0;
  }

  Future<void> _pickNovoContratoDate(bool isStart) async {
    final initial = isStart ? _novoContratoInicio : _novoContratoFim;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2018),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      final day = DateTime(picked.year, picked.month, picked.day);
      if (isStart) {
        _novoContratoInicio = day;
      } else {
        _novoContratoFim = day;
      }
      if (_novoContratoFim != null &&
          _novoContratoInicio != null &&
          _novoContratoFim!.isBefore(_novoContratoInicio!)) {
        _novoContratoFim = _novoContratoInicio;
      }
    });
  }

  /// Abre grade (tabela) de usuários do convênio UNIMIL (`id` unimil ou plano premium_unimil).
  Future<void> _abrirGradeUnimil(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    QueryDocumentSnapshot<Map<String, dynamic>>? target;
    for (final d in docs) {
      if (d.id.toLowerCase() == 'unimil') {
        target = d;
        break;
      }
    }
    if (target == null) {
      for (final d in docs) {
        final pc =
            (d.data()['planCode'] ?? '').toString().trim().toLowerCase();
        if (pc == 'premium_unimil') {
          target = d;
          break;
        }
      }
    }
    if (target == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhum convênio UNIMIL encontrado (id «unimil» ou plano premium_unimil). Cadastre em «Novo convênio».',
          ),
        ),
      );
      return;
    }
    final id = target.id;
    final plan =
        (target.data()['planCode'] ?? 'premium_unimil').toString();
    final name = (target.data()['name'] ?? id).toString();
    await openPartnershipUsersPreview(
      context,
      partnershipId: id,
      partnershipPlanCode: plan,
      partnershipName: name,
    );
  }

  String _slugify(String v) {
    return v
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  Future<void> _saveConvenio() async {
    final idRaw = _idCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final slug = _slugify(idRaw);
    final days = int.tryParse(_daysCtrl.text.trim()) ?? 365;
    var planCode = _newPlanCodeCtrl.text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '');
    if (planCode.isEmpty) planCode = 'premium_assego';
    if (slug.isEmpty || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe ID curto (slug) e nome do convênio/parceria.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await FunctionsService().createOrUpdatePartnership(
        id: slug,
        slug: slug,
        name: name,
        durationDays: days <= 0 ? 365 : days,
        planCode: planCode,
        active: true,
        autoApplyOnSignup: true,
        contractStartsAtIso: _novoContratoInicio == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(_novoContratoInicio!),
        contractEndsAtIso: _novoContratoFim == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(_novoContratoFim!),
      );
      final q =
          int.tryParse(_novoTetoUsuariosCtrl.text.trim()) ?? 4000;
      final exPrice = _parseMoneyNovoConvenio(_novoValorExcedenteCtrl.text);
      final quotaOk = await _saveQuotaBillingParams(
        slug,
        includedUsersQuota: q.clamp(1, 9999999),
        excessUserUnitPrice: exPrice,
        showSuccessSnack: false,
        silentErrors: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            quotaOk
                ? 'Convênio "$name" salvo (plano, vigência se informada, teto e excedente).'
                : 'Convênio "$name" criado, mas não foi possível gravar teto/excedente — tente de novo no card do convênio.',
          ),
          backgroundColor: quotaOk ? AppColors.success : Colors.orange.shade800,
        ),
      );
      _idCtrl.clear();
      _nameCtrl.clear();
      _daysCtrl.text = '365';
      _newPlanCodeCtrl.text = 'premium_assego';
      setState(() {
        _novoContratoInicio = null;
        _novoContratoFim = null;
      });
      _novoTetoUsuariosCtrl.text = '4000';
      _novoValorExcedenteCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar convênio: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Cartão premium alinhado ao consolidado (borda índigo, sombra, cabeçalho com gradiente).
  Widget _partnershipAdminPremiumCard({
    required String title,
    String? subtitle,
    required IconData headerIcon,
    required Widget child,
  }) {
    return RepaintBoundary(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF1A237E).withValues(alpha: 0.1)),
            boxShadow: [
              BoxShadow(
                color: widget.brandBlue.withValues(alpha: 0.07),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [widget.brandBlue, widget.brandTeal],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(headerIcon, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Formulário «Novo convênio» (lista principal e tela cheia).
  Widget _buildNovoConvenioFormSection({bool showTitleBlock = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitleBlock) ...[
        const Text(
          'Novo convênio',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Ao salvar, o perfil do convênio fica pronto no Firestore e o link público já pode ser divulgado.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: FastTextField(
                controller: _idCtrl,
                decoration: const InputDecoration(
                  labelText: 'ID (slug)',
                  hintText: 'minha_empresa',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FastTextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nome',
                  hintText: 'Nome do parceiro',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FastTextField(
                controller: _daysCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Duração (dias)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FastTextField(
                controller: _newPlanCodeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Plano do convênio (controle)',
                  hintText: 'premium_unimil, premium_assego, premium…',
                  helperText:
                      'Permissões no app = mesmo pacote premium; o código identifica o convênio.',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ActionChip(
              label: const Text('premium'),
              onPressed: () {
                _newPlanCodeCtrl.text = 'premium';
                setState(() {});
              },
            ),
            ActionChip(
              label: const Text('premium_assego'),
              onPressed: () {
                _newPlanCodeCtrl.text = 'premium_assego';
                setState(() {});
              },
            ),
            ActionChip(
              label: const Text('premium_unimil'),
              onPressed: () {
                _newPlanCodeCtrl.text = 'premium_unimil';
                setState(() {});
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Vigência do contrato (opcional)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: () => _pickNovoContratoDate(true),
              icon: const Icon(Icons.date_range_rounded, size: 18),
              label: Text(
                _novoContratoInicio == null
                    ? 'Data inicial'
                    : 'Início ${DateFormat('dd/MM/yyyy').format(_novoContratoInicio!)}',
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _pickNovoContratoDate(false),
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text(
                _novoContratoFim == null
                    ? 'Data final'
                    : 'Fim ${DateFormat('dd/MM/yyyy').format(_novoContratoFim!)}',
              ),
            ),
            TextButton.icon(
              onPressed: () => setState(() {
                _novoContratoInicio = null;
                _novoContratoFim = null;
              }),
              icon: const Icon(Icons.clear_rounded),
              label: const Text('Limpar datas'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Teto de usuários e valor do excedente (franquia/cobrança)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 520;
            final teto = FastTextField(
              controller: _novoTetoUsuariosCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: const InputDecoration(
                labelText: 'Teto (usuários incluídos)',
                helperText: 'Ex.: 4000 — referência orçamento 4K.',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            );
            final exced = BrlAmountTextField(
              controller: _novoValorExcedenteCtrl,
              decoration: const InputDecoration(
                labelText: 'Valor por usuário excedente (R\$)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            );
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  teto,
                  const SizedBox(height: 8),
                  exced,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: teto),
                const SizedBox(width: 8),
                Expanded(child: exced),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _saving ? null : _saveConvenio,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(_saving ? 'Salvando...' : 'Salvar convênio'),
          ),
        ),
      ],
    );
  }

  void _openNovoConvenioFullscreen() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          resizeToAvoidBottomInset: scaffoldKeyboardResizeToAvoidBottomInset(),
          backgroundColor: const Color(0xFFF0F4F9),
          appBar: AppBar(
            title: const Text('Incluir convênio'),
            leading: IconButton(
              tooltip: 'Fechar',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ModuleHeaderPremium(
                  title: 'Novo convênio',
                  icon: Icons.add_business_rounded,
                  subtitle:
                      'Cadastro dedicado em tela cheia — teclado e campos sem interferência de seleção.',
                ),
                const SizedBox(height: 12),
                _partnershipAdminPremiumCard(
                  title: 'Identificação e contrato',
                  subtitle:
                      'Slug, nome, plano, vigência e teto — mesmo fluxo da lista principal.',
                  headerIcon: Icons.app_registration_rounded,
                  child: _buildNovoConvenioFormSection(showTitleBlock: false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeactivatePartnership(
    BuildContext routeContext,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final m = doc.data();
    final nome = (m['name'] ?? doc.id).toString();
    final ok = await showDialog<bool>(
      context: routeContext,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Desativar convênio'),
        content: Text(
          'O convênio «$nome» será marcado como inativo. Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text('Desativar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final slugRaw = (m['slug'] ?? doc.id).toString().trim();
      final slug = slugRaw.isEmpty ? doc.id : slugRaw;
      var planCode =
          _normalizePartnershipPlanCode(m['planCode']?.toString());
      planCode = planCode.replaceAll(RegExp(r'[^a-z0-9_]'), '');
      if (planCode.isEmpty) planCode = 'premium_assego';
      final days = int.tryParse('${m['durationDays'] ?? 365}') ?? 365;
      String isoStart = '';
      String isoEnd = '';
      final cs = m['contractStartsAt'];
      if (cs is Timestamp) {
        final d = cs.toDate();
        isoStart = DateFormat('yyyy-MM-dd')
            .format(DateTime(d.year, d.month, d.day));
      }
      final ce = m['contractEndsAt'];
      if (ce is Timestamp) {
        final d = ce.toDate();
        isoEnd = DateFormat('yyyy-MM-dd')
            .format(DateTime(d.year, d.month, d.day));
      }
      final extRaw = m['licenseRenewalExtensionDays'];
      final extVal =
          extRaw is num ? extRaw.toInt() : int.tryParse('$extRaw') ?? 0;

      await FunctionsService().createOrUpdatePartnership(
        id: doc.id,
        slug: slug,
        name: nome.isEmpty ? doc.id : nome,
        durationDays: days <= 0 ? 365 : days,
        planCode: planCode,
        active: false,
        autoApplyOnSignup: m['autoApplyOnSignup'] != false,
        contractStartsAtIso: isoStart,
        contractEndsAtIso: isoEnd,
        licenseRenewalExtensionDays: extVal.clamp(0, 120),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Convênio «$nome» desativado.'),
          backgroundColor: AppColors.success,
        ),
      );
      if (routeContext.mounted) Navigator.of(routeContext).pop();
    } catch (e) {
      if (!routeContext.mounted) return;
      ScaffoldMessenger.of(routeContext).showSnackBar(
        SnackBar(
          content: Text('Erro ao desativar: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _renewPartnership(String partnershipId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Prorrogar licenças'),
        content: Text(
          'Deseja prorrogar +1 ciclo para os usuários do convênio "$partnershipId"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Prorrogar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final res = await FunctionsService()
          .renewPartnershipLicenses(partnershipId: partnershipId);
      if (!mounted) return;
      final renewed = (res['renewed'] ?? 0).toString();
      final total = (res['total'] ?? 0).toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Convênio $partnershipId: $renewed/$total licença(s) prorrogada(s).',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao prorrogar: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _markSubmissionChecked(
    String partnershipId,
    String submissionId,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('partnerships')
          .doc(partnershipId)
          .collection('submissions')
          .doc(submissionId)
          .set(
            {
              'status': 'conferido',
              'checkedAt': FieldValue.serverTimestamp(),
              'checkedBy': FirebaseAuth.instance.currentUser?.uid,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cadastro marcado como conferido no painel ADM.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao marcar conferido: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _saveCsvSourceUrl(String partnershipId, String url) async {
    final trimmed = url.trim();
    try {
      await FirebaseFirestore.instance
          .collection('partnerships')
          .doc(partnershipId)
          .set(
            {
              if (trimmed.isEmpty) ...{
                'csvSourceUrl': FieldValue.delete(),
                'csvPendingAdminReview': false,
                'csvImportFlowStatus': FieldValue.delete(),
                'csvImportFlowMessage': FieldValue.delete(),
              },
              if (trimmed.isNotEmpty) ...{
                'csvSourceUrl': trimmed,
                'csvPendingAdminReview': true,
                'csvImportFlowStatus': 'url_saved',
                'csvImportFlowUpdatedAt': FieldValue.serverTimestamp(),
              },
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL do CSV salva no convênio.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar URL: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _saveFinancialParams(
    String partnershipId, {
    required double costPerUser,
    required double revenuePerUser,
    double contractMonthlyIncome = 0,
    int contractDurationMonths = 12,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('partnerships')
          .doc(partnershipId)
          .set(
        {
          'costPerUser': costPerUser,
          'revenuePerUser': revenuePerUser,
          'contractMonthlyIncome': contractMonthlyIncome,
          'contractDurationMonths': contractDurationMonths < 1 ? 12 : contractDurationMonths,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Parâmetros financeiros salvos no convênio.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar parâmetros financeiros: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  /// Franquia de usuários (ex.: 4K) e preço por excedente — só controle / cobrança no painel.
  /// Retorna `false` se falhar (exceto quando [silentErrors] omite o snack de erro).
  Future<bool> _saveQuotaBillingParams(
    String partnershipId, {
    required int includedUsersQuota,
    required double excessUserUnitPrice,
    /// Evita snack duplicado ao salvar «Novo convênio» (já há confirmação geral).
    bool showSuccessSnack = true,
    bool silentErrors = false,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('partnerships')
          .doc(partnershipId)
          .set(
        {
          'includedUsersQuota': includedUsersQuota.clamp(1, 9999999),
          'excessUserUnitPrice': excessUserUnitPrice < 0 ? 0.0 : excessUserUnitPrice,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (!mounted) return false;
      if (showSuccessSnack) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Franquia e preço de excedente salvos no convênio.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
      return true;
    } catch (e) {
      if (!mounted) return false;
      if (!silentErrors) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar franquia: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return false;
    }
  }

  Future<void> _importCsvManualFromPicker(
    String partnershipId, {
    bool removeMissingNotInCsv = false,
  }) async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'txt'],
      withData: true,
    );
    if (r == null || r.files.isEmpty) return;
    final bytes = r.files.first.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível ler o arquivo.')),
      );
      return;
    }
    final csvText = utf8.decode(bytes, allowMalformed: true);
    if (csvText.length > 900000) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Arquivo muito grande (máx. ~900 KB). Use importação por URL ou divida o CSV.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Enviando CSV para importação no servidor...')),
    );
    try {
      final res = await FunctionsService().importPartnershipCsvManual(
        partnershipId: partnershipId,
        csvText: csvText,
        removeMissingNotInCsv: removeMissingNotInCsv,
      );
      if (!mounted) return;
      final imported = res['imported'];
      final backendMsg = (res['message'] ?? '').toString().trim();
      final msg = backendMsg.isNotEmpty
          ? backendMsg
          : imported != null
              ? 'Importação manual concluída (importados/atualizados: $imported).'
              : 'Importação manual concluída.';
      await FirebaseFirestore.instance
          .collection('partnerships')
          .doc(partnershipId)
          .set(
            {
              'csvPendingAdminReview': true,
              'csvImportFlowStatus': 'manual_upload',
              'csvImportFlowMessage': msg,
              'csvImportFlowUpdatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$msg Revise membros/usuários e toque em «Conferência OK» quando estiver tudo certo.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      final friendly = _friendlyCsvSyncError(e);
      try {
        await FirebaseFirestore.instance
            .collection('partnerships')
            .doc(partnershipId)
            .set(
              {
                'csvPendingAdminReview': true,
                'csvImportFlowStatus': 'manual_upload_error',
                'csvImportFlowMessage': friendly,
                'csvImportFlowUpdatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro na importação manual: $friendly'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _syncCsvNow(
    String partnershipId, {
    String? csvUrl,
    bool removeMissingNotInCsv = false,
  }) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sincronizando CSV no servidor...')),
    );
    try {
      final res = await FunctionsService().syncPartnershipCsvSource(
        partnershipId: partnershipId,
        csvUrl: csvUrl,
        removeMissingNotInCsv: removeMissingNotInCsv,
      );
      if (!mounted) return;
      final imported = res['imported'];
      final backendMsg = (res['message'] ?? '').toString().trim();
      final msg = backendMsg.isNotEmpty
          ? backendMsg
          : imported != null
              ? 'Sincronização concluída (importados/atualizados: $imported).'
              : 'Sincronização concluída.';
      final prune = res['pruneSummary'];
      var pruneLine = '';
      if (prune is Map) {
        final mu = prune['updatedUsers'];
        final mm = prune['removedMembers'];
        if (mu != null || mm != null) {
          pruneLine =
              ' Remoção automática (quem saiu do CSV): ${mm ?? 0} membro(s), ${mu ?? 0} usuário(s) ajustado(s).';
        }
      }
      await FirebaseFirestore.instance
          .collection('partnerships')
          .doc(partnershipId)
          .set(
            {
              'csvPendingAdminReview': true,
              'csvImportFlowStatus': 'synced',
              'csvImportFlowMessage': msg,
              'csvImportFlowUpdatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$msg$pruneLine Revise membros/usuários e toque em «Conferência OK» no CSV quando estiver tudo certo.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      final friendly = _friendlyCsvSyncError(e);
      try {
        await FirebaseFirestore.instance
            .collection('partnerships')
            .doc(partnershipId)
            .set(
              {
                'csvPendingAdminReview': true,
                'csvImportFlowStatus': 'sync_error',
                'csvImportFlowMessage': friendly,
                'csvImportFlowUpdatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro na sincronização: $friendly'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  String _friendlyCsvSyncError(Object e) {
    if (e is FirebaseFunctionsException) {
      final msg = (e.message ?? '').toString().trim();
      if (msg.isNotEmpty) return msg;
      switch (e.code) {
        case 'failed-precondition':
          return 'O CSV foi recebido, mas ainda não está no formato esperado para importação.';
        case 'invalid-argument':
          return 'Verifique o CSV (URL http(s) ou arquivo .csv com e-mails válidos; máx. ~900 KB no upload manual).';
        case 'permission-denied':
          return 'Ação restrita ao administrador.';
        default:
          return 'Falha ao sincronizar CSV (código: ${e.code}).';
      }
    }
    return e.toString().split('\n').first.trim();
  }

  /// Fluxo controlado: URL gravada no Firestore + import no servidor + flag para você conferir.
  Future<void> _pipelineCsvExterno(
    String partnershipId,
    String url, {
    bool removeMissingNotInCsv = false,
  }) async {
    final t = url.trim();
    if (t.isEmpty ||
        (!t.startsWith('http://') && !t.startsWith('https://'))) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Informe uma URL http(s) pública do CSV (o programador externo mantém o arquivo; o sistema baixa e importa).',
          ),
        ),
      );
      return;
    }
    await _saveCsvSourceUrl(partnershipId, t);
    await _syncCsvNow(
      partnershipId,
      csvUrl: t,
      removeMissingNotInCsv: removeMissingNotInCsv,
    );
  }

  Future<void> _dismissCsvAdminReview(String partnershipId) async {
    try {
      await FirebaseFirestore.instance
          .collection('partnerships')
          .doc(partnershipId)
          .set(
            {'csvPendingAdminReview': false},
            SetOptions(merge: true),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conferência registrada. Fluxo CSV marcado como OK por você.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao atualizar conferência: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _copyReportCsvLine({
    required String partnershipId,
    required String name,
    String? partnershipPlanCode,
  }) async {
    try {
      final fs = FirebaseFirestore.instance;
      final base = fs.collection('partnerships').doc(partnershipId);
      final members =
          await base.collection('members').where('active', isEqualTo: true).count().get();
      final usersCount = await countUsersPartnershipInPeriod(
        fs,
        partnershipId,
        0,
        partnershipPlanCode: partnershipPlanCode,
      );
      final subs = await base.collection('submissions').count().get();
      final since = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 7)),
      );
      final subs7d = await base
          .collection('submissions')
          .where('createdAt', isGreaterThan: since)
          .count()
          .get();
      final line =
          'id;$name;membros_ativos;usuarios_app;submissoes_total;submissoes_7d\n'
          '$partnershipId;"$name";${members.count};$usersCount;${subs.count};${subs7d.count}\n';
      await Clipboard.setData(ClipboardData(text: line));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Relatório (1 linha + cabeçalho) copiado para a área de transferência.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao montar relatório: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _copyMembersEmailsSample(String partnershipId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('partnerships')
          .doc(partnershipId)
          .collection('members')
          .orderBy('email')
          .limit(800)
          .get();
      final emails = snap.docs
          .map((d) => (d.data()['email'] ?? '').toString().trim().toLowerCase())
          .where((e) => e.contains('@'))
          .toList();
      if (emails.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhum membro com e-mail encontrado.')),
        );
        return;
      }
      await Clipboard.setData(ClipboardData(text: emails.join('\n')));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${emails.length} e-mail(s) copiados (até 800).'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao exportar e-mails: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  String _labelAssociacaoSelecionada(
    String? pid,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (pid == null) return 'Todas as associações';
    for (final d in docs) {
      if (d.id == pid) {
        final nm = (d.data()['name'] ?? d.id).toString();
        return '$nm (${d.id})';
      }
    }
    return pid;
  }

  Future<void> _abrirSeletorAssociacaoComBusca(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final searchCtrl = TextEditingController();
    try {
      final picked = await showModalBottomSheet<_PartnershipPickResult>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setModal) {
              final q = searchCtrl.text.trim().toLowerCase();
              final filtered = docs.where((d) {
                if (q.isEmpty) return true;
                final name = (d.data()['name'] ?? '').toString().toLowerCase();
                final slug =
                    (d.data()['slug'] ?? d.id).toString().toLowerCase();
                final id = d.id.toLowerCase();
                return name.contains(q) || slug.contains(q) || id.contains(q);
              }).toList()
                ..sort((a, b) {
                  final na = (a.data()['name'] ?? a.id).toString();
                  final nb = (b.data()['name'] ?? b.id).toString();
                  return na.toLowerCase().compareTo(nb.toLowerCase());
                });
              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: AppKeyboardInsets.of(ctx),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: Text(
                          'Buscar associação / convênio',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey.shade900,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: FastTextField(
                          controller: searchCtrl,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search_rounded),
                            hintText: 'Nome, slug ou ID…',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (_) => setModal(() {}),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.select_all_rounded),
                        title: const Text('Todas as associações'),
                        subtitle: const Text('Consolidado e lista completos'),
                        minVerticalPadding: 14,
                        onTap: () =>
                            Navigator.pop(ctx, const _PartnershipPickResult.all()),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text(
                          '${filtered.length} resultado(s)',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 420),
                        child: filtered.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'Nenhum convênio encontrado para "$q".',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey.shade700),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: filtered.length,
                                itemBuilder: (ctx, i) {
                                  final d = filtered[i];
                                  final nm =
                                      (d.data()['name'] ?? d.id).toString();
                                  final slug =
                                      (d.data()['slug'] ?? d.id).toString();
                                  return ListTile(
                                    minVerticalPadding: 14,
                                    title: Text(nm),
                                    subtitle: Text(
                                      '${d.id} • slug: $slug',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () => Navigator.pop(
                                      ctx,
                                      _PartnershipPickResult.one(d.id),
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
      if (!mounted || picked == null) return;
      setState(() {
        if (picked.all) {
          _filtroPartnershipId = null;
        } else {
          _filtroPartnershipId = picked.id;
        }
      });
    } finally {
      searchCtrl.dispose();
    }
  }

  ({List<double> values, List<String> labels}) _chartFromSubmissions(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = List.generate(
      7,
      (i) => today.subtract(Duration(days: 6 - i)),
    );
    final counts = List<double>.filled(7, 0);
    for (final doc in docs) {
      final ts = doc.data()['createdAt'];
      if (ts is! Timestamp) continue;
      final d = DateTime(ts.toDate().year, ts.toDate().month, ts.toDate().day);
      final idx = days.indexWhere(
        (x) => x.year == d.year && x.month == d.month && x.day == d.day,
      );
      if (idx >= 0) counts[idx] += 1;
    }
    final fmt = DateFormat('dd/MM');
    final labels = days.map(fmt.format).toList();
    return (values: counts, labels: labels);
  }

  @override
  Widget build(BuildContext context) {
    return SelectionContainer.disabled(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: AdminPageShell.listPadding(context, top: 8),
        children: [
          ModuleHeaderPremium(
            title: 'Convênios e parcerias',
            icon: Icons.handshake_rounded,
            subtitle:
                'Cadastre o parceiro, use o link público automático, acompanhe cadastros, gráficos e volume de dados no Firestore (membros, usuários vinculados e submissões).',
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FilledButton.tonalIcon(
                onPressed: _openNovoConvenioFullscreen,
                icon: const Icon(Icons.add_business_rounded),
                label: const Text('Incluir convênio — tela cheia'),
              ),
            ),
          ),
          const SizedBox(height: 6),
          _partnershipAdminPremiumCard(
            title: 'Novo convênio',
            subtitle:
                'Ao salvar, o perfil do convênio fica pronto no Firestore e o link público já pode ser divulgado.',
            headerIcon: Icons.add_business_rounded,
            child: _buildNovoConvenioFormSection(showTitleBlock: false),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('partnerships')
                .orderBy('name')
                .snapshots(),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? [];
              if (snap.hasError) {
                return _partnershipAdminPremiumCard(
                  title: 'Erro ao carregar convênios',
                  headerIcon: Icons.error_outline_rounded,
                  child: Text(
                    '${snap.error}',
                    style: TextStyle(color: Colors.red.shade800, fontSize: 13, height: 1.35),
                  ),
                );
              }
              if (docs.isEmpty) {
                return _partnershipAdminPremiumCard(
                  title: 'Nenhum convênio cadastrado',
                  subtitle:
                      'Use o formulário «Novo convênio» acima ou «Incluir convênio — tela cheia» para criar o primeiro parceiro.',
                  headerIcon: Icons.inbox_rounded,
                  child: const SizedBox.shrink(),
                );
              }
              final selectedPid = _filtroPartnershipId != null &&
                      docs.any((d) => d.id == _filtroPartnershipId)
                  ? _filtroPartnershipId
                  : null;
              var filteredDocs = selectedPid == null
                  ? docs
                  : docs.where((d) => d.id == selectedPid).toList();
              if (_filtroPlanCode != null && _filtroPlanCode!.isNotEmpty) {
                final fp = _filtroPlanCode!.trim().toLowerCase();
                filteredDocs = filteredDocs
                    .where((d) {
                      final pc = (d.data()['planCode'] ?? '')
                          .toString()
                          .trim()
                          .toLowerCase();
                      return pc == fp;
                    })
                    .toList();
              }
              return Column(
                children: [
                  _partnershipAdminPremiumCard(
                    title: 'Filtros — consolidado e financeiro',
                    subtitle:
                        'Período usa a data de cadastro (createdAt) em usuários e membros. '
                        'Se não houver usuário vinculado no período, usa membros ativos no período.',
                    headerIcon: Icons.filter_alt_rounded,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Text(
                            'Plano do convênio (consulta)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('Todos os planos'),
                                selected: _filtroPlanCode == null,
                                onSelected: (_) =>
                                    setState(() => _filtroPlanCode = null),
                              ),
                              ChoiceChip(
                                label: const Text('premium'),
                                selected: _filtroPlanCode == 'premium',
                                onSelected: (_) => setState(
                                    () => _filtroPlanCode = 'premium'),
                              ),
                              ChoiceChip(
                                label: const Text('premium_assego'),
                                selected: _filtroPlanCode == 'premium_assego',
                                onSelected: (_) => setState(
                                    () => _filtroPlanCode = 'premium_assego'),
                              ),
                              ChoiceChip(
                                label: const Text('premium_unimil'),
                                selected: _filtroPlanCode == 'premium_unimil',
                                onSelected: (sel) {
                                  setState(() => _filtroPlanCode =
                                      sel ? 'premium_unimil' : null);
                                  if (sel) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      if (!context.mounted) return;
                                      _abrirGradeUnimil(context, docs);
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Filtra a lista e o consolidado pelo campo planCode do convênio. '
                            'Ao escolher premium_unimil, abre também a grade de usuários. '
                            'Não altera permissões dos usuários no app.',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              alignment: Alignment.centerLeft,
                            ),
                            icon: const Icon(Icons.grid_on_rounded),
                            label: const Text(
                              'UNIMIL — grade de usuários (mesmo atalho do chip premium_unimil)',
                            ),
                            onPressed: docs.isEmpty
                                ? null
                                : () => _abrirGradeUnimil(context, docs),
                          ),
                          Text(
                            'Convênio id «unimil» ou o primeiro com plano premium_unimil.',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('Todo período'),
                                selected: _filtroFinancePeriodoDias == 0,
                                onSelected: (_) => setState(
                                    () => _filtroFinancePeriodoDias = 0),
                              ),
                              ChoiceChip(
                                label: const Text('30 dias'),
                                selected: _filtroFinancePeriodoDias == 30,
                                onSelected: (_) => setState(
                                    () => _filtroFinancePeriodoDias = 30),
                              ),
                              ChoiceChip(
                                label: const Text('90 dias'),
                                selected: _filtroFinancePeriodoDias == 90,
                                onSelected: (_) => setState(
                                    () => _filtroFinancePeriodoDias = 90),
                              ),
                              ChoiceChip(
                                label: const Text('365 dias'),
                                selected: _filtroFinancePeriodoDias == 365,
                                onSelected: (_) => setState(
                                    () => _filtroFinancePeriodoDias = 365),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Associação / convênio',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 14),
                                    alignment: Alignment.centerLeft,
                                  ),
                                  icon: const Icon(Icons.business_rounded,
                                      size: 22),
                                  label: Text(
                                    _labelAssociacaoSelecionada(
                                        selectedPid, docs),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onPressed: () =>
                                      _abrirSeletorAssociacaoComBusca(docs),
                                ),
                              ),
                              if (selectedPid != null) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: 'Limpar filtro de associação',
                                  onPressed: () => setState(
                                      () => _filtroPartnershipId = null),
                                  icon: const Icon(Icons.clear_rounded),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Toque para buscar por nome, slug ou ID — útil quando há muitos convênios.',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ConsolidadoConveniosCard(
                    docs: filteredDocs,
                    periodDays: _filtroFinancePeriodoDias,
                  ),
                  const SizedBox(height: 10),
                  ...filteredDocs.map((d) {
                  final m = d.data();
                  final id = d.id;
                  final publicSlug =
                      (m['slug'] ?? id).toString().trim().toLowerCase();
                  final publicLink =
                      'https://wisdomapp-b9e98.web.app/convenio_usuarios?id=$publicSlug';
                  final name = (m['name'] ?? id).toString();
                  final days = (m['durationDays'] ?? 365).toString();
                  final planCode =
                      (m['planCode'] ?? 'premium_assego').toString();
                  final active = m['active'] != false;
                  final csvUrl = (m['csvSourceUrl'] ?? '').toString();
                  final csvStatus = (m['csvLastSyncStatus'] ?? '').toString();
                  final csvErr = (m['csvLastSyncError'] ?? '').toString();
                  final csvPendingReview = m['csvPendingAdminReview'] == true;
                  final costPerUser = (m['costPerUser'] is num)
                      ? (m['costPerUser'] as num).toDouble()
                      : 0.0;
                  final revenuePerUser = (m['revenuePerUser'] is num)
                      ? (m['revenuePerUser'] as num).toDouble()
                      : 0.0;
                  final contractMonthlyIncome = (m['contractMonthlyIncome'] is num)
                      ? (m['contractMonthlyIncome'] as num).toDouble()
                      : 0.0;
                  final contractDurationMonths = (m['contractDurationMonths'] is num)
                      ? (m['contractDurationMonths'] as num).toInt().clamp(1, 600)
                      : 12;
                  final includedUsersQuota = (m['includedUsersQuota'] is num)
                      ? (m['includedUsersQuota'] as num).toInt().clamp(1, 9999999)
                      : 4000;
                  final excessUserUnitPrice = (m['excessUserUnitPrice'] is num)
                      ? (m['excessUserUnitPrice'] as num).toDouble()
                      : 0.0;
                  final vigLine = _formatPartnershipVigenciaSubtitle(m);
                  final screenW = MediaQuery.sizeOf(context).width;
                  final narrowTop = screenW < 400;
                  final narrowActionsRow = screenW < 420;

                  List<Widget> partnershipPanels(BuildContext panelCtx) {
                    return [
                          _PartnershipVigenciaEditor(
                            partnershipId: id,
                            partnershipData: m,
                          ),
                          const SizedBox(height: 10),
                          _PartnershipMetricsRow(
                            partnershipId: id,
                            partnershipPlanCode: planCode,
                          ),
                          const SizedBox(height: 10),
                          _PartnershipQuotaBillingPanel(
                            partnershipId: id,
                            partnershipPlanCode: planCode,
                            partnershipName: name,
                            includedUsersQuota: includedUsersQuota,
                            excessUserUnitPrice: excessUserUnitPrice,
                            onSave:
                                ({
                                  required includedUsersQuota,
                                  required excessUserUnitPrice,
                                }) =>
                                    _saveQuotaBillingParams(
                                      id,
                                      includedUsersQuota: includedUsersQuota,
                                      excessUserUnitPrice: excessUserUnitPrice,
                                    ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Uso no banco (Firestore): contagens neste convênio — '
                            'membros ativos, usuários do app (partnershipId ou plano igual ao do convênio, ex.: premium_assego, se alterado manualmente no painel) e submissões pelo link. '
                            'Não inclui escalas/transações dos usuários.',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFD9E2EC)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Link público do convênio',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF334155),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SelectableText(
                                  publicLink,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E40AF),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () async {
                                        await Clipboard.setData(
                                          ClipboardData(text: publicLink),
                                        );
                                        if (!panelCtx.mounted) return;
                                        ScaffoldMessenger.of(panelCtx).showSnackBar(
                                          const SnackBar(
                                            content: Text('Link público copiado.'),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.copy_rounded),
                                      label: const Text('Copiar link'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: () => url_helper.openUrlPreferChrome(
                                            publicLink,
                                          ),
                                      icon: const Icon(Icons.open_in_new_rounded),
                                      label: const Text('Abrir link'),
                                    ),
                                    if (id == 'assego')
                                      OutlinedButton.icon(
                                        onPressed: () => url_helper.openUrlPreferChrome(
                                              'https://wisdomapp-b9e98.web.app/assego_usuarios',
                                            ),
                                        icon: const Icon(Icons.link_rounded),
                                        label: const Text('Link legado ASSEGO'),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _PartnershipFinancialPanel(
                            partnershipId: id,
                            partnershipPlanCode: planCode,
                            periodDays: _filtroFinancePeriodoDias,
                            costPerUser: costPerUser,
                            revenuePerUser: revenuePerUser,
                            contractMonthlyIncome: contractMonthlyIncome,
                            contractDurationMonths: contractDurationMonths,
                            onSaveParams:
                                ({
                                  required costPerUser,
                                  required revenuePerUser,
                                  required contractMonthlyIncome,
                                  required contractDurationMonths,
                                }) {
                              return _saveFinancialParams(
                                id,
                                costPerUser: costPerUser,
                                revenuePerUser: revenuePerUser,
                                contractMonthlyIncome: contractMonthlyIncome,
                                contractDurationMonths: contractDurationMonths,
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          _PartnershipManualEmailCard(partnershipId: id),
                          const SizedBox(height: 12),
                          PartnershipUsersPanel(
                            partnershipId: id,
                            partnershipPlanCode: planCode,
                            scope: PartnershipUsersPreviewScope.byPartnership,
                            conveniosCatalog: const <AdminPartnershipPlanOption>[],
                            useRichUserCards: AdminResponsive.useMobileLayout(panelCtx),
                          ),
                          const SizedBox(height: 12),
                          _CsvSourceBlock(
                            partnershipId: id,
                            initialUrl: csvUrl,
                            csvStatus: csvStatus,
                            csvErr: csvErr,
                            csvPendingAdminReview: csvPendingReview,
                            onSaveUrl: (u) => _saveCsvSourceUrl(id, u),
                            onSync: (u, rm) => _syncCsvNow(
                              id,
                              csvUrl: u.isEmpty ? null : u,
                              removeMissingNotInCsv: rm,
                            ),
                            onPipelineExternal: (u, rm) => _pipelineCsvExterno(
                              id,
                              u,
                              removeMissingNotInCsv: rm,
                            ),
                            onDismissReview: () => _dismissCsvAdminReview(id),
                            onPickCsvFile: (rm) => _importCsvManualFromPicker(
                              id,
                              removeMissingNotInCsv: rm,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: const Text(
                              'Fluxo recomendado: URL CSV pública (parceiro mantém o link). Alternativa: upload manual do arquivo .csv aqui no painel — mesma conferência e status no convênio. Usuários em plano de convênio (premium_*) têm o mesmo pacote de acesso premium na web/app conforme licença ativa.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF334155),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: FirebaseFirestore.instance
                                .collection('partnerships')
                                .doc(id)
                                .collection('submissions')
                                .orderBy('createdAt', descending: true)
                                .limit(120)
                                .snapshots(),
                            builder: (context, subSnap) {
                              final subDocs = subSnap.data?.docs ?? [];
                              final chart = _chartFromSubmissions(subDocs);
                              final pending = subDocs
                                  .where(
                                    (x) =>
                                        (x.data()['status'] ?? 'novo')
                                            .toString() !=
                                        'conferido',
                                  )
                                  .length;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'Cadastros pelo link (últimos envios)',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      if (pending > 0)
                                        Chip(
                                          label: Text('$pending a conferir'),
                                          backgroundColor: Colors.orange.shade100,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  AppBarChart(
                                    title: 'Cadastros nos últimos 7 dias (amostra até 120 envios)',
                                    values: chart.values,
                                    labels: chart.labels,
                                    barColor: widget.brandBlue,
                                    height: 160,
                                  ),
                                  const SizedBox(height: 8),
                                  if (subDocs.isEmpty)
                                    Text(
                                      'Nenhum cadastro pelo formulário público ainda.',
                                      style: TextStyle(color: Colors.grey.shade600),
                                    )
                                  else
                                    ...subDocs.take(10).map((doc) {
                                      final data = doc.data();
                                      final status =
                                          (data['status'] ?? 'novo').toString();
                                      final nome =
                                          (data['name'] ?? '-').toString();
                                      final email =
                                          (data['email'] ?? '-').toString();
                                      final createdAt =
                                          (data['createdAt'] as Timestamp?)
                                              ?.toDate();
                                      final when = createdAt != null
                                          ? DateFormat('dd/MM/yyyy HH:mm')
                                              .format(createdAt)
                                          : '--';
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: status == 'conferido'
                                              ? Colors.green.shade50
                                              : Colors.orange.shade50,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: status == 'conferido'
                                                ? Colors.green.shade200
                                                : Colors.orange.shade200,
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    '$nome • $email',
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Recebido em $when • Status: $status',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Color(0xFF475569),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (status != 'conferido')
                                              TextButton(
                                                onPressed: () =>
                                                    _markSubmissionChecked(
                                                  id,
                                                  doc.id,
                                                ),
                                                child: const Text('Marcar conferido'),
                                              ),
                                          ],
                                        ),
                                      );
                                    }),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Relatórios rápidos',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _copyReportCsvLine(
                                  partnershipId: id,
                                  name: name,
                                  partnershipPlanCode: planCode,
                                ),
                                icon: const Icon(Icons.analytics_outlined),
                                label: const Text('Copiar resumo CSV'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _copyMembersEmailsSample(id),
                                icon: const Icon(Icons.mark_email_read_outlined),
                                label: const Text('Copiar e-mails membros'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: () => _renewPartnership(id),
                                icon: const Icon(Icons.autorenew_rounded),
                                label: const Text('Prorrogar +1 ciclo'),
                              ),
                            ],
                          ),
                        ];
                  }

                  void openFullPartnershipPanel() {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        fullscreenDialog: true,
                        builder: (ctx) => Scaffold(
                          resizeToAvoidBottomInset: scaffoldKeyboardResizeToAvoidBottomInset(),
                          backgroundColor: const Color(0xFFF0F4F9),
                          appBar: AppBar(
                            title: Text(name),
                            leading: IconButton(
                              tooltip: 'Fechar',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                            actions: [
                              TextButton.icon(
                                onPressed: () =>
                                    _confirmDeactivatePartnership(ctx, d),
                                icon: Icon(Icons.visibility_off_outlined,
                                    color: Colors.orange.shade900),
                                label: const Text('Desativar'),
                              ),
                            ],
                          ),
                          body: SafeArea(
                            child: ListView(
                              padding: const EdgeInsets.all(16),
                              children: partnershipPanels(ctx),
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  void openEditPartnershipOnly() {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        fullscreenDialog: true,
                        builder: (ctx) => Scaffold(
                          resizeToAvoidBottomInset: scaffoldKeyboardResizeToAvoidBottomInset(),
                          backgroundColor: const Color(0xFFF0F4F9),
                          appBar: AppBar(
                            titleSpacing: 0,
                            title: ListTile(
                              contentPadding: const EdgeInsets.only(right: 8),
                              title: const Text(
                                'Editar convênio',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                ),
                              ),
                              subtitle: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            leading: IconButton(
                              tooltip: 'Fechar',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ),
                          body: SafeArea(
                            child: ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                _PartnershipVigenciaEditor(
                                  partnershipId: id,
                                  partnershipData: Map<String, dynamic>.from(m),
                                ),
                                const SizedBox(height: 20),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(52),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      if (!context.mounted) return;
                                      openFullPartnershipPanel();
                                    });
                                  },
                                  icon: const Icon(Icons.open_in_new_rounded),
                                  label: const Text(
                                    'Abrir gestão completa (link, CSV, usuários, financeiro)',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  Widget statusPill() {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: active ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: active ? const Color(0xFF22C55E) : const Color(0xFF94A3B8),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        active ? 'Ativo' : 'Inativo',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: active ? const Color(0xFF14532D) : const Color(0xFF475569),
                          letterSpacing: 0.2,
                        ),
                      ),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      clipBehavior: Clip.antiAlias,
                      child: Ink(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF1A237E).withValues(alpha: 0.1),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: widget.brandBlue.withValues(alpha: 0.08),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            InkWell(
                              onTap: openFullPartnershipPanel,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                                child: Builder(
                                  builder: (context) {
                                    final topRow = Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 52,
                                          height: 52,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                widget.brandBlue,
                                                widget.brandTeal,
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius: BorderRadius.circular(16),
                                            boxShadow: [
                                              BoxShadow(
                                                color: widget.brandBlue.withValues(alpha: 0.35),
                                                blurRadius: 10,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.handshake_rounded,
                                            color: Colors.white,
                                            size: 28,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: const TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: -0.3,
                                                  height: 1.15,
                                                  color: Color(0xFF0F172A),
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                '${id.toUpperCase()} • $planCode',
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  color: Colors.grey.shade800,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                vigLine.isEmpty
                                                    ? 'Duração: $days dia(s) • Toque abaixo em «Gestão» para link, CSV e usuários'
                                                    : vigLine,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade600,
                                                  height: 1.35,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (!narrowTop) ...[
                                          const SizedBox(width: 8),
                                          statusPill(),
                                          if (csvPendingReview) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 5,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.shade50,
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: Colors.orange.shade300,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.flag_rounded,
                                                      size: 14, color: Colors.orange.shade900),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'CSV',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.w800,
                                                      fontSize: 11,
                                                      color: Colors.orange.shade900,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ],
                                    );
                                    if (narrowTop) {
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          topRow,
                                          const SizedBox(height: 10),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            children: [
                                              statusPill(),
                                              if (csvPendingReview)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 5,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.orange.shade50,
                                                    borderRadius: BorderRadius.circular(10),
                                                    border: Border.all(
                                                      color: Colors.orange.shade300,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.flag_rounded,
                                                          size: 14, color: Colors.orange.shade900),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        'CSV',
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.w800,
                                                          fontSize: 11,
                                                          color: Colors.orange.shade900,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      );
                                    }
                                    return topRow;
                                  },
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: Builder(
                                builder: (context) {
                                final btnStyle = FilledButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                );
                                final outStyle = OutlinedButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                  foregroundColor: const Color(0xFF1A237E),
                                  side: BorderSide(
                                    color: const Color(0xFF1A237E).withValues(alpha: 0.35),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                );
                                final editBtn = FilledButton.tonalIcon(
                                  style: btnStyle,
                                  onPressed: openEditPartnershipOnly,
                                  icon: const Icon(Icons.edit_rounded, size: 20),
                                  label: const Text(
                                    'Editar',
                                    style: TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                );
                                final fullBtn = OutlinedButton.icon(
                                  style: outStyle,
                                  onPressed: openFullPartnershipPanel,
                                  icon: const Icon(Icons.dashboard_customize_outlined, size: 20),
                                  label: const Text(
                                    'Gestão completa',
                                    style: TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                );
                                return narrowActionsRow
                                    ? Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          editBtn,
                                          const SizedBox(height: 8),
                                          fullBtn,
                                        ],
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          editBtn,
                                          const SizedBox(width: 8),
                                          fullBtn,
                                        ],
                                      );
                              },
                            ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Edição da vigência do contrato, plano aplicado e aplicação da licença aos usuários vinculados.
class _PartnershipVigenciaEditor extends StatefulWidget {
  final String partnershipId;
  final Map<String, dynamic> partnershipData;

  const _PartnershipVigenciaEditor({
    required this.partnershipId,
    required this.partnershipData,
  });

  @override
  State<_PartnershipVigenciaEditor> createState() =>
      _PartnershipVigenciaEditorState();
}

class _PartnershipVigenciaEditorState extends State<_PartnershipVigenciaEditor> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _durationCtrl;
  late final TextEditingController _planCodeCtrl;
  late final TextEditingController _licenseExtensionDaysCtrl;
  DateTime? _contractStart;
  DateTime? _contractEnd;
  bool _saving = false;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    final m = widget.partnershipData;
    _nameCtrl = TextEditingController(
      text: (m['name'] ?? widget.partnershipId).toString(),
    );
    _durationCtrl =
        TextEditingController(text: '${(m['durationDays'] ?? 365)}');
    _planCodeCtrl = TextEditingController(
      text: (m['planCode'] ?? 'premium_assego').toString(),
    );
    final extRaw = m['licenseRenewalExtensionDays'];
    final extVal = extRaw is num ? extRaw.toInt() : int.tryParse('$extRaw') ?? 0;
    _licenseExtensionDaysCtrl = TextEditingController(
      text: extVal > 0 ? '$extVal' : '',
    );
    final cs = m['contractStartsAt'];
    if (cs is Timestamp) {
      final d = cs.toDate();
      _contractStart = DateTime(d.year, d.month, d.day);
    }
    final ce = m['contractEndsAt'];
    if (ce is Timestamp) {
      final d = ce.toDate();
      _contractEnd = DateTime(d.year, d.month, d.day);
    }
  }

  @override
  void didUpdateWidget(covariant _PartnershipVigenciaEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.partnershipData['licenseRenewalExtensionDays'] !=
        widget.partnershipData['licenseRenewalExtensionDays']) {
      final v = widget.partnershipData['licenseRenewalExtensionDays'];
      final n = v is num ? v.toInt() : int.tryParse('$v') ?? 0;
      final t = n > 0 ? '$n' : '';
      if (_licenseExtensionDaysCtrl.text != t) {
        _licenseExtensionDaysCtrl.text = t;
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _durationCtrl.dispose();
    _planCodeCtrl.dispose();
    _licenseExtensionDaysCtrl.dispose();
    super.dispose();
  }

  String _normalizedPlanCodeInput() {
    return _planCodeCtrl.text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '');
  }

  Future<void> _pickDate(bool isStart) async {
    final initial = isStart ? _contractStart : _contractEnd;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      final day = DateTime(picked.year, picked.month, picked.day);
      if (isStart) {
        _contractStart = day;
      } else {
        _contractEnd = day;
      }
      if (_contractEnd != null &&
          _contractStart != null &&
          _contractEnd!.isBefore(_contractStart!)) {
        _contractEnd = _contractStart;
      }
    });
  }

  Future<void> _save() async {
    final days = int.tryParse(_durationCtrl.text.trim()) ?? 365;
    var pc = _normalizedPlanCodeInput();
    if (pc.isEmpty) pc = 'premium_assego';
    final extDays =
        int.tryParse(_licenseExtensionDaysCtrl.text.trim()) ?? 0;
    final extClamped = extDays.clamp(0, 120);
    setState(() => _saving = true);
    try {
      final nameOut = _nameCtrl.text.trim().isEmpty
          ? (widget.partnershipData['name'] ?? widget.partnershipId).toString()
          : _nameCtrl.text.trim();
      await FunctionsService().createOrUpdatePartnership(
        id: widget.partnershipId,
        slug: widget.partnershipId,
        name: nameOut,
        durationDays: days <= 0 ? 365 : days,
        planCode: pc,
        active: widget.partnershipData['active'] != false,
        autoApplyOnSignup: widget.partnershipData['autoApplyOnSignup'] != false,
        contractStartsAtIso:
            _contractStart == null ? '' : DateFormat('yyyy-MM-dd').format(_contractStart!),
        contractEndsAtIso:
            _contractEnd == null ? '' : DateFormat('yyyy-MM-dd').format(_contractEnd!),
        licenseRenewalExtensionDays: extClamped,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Convênio "${widget.partnershipData['name'] ?? widget.partnershipId}" atualizado.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar convênio: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _applyLicenseToUsers() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aplicar licença aos usuários'),
        content: const Text(
          'Recalcula plano, vínculo e data de validade da licença para os usuários deste convênio, '
          'alinhando ao fim do contrato (+ dias extras de prorrogação, se configurados). '
          'Inclui quem está só com o mesmo código de plano no cadastro, sem partnershipId '
          '(mesmo critério das métricas). Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _applying = true);
    try {
      final res = await FunctionsService().renewPartnershipLicenses(
        partnershipId: widget.partnershipId,
        unionPlanMatch: true,
      );
      if (!mounted) return;
      final renewed = (res['renewed'] ?? 0).toString();
      final total = (res['total'] ?? 0).toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Licenças atualizadas: $renewed / $total usuário(s).',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao aplicar: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            widget.partnershipData['active'] != false
                ? const Color(0xFFEEF2FF)
                : const Color(0xFFF1F5F9),
            Colors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF312E81).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF4338CA),
                      const Color(0xFF0D9488),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.edit_calendar_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Dados do convênio',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Nome, plano, vigência do contrato e prorrogação. Depois de alterar, use «Aplicar licença aos usuários».',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4),
          ),
          const SizedBox(height: 14),
          FastTextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Nome do convênio',
              hintText: 'Ex.: Assego App',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF4338CA), width: 2),
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          FastTextField(
            controller: _planCodeCtrl,
            decoration: const InputDecoration(
              labelText: 'Código do plano aplicado',
              hintText: 'premium_assego, premium_unimil, …',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ActionChip(
                label: const Text('premium'),
                onPressed: () {
                  _planCodeCtrl.text = 'premium';
                  setState(() {});
                },
              ),
              ActionChip(
                label: const Text('premium_assego'),
                onPressed: () {
                  _planCodeCtrl.text = 'premium_assego';
                  setState(() {});
                },
              ),
              ActionChip(
                label: const Text('premium_unimil'),
                onPressed: () {
                  _planCodeCtrl.text = 'premium_unimil';
                  setState(() {});
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          FastTextField(
            controller: _durationCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Duração padrão (dias) — quando não há data final',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickDate(true),
                icon: const Icon(Icons.date_range_rounded, size: 18),
                label: Text(
                  _contractStart == null
                      ? 'Data inicial do contrato'
                      : 'Início: ${DateFormat('dd/MM/yyyy').format(_contractStart!)}',
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickDate(false),
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(
                  _contractEnd == null
                      ? 'Data final do contrato'
                      : 'Fim: ${DateFormat('dd/MM/yyyy').format(_contractEnd!)}',
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  _contractStart = null;
                  _contractEnd = null;
                }),
                icon: const Icon(Icons.clear_rounded),
                label: const Text('Limpar datas'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FastTextField(
            controller: _licenseExtensionDaysCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Prorrogação extra (dias após o fim do contrato)',
              helperText:
                  'Ex.: 30 se a renovação pode levar um mês. Só vale quando há data final. Máx. 120.',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(_saving ? 'Salvando…' : 'Salvar alterações'),
              ),
              FilledButton.tonalIcon(
                onPressed: _applying ? null : _applyLicenseToUsers,
                icon: _applying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.groups_rounded),
                label: Text(_applying ? 'Aplicando…' : 'Aplicar licença aos usuários'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'ID interno (slug): ${widget.partnershipId}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _PartnershipMetricsRow extends StatefulWidget {
  final String partnershipId;
  /// Plano do convênio (ex.: premium_assego) — usado para contar usuários também pelo campo `plan`.
  final String partnershipPlanCode;

  const _PartnershipMetricsRow({
    required this.partnershipId,
    required this.partnershipPlanCode,
  });

  @override
  State<_PartnershipMetricsRow> createState() => _PartnershipMetricsRowState();
}

class _PartnershipMetricsRowState extends State<_PartnershipMetricsRow> {
  Future<List<dynamic>>? _metricsFuture;
  int _lastKey = 0;

  int _fingerprint() =>
      Object.hash(widget.partnershipId, widget.partnershipPlanCode);

  Future<List<dynamic>> _loadMetrics() {
    final fs = FirebaseFirestore.instance;
    final base = fs.collection('partnerships').doc(widget.partnershipId);
    return Future.wait([
      base.collection('members').where('active', isEqualTo: true).count().get(),
      countUsersPartnershipInPeriod(
        fs,
        widget.partnershipId,
        0,
        partnershipPlanCode: widget.partnershipPlanCode,
      ),
      base.collection('submissions').count().get(),
    ]);
  }

  @override
  void initState() {
    super.initState();
    _lastKey = _fingerprint();
    _metricsFuture = _loadMetrics();
  }

  @override
  void didUpdateWidget(covariant _PartnershipMetricsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final k = _fingerprint();
    if (k != _lastKey) {
      _lastKey = k;
      _metricsFuture = _loadMetrics();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _metricsFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const LinearProgressIndicator(minHeight: 3);
        }
        if (snap.hasError || snap.data == null || snap.data!.length < 3) {
          return Text(
            'Não foi possível carregar métricas.',
            style: TextStyle(color: Colors.red.shade700, fontSize: 12),
          );
        }
        final mem = (snap.data![0] as AggregateQuerySnapshot).count ?? 0;
        final usr = snap.data![1] as int;
        final sub = (snap.data![2] as AggregateQuerySnapshot).count ?? 0;
        return Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            _metricChip(Icons.people_outline_rounded, 'Membros ativos', mem),
            _metricChip(Icons.phone_android_rounded, 'Usuários app', usr),
            _metricChip(Icons.inbox_rounded, 'Submissões (total)', sub),
          ],
        );
      },
    );
  }

  Widget _metricChip(IconData icon, String label, int value) {
    return Chip(
      avatar: Icon(icon, size: 18, color: const Color(0xFF1E3A5F)),
      label: Text('$label: $value'),
      backgroundColor: const Color(0xFFE8EEF5),
      side: BorderSide(color: Colors.blueGrey.shade100),
    );
  }
}

/// Franquia tipo orçamento (ex.: 4K usuários), excedentes e valor para fechar cobrança — só controle no painel.
class _PartnershipQuotaBillingPanel extends StatefulWidget {
  final String partnershipId;
  final String partnershipPlanCode;
  final String partnershipName;
  final int includedUsersQuota;
  final double excessUserUnitPrice;
  final Future<void> Function({
    required int includedUsersQuota,
    required double excessUserUnitPrice,
  }) onSave;

  const _PartnershipQuotaBillingPanel({
    required this.partnershipId,
    required this.partnershipPlanCode,
    required this.partnershipName,
    required this.includedUsersQuota,
    required this.excessUserUnitPrice,
    required this.onSave,
  });

  @override
  State<_PartnershipQuotaBillingPanel> createState() =>
      _PartnershipQuotaBillingPanelState();
}

class _PartnershipQuotaBillingPanelState extends State<_PartnershipQuotaBillingPanel> {
  late final TextEditingController _quotaCtrl;
  late final TextEditingController _excessPriceCtrl;
  late Future<int> _usersCountFuture;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _quotaCtrl = TextEditingController(text: '${widget.includedUsersQuota}');
    _excessPriceCtrl = TextEditingController(
      text: widget.excessUserUnitPrice > 0
          ? widget.excessUserUnitPrice.toStringAsFixed(2)
          : '',
    );
    _quotaCtrl.addListener(_onFieldChanged);
    _excessPriceCtrl.addListener(_onFieldChanged);
    _usersCountFuture = _reloadUserCount();
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  Future<int> _reloadUserCount() {
    return countUsersPartnershipInPeriod(
      FirebaseFirestore.instance,
      widget.partnershipId,
      0,
      partnershipPlanCode: widget.partnershipPlanCode,
    );
  }

  @override
  void didUpdateWidget(covariant _PartnershipQuotaBillingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.includedUsersQuota != widget.includedUsersQuota &&
        _quotaCtrl.text.trim() != '${widget.includedUsersQuota}') {
      _quotaCtrl.text = '${widget.includedUsersQuota}';
    }
    if (oldWidget.excessUserUnitPrice != widget.excessUserUnitPrice) {
      final t = widget.excessUserUnitPrice > 0
          ? widget.excessUserUnitPrice.toStringAsFixed(2)
          : '';
      if (_excessPriceCtrl.text.trim() != t) {
        _excessPriceCtrl.text = t;
      }
    }
    if (oldWidget.partnershipId != widget.partnershipId ||
        oldWidget.partnershipPlanCode != widget.partnershipPlanCode) {
      _usersCountFuture = _reloadUserCount();
    }
  }

  @override
  void dispose() {
    _quotaCtrl.removeListener(_onFieldChanged);
    _excessPriceCtrl.removeListener(_onFieldChanged);
    _quotaCtrl.dispose();
    _excessPriceCtrl.dispose();
    super.dispose();
  }

  int _parseQuota(String raw) {
    final v = int.tryParse(raw.trim()) ?? 4000;
    return v.clamp(1, 9999999);
  }

  double _parseMoneyLocal(String raw) {
    final normalized = raw.replaceAll('.', '').replaceAll(',', '.').trim();
    return double.tryParse(normalized) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF8FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE9D5FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_outlined,
                  color: Colors.purple.shade800, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Orçamento / franquia (ex.: 4 mil usuários)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF581C87),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Controle para cobrança: usuários incluídos na franquia e valor por excedente. '
            'Permissões no app permanecem as do premium (mesmo comportamento dos demais convênios).',
            style: TextStyle(
                fontSize: 11, color: Colors.grey.shade800, height: 1.35),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 520;
              final quotaField = FastTextField(
                controller: _quotaCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Usuários incluídos na franquia',
                  helperText:
                      'Padrão 4000 (referência orçamento 4K); ajuste por contrato.',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              );
              final priceField = BrlAmountTextField(
                controller: _excessPriceCtrl,
                decoration: const InputDecoration(
                  labelText: 'Valor por usuário excedente (R\$)',
                  helperText: 'Para fechar o valor dos excedentes na cobrança.',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    quotaField,
                    const SizedBox(height: 8),
                    priceField,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: quotaField),
                  const SizedBox(width: 8),
                  Expanded(child: priceField),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          FutureBuilder<int>(
            future: _usersCountFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator(minHeight: 2);
              }
              if (snap.hasError) {
                return Text(
                  'Erro ao contar usuários.',
                  style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                );
              }
              final users = snap.data ?? 0;
              final quota = _parseQuota(_quotaCtrl.text);
              final unit = _parseMoneyLocal(_excessPriceCtrl.text);
              final excess = (users - quota) > 0 ? users - quota : 0;
              final totalExcessBrl = excess * unit;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        avatar: Icon(Icons.groups_rounded,
                            size: 18, color: Colors.indigo.shade900),
                        label: Text(
                            'Usuários no app (este convênio): $users'),
                      ),
                      Chip(
                        avatar: Icon(Icons.check_circle_outline_rounded,
                            size: 18, color: Colors.green.shade900),
                        label: Text(
                          'Dentro da franquia: ${users <= quota ? users : quota}',
                        ),
                      ),
                      Chip(
                        avatar: Icon(Icons.warning_amber_rounded,
                            size: 18,
                            color: excess > 0
                                ? Colors.orange.shade900
                                : Colors.grey.shade700),
                        label: Text('Excedentes: $excess'),
                      ),
                      Chip(
                        avatar: Icon(Icons.payments_outlined,
                            size: 18, color: Colors.purple.shade900),
                        label: Text(
                          'Total excedentes: ${CurrencyFormats.formatBRL(totalExcessBrl)}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final line =
                              '${widget.partnershipId};${widget.partnershipPlanCode};$users;$quota;$excess;${unit.toStringAsFixed(2)};${totalExcessBrl.toStringAsFixed(2)}';
                          await Clipboard.setData(ClipboardData(text: line));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Linha copiada (id;plano;usuários;franquia;excedentes;preço_unit;total_excedentes).',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.content_copy_rounded),
                        label: const Text('Copiar linha para cobrança'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _usersCountFuture = _reloadUserCount();
                          });
                        },
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Atualizar contagem'),
                      ),
                      FilledButton.icon(
                        onPressed: _saving
                            ? null
                            : () async {
                                setState(() => _saving = true);
                                try {
                                  await widget.onSave(
                                    includedUsersQuota:
                                        _parseQuota(_quotaCtrl.text),
                                    excessUserUnitPrice:
                                        _parseMoneyLocal(_excessPriceCtrl.text),
                                  );
                                } finally {
                                  if (mounted) {
                                    setState(() => _saving = false);
                                  }
                                }
                              },
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(_saving ? 'Salvando…' : 'Salvar franquia'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Inclusão/remoção pontual por e-mail (admin), alinhado a CSV/URL e migração em massa.
class _PartnershipManualEmailCard extends StatefulWidget {
  final String partnershipId;

  const _PartnershipManualEmailCard({required this.partnershipId});

  @override
  State<_PartnershipManualEmailCard> createState() =>
      _PartnershipManualEmailCardState();
}

class _PartnershipManualEmailCardState extends State<_PartnershipManualEmailCard> {
  final TextEditingController _emailCtrl = TextEditingController();
  bool _submittingInclude = false;
  bool _submittingRemove = false;

  bool get _busy => _submittingInclude || _submittingRemove;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  /// E-mail normalizado ou `null` se vazio, `''` se inválido.
  String? _normalizedEmail() {
    final r = _emailCtrl.text.trim().toLowerCase();
    if (r.isEmpty) return null;
    if (!r.contains('@') || r.split('@').length != 2) return '';
    final local = r.split('@').first;
    final domain = r.split('@').last;
    if (local.isEmpty || domain.isEmpty || !domain.contains('.')) return '';
    return r;
  }

  Future<void> _include() async {
    final email = _normalizedEmail();
    if (email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um e-mail.')),
      );
      return;
    }
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-mail inválido.')),
      );
      return;
    }
    setState(() => _submittingInclude = true);
    try {
      final res = await FunctionsService().upsertPartnershipMembers(
        partnershipId: widget.partnershipId,
        emails: [email],
        source: 'admin_manual_single',
      );
      if (!mounted) return;
      final backendMsg = (res['message'] ?? '').toString().trim();
      final msg = backendMsg.isNotEmpty
          ? backendMsg
          : 'Inclusão/atualização registrada para $email.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _submittingInclude = false);
    }
  }

  Future<void> _remove() async {
    final email = _normalizedEmail();
    if (email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um e-mail.')),
      );
      return;
    }
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-mail inválido.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover do convênio?'),
        content: Text(
          '$email será removido da lista deste convênio '
          '(membro inativo; o usuário volta ao premium varejo quando aplicável).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _submittingRemove = true);
    try {
      await FunctionsService().removeEmailsFromPartnership(
        partnershipId: widget.partnershipId,
        emails: [email],
        source: 'admin_manual_single',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removido do convênio: $email'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _submittingRemove = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Inclusão manual por e-mail',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Digite o e-mail e use Incluir ou Remover. Combine com CSV, URL/sync automático e com a migração em massa na lista abaixo.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, c) {
                final narrow = c.maxWidth < 440;
                final field = FastTextField(
                  controller: _emailCtrl,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    hintText: 'nome@empresa.com',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) {
                    if (!_busy) _include();
                  },
                );
                final actions = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: _busy ? null : _include,
                      icon: _submittingInclude
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.person_add_alt_1_rounded),
                      label: Text(_submittingInclude ? 'Aguarde…' : 'Incluir'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: _busy ? null : _remove,
                      icon: _submittingRemove
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.person_remove_rounded),
                      label: Text(
                        _submittingRemove ? 'Aguarde…' : 'Remover do convênio',
                      ),
                    ),
                  ],
                );
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      field,
                      const SizedBox(height: 10),
                      actions,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: field),
                    const SizedBox(width: 10),
                    actions,
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class PartnershipUsersPanel extends StatefulWidget {
  final String partnershipId;
  final String partnershipPlanCode;
  /// [dataTable] = grade larga (desktop); [cards] = lista mobile / painel convênio.
  final PartnershipUsersPanelLayout layout;
  final PartnershipUsersPreviewScope scope;
  final List<AdminPartnershipPlanOption> conveniosCatalog;
  /// Cards estilo «Usuários» do Admin (plano, licença, remover…) — ideal mobile.
  final bool useRichUserCards;

  const PartnershipUsersPanel({
    super.key,
    required this.partnershipId,
    required this.partnershipPlanCode,
    this.layout = PartnershipUsersPanelLayout.cards,
    this.scope = PartnershipUsersPreviewScope.byPartnership,
    this.conveniosCatalog = const [],
    this.useRichUserCards = false,
  });

  @override
  State<PartnershipUsersPanel> createState() => _PartnershipUsersPanelState();
}

class _PartnershipUsersPanelState extends State<PartnershipUsersPanel> {
  int _localRefreshNonce = 0;
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _selectedUids = {};
  VoidCallback? _detachSearchListener;

  @override
  void initState() {
    super.initState();
    // Debounce: evita rebuild da lista por keystroke — soluciona o
    // "teclado Android lento" sentido neste painel.
    _detachSearchListener = attachDebouncedRebuild(_searchCtrl, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _detachSearchListener?.call();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _migrateSelected() async {
    if (_selectedUids.isEmpty) return;
    final ctrl = TextEditingController(text: widget.partnershipPlanCode);
    var planOverride = '';
    bool? ok;
    try {
      ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Migrar para este convênio'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${_selectedUids.length} usuário(s). O servidor define partnershipId, '
                  'aplica o plano abaixo e recalcula a data da licença conforme o convênio '
                  '(vigência em dias ou data final do contrato).',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                ),
                const SizedBox(height: 12),
                FastTextField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                    labelText: 'Código do plano',
                    hintText: 'premium_unimil',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Migrar'),
            ),
          ],
        ),
      );
      planOverride = ctrl.text.trim();
    } finally {
      ctrl.dispose();
    }
    if (ok != true || !mounted) return;
    try {
      final res = await FunctionsService().bulkMigrateUsersToPartnership(
        partnershipId: widget.partnershipId,
        uids: _selectedUids.toList(),
        planCodeOverride: planOverride.isEmpty ? null : planOverride,
      );
      if (!mounted) return;
      final updated = (res['updated'] ?? 0).toString();
      final requested = (res['requested'] ?? 0).toString();
      setState(() {
        _selectedUids.clear();
        _localRefreshNonce++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Migração concluída: $updated / $requested usuário(s).'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro na migração: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _inactivateSelected() async {
    if (_selectedUids.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Inativar licença'),
        content: Text(
          '${_selectedUids.length} usuário(s): o campo planStatus será definido como cancelado — '
          'sem acesso premium até reativar no painel Admin › Usuários.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Inativar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final uid in _selectedUids) {
        batch.set(
          FirebaseFirestore.instance.collection('users').doc(uid),
          {
            'planStatus': 'canceled',
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();
      if (!mounted) return;
      setState(() {
        _selectedUids.clear();
        _localRefreshNonce++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Licença inativada para os usuários selecionados.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _bulkDeletePermanentSelected() async {
    if (_selectedUids.isEmpty) return;
    final n = _selectedUids.length;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir permanentemente?'),
        content: Text(
          'Remove login e dados de $n usuário(s) via Cloud Function. '
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir todos'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final uids = _selectedUids.toList();
    var okCount = 0;
    var fail = 0;
    for (final uid in uids) {
      try {
        final callable = FirebaseFunctions.instance.httpsCallable(
          'ctDeleteUserTotal',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 280)),
        );
        await callable.call<Map<String, dynamic>>({'uid': uid});
        okCount++;
      } catch (_) {
        fail++;
      }
    }
    if (!mounted) return;
    setState(() {
      _selectedUids.clear();
      _localRefreshNonce++;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exclusão: $okCount ok • $fail falha(s).'),
        backgroundColor: fail == 0 ? AppColors.success : Colors.orange.shade700,
      ),
    );
  }

  Future<void> _inactivateOneUser(String uid) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'planStatus': 'canceled',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (!mounted) return;
      setState(() => _localRefreshNonce++);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Licença inativada.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _editUserDialog({
    required String uid,
    required Map<String, dynamic> data,
  }) async {
    final nameCtrl = TextEditingController(text: (data['name'] ?? '').toString());
    final emailCtrl = TextEditingController(text: (data['email'] ?? '').toString());
    final phoneCtrl = TextEditingController(text: (data['phone'] ?? '').toString());
    final planCtrl = TextEditingController(text: (data['plan'] ?? '').toString());
    final partnershipCtrl =
        TextEditingController(text: (data['partnershipId'] ?? widget.partnershipId).toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar usuário do convênio'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FastTextField(
                  controller: nameCtrl,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(ctx).nextFocus(),
                  onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                    labelText: 'Nome',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                FastTextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(ctx).nextFocus(),
                  onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                FastTextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(ctx).nextFocus(),
                  onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                    labelText: 'Telefone',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                FastTextField(
                  controller: planCtrl,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(ctx).nextFocus(),
                  onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                    labelText: 'Plano',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                FastTextField(
                  controller: partnershipCtrl,
                  textInputAction: TextInputAction.done,
                  onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                    labelText: 'ID do convênio',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;
    final emailNorm = emailCtrl.text.trim().toLowerCase();
    if (emailNorm.isEmpty || !emailNorm.contains('@')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe um e-mail válido. Todo usuário precisa de e-mail.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'name': nameCtrl.text.trim(),
          'email': emailNorm,
          'phone': phoneCtrl.text.trim(),
          'plan': planCtrl.text.trim(),
          'partnershipId': partnershipCtrl.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (!mounted) return;
      setState(() => _localRefreshNonce++);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usuário atualizado com sucesso.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao editar usuário: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _showAuthorizedDelegateDialog({
    required String uid,
    required Map<String, dynamic> data,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('E-mail autorizado (sub-login)'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: AdminDelegateEmailSection(
              principalUid: uid,
              principalEmail: (data['email'] ?? '').toString(),
              authorizedEmail: () {
                final raw =
                    (data['authorizedDelegateEmail'] ?? '').toString().trim();
                return raw.isEmpty ? null : raw;
              }(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
    if (mounted) setState(() => _localRefreshNonce++);
  }

  Future<void> _editLicenseDate({
    required String uid,
    required Map<String, dynamic> data,
  }) async {
    final currentTs = data['licenseExpiresAt'];
    DateTime initialDate = DateTime.now().add(const Duration(days: 365));
    if (currentTs is Timestamp) {
      initialDate = currentTs.toDate();
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'licenseExpiresAt': Timestamp.fromDate(
            DateTime(picked.year, picked.month, picked.day, 23, 59, 59),
          ),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (!mounted) return;
      setState(() => _localRefreshNonce++);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Data da licença atualizada para ${DateFormat('dd/MM/yyyy').format(picked)}.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao atualizar licença: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _confirmRemoveUser(
    BuildContext context, {
    required String uid,
    required String name,
    required String email,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover usuário?'),
        content: Text(
          'Remover ${name.isEmpty ? uid : name}? Perde acesso ao app; pode reativar depois no Admin › Usuários.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await BillingService().removerUsuario(uid);
    await AdminAuditService().logAdminAction(
      action: removerUsuario,
      targetUserId: uid,
      targetUserEmail: email.trim().isNotEmpty ? email.trim() : null,
      details: name.isEmpty ? uid : name,
    );
    await LogsService().saveLog(
      modulo: 'Admin',
      acao: 'Removeu usuário',
      detalhes: name.isEmpty ? uid : name,
    );
    if (!mounted) return;
    setState(() => _localRefreshNonce++);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Usuário removido. Pode reativar no filtro Removidos.')),
    );
  }

  Widget _buildRichManageCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final u = doc.data();
    final uid = doc.id;
    final name = (u['name'] ?? '').toString().trim();
    final email = (u['email'] ?? '').toString().trim();
    final plan = (u['plan'] ?? 'free').toString().toLowerCase();
    final partnershipId = (u['partnershipId'] ?? '').toString().trim();
    final partnershipName = (u['partnershipName'] ?? '').toString().trim();
    final removedByAdminAt = u['removedByAdminAt'];
    final isRemoved = removedByAdminAt != null;
    final licenseExpiresAt = u['licenseExpiresAt'] is Timestamp
        ? (u['licenseExpiresAt'] as Timestamp).toDate()
        : null;
    final planLabel = UserProfile.planDisplayLabelForFirestorePlan(plan);
    final catalog = widget.conveniosCatalog;

    String validadeStr;
    Color statusColor;
    String statusLabel;
    if (isRemoved) {
      validadeStr = 'Removido pelo admin';
      statusLabel = 'Removido';
      statusColor = Colors.grey;
    } else if (licenseExpiresAt == null) {
      validadeStr = plan == 'free' ? 'Sem licença' : '—';
      statusLabel = plan == 'free' ? 'Free' : '—';
      statusColor = Colors.grey;
    } else if (UserProfile.isLicenseExpiredByDate(licenseExpiresAt)) {
      validadeStr =
          'Vencimento: ${DateFormat('dd/MM/yyyy').format(licenseExpiresAt)}';
      statusLabel = 'Vencida';
      statusColor = AppColors.error;
    } else {
      validadeStr =
          'Vencimento: ${DateFormat('dd/MM/yyyy').format(licenseExpiresAt)}';
      statusLabel = 'Ativa';
      statusColor = AppColors.success;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isRemoved ? Colors.grey.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRemoved ? Colors.grey.shade300 : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                radius: 20,
                child: Icon(Icons.person, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Usuário' : name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    Text(
                      '$planLabel • $validadeStr',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                    if (partnershipId.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          partnershipName.isNotEmpty
                              ? 'Convênio: $partnershipName'
                              : 'Convênio: $partnershipId',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.indigo.shade800,
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!isRemoved) ...[
            DropdownButtonFormField<String>(
              value: adminUserPlanDropdownValue(plan),
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Plano / convênio',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: adminUserPlanDropdownItems(
                currentPlan: plan,
                convenios: catalog,
              ),
              onChanged: (newPlan) async {
                if (newPlan == null) return;
                try {
                  await AdminUserPlanApplyService.apply(
                    ref: doc.reference,
                    uid: uid,
                    name: name,
                    email: email,
                    currentPlan: plan,
                    currentPartnershipId: partnershipId,
                    currentPartnershipName: partnershipName,
                    newPlan: newPlan,
                    conveniosCatalog: catalog,
                  );
                  if (!mounted) return;
                  setState(() => _localRefreshNonce++);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Plano: ${UserProfile.planDisplayLabelForFirestorePlan(newPlan)}',
                      ),
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erro: $e')),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!isRemoved && plan != 'free')
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await BillingService().prorrogarPrazo(uid, 15);
                    if (!mounted) return;
                    setState(() => _localRefreshNonce++);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Prazo +15 dias.')),
                    );
                  },
                  icon: const Icon(Icons.date_range, size: 18),
                  label: const Text('+15 dias'),
                ),
              if (!isRemoved)
                OutlinedButton.icon(
                  onPressed: () => _editLicenseDate(uid: uid, data: u),
                  icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                  label: const Text('Licença'),
                ),
              if (!isRemoved)
                OutlinedButton.icon(
                  onPressed: () => _editUserDialog(uid: uid, data: u),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Editar'),
                ),
              if (!isRemoved)
                OutlinedButton.icon(
                  onPressed: () =>
                      _showAuthorizedDelegateDialog(uid: uid, data: u),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('Autorizado'),
                ),
              if (isRemoved)
                FilledButton.icon(
                  onPressed: () async {
                    await BillingService().reativarUsuario(uid);
                    if (!mounted) return;
                    setState(() => _localRefreshNonce++);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Usuário reativado.')),
                    );
                  },
                  icon: const Icon(Icons.person_add_rounded, size: 18),
                  label: const Text('Reativar'),
                ),
              if (!isRemoved)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                  ),
                  onPressed: () => _confirmRemoveUser(
                    context,
                    uid: uid,
                    name: name,
                    email: email,
                  ),
                  icon: const Icon(Icons.person_remove_rounded, size: 18),
                  label: const Text('Remover'),
                ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () => _deleteUserPermanent(
                  uid: uid,
                  name: name.isEmpty ? 'Usuário' : name,
                  email: email,
                ),
                icon: const Icon(Icons.delete_forever_rounded, size: 18),
                label: const Text('Excluir'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _deleteUserPermanent({
    required String uid,
    required String name,
    required String email,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir usuário permanentemente?'),
        content: Text(
          'Esta ação remove login e dados do usuário de forma definitiva.\n\n$name\n$email\nUID: $uid',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir permanente'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'ctDeleteUserTotal',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 280)),
      );
      await callable.call<Map<String, dynamic>>({'uid': uid});
      if (!mounted) return;
      setState(() => _localRefreshNonce++);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usuário excluído permanentemente.'),
          backgroundColor: AppColors.success,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final detail = e.message?.trim().isNotEmpty == true
          ? e.message!
          : (e.details?.toString() ?? e.code);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao excluir: $detail'),
          backgroundColor: AppColors.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao excluir: ${e.toString().split('\n').first}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _usersListFromDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final d in docs) {
      merged[d.id] = d;
    }
    final list = merged.values.toList()
      ..sort((a, b) {
        final ta = (a.data()['createdAt'] as Timestamp?)?.toDate();
        final tb = (b.data()['createdAt'] as Timestamp?)?.toDate();
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? list
        : list.where((doc) {
            final u = doc.data();
            final name = (u['name'] ?? '').toString().toLowerCase();
            final email = (u['email'] ?? '').toString().toLowerCase();
            return name.contains(query) || email.contains(query);
          }).toList();

    if (filtered.isEmpty) {
      return Text(
        query.isEmpty
            ? 'Nenhum usuário encontrado para este convênio.'
            : 'Nenhum usuário encontrado para a busca informada.',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
      );
    }

    final isGrid = widget.layout == PartnershipUsersPanelLayout.dataTable;
    final selectCap = isGrid
        ? (filtered.length > 400 ? 400 : filtered.length)
        : (filtered.length > 80 ? 80 : filtered.length);

    if (isGrid) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Usuários vinculados: ${list.length} • filtrados: ${filtered.length}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          if (_selectedUids.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => setState(() => _selectedUids.clear()),
                  child: Text('Limpar (${_selectedUids.length})'),
                ),
                FilledButton.icon(
                  onPressed: _migrateSelected,
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: const Text('Migrar convênio/plano'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _inactivateSelected,
                  icon: const Icon(Icons.block_rounded, size: 18),
                  label: const Text('Inativar licença'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                  onPressed: _bulkDeletePermanentSelected,
                  icon: const Icon(Icons.delete_forever_rounded, size: 18),
                  label: const Text('Excluir definitivo'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          FastTextField(
            controller: _searchCtrl,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            spellCheckConfiguration:
                const SpellCheckConfiguration.disabled(),
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            textInputAction: TextInputAction.search,
            onTapOutside: (_) =>
                FocusManager.instance.primaryFocus?.unfocus(),
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Buscar por nome ou e-mail',
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar busca',
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: filtered.isEmpty
                  ? null
                  : () {
                      setState(() {
                        for (final d in filtered.take(selectCap)) {
                          _selectedUids.add(d.id);
                        }
                      });
                    },
              icon: const Icon(Icons.select_all_rounded, size: 18),
              label: Text(
                'Selecionar todos os visíveis (até $selectCap)',
              ),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 720),
              child: DataTable(
                headingRowHeight: 44,
                dataRowMinHeight: 48,
                columnSpacing: 12,
                columns: const [
                  DataColumn(label: Text('')),
                  DataColumn(label: Text('Nome')),
                  DataColumn(label: Text('E-mail')),
                  DataColumn(label: Text('Plano')),
                  DataColumn(label: Text('Convênio')),
                  DataColumn(label: Text('Licença')),
                  DataColumn(label: Text('Autorizado')),
                  DataColumn(label: Text('Ações')),
                ],
                rows: filtered.take(400).map((doc) {
                  final u = doc.data();
                  final name = (u['name'] ?? '').toString().trim().isEmpty
                      ? 'Sem nome'
                      : (u['name'] ?? '').toString();
                  final email = (u['email'] ?? '').toString();
                  final plan = (u['plan'] ?? '').toString();
                  final pId = (u['partnershipId'] ?? '').toString();
                  final expTs = u['licenseExpiresAt'];
                  final exp = expTs is Timestamp
                      ? DateFormat('dd/MM/yyyy').format(expTs.toDate())
                      : '—';
                  final delegateEmail =
                      (u['authorizedDelegateEmail'] ?? '').toString().trim();
                  return DataRow(
                    cells: [
                      DataCell(
                        Checkbox(
                          value: _selectedUids.contains(doc.id),
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selectedUids.add(doc.id);
                              } else {
                                _selectedUids.remove(doc.id);
                              }
                            });
                          },
                        ),
                      ),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(name, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 200),
                          child: Text(
                            email.isEmpty ? '—' : email,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(Text(plan.isEmpty ? '—' : plan)),
                      DataCell(Text(pId.isEmpty ? '—' : pId)),
                      DataCell(Text(exp)),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            delegateEmail.isEmpty ? '—' : delegateEmail,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: delegateEmail.isEmpty
                                  ? Colors.grey.shade600
                                  : const Color(0xFF4338CA),
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        PopupMenuButton<String>(
                          tooltip: 'Ações',
                          onSelected: (v) {
                            if (v == 'edit') {
                              _editUserDialog(uid: doc.id, data: u);
                            } else if (v == 'inactivate') {
                              _inactivateOneUser(doc.id);
                            } else if (v == 'license') {
                              _editLicenseDate(uid: doc.id, data: u);
                            } else if (v == 'delegate') {
                              _showAuthorizedDelegateDialog(
                                uid: doc.id,
                                data: u,
                              );
                            } else if (v == 'delete_perm') {
                              _deleteUserPermanent(
                                uid: doc.id,
                                name: name,
                                email: email,
                              );
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text('Editar cadastro'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'inactivate',
                              child: Row(
                                children: [
                                  Icon(Icons.block_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text('Inativar licença'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'license',
                              child: Row(
                                children: [
                                  Icon(Icons.event_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text('Data licença'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delegate',
                              child: Row(
                                children: [
                                  Icon(Icons.person_add_alt_1_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text('E-mail autorizado'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete_perm',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_forever_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text('Excluir permanente'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          if (filtered.length > 400)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Há mais de 400 usuários: refine a busca para listar todos em lotes.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Usuários vinculados: ${list.length} • filtrados: ${filtered.length}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        if (_selectedUids.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () => setState(() => _selectedUids.clear()),
                child: Text('Limpar (${_selectedUids.length})'),
              ),
              FilledButton.icon(
                onPressed: _migrateSelected,
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: const Text('Migrar convênio/plano'),
              ),
              FilledButton.tonalIcon(
                onPressed: _inactivateSelected,
                icon: const Icon(Icons.block_rounded, size: 18),
                label: const Text('Inativar licença'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: _bulkDeletePermanentSelected,
                icon: const Icon(Icons.delete_forever_rounded, size: 18),
                label: const Text('Excluir definitivo'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        FastTextField(
          controller: _searchCtrl,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          spellCheckConfiguration:
              const SpellCheckConfiguration.disabled(),
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          textInputAction: TextInputAction.search,
          onTapOutside: (_) =>
              FocusManager.instance.primaryFocus?.unfocus(),
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: 'Buscar por nome ou e-mail',
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpar busca',
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.clear_rounded),
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: filtered.isEmpty
                ? null
                : () {
                    setState(() {
                      for (final d in filtered.take(selectCap)) {
                        _selectedUids.add(d.id);
                      }
                    });
                  },
            icon: const Icon(Icons.select_all_rounded, size: 18),
            label: Text('Selecionar todos os visíveis (até $selectCap)'),
          ),
        ),
        const SizedBox(height: 8),
        ...filtered.take(widget.useRichUserCards ? 120 : 80).map((doc) {
          if (widget.useRichUserCards) {
            return _buildRichManageCard(doc);
          }
          final u = doc.data();
          final name = (u['name'] ?? '').toString().trim().isEmpty
              ? 'Sem nome'
              : (u['name'] ?? '').toString();
          final email = (u['email'] ?? '').toString();
          final plan = (u['plan'] ?? '').toString();
          final pId = (u['partnershipId'] ?? '').toString();
          final expTs = u['licenseExpiresAt'];
          final exp = expTs is Timestamp
              ? DateFormat('dd/MM/yyyy').format(expTs.toDate())
              : '—';
          final delegateEmail =
              (u['authorizedDelegateEmail'] ?? '').toString().trim();
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _selectedUids.contains(doc.id),
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedUids.add(doc.id);
                      } else {
                        _selectedUids.remove(doc.id);
                      }
                    });
                  },
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email.isEmpty ? 'Sem e-mail' : email,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Plano: ${plan.isEmpty ? '—' : plan} • Convênio: ${pId.isEmpty ? '—' : pId} • Licença: $exp',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      if (delegateEmail.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Autorizado: $delegateEmail',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF4338CA),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Ações do usuário',
                  onSelected: (v) {
                    if (v == 'edit') {
                      _editUserDialog(uid: doc.id, data: u);
                    } else if (v == 'inactivate') {
                      _inactivateOneUser(doc.id);
                    } else if (v == 'license') {
                      _editLicenseDate(uid: doc.id, data: u);
                    } else if (v == 'delegate') {
                      _showAuthorizedDelegateDialog(uid: doc.id, data: u);
                    } else if (v == 'delete_perm') {
                      _deleteUserPermanent(
                        uid: doc.id,
                        name: name,
                        email: email,
                      );
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Alterar / editar cadastro'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'inactivate',
                      child: Row(
                        children: [
                          Icon(Icons.block_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Inativar licença'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'license',
                      child: Row(
                        children: [
                          Icon(Icons.event_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Editar data licença'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delegate',
                      child: Row(
                        children: [
                          Icon(Icons.person_add_alt_1_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('E-mail autorizado'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete_perm',
                      child: Row(
                        children: [
                          Icon(Icons.delete_forever_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Excluir permanente'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
        if (filtered.length > (widget.useRichUserCards ? 120 : 80))
          Text(
            widget.useRichUserCards
                ? 'Mostrando até 120 usuários. Refine a busca.'
                : 'Mostrando 80 usuários. Refine a busca para reduzir a base.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;
    final pid = widget.partnershipId;
    final planCode = _normalizePartnershipPlanCode(widget.partnershipPlanCode);
    final includePlanQuery = !_isRetailPremiumPlanNorm(planCode) &&
        widget.scope == PartnershipUsersPreviewScope.byPartnership;

    if (widget.scope == PartnershipUsersPreviewScope.allWithPartnershipLink) {
      return Container(
        key: ValueKey('partnership_users_all_link_${widget.layout}_$_localRefreshNonce'),
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.useRichUserCards
                  ? 'Utilizadores com convênio — edição como na tela Usuários'
                  : 'Utilizadores com partnershipId preenchido',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: fs
                  .collection('users')
                  .where('partnershipId', isNotEqualTo: '')
                  .limit(500)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Text('Erro: ${snap.error}');
                }
                if (!snap.hasData) {
                  return const LinearProgressIndicator(minHeight: 3);
                }
                final docs = snap.data!.docs.where((d) {
                  final p = (d.data()['partnershipId'] ?? '').toString().trim();
                  return p.isNotEmpty;
                }).toList();
                return _usersListFromDocs(docs);
              },
            ),
          ],
        ),
      );
    }

    return Container(
      key: ValueKey(
          'partnership_users_${widget.partnershipId}_${widget.layout}_$_localRefreshNonce'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.layout == PartnershipUsersPanelLayout.dataTable
                ? 'Grade de usuários — edição, licença e exclusão'
                : 'Usuários do convênio (seleção / migração / edição / licença / exclusão)',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: fs
                .collection('users')
                .where('partnershipId', isEqualTo: pid)
                .limit(400)
                .snapshots(),
            builder: (context, byPidSnap) {
              final byPidDocs = byPidSnap.data?.docs ?? const [];
              if (!includePlanQuery) {
                return _usersListFromDocs(byPidDocs);
              }
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: fs
                    .collection('users')
                    .where('plan', isEqualTo: planCode)
                    .limit(400)
                    .snapshots(),
                builder: (context, byPlanSnap) {
                  final byPlanDocs = byPlanSnap.data?.docs ?? const [];
                  final all = <QueryDocumentSnapshot<Map<String, dynamic>>>[
                    ...byPidDocs,
                    ...byPlanDocs,
                  ];
                  return _usersListFromDocs(all);
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Evita recriar [Future.wait] no `build` a cada snapshot do Firestore (causava travamentos).
class _ConsolidadoConveniosCard extends StatefulWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  /// 0 = todo o período; senão últimos [periodDays] dias por `createdAt`.
  final int periodDays;

  const _ConsolidadoConveniosCard({
    required this.docs,
    required this.periodDays,
  });

  @override
  State<_ConsolidadoConveniosCard> createState() => _ConsolidadoConveniosCardState();
}

class _ConsolidadoConveniosCardState extends State<_ConsolidadoConveniosCard> {
  Future<List<Map<String, dynamic>>>? _rowsFuture;
  int _lastFp = 0;

  int _fingerprint() {
    var h = Object.hash(widget.periodDays, widget.docs.length);
    for (final d in widget.docs) {
      final m = d.data();
      h = Object.hash(
        h,
        d.id,
        m['planCode'],
        m['costPerUser'],
        m['revenuePerUser'],
        m['durationDays'],
      );
    }
    return h;
  }

  Future<List<Map<String, dynamic>>> _loadRows() async {
    final fs = FirebaseFirestore.instance;
    final periodDays = widget.periodDays;
    return Future.wait(
      widget.docs.map((doc) async {
        final data = doc.data();
        final id = doc.id;
        final costPerUser = (data['costPerUser'] is num)
            ? (data['costPerUser'] as num).toDouble()
            : 0.0;
        final revenuePerUser = (data['revenuePerUser'] is num)
            ? (data['revenuePerUser'] as num).toDouble()
            : 0.0;
        final planCode = (data['planCode'] ?? 'premium_assego').toString();
        final userCount = await countUsersPartnershipInPeriod(
          fs,
          id,
          periodDays,
          partnershipPlanCode: planCode,
        );
        final memberCount = await _countMembersPartnershipInPeriod(fs, id, periodDays);
        final qtdBase = userCount > 0 ? userCount : memberCount;
        final totalCost = qtdBase * costPerUser;
        final totalRevenue = qtdBase * revenuePerUser;
        return {
          'id': id,
          'qtdBase': qtdBase,
          'totalCost': totalCost,
          'totalRevenue': totalRevenue,
          'costPerUser': costPerUser,
          'revenuePerUser': revenuePerUser,
        };
      }).toList(),
    );
  }

  @override
  void initState() {
    super.initState();
    _lastFp = _fingerprint();
    _rowsFuture = _loadRows();
  }

  @override
  void didUpdateWidget(covariant _ConsolidadoConveniosCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fp = _fingerprint();
    if (fp != _lastFp) {
      _lastFp = fp;
      _rowsFuture = _loadRows();
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = widget.docs;
    final periodDays = widget.periodDays;
    return RepaintBoundary(
      child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF1A237E).withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F766E).withValues(alpha: 0.07),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _rowsFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator(minHeight: 3);
            }
            if (snap.hasError || snap.data == null) {
              return Text(
                'Não foi possível carregar o consolidado dos convênios.',
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
              );
            }
            final rows = snap.data!;
            var totalAssociados = 0;
            var totalCost = 0.0;
            var totalRevenue = 0.0;
            for (final row in rows) {
              totalAssociados += (row['qtdBase'] as int? ?? 0);
              totalCost += (row['totalCost'] as double? ?? 0);
              totalRevenue += (row['totalRevenue'] as double? ?? 0);
            }
            final totalResultado = totalRevenue - totalCost;
            final perUserCost = totalAssociados > 0 ? totalCost / totalAssociados : 0.0;
            final perUserRevenue =
                totalAssociados > 0 ? totalRevenue / totalAssociados : 0.0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF1A237E).withValues(alpha: 0.9),
                            const Color(0xFF0D9488),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.insights_rounded, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Consolidado geral dos associados',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  docs.length == 1
                      ? (periodDays <= 0
                          ? 'Convênio ${docs.first.id}: usuários com partnershipId ou plano igual ao do convênio (fallback: membros ativos), sem filtro de data.'
                          : 'Convênio ${docs.first.id}: mesmo critério nos últimos $periodDays dias (createdAt).')
                      : (periodDays <= 0
                          ? 'Soma de ${docs.length} associações — partnershipId ou plano do convênio (fallback: membros ativos), sem filtro de data.'
                          : 'Soma de ${docs.length} associações — quantidade no período: últimos $periodDays dias (createdAt).'),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip(
                      periodDays <= 0
                          ? 'Associados (total)'
                          : 'Associados no período',
                      '$totalAssociados',
                      const Color(0xFFE0F2FE),
                    ),
                    _chip('Custo total', CurrencyFormats.formatBRL(totalCost), const Color(0xFFFEE2E2)),
                    _chip('Receita total', CurrencyFormats.formatBRL(totalRevenue), const Color(0xFFDCFCE7)),
                    _chip('Resultado total', CurrencyFormats.formatBRL(totalResultado), const Color(0xFFEDE9FE)),
                    _chip('Custo médio/usuário', CurrencyFormats.formatBRL(perUserCost), const Color(0xFFFFF7ED)),
                    _chip('Receita média/usuário', CurrencyFormats.formatBRL(perUserRevenue), const Color(0xFFF0FDF4)),
                  ],
                ),
                const SizedBox(height: 10),
                AppBarChart(
                  title: 'Consolidado financeiro (usuário e total)',
                  values: [
                    perUserCost < 0 ? 0 : perUserCost,
                    perUserRevenue < 0 ? 0 : perUserRevenue,
                    totalCost < 0 ? 0 : totalCost,
                    totalRevenue < 0 ? 0 : totalRevenue,
                    totalResultado < 0 ? 0 : totalResultado,
                  ],
                  labels: const ['Custo/U', 'Receita/U', 'Custo T', 'Receita T', 'Resultado'],
                  barColor: const Color(0xFF0F766E),
                  height: 168,
                ),
                if (totalAssociados == 0 &&
                    totalCost == 0 &&
                    totalRevenue == 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Valores em zero no período — ajuste filtros ou aguarde cadastros vinculados ao convênio.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.35),
                    ),
                  ),
              ],
            );
          },
        ),
        ),
      ),
    ),
    );
  }

  Widget _chip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _PartnershipFinancialPanel extends StatefulWidget {
  final String partnershipId;
  final String partnershipPlanCode;
  /// Referência ao filtro global (legendas).
  final int periodDays;
  final double costPerUser;
  final double revenuePerUser;
  final double contractMonthlyIncome;
  final int contractDurationMonths;
  final Future<void> Function({
    required double costPerUser,
    required double revenuePerUser,
    required double contractMonthlyIncome,
    required int contractDurationMonths,
  }) onSaveParams;

  const _PartnershipFinancialPanel({
    required this.partnershipId,
    required this.partnershipPlanCode,
    required this.periodDays,
    required this.costPerUser,
    required this.revenuePerUser,
    required this.contractMonthlyIncome,
    required this.contractDurationMonths,
    required this.onSaveParams,
  });

  @override
  State<_PartnershipFinancialPanel> createState() =>
      _PartnershipFinancialPanelState();
}

class _PartnershipFinancialPanelState extends State<_PartnershipFinancialPanel> {
  late final TextEditingController _costCtrl;
  late final TextEditingController _revenueCtrl;
  late final TextEditingController _monthlyContractCtrl;
  late final TextEditingController _contractMonthsCtrl;
  late DateTime _rangeStart;
  late DateTime _rangeEnd;
  bool _saving = false;

  static const double _kMbEstimativaPorUsuario = 0.35;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _rangeEnd = DateTime(now.year, now.month, now.day);
    _rangeStart = DateTime(now.year, now.month, 1);
    _costCtrl = TextEditingController(
      text: widget.costPerUser > 0 ? widget.costPerUser.toStringAsFixed(2) : '',
    );
    _revenueCtrl = TextEditingController(
      text:
          widget.revenuePerUser > 0 ? widget.revenuePerUser.toStringAsFixed(2) : '',
    );
    _monthlyContractCtrl = TextEditingController(
      text: widget.contractMonthlyIncome > 0
          ? widget.contractMonthlyIncome.toStringAsFixed(2)
          : '',
    );
    _contractMonthsCtrl = TextEditingController(
      text: '${widget.contractDurationMonths}',
    );
  }

  @override
  void didUpdateWidget(covariant _PartnershipFinancialPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.costPerUser != widget.costPerUser) {
      _costCtrl.text =
          widget.costPerUser > 0 ? widget.costPerUser.toStringAsFixed(2) : '';
    }
    if (oldWidget.revenuePerUser != widget.revenuePerUser) {
      _revenueCtrl.text = widget.revenuePerUser > 0
          ? widget.revenuePerUser.toStringAsFixed(2)
          : '';
    }
    if (oldWidget.contractMonthlyIncome != widget.contractMonthlyIncome) {
      _monthlyContractCtrl.text = widget.contractMonthlyIncome > 0
          ? widget.contractMonthlyIncome.toStringAsFixed(2)
          : '';
    }
    if (oldWidget.contractDurationMonths != widget.contractDurationMonths) {
      _contractMonthsCtrl.text = '${widget.contractDurationMonths}';
    }
  }

  @override
  void dispose() {
    _costCtrl.dispose();
    _revenueCtrl.dispose();
    _monthlyContractCtrl.dispose();
    _contractMonthsCtrl.dispose();
    super.dispose();
  }

  double _parseMoney(String raw) {
    final normalized = raw.replaceAll('.', '').replaceAll(',', '.').trim();
    return double.tryParse(normalized) ?? 0;
  }

  int _parseMonths(String raw) {
    final v = int.tryParse(raw.trim()) ?? 12;
    return v.clamp(1, 600);
  }

  Future<void> _pickAnalysisDate(bool isStart) async {
    final initial = isStart ? _rangeStart : _rangeEnd;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2018),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      final day = DateTime(picked.year, picked.month, picked.day);
      if (isStart) {
        _rangeStart = day;
      } else {
        _rangeEnd = day;
      }
      if (_rangeEnd.isBefore(_rangeStart)) {
        _rangeEnd = _rangeStart;
      }
    });
  }

  String _displayUserLine(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data();
    if (m == null) return doc.id;
    final dn = (m['displayName'] ?? m['name'] ?? '').toString().trim();
    final em = (m['email'] ?? '').toString().trim();
    if (dn.isNotEmpty && em.isNotEmpty) return '$dn · $em';
    if (dn.isNotEmpty) return dn;
    if (em.isNotEmpty) return em;
    return doc.id;
  }

  String? _createdAtLine(DocumentSnapshot<Map<String, dynamic>> doc) {
    final c = doc.data()?['createdAt'];
    if (c is! Timestamp) return null;
    return DateFormat('dd/MM/yyyy HH:mm').format(c.toDate());
  }

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;
    final billingMonths = _billingMonthsBetween(_rangeStart, _rangeEnd);
    final contractMonthsPlanned = _parseMonths(_contractMonthsCtrl.text);
    final monthlyContract = _parseMoney(_monthlyContractCtrl.text);
    final contractTotalClosed = monthlyContract * contractMonthsPlanned;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ModuleHeaderPremium(
            dense: true,
            title: 'Financeiro SAS — Convênio',
            subtitle:
                'Custo e receita por usuário, receita mensal do contrato e duração fechada (12+ meses). Escolha o período para ver lucro e lista usuário a usuário.',
            icon: Icons.account_balance_wallet_rounded,
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Período de análise (${billingMonths.toStringAsFixed(2)} meses · base ~30 dias)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _pickAnalysisDate(true),
                      icon: const Icon(Icons.calendar_today_rounded, size: 18),
                      label: Text(
                        'Início ${DateFormat('dd/MM/yyyy').format(_rangeStart)}',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _pickAnalysisDate(false),
                      icon: const Icon(Icons.event_rounded, size: 18),
                      label: Text(
                        'Fim ${DateFormat('dd/MM/yyyy').format(_rangeEnd)}',
                      ),
                    ),
                    Chip(
                      avatar: Icon(Icons.schedule_rounded,
                          size: 18, color: Colors.blue.shade800),
                      label: Text(
                        'Valor total contrato: ${CurrencyFormats.formatBRL(contractTotalClosed)} ($contractMonthsPlanned meses)',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 560;
                    final fieldCost = BrlAmountTextField(
                      controller: _costCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Custo por usuário (R\$)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    );
                    final fieldRev = BrlAmountTextField(
                      controller: _revenueCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Receita por usuário (R\$)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    );
                    final fieldContract = BrlAmountTextField(
                      controller: _monthlyContractCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Receita mensal do contrato (R\$)',
                        helperText: 'O que você recebe por mês do convênio',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    );
                    final fieldMonths = FastTextField(
                      controller: _contractMonthsCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Meses do contrato',
                        helperText: 'Ex.: 12 ou 24',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    );
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          fieldCost,
                          const SizedBox(height: 8),
                          fieldRev,
                          const SizedBox(height: 8),
                          fieldContract,
                          const SizedBox(height: 8),
                          fieldMonths,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: fieldCost),
                        const SizedBox(width: 8),
                        Expanded(child: fieldRev),
                        const SizedBox(width: 8),
                        Expanded(child: fieldContract),
                        const SizedBox(width: 8),
                        Expanded(child: fieldMonths),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _saving
                        ? null
                        : () async {
                            setState(() => _saving = true);
                            try {
                              await widget.onSaveParams(
                                costPerUser: _parseMoney(_costCtrl.text),
                                revenuePerUser: _parseMoney(_revenueCtrl.text),
                                contractMonthlyIncome:
                                    _parseMoney(_monthlyContractCtrl.text),
                                contractDurationMonths:
                                    _parseMonths(_contractMonthsCtrl.text),
                              );
                            } finally {
                              if (mounted) setState(() => _saving = false);
                            }
                          },
                    icon: const Icon(Icons.save_rounded),
                    label: Text(_saving ? 'Salvando...' : 'Salvar parâmetros'),
                  ),
                ),
                const Divider(height: 28),
                FutureBuilder<List<Object?>>(
                  future: Future.wait<Object?>([
                    _countUsersPartnershipDateRange(
                      fs,
                      widget.partnershipId,
                      widget.partnershipPlanCode,
                      _rangeStart,
                      _rangeEnd,
                    ),
                    _listUserDocsPartnershipDateRange(
                      fs,
                      widget.partnershipId,
                      widget.partnershipPlanCode,
                      _rangeStart,
                      _rangeEnd,
                      500,
                    ),
                  ]),
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: LinearProgressIndicator(minHeight: 3),
                      );
                    }
                    if (snap.hasError || snap.data == null) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Não foi possível carregar o financeiro deste convênio.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.red.shade700),
                        ),
                      );
                    }
                    final qtd = snap.data![0] as int;
                    final docs = snap.data![1]
                        as List<DocumentSnapshot<Map<String, dynamic>>>;
                    final costUser = _parseMoney(_costCtrl.text);
                    final revenueUser = _parseMoney(_revenueCtrl.text);
                    final monthlyC = _parseMoney(_monthlyContractCtrl.text);

                    final totalCostPeriod = costUser * qtd;
                    final totalRevenueUsers = revenueUser * qtd;
                    final contractInPeriod = monthlyC * billingMonths;
                    final resultado =
                        contractInPeriod + totalRevenueUsers - totalCostPeriod;
                    final mbTotal = qtd * _kMbEstimativaPorUsuario;

                    final lucroColor = resultado >= 0
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFFEE2E2);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.periodDays <= 0
                              ? 'Cadastros no período (partnershipId ou plan do convênio + createdAt). Filtro global de dias não altera esta grade — use as datas acima.'
                              : 'Cadastros no período (partnershipId ou plan do convênio + createdAt).',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _financeChip(
                              label: 'Usuários no período',
                              value: '$qtd',
                              color: const Color(0xFFDBEAFE),
                            ),
                            _financeChip(
                              label: 'Dados estimados (total)',
                              value:
                                  '${mbTotal.toStringAsFixed(2)} MB (~$_kMbEstimativaPorUsuario MB/u)',
                              color: const Color(0xFFE0F2FE),
                            ),
                            _financeChip(
                              label: 'Custo total (período)',
                              value: CurrencyFormats.formatBRL(totalCostPeriod),
                              color: const Color(0xFFFEE2E2),
                            ),
                            _financeChip(
                              label: 'Receita usuários (período)',
                              value: CurrencyFormats.formatBRL(totalRevenueUsers),
                              color: const Color(0xFFDCFCE7),
                            ),
                            _financeChip(
                              label: 'Receita contrato (período)',
                              value: CurrencyFormats.formatBRL(contractInPeriod),
                              color: const Color(0xFFE9D5FF),
                            ),
                            _financeChip(
                              label: 'Resultado no período',
                              value: CurrencyFormats.formatBRL(resultado),
                              color: lucroColor,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        AppBarChart(
                          title: 'Visão rápida (valores no período)',
                          values: [
                            totalCostPeriod < 0 ? 0 : totalCostPeriod,
                            totalRevenueUsers < 0 ? 0 : totalRevenueUsers,
                            contractInPeriod < 0 ? 0 : contractInPeriod,
                            resultado.abs(),
                          ],
                          labels: const [
                            'Custo período',
                            'Rec. usuários',
                            'Contrato perí.',
                            '|Result.|',
                          ],
                          barColor: const Color(0xFF2563EB),
                          height: 160,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Resultado = receita do contrato no período + (receita/usuário × Q) − (custo/usuário × Q). Unidades ~MB são estimativa.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Detalhe usuário a usuário (até ${docs.length} listados)',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (docs.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'Nenhum usuário com cadastro neste intervalo.',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: docs.length,
                            separatorBuilder: (_, __) =>
                                Divider(height: 1, color: Colors.grey.shade200),
                            itemBuilder: (context, i) {
                              final doc = docs[i];
                              return ExpansionTile(
                                tilePadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 0,
                                ),
                                childrenPadding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                title: Text(
                                  _displayUserLine(doc),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  _createdAtLine(doc) ??
                                      'Sem data de cadastro',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                children: [
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Custo atribuído: ${CurrencyFormats.formatBRL(costUser)}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        Text(
                                          'Receita/usuário: ${CurrencyFormats.formatBRL(revenueUser)}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        Text(
                                          'Dados ~ $_kMbEstimativaPorUsuario MB (estimativa)',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _financeChip({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _CsvSourceBlock extends StatefulWidget {
  final String partnershipId;
  final String initialUrl;
  final String csvStatus;
  final String csvErr;
  final bool csvPendingAdminReview;
  final Future<void> Function(String url) onSaveUrl;
  final Future<void> Function(String url, bool removeMissingNotInCsv) onSync;
  final Future<void> Function(String url, bool removeMissingNotInCsv)
      onPipelineExternal;
  final VoidCallback onDismissReview;
  final Future<void> Function(bool removeMissingNotInCsv) onPickCsvFile;

  const _CsvSourceBlock({
    required this.partnershipId,
    required this.initialUrl,
    required this.csvStatus,
    required this.csvErr,
    this.csvPendingAdminReview = false,
    required this.onSaveUrl,
    required this.onSync,
    required this.onPipelineExternal,
    required this.onDismissReview,
    required this.onPickCsvFile,
  });

  @override
  State<_CsvSourceBlock> createState() => _CsvSourceBlockState();
}

class _CsvSourceBlockState extends State<_CsvSourceBlock> {
  late final TextEditingController _ctrl;
  bool _removeMissingNotInCsv = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialUrl);
  }

  @override
  void didUpdateWidget(covariant _CsvSourceBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialUrl != widget.initialUrl &&
        widget.initialUrl != _ctrl.text) {
      _ctrl.text = widget.initialUrl;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CSV — URL ou upload manual',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Por URL: integração/API — o parceiro mantém um CSV público em https; o sistema baixa e importa em cada sync. Por arquivo: upload manual. Mesmo fluxo de conferência.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Remover quem não está mais no CSV'),
          subtitle: Text(
            'Ao sincronizar, retira do convênio os e-mails que saíram da lista (automático).',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
          value: _removeMissingNotInCsv,
          onChanged: (v) => setState(() => _removeMissingNotInCsv = v),
        ),
        const SizedBox(height: 8),
        if (widget.csvPendingAdminReview)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: widget.onDismissReview,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.flag_rounded,
                          color: Colors.orange.shade900, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Aguardando sua conferência (importação CSV)',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                                color: Colors.orange.shade900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Confira membros, usuários criados e logs de sync. Depois toque em «Conferência OK».',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade800,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: widget.onDismissReview,
                        child: const Text('Conferência OK'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        FastTextField(
          controller: _ctrl,
          decoration: const InputDecoration(
            labelText: 'URL do CSV (https://...)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          keyboardType: TextInputType.url,
        ),
        if (widget.csvStatus.isNotEmpty || widget.csvErr.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              [
                if (widget.csvStatus.isNotEmpty) 'Último sync: ${widget.csvStatus}',
                if (widget.csvErr.isNotEmpty) widget.csvErr,
              ].join(' — '),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () =>
                  widget.onPickCsvFile(_removeMissingNotInCsv),
              icon: const Icon(Icons.upload_file_rounded),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
              ),
              label: const Text('Escolher arquivo .csv (manual)'),
            ),
            FilledButton.icon(
              onPressed: () => widget.onPipelineExternal(
                    _ctrl.text,
                    _removeMissingNotInCsv,
                  ),
              icon: const Icon(Icons.cloud_download_rounded),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.deepBlueDark,
                foregroundColor: Colors.white,
              ),
              label: const Text('Gravar URL + importar (fluxo completo)'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => widget.onSaveUrl(_ctrl.text),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Só gravar URL'),
            ),
            FilledButton.icon(
              onPressed: () =>
                  widget.onSync(_ctrl.text, _removeMissingNotInCsv),
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Sincronizar agora'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Pré-visualização em tela cheia: usuários vinculados ao convênio (Resumo Admin / convênios).
Future<void> openPartnershipUsersPreview(
  BuildContext context, {
  PartnershipUsersPreviewScope scope = PartnershipUsersPreviewScope.byPartnership,
  required String partnershipId,
  required String partnershipPlanCode,
  required String partnershipName,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (ctx) => AdminPartnershipUsersPreviewPage(
        scope: scope,
        partnershipId: partnershipId,
        partnershipPlanCode: partnershipPlanCode,
        partnershipName: partnershipName,
      ),
    ),
  );
}

/// Tela cheia com lista estilo Admin › Usuários (plano, licença, convênio, remoção).
class AdminPartnershipUsersPreviewPage extends StatelessWidget {
  final PartnershipUsersPreviewScope scope;
  final String partnershipId;
  final String partnershipPlanCode;
  final String partnershipName;

  const AdminPartnershipUsersPreviewPage({
    super.key,
    required this.scope,
    required this.partnershipId,
    required this.partnershipPlanCode,
    required this.partnershipName,
  });

  String get _title {
    if (scope == PartnershipUsersPreviewScope.allWithPartnershipLink) {
      return 'Utilizadores com convênio';
    }
    return 'Convênio $partnershipName';
  }

  String get _subtitle {
    if (scope == PartnershipUsersPreviewScope.allWithPartnershipLink) {
      return 'Campo partnershipId preenchido — editar plano, licença, convênio ou remover.';
    }
    return 'Pré-visualização e gestão — igual à tela Usuários do Admin.';
  }

  @override
  Widget build(BuildContext context) {
    final mobile = AdminResponsive.useMobileLayout(context);
    final layout = mobile
        ? PartnershipUsersPanelLayout.cards
        : PartnershipUsersPanelLayout.dataTable;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      resizeToAvoidBottomInset: scaffoldKeyboardResizeToAvoidBottomInset(),
      backgroundColor: const Color(0xFFF0F4F9),
      appBar: AppBar(
        title: Text(_title, maxLines: 2, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Fechar',
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('partnerships')
              .limit(200)
              .snapshots(),
          builder: (context, snap) {
            final catalog = snap.hasData
                ? parsePartnershipPlansSnapshot(snap.data!)
                : const <AdminPartnershipPlanOption>[];
            return ListView(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottom),
              children: [
                ModuleHeaderPremium(
                  title: _title,
                  icon: Icons.people_rounded,
                  dense: mobile,
                  subtitle: _subtitle,
                ),
                const SizedBox(height: 12),
                PartnershipUsersPanel(
                  partnershipId: partnershipId,
                  partnershipPlanCode: partnershipPlanCode,
                  layout: layout,
                  scope: scope,
                  conveniosCatalog: catalog,
                  useRichUserCards: mobile,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
