import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart' hide showDatePicker;
import '../widgets/fast_text_field.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/user_profile.dart';
import '../models/financial_goal.dart';
import '../theme/app_colors.dart';
import '../constants/finance_tips.dart';
import '../constants/currency_formats.dart';
import '../utils/premium_upgrade.dart';
import '../widgets/registrar_aporte_dialog.dart';
import '../utils/date_picker_a11y.dart';
import '../constants/app_business_rules.dart';
import '../utils/firestore_user_doc_id.dart';
import '../widgets/brl_amount_text_field.dart';
import '../utils/keyboard_form_scaffold.dart';
import '../utils/home_shell_layout.dart';
import '../utils/fifty_two_weeks_plan.dart';
import '../utils/goal_objective_visuals.dart';
import '../widgets/fifty_two_weeks_schedule_sheet.dart';

/// Categorias de metas (estrutura base Premium).
final List<GoalCategory> kGoalCategories = GoalCategory.values.toList();

/// Sugestões rápidas de metas para o usuário escolher ou inspirar.
const List<Map<String, String>> kMetaSugestoes = [
  {'title': 'Comprar um carro', 'emoji': '🚗', 'cat': 'veiculo'},
  {'title': 'Pagar contas / quitar dívidas', 'emoji': '📋', 'cat': 'personalizada'},
  {'title': 'Reserva de emergência', 'emoji': '🛡️', 'cat': 'reserva_emergencia'},
  {'title': 'Viagem', 'emoji': '✈️', 'cat': 'viagem'},
  {'title': 'Reforma da casa', 'emoji': '🏠', 'cat': 'casa'},
  {'title': 'Curso ou especialização', 'emoji': '📚', 'cat': 'estudo'},
  {'title': 'Investimento', 'emoji': '📈', 'cat': 'investimento'},
  {'title': 'Outro', 'emoji': '🎯', 'cat': 'personalizada'},
];

class MetaFinanceiraScreen extends StatefulWidget {
  final String uid;
  final UserProfile profile;
  final void Function(int index)? onNavigateTo;

  const MetaFinanceiraScreen({super.key, required this.uid, required this.profile, this.onNavigateTo});

  @override
  State<MetaFinanceiraScreen> createState() => _MetaFinanceiraScreenState();
}

enum _GoalListSort { prazo, titulo, valorAlvoDesc }

class _MetaFinanceiraScreenState extends State<MetaFinanceiraScreen> {
  StreamSubscription<fa.User?>? _authStateSub;

  _GoalListSort _goalListSort = _GoalListSort.prazo;

  /// Blindagem: usa UID efetivo (titular quando sub-login).
  String get _userDocId => firestoreUserDocIdStrictFromSession();

  CollectionReference<Map<String, dynamic>> get _goals =>
      FirebaseFirestore.instance.collection('users').doc(_userDocId).collection('goals');
  CollectionReference<Map<String, dynamic>> get _tx =>
      FirebaseFirestore.instance.collection('users').doc(_userDocId).collection('transactions');
  DocumentReference<Map<String, dynamic>> get _planningRef => FirebaseFirestore.instance
      .collection('users')
      .doc(_userDocId)
      .collection('settings')
      .doc('planning');

  @override
  void initState() {
    super.initState();
    _authStateSub = fa.FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _authStateSub?.cancel();
    _authStateSub = null;
    super.dispose();
  }

  /// Dica do dia (rotacionada pelo dia do ano).
  String get _dicaDoDia {
    final dayOfYear = DateTime.now().difference(DateTime(DateTime.now().year, 1, 1)).inDays;
    return kFinanceTips[dayOfYear % kFinanceTips.length];
  }

  Future<void> _criarMeta(BuildContext context) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    if (_userDocId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A sincronizar sessão… tente novamente em instantes.')),
        );
      }
      return;
    }
    final titleCtrl = TextEditingController();
    final targetCtrl = TextEditingController();
    DateTime? dueDate;
    bool reminderAporte = false;
    GoalCategory category = GoalCategory.personalizada;
    GoalPriority priority = GoalPriority.media;
    final interestCtrl = TextEditingController(text: '0.5');
    bool hasInterest = false;
    bool use52WeeksPlan = true;
    String selectedEmoji = '🎯';
    Timer? metaSuggestDebounce;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final target = CurrencyFormats.parseBRLInput(targetCtrl.text) ?? 0;
          int monthsLeft = 0;
          if (dueDate != null && target > 0) {
            final d = dueDate!;
            final now = DateTime.now();
            var m = (d.year - now.year) * 12 + (d.month - now.month);
            if (d.day < now.day) m--;
            monthsLeft = m.clamp(1, 999);
          }
          String? suggestedMonthly;
          final rate = double.tryParse(interestCtrl.text.replaceAll(',', '.')) ?? 0;
          if (monthsLeft > 0 && target > 0) {
            if (hasInterest && rate > 0) {
              final i = rate / 100;
              final denom = math.pow(1 + i, monthsLeft).toDouble() - 1;
              suggestedMonthly = denom > 0 ? (target * i / denom).toStringAsFixed(2) : (target / monthsLeft).toStringAsFixed(2);
            } else {
              suggestedMonthly = (target / monthsLeft).toStringAsFixed(2);
            }
          }
          const atalhosMeta = [
            (Icons.home_rounded, Color(0xFF0D9488), 'Compra Casa', 'casa'),
            (Icons.build_rounded, Color(0xFFB45309), 'Reforma de Casa', 'casa'),
            (Icons.flight_rounded, Color(0xFF2563EB), 'Viagem', 'viagem'),
            (Icons.school_rounded, Color(0xFF7C3AED), 'Escola', 'estudo'),
            (Icons.menu_book_rounded, Color(0xFF059669), 'Faculdade', 'estudo'),
            (Icons.directions_car_rounded, Color(0xFFDC2626), 'Comprar um carro', 'veiculo'),
            (Icons.edit_rounded, Color(0xFF64748B), 'Personalizado', 'personalizada'),
          ];
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
            titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 4),
            contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            title: _metaDialogTitleRow(icon: Icons.flag_rounded, title: 'Novo objetivo financeiro'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('O que você quer conquistar?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final at in atalhosMeta)
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              titleCtrl.text = at.$3;
                              category = GoalCategory.fromId(at.$4);
                              final preset = presetForCategory(at.$4);
                              selectedEmoji = preset?.visual.emoji ?? '🎯';
                              setState(() {});
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: (at.$2).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: (at.$2).withOpacity(0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(at.$1, size: 22, color: at.$2),
                                  const SizedBox(width: 8),
                                  Text(at.$3, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: at.$2)),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  FastTextField(
                    controller: titleCtrl,
                    decoration: _metaInputDecoration(
                      labelText: 'Nome da meta',
                      hintText: 'Ex: Comprar um carro, Reserva de emergência, Viagem',
                    ),
                  ),
                  const SizedBox(height: 12),
                  BrlAmountTextField(
                    controller: targetCtrl,
                    decoration: _metaInputDecoration(
                      labelText: 'Valor alvo (R\$)',
                      hintText: 'Ex: 50.000,00',
                      prefixText: 'R\$ ',
                    ),
                    onChanged: (_) {
                      metaSuggestDebounce?.cancel();
                      metaSuggestDebounce = Timer(
                        Duration(
                            milliseconds: AppBusinessRules.searchDebounceMs),
                        () {
                          if (ctx.mounted) setState(() {});
                        },
                      );
                    },
                  ),
                  if (suggestedMonthly != null && !use52WeeksPlan) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.success.withOpacity(0.35)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lightbulb_outline_rounded, size: 20, color: AppColors.success),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Sugestão: guarde ${CurrencyFormats.formatBRL(double.tryParse(suggestedMonthly) ?? 0)}/mês para atingir no prazo${hasInterest && rate > 0 ? " (com juros)" : ""}.',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF6366F1).withOpacity(0.12),
                          const Color(0xFFEC4899).withOpacity(0.10),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: use52WeeksPlan,
                          onChanged: (v) => setState(() => use52WeeksPlan = v),
                          title: const Text(
                            'Projeto 52 semanas',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                          subtitle: const Text(
                            'Programação semanal automática (incremento progressivo até a meta).',
                            style: TextStyle(fontSize: 12),
                          ),
                          activeColor: const Color(0xFF6366F1),
                        ),
                        if (use52WeeksPlan && target > 0) ...[
                          const Divider(height: 16),
                          Text(
                            'Semana 1: ${CurrencyFormats.formatBRL(FiftyTwoWeeksPlan.amountForWeek(target, 1))}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                          ),
                          Text(
                            'Semana 52: ${CurrencyFormats.formatBRL(FiftyTwoWeeksPlan.amountForWeek(target, 52))}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                          ),
                          Text(
                            'Total programado: ${CurrencyFormats.formatBRL(target)} em 52 semanas',
                            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!use52WeeksPlan) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          dueDate == null
                              ? 'Sem prazo'
                              : 'Prazo: ${DateFormat('dd/MM/yyyy').format(dueDate!)}',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.now().add(const Duration(days: 365)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime(2030, 12, 31),
                          );
                          if (picked != null) setState(() => dueDate = picked);
                        },
                        icon: const Icon(Icons.calendar_today_rounded, size: 18),
                        label: const Text('Definir prazo'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent.withOpacity(0.16),
                          foregroundColor: AppColors.accent,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ],
                  ),
                  ],
                  const SizedBox(height: 12),
                  const Text('Prioridade', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: GoalPriority.values.map((p) {
                      final sel = priority == p;
                      return _buildSortChip(
                        label: p.label,
                        selected: sel,
                        onTap: () => setState(() => priority = p),
                        active: _priorityActiveColor(p),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: hasInterest,
                    onChanged: (v) => setState(() => hasInterest = v ?? false),
                    title: const Text('Meta com rendimento (juros compostos)', style: TextStyle(fontSize: 14)),
                    subtitle: hasInterest
                        ? Text('Ex: CDI ~0,5%/mês, Tesouro Selic. Projeção: FV = PV(1+i)^n', style: TextStyle(fontSize: 11, color: Colors.grey.shade600))
                        : null,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (hasInterest) ...[
                    const SizedBox(height: 8),
                    FastTextField(
                      controller: interestCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: _metaInputDecoration(
                        labelText: 'Taxa mensal estimada (%)',
                        hintText: 'Ex: 0.5 (CDI)',
                        suffixText: '%',
                        prefixIcon: const Icon(Icons.trending_up_rounded, size: 20),
                      ),
                      onChanged: (_) {
                        metaSuggestDebounce?.cancel();
                        metaSuggestDebounce = Timer(
                          Duration(
                              milliseconds: AppBusinessRules.searchDebounceMs),
                          () {
                            if (ctx.mounted) setState(() {});
                          },
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: reminderAporte,
                    onChanged: (v) => setState(() => reminderAporte = v ?? false),
                    title: const Text('Lembrar de aportar todo mês', style: TextStyle(fontSize: 14)),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            actions: [
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 10,
                children: [
                  _metaDialogCancel(onPressed: () => Navigator.pop(ctx, false)),
                  _metaDialogGradientButton(
                    label: 'Criar meta',
                    onPressed: () => Navigator.pop(ctx, true),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    ).whenComplete(() => metaSuggestDebounce?.cancel());

    try {
      if (ok != true) return;
      final title = titleCtrl.text.trim();
      final target = CurrencyFormats.parseBRLInput(targetCtrl.text) ?? 0;
      if (title.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe o nome da meta.')));
        return;
      }
      if (target <= 0) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe o valor alvo.')));
        return;
      }

      try {
        final planStart = FiftyTwoWeeksPlan.normalizePlanStart(DateTime.now());
        await _goals.add({
          'title': title,
          'targetAmount': target,
          'dueDate': use52WeeksPlan
              ? Timestamp.fromDate(planStart.add(const Duration(days: 52 * 7)))
              : (dueDate != null ? Timestamp.fromDate(dueDate!) : null),
          'reminderAporte': reminderAporte,
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'active',
          'category': category.id,
          'priority': priority.name,
          'interestRateMonthly': hasInterest ? (double.tryParse(interestCtrl.text.replaceAll(',', '.')) ?? 0) : 0,
          'planType': use52WeeksPlan ? '52weeks' : 'classic',
          if (use52WeeksPlan) ...{
            'planStartDate': Timestamp.fromDate(planStart),
            'weeklyIncrement': FiftyTwoWeeksPlan.weeklyIncrementForTarget(target),
            'weeksPaid': <int>[],
          },
          'emoji': selectedEmoji,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              use52WeeksPlan
                  ? 'Objetivo "$title" criado com Projeto 52 semanas!'
                  : 'Objetivo "$title" criado! Acompanhe o progresso abaixo.',
            ),
          ));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao criar meta: ${e.toString().split('\n').first}')),
          );
        }
      }
    } finally {
      titleCtrl.dispose();
      targetCtrl.dispose();
      interestCtrl.dispose();
    }
  }

  Future<void> _registrarAporte(BuildContext context, DocumentReference<Map<String, dynamic>> goalRef) async {
    final ok = await showRegistrarAporteDialog(
      context: context,
      goalRef: goalRef,
      profile: widget.profile,
    );
    if (ok && mounted && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aporte registrado!')));
    }
  }

  /// Barra superior padrão dos previews/sheets do módulo Meta — pedido do
  /// usuário: cada preview tem **«Voltar»** à esquerda (paridade total
  /// iPhone / iOS / Android / Web) + atalho **«X»** à direita. Mesmo
  /// visual dos previews do Painel Inicial e dos demais módulos.
  Widget _metaPreviewTopBar(BuildContext ctx) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Row(
        children: [
          Material(
            color: AppColors.primary.withValues(alpha: 0.08),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(ctx).pop(),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: AppColors.primary,
                  size: 22,
                  semanticLabel: 'Voltar',
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              foregroundColor: AppColors.primary,
            ),
            child: const Text(
              'Voltar',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const Spacer(),
          Material(
            color: Colors.grey.shade100,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(ctx).pop(),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  Icons.close_rounded,
                  size: 22,
                  color: Color(0xFF1A237E),
                  semanticLabel: 'Fechar',
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  /// Abre tela de Ver/Editar Lançamentos (aportes) da meta — estilo módulo Controle Financeiro.
  Future<void> _verEditarLancamentos(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> goalDoc,
    String goalTitle,
  ) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final contribRef = goalDoc.reference.collection('contributions');
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              // Topo do preview: «Voltar» (esquerda) + X (direita).
              _metaPreviewTopBar(ctx),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: [
                    Icon(Icons.list_alt_rounded, color: AppColors.primary, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Lançamentos · $goalTitle',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1A237E)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: contribRef.orderBy('date', descending: true).snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(child: Text('Erro: ${snap.error}', style: TextStyle(color: Colors.grey.shade700)));
                    }
                    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snap.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inbox_rounded, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text('Nenhum aporte ainda', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                            const SizedBox(height: 8),
                            Text('Use "Registrar aporte" no card da meta.', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                          ],
                        ),
                      );
                    }
                    return ListView.builder(
                      controller: scrollController,
                      cacheExtent: 400,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final doc = docs[i];
                        final d = doc.data();
                        final amount = (d['amount'] ?? 0).toDouble();
                        final dateTs = d['date'] as Timestamp?;
                        final date = dateTs?.toDate() ?? DateTime.now();
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          color: AppColors.primary.withOpacity(0.04),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: CircleAvatar(
                              backgroundColor: AppColors.primary.withOpacity(0.15),
                              child: Icon(Icons.savings_rounded, color: AppColors.primary, size: 22),
                            ),
                            title: Text(
                              CurrencyFormats.formatBRL(amount),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                            subtitle: Text(DateFormat('dd/MM/yyyy').format(date), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.edit_rounded, size: 22, color: Colors.grey.shade700),
                                  onPressed: () => _editarAporte(ctx, doc, goalTitle),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete_outline_rounded, size: 22, color: AppColors.error),
                                  onPressed: () => _excluirAporte(ctx, doc, goalTitle),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editarAporte(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> contribDoc,
    String goalTitle,
  ) async {
    final d = contribDoc.data();
    final amountCtrl = TextEditingController(text: CurrencyFormats.formatBRLInput((d['amount'] ?? 0) as num));
    DateTime date = (d['date'] as Timestamp?)?.toDate() ?? DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 4),
          contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: _metaDialogTitleRow(icon: Icons.savings_rounded, title: 'Editar aporte'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BrlAmountTextField(
                  controller: amountCtrl,
                  decoration: _metaInputDecoration(
                    labelText: 'Valor (R\$)',
                    prefixText: 'R\$ ',
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  tileColor: const Color(0xFFF8FAFC),
                  title: const Text('Data do aporte', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(date), style: TextStyle(color: Colors.grey.shade700)),
                  trailing: FilledButton.tonal(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setState(() => date = picked);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary.withOpacity(0.12),
                      foregroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Alterar'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 10,
              children: [
                _metaDialogCancel(onPressed: () => Navigator.pop(ctx, false)),
                _metaDialogGradientButton(
                  label: 'Salvar',
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    try {
      if (ok != true) return;
      final amount = CurrencyFormats.parseBRLInput(amountCtrl.text) ?? 0;
      if (amount <= 0) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe um valor maior que zero.')));
        return;
      }
      try {
        await contribDoc.reference.update({
          'amount': amount,
          'date': Timestamp.fromDate(date),
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aporte atualizado!')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: ${e.toString().split('\n').first}')));
      }
    } finally {
      amountCtrl.dispose();
    }
  }

  Future<void> _excluirAporte(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> contribDoc,
    String goalTitle,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: _metaDialogTitleRow(icon: Icons.delete_outline_rounded, title: 'Excluir aporte'),
        content: const Text('Deseja realmente excluir este lançamento? O valor será descontado do progresso da meta.'),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            children: [
              _metaDialogCancel(onPressed: () => Navigator.pop(ctx, false)),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Excluir', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await contribDoc.reference.delete();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lançamento excluído.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao excluir: ${e.toString().split('\n').first}')));
    }
  }

  Future<void> _editarMeta(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> goalDoc) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final data = goalDoc.data();
    final titleCtrl = TextEditingController(text: (data['title'] ?? '').toString());
    final targetCtrl = TextEditingController(text: CurrencyFormats.formatBRLInput((data['targetAmount'] ?? 0) as num));
    DateTime? dueDate = (data['dueDate'] as Timestamp?)?.toDate();
    GoalPriority priority = GoalPriority.media;
    try {
      priority = GoalPriority.values.firstWhere((e) => e.name == (data['priority'] ?? ''));
    } catch (_) {}

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 4),
          contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: _metaDialogTitleRow(icon: Icons.edit_rounded, title: 'Editar meta'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FastTextField(
                  controller: titleCtrl,
                  decoration: _metaInputDecoration(labelText: 'Nome da meta'),
                ),
                const SizedBox(height: 12),
                BrlAmountTextField(
                  controller: targetCtrl,
                  decoration: _metaInputDecoration(
                    labelText: 'Valor alvo (R\$)',
                    prefixText: 'R\$ ',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        dueDate == null ? 'Sem prazo' : 'Prazo: ${DateFormat('dd/MM/yyyy').format(dueDate!)}',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: dueDate ?? DateTime.now().add(const Duration(days: 365)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2030, 12, 31),
                        );
                        if (picked != null) setState(() => dueDate = picked);
                      },
                      icon: const Icon(Icons.calendar_today_rounded, size: 18),
                      label: const Text('Alterar'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent.withOpacity(0.16),
                        foregroundColor: AppColors.accent,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Prioridade', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: GoalPriority.values.map((p) {
                    final sel = priority == p;
                    return _buildSortChip(
                      label: p.label,
                      selected: sel,
                      onTap: () => setState(() => priority = p),
                      active: _priorityActiveColor(p),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 10,
              children: [
                _metaDialogCancel(onPressed: () => Navigator.pop(ctx, false)),
                _metaDialogGradientButton(
                  label: 'Salvar alterações',
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    try {
      if (ok != true) return;
      final title = titleCtrl.text.trim();
      final target = CurrencyFormats.parseBRLInput(targetCtrl.text) ?? 0;
      if (title.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe o nome da meta.')));
        return;
      }
      if (target <= 0) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe o valor alvo.')));
        return;
      }
      try {
        await goalDoc.reference.update({
          'title': title,
          'targetAmount': target,
          'dueDate': dueDate != null ? Timestamp.fromDate(dueDate!) : null,
          'priority': priority.name,
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Meta atualizada.')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao atualizar: ${e.toString().split('\n').first}')));
      }
    } finally {
      titleCtrl.dispose();
      targetCtrl.dispose();
    }
  }

  Future<void> _excluirMeta(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> goalDoc) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: _metaDialogTitleRow(icon: Icons.flag_outlined, title: 'Excluir meta'),
        content: Text(
          'Excluir "${(goalDoc.data()['title'] ?? 'Meta').toString()}"? Os aportes já registrados não serão removidos.',
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            children: [
              _metaDialogCancel(onPressed: () => Navigator.pop(ctx, false)),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Excluir', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await goalDoc.reference.delete();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Meta excluída.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao excluir: ${e.toString().split('\n').first}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final padding = MediaQuery.paddingOf(context);
    final isNarrow = width < 720;
    final isCompact = width < 400;
    final embeddedInShell = widget.onNavigateTo != null;

    return Scaffold(
      resizeToAvoidBottomInset: scaffoldKeyboardResizeToAvoidBottomInset(
        embeddedInHomeShell: embeddedInShell,
      ),
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF5F8FC),
              Color(0xFFEEF3FA),
              Color(0xFFE8F0F8),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          top: false,
          bottom: homeShellSafeAreaBottom(embeddedInHomeShell: embeddedInShell),
          left: true,
          right: true,
          child: RepaintBoundary(
            child: CustomScrollView(
              slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  (isNarrow ? 16 : 24) + padding.left,
                  isNarrow ? 6 : 4,
                  (isNarrow ? 16 : 24) + padding.right,
                  homeShellScrollBottomPadding(
                    context,
                    embeddedInHomeShell: embeddedInShell,
                    tail: 20,
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_userDocId.isNotEmpty)
                          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                            key: ValueKey<String>('meta-planning-${_userDocId}'),
                            stream: _planningRef.snapshots(),
                            builder: (context, snap) {
                              final enabled = (snap.data?.data()?['dailyTipsEnabled'] ?? false) as bool;
                              if (!enabled) return const SizedBox.shrink();
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildDicaCard(context),
                                  const SizedBox(height: 24),
                                ],
                              );
                            },
                          ),
                        if (isCompact)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildModuleHeroHeader(isCompact: true),
                              const SizedBox(height: 16),
                              const Text('Meus objetivos', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A237E))),
                              const SizedBox(height: 12),
                              _buildNovaMetaButton(expand: true, label: 'Novo objetivo'),
                            ],
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildModuleHeroHeader(isCompact: false),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Text('Meus objetivos', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A237E))),
                                  _buildNovaMetaButton(expand: false, label: 'Novo objetivo'),
                                ],
                              ),
                            ],
                          ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Ordenar metas:',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            _buildSortChip(
                              label: 'Prazo',
                              selected: _goalListSort == _GoalListSort.prazo,
                              onTap: () => setState(() => _goalListSort = _GoalListSort.prazo),
                              active: _sortPrazo,
                            ),
                            _buildSortChip(
                              label: 'Título A–Z',
                              selected: _goalListSort == _GoalListSort.titulo,
                              onTap: () => setState(() => _goalListSort = _GoalListSort.titulo),
                              active: _sortTitulo,
                            ),
                            _buildSortChip(
                              label: 'Valor alvo',
                              selected: _goalListSort == _GoalListSort.valorAlvoDesc,
                              onTap: () => setState(() => _goalListSort = _GoalListSort.valorAlvoDesc),
                              active: _sortValor,
                              onActive: const Color(0xFF78350F),
                              onActiveMuted: const Color(0xFF78350F),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildGoalsList(context),
                      ],
                    ),
                  ),
                ),
              ),
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Cabeçalho colorido do módulo Objetivo Financeiro.
  Widget _buildModuleHeroHeader({required bool isCompact}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isCompact ? 16 : 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFFEC4899)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withOpacity(0.32),
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
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.flag_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Objetivo Financeiro',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Projeto 52 semanas · viagem, carro, casa, reforma, quitar dívidas',
            style: TextStyle(
              color: Colors.white.withOpacity(0.92),
              fontWeight: FontWeight.w600,
              fontSize: isCompact ? 12 : 13,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  /// CTA principal — gradiente + sombra (visual premium).
  Widget _buildNovaMetaButton({required bool expand, String label = 'Nova meta'}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _criarMeta(context),
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF2563EB),
                Color(0xFF1D4ED8),
                Color(0xFF0D9488),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0xFF0D9488).withOpacity(0.38),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const Color _sortPrazo = Color(0xFF0D9488);
  static const Color _sortTitulo = Color(0xFF4F46E5);
  static const Color _sortValor = Color(0xFFF59E0B);

  Widget _buildSortChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Color active,
    Color onActive = Colors.white,
    Color? onActiveMuted,
  }) {
    final muted = onActiveMuted ?? onActive;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? active : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? active.withOpacity(0.95) : Colors.grey.shade300,
              width: selected ? 0 : 1.2,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: active.withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check_rounded, size: 18, color: onActive),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: selected ? muted : Colors.grey.shade700,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Barra de progresso com gradiente e altura confortável para leitura.
  Widget _buildGoalProgressTrack(double progress, Color accentEnd) {
    final p = progress.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 14,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.grey.shade100),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: p,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.accent,
                      accentEnd,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const LinearGradient _metaCtaGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF2563EB),
      Color(0xFF1D4ED8),
      Color(0xFF0D9488),
    ],
  );

  Widget _metaDialogTitleRow({required IconData icon, required String title}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: _metaCtaGradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0D9488).withOpacity(0.28),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A237E),
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _metaInputDecoration({
    required String labelText,
    String? hintText,
    Widget? prefixIcon,
    String? prefixText,
    String? suffixText,
  }) {
    final r = BorderRadius.circular(14);
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixIcon: prefixIcon,
      prefixText: prefixText,
      suffixText: suffixText,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(borderRadius: r),
      enabledBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: const BorderSide(color: AppColors.accent, width: 2),
      ),
    );
  }

  Widget _metaDialogCancel({required VoidCallback onPressed}) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF334155),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: Colors.grey.shade300, width: 1.2),
      ),
      child: const Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Widget _metaDialogGradientButton({required String label, required VoidCallback onPressed}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            gradient: _metaCtaGradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0D9488).withOpacity(0.32),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ),
      ),
    );
  }

  Color _priorityActiveColor(GoalPriority p) {
    return switch (p) {
      GoalPriority.alta => AppColors.error,
      GoalPriority.media => AppColors.primary,
      GoalPriority.baixa => const Color(0xFF64748B),
    };
  }

  Widget _buildDicaCard(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 400;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(isCompact ? 14 : 18, isCompact ? 14 : 16, isCompact ? 14 : 18, isCompact ? 14 : 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.deepBlueDark.withOpacity(0.92),
            const Color(0xFF134E6F),
            AppColors.accent.withOpacity(0.88),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(color: AppColors.accent.withOpacity(0.22), blurRadius: 18, offset: const Offset(0, 8)),
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.lightbulb_rounded, color: Colors.amber.shade200, size: isCompact ? 22 : 24),
              ),
              SizedBox(width: isCompact ? 10 : 12),
              const Expanded(
                child: Text(
                  'Dica do dia',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _dicaDoDia,
            style: TextStyle(
              color: Colors.white.withOpacity(0.95),
              fontSize: isCompact ? 13 : 14,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalsList(BuildContext context) {
    final id = _userDocId;
    if (id.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(strokeWidth: 2),
              SizedBox(height: 16),
              Text('A sincronizar sessão…', textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      key: ValueKey<String>('meta-goals-$id'),
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(id)
          .collection('goals')
          .where('status', isEqualTo: 'active')
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 48, color: Colors.orange.shade700),
                const SizedBox(height: 16),
                Text('Erro ao carregar metas. Tente novamente.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
                const SizedBox(height: 16),
                FilledButton.icon(onPressed: () => setState(() {}), icon: const Icon(Icons.refresh_rounded), label: const Text('Atualizar')),
              ],
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
        }
        var docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildEmptyGoals();
        }
        docs = docs.toList()
          ..sort((a, b) {
            final da = a.data();
            final db = b.data();
            switch (_goalListSort) {
              case _GoalListSort.prazo:
                final ta = da['dueDate'] as Timestamp?;
                final tb = db['dueDate'] as Timestamp?;
                if (ta == null && tb == null) return 0;
                if (ta == null) return 1;
                if (tb == null) return -1;
                return ta.compareTo(tb);
              case _GoalListSort.titulo:
                return (da['title'] ?? '')
                    .toString()
                    .toLowerCase()
                    .compareTo((db['title'] ?? '').toString().toLowerCase());
              case _GoalListSort.valorAlvoDesc:
                return ((db['targetAmount'] ?? 0) as num)
                    .compareTo((da['targetAmount'] ?? 0) as num);
            }
          });
        return Column(
          children: docs.map((doc) => _buildGoalCard(context, doc)).toList(),
        );
      },
    );
  }

  Widget _buildEmptyGoals() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        children: [
          Icon(Icons.flag_rounded, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text(
            'Nenhum objetivo ainda',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1A237E)),
          ),
          const SizedBox(height: 8),
          Text(
            'Crie um objetivo com Projeto 52 semanas — o app monta a programação semanal automaticamente.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          _buildNovaMetaButton(expand: true, label: 'Criar meu primeiro objetivo'),
        ],
      ),
    );
  }

  /// Cor do indicador de progresso: verde = no prazo, amarelo = risco, vermelho = atrasado.
  Color _progressColor(GoalProjection proj, double progress, DateTime? dueDate) {
    if (progress >= 1) return AppColors.success;
    if (dueDate == null) return AppColors.primary;
    if (!proj.isOnTrack && proj.monthsAheadOrBehind != null && proj.monthsAheadOrBehind! > 0) {
      return AppColors.error;
    }
    if (proj.daysRemaining <= 90 && progress < 0.5) return Colors.orange;
    return AppColors.success;
  }

  Future<void> _simularCenario(BuildContext context, String goalId, String title, double target, double current, DateTime? dueDate) async {
    final valorCtrl = TextEditingController(text: CurrencyFormats.formatBRLInput(target - current > 0 ? (target - current) / 12 : 500));
    final taxaCtrl = TextEditingController(text: '0.5');
    Timer? simDeb;

    await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) {
          void onSimFieldChanged() {
            simDeb?.cancel();
            simDeb = Timer(
              Duration(milliseconds: AppBusinessRules.searchDebounceMs),
              () {
                if (ctx.mounted) setState(() {});
              },
            );
          }

          final aporte = CurrencyFormats.parseBRLInput(valorCtrl.text) ?? 0;
          final taxaMensal = double.tryParse(taxaCtrl.text.replaceAll(',', '.')) ?? 0.5;
          int meses = 12;
          if (dueDate != null) {
            final now = DateTime.now();
            meses = (dueDate.year - now.year) * 12 + (dueDate.month - now.month);
            if (meses < 1) meses = 1;
          }
          double fv = current;
          for (int m = 0; m < meses; m++) {
            fv = futureValueCompound(fv, taxaMensal, 1) + aporte;
          }
          final atingiu = fv >= target;
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
            titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 4),
            contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            title: _metaDialogTitleRow(icon: Icons.bar_chart_rounded, title: 'Simular cenário'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Meta: $title', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1A237E))),
                  const SizedBox(height: 8),
                  Text('Se você guardar por mês:', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                  const SizedBox(height: 6),
                  BrlAmountTextField(
                    controller: valorCtrl,
                    decoration: _metaInputDecoration(
                      labelText: 'Valor (R\$)',
                      prefixText: 'R\$ ',
                    ),
                    onChanged: (_) => onSimFieldChanged(),
                  ),
                  const SizedBox(height: 8),
                  FastTextField(
                    controller: taxaCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: _metaInputDecoration(
                      labelText: 'Taxa mensal (%)',
                      hintText: '0.5 = CDI',
                      suffixText: '%',
                    ),
                    onChanged: (_) => onSimFieldChanged(),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (atingiu ? AppColors.success : Colors.orange).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: (atingiu ? AppColors.success : Colors.orange).withOpacity(0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          atingiu
                              ? '✓ Em $meses meses você atingiria a meta (FV ≈ ${CurrencyFormats.formatBRL(fv)})'
                              : 'Em $meses meses: ${CurrencyFormats.formatBRL(fv)} (faltariam ${CurrencyFormats.formatBRL(target - fv)})',
                          style: TextStyle(fontWeight: FontWeight.w600, color: atingiu ? AppColors.success : Colors.orange.shade800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Fórmula: FV = PV(1+i)^n + aportes',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              Align(
                alignment: Alignment.centerRight,
                child: _metaDialogGradientButton(
                  label: 'Fechar',
                  onPressed: () => Navigator.pop(ctx, false),
                ),
              ),
            ],
          );
        },
      ),
    ).whenComplete(() => simDeb?.cancel());
    valorCtrl.dispose();
    taxaCtrl.dispose();
  }

  Widget _buildGoalCard(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> goalDoc) {
    final isCompact = MediaQuery.sizeOf(context).width < 400;
    final data = goalDoc.data();
    final title = (data['title'] ?? 'Meta').toString();
    final target = (data['targetAmount'] ?? 0).toDouble();
    final dueTs = data['dueDate'] as Timestamp?;
    final category = GoalCategory.fromId(data['category'] as String?);
    GoalPriority priority = GoalPriority.media;
    try {
      priority = GoalPriority.values.firstWhere((e) => e.name == (data['priority'] ?? ''));
    } catch (_) {}
    final interestRate = (data['interestRateMonthly'] ?? 0).toDouble();
    final is52Weeks = FiftyTwoWeeksPlan.is52WeeksGoal(data);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: goalDoc.reference.collection('contributions').orderBy('date', descending: false).snapshots(),
      builder: (context, contribSnap) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _tx.where('goalId', isEqualTo: goalDoc.id).snapshots(),
          builder: (context, txSnap) {
            double contribSum = 0;
            final contribDocs = contribSnap.data?.docs ?? [];
            final contribByMonth = <String, double>{};
            for (final d in contribDocs) {
              final amount = (d.data()['amount'] ?? 0).toDouble();
              contribSum += amount;
              final date = (d.data()['date'] as Timestamp?)?.toDate();
              if (date != null) {
                final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
                contribByMonth[key] = (contribByMonth[key] ?? 0) + amount;
              }
            }
            double txSum = 0;
            for (final d in txSnap.data?.docs ?? []) {
              txSum += (d.data()['amount'] ?? 0).toDouble();
            }
            final current = contribSum + txSum;
            final progress = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
            final faltam = (target - current).clamp(0.0, double.infinity);
            final due = dueTs?.toDate();

            final proj = computeGoalProjection(
              target: target,
              current: current,
              dueDate: due,
              contribByMonth: contribByMonth,
              monthlyInterestRate: interestRate,
            );
            final dicaMeta = proj.statusMessage;
            final progressColor = _progressColor(proj, progress, due);

            final sortedMonths = contribByMonth.keys.toList()..sort();
            double cumul = 0;
            final lineSpots = <FlSpot>[];
            for (int i = 0; i < sortedMonths.length; i++) {
              cumul += contribByMonth[sortedMonths[i]] ?? 0;
              lineSpots.add(FlSpot(i.toDouble(), cumul));
            }
            if (lineSpots.isEmpty) lineSpots.add(const FlSpot(0, 0));

            final progressSize = isCompact ? 52.0 : 64.0;
            return Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: EdgeInsets.all(isCompact ? 14 : 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.9)),
                boxShadow: [
                  BoxShadow(color: AppColors.primary.withOpacity(0.07), blurRadius: 22, offset: const Offset(0, 8)),
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 14, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: progressSize,
                        height: progressSize,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: progressSize,
                              height: progressSize,
                              child: CircularProgressIndicator(
                                value: progress,
                                strokeWidth: isCompact ? 6.5 : 7.5,
                                strokeCap: StrokeCap.round,
                                backgroundColor: Colors.grey.shade100,
                                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                              ),
                            ),
                            Text(
                              '${(progress * 100).round()}%',
                              style: TextStyle(fontSize: isCompact ? 12 : 14, fontWeight: FontWeight.w900, color: progressColor),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: isCompact ? 10 : 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    style: TextStyle(fontSize: isCompact ? 16 : 18, fontWeight: FontWeight.w800, color: const Color(0xFF1A237E)),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 3,
                                    softWrap: true,
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  icon: Icon(Icons.more_vert_rounded, color: Colors.grey.shade600, size: isCompact ? 20 : 24),
                                  padding: EdgeInsets.zero,
                                  onSelected: (v) async {
                                    if (v == 'edit') await _editarMeta(context, goalDoc);
                                    if (v == 'delete') await _excluirMeta(context, goalDoc);
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(value: 'edit', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.edit_rounded, size: 20), title: Text('Editar meta'))),
                                    const PopupMenuItem(value: 'delete', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red), title: Text('Excluir meta', style: TextStyle(color: Colors.red)))),
                                  ],
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(category.label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis),
                                ),
                                if (priority == GoalPriority.alta) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: AppColors.error.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                                    child: Text(priority.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.error)),
                                  ),
                                ],
                              ],
                            ),
                            if (dueTs != null)
                              Row(
                                children: [
                                  Icon(Icons.calendar_today_rounded, size: 12, color: Colors.grey.shade600),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      'Prazo: ${DateFormat('dd/MM/yyyy').format(dueTs.toDate())}',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            if (interestRate > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'Rendimento: ${interestRate.toStringAsFixed(1)}%/mês',
                                  style: TextStyle(fontSize: 11, color: AppColors.accent, fontWeight: FontWeight.w600),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: isCompact ? 12 : 16),
                  _buildGoalProgressTrack(progress, progressColor),
                  const SizedBox(height: 12),
                  if (isCompact)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${CurrencyFormats.formatBRLTight(current)} de ${CurrencyFormats.formatBRLTight(target)}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            maxLines: 1,
                          ),
                        ),
                        if (faltam > 0) ...[
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Faltam ${CurrencyFormats.formatBRLTight(faltam)}',
                              style: TextStyle(fontSize: 13, color: Colors.orange.shade700, fontWeight: FontWeight.w600),
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ],
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${CurrencyFormats.formatBRLTight(current)} de ${CurrencyFormats.formatBRLTight(target)}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            maxLines: 1,
                          ),
                        ),
                        if (faltam > 0) ...[
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Faltam ${CurrencyFormats.formatBRLTight(faltam)}',
                              style: TextStyle(fontSize: 13, color: Colors.orange.shade700, fontWeight: FontWeight.w600),
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ],
                    ),
                  if (dicaMeta.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: progressColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: progressColor.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (proj.daysRemaining > 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '${proj.daysRemaining} dias restantes',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: progressColor),
                              ),
                            ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.insights_rounded, size: 18, color: progressColor),
                              const SizedBox(width: 8),
                              Expanded(child: Text(dicaMeta, style: TextStyle(fontSize: 12, color: Colors.grey.shade800))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (lineSpots.length > 1) ...[
                    const SizedBox(height: 20),
                    const Text('Evolução do alcance', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 120,
                      child: LineChart(
                        LineChartData(
                          gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.shade200, strokeWidth: 1)),
                          titlesData: FlTitlesData(
                            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, meta) => Text('R\$${v.toInt()}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)))),
                            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 24, getTitlesWidget: (v, meta) {
                              if (v.toInt() >= 0 && v.toInt() < sortedMonths.length) {
                                final m = sortedMonths[v.toInt()].split('-');
                                return Text('${m[1]}/${m[0].substring(2)}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600));
                              }
                              return const SizedBox.shrink();
                            })),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          borderData: FlBorderData(show: false),
                          minX: 0,
                          maxX: (lineSpots.length - 1).toDouble().clamp(0.0, double.infinity),
                          minY: 0,
                          maxY: lineSpots.isEmpty ? 1.0 : (lineSpots.map((e) => e.y).reduce((a, b) => a > b ? a : b) * 1.1).clamp(1.0, double.infinity),
                          lineBarsData: [
                            LineChartBarData(
                              spots: lineSpots,
                              isCurved: true,
                              color: AppColors.primary,
                              barWidth: 3,
                              isStrokeCapRound: true,
                              dotData: const FlDotData(show: true),
                              belowBarData: BarAreaData(show: true, color: AppColors.primary.withOpacity(0.15)),
                            ),
                          ],
                        ),
                        duration: const Duration(milliseconds: 250),
                      ),
                    ),
                  ],
                  SizedBox(height: isCompact ? 12 : 16),
                  if (isCompact)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _registrarAporte(context, goalDoc.reference),
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: const Text('Registrar aporte'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 1,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            minimumSize: const Size(0, 50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                        if (is52Weeks) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () => showFiftyTwoWeeksScheduleSheet(
                              context: context,
                              goalDoc: goalDoc,
                              profile: widget.profile,
                            ),
                            icon: const Icon(Icons.calendar_view_week_rounded, size: 20),
                            label: const Text('Projeto 52 semanas'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF6366F1),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              minimumSize: const Size(0, 50),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: () => _verEditarLancamentos(context, goalDoc, title),
                          icon: const Icon(Icons.list_alt_rounded, size: 20),
                          label: const Text('Ver / Editar lançamentos'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                            elevation: 1,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            minimumSize: const Size(0, 50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: () => _simularCenario(context, goalDoc.id, title, target, current, due),
                          icon: const Icon(Icons.bar_chart_rounded, size: 20),
                          label: const Text('Simular'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.logoOrange,
                            foregroundColor: Colors.white,
                            elevation: 1,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            minimumSize: const Size(0, 50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _registrarAporte(context, goalDoc.reference),
                            icon: const Icon(Icons.add_rounded, size: 20),
                            label: const Text('Aporte'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 1,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              minimumSize: const Size(0, 50),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _verEditarLancamentos(context, goalDoc, title),
                            icon: const Icon(Icons.list_alt_rounded, size: 18),
                            label: const Text('Lançamentos'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.white,
                              elevation: 1,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              minimumSize: const Size(0, 50),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: () => _simularCenario(context, goalDoc.id, title, target, current, due),
                          icon: const Icon(Icons.bar_chart_rounded, size: 20),
                          label: const Text('Simular'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.logoOrange,
                            foregroundColor: Colors.white,
                            elevation: 1,
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                            minimumSize: const Size(0, 50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
