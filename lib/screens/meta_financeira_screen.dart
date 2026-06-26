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
import '../widgets/create_financial_goal_dialog.dart';
import '../widgets/app_pie_chart.dart';
import '../widgets/registrar_deposito_dialog.dart';
import '../widgets/goal_contributions_sheet.dart';
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

/// SugestÃµes rÃ¡pidas de metas para o usuÃ¡rio escolher ou inspirar.
const List<Map<String, String>> kMetaSugestoes = [
  {'title': 'Comprar um carro', 'emoji': 'ðŸš—', 'cat': 'veiculo'},
  {'title': 'Pagar contas / quitar dÃ­vidas', 'emoji': 'ðŸ“‹', 'cat': 'personalizada'},
  {'title': 'Reserva de emergÃªncia', 'emoji': 'ðŸ›¡ï¸', 'cat': 'reserva_emergencia'},
  {'title': 'Viagem', 'emoji': 'âœˆï¸', 'cat': 'viagem'},
  {'title': 'Reforma da casa', 'emoji': 'ðŸ ', 'cat': 'casa'},
  {'title': 'Curso ou especializaÃ§Ã£o', 'emoji': 'ðŸ“š', 'cat': 'estudo'},
  {'title': 'Investimento', 'emoji': 'ðŸ“ˆ', 'cat': 'investimento'},
  {'title': 'Outro', 'emoji': 'ðŸŽ¯', 'cat': 'personalizada'},
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
    await showCreateFinancialGoalDialog(
      context,
      profile: widget.profile,
      uid: widget.uid,
    );
  }

  Future<void> _registrarDeposito(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> goalDoc,
  ) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final data = goalDoc.data();
    final is52 = FiftyTwoWeeksPlan.is52WeeksGoal(data);
    if (is52) {
      await showFiftyTwoWeeksScheduleSheet(
        context: context,
        goalDoc: goalDoc,
        profile: widget.profile,
        uid: widget.uid,
        depositMode: true,
      );
      return;
    }
    final title = (data['title'] ?? 'Objetivo').toString();
    final ok = await showRegistrarDepositoDialog(
      context: context,
      goalRef: goalDoc.reference,
      goalId: goalDoc.id,
      goalTitle: title,
      uid: widget.uid,
      profile: widget.profile,
    );
    if (ok && mounted && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Depósito registrado!')),
      );
    }
  }

  /// Barra superior padrÃ£o dos previews/sheets do mÃ³dulo Meta â€” pedido do
  /// usuÃ¡rio: cada preview tem **Â«VoltarÂ»** Ã  esquerda (paridade total
  /// iPhone / iOS / Android / Web) + atalho **Â«XÂ»** Ã  direita. Mesmo
  /// visual dos previews do Painel Inicial e dos demais mÃ³dulos.
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

  Future<void> _verEditarLancamentos(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> goalDoc,
    String goalTitle,
  ) async {
    await showGoalContributionsSheet(
      context: context,
      goalDoc: goalDoc,
      goalTitle: goalTitle,
      uid: widget.uid,
      profile: widget.profile,
    );
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
                  label: 'Salvar alteraÃ§Ãµes',
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
          'Excluir "${(goalDoc.data()['title'] ?? 'Meta').toString()}"? Os aportes jÃ¡ registrados nÃ£o serÃ£o removidos.',
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Meta excluÃ­da.')));
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
                              label: 'TÃ­tulo Aâ€“Z',
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

  /// CabeÃ§alho colorido do mÃ³dulo Objetivo Financeiro.
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
            'Projeto 52 semanas Â· viagem, carro, casa, reforma, quitar dÃ­vidas',
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

  /// CTA principal â€” gradiente + sombra (visual premium).
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

  /// Barra de progresso com gradiente e altura confortÃ¡vel para leitura.
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
              Text('A sincronizar sessÃ£oâ€¦', textAlign: TextAlign.center),
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
            'Crie um objetivo com Projeto 52 semanas â€” o app monta a programaÃ§Ã£o semanal automaticamente.',
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

  Widget _goalStatPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
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
                                  'Rendimento: ${interestRate.toStringAsFixed(1)}%/mÃªs',
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
                    const Text('EvoluÃ§Ã£o do alcance', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey)),
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
                  if (is52Weeks) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _goalStatPill(
                          icon: Icons.check_circle_outline_rounded,
                          label: '${FiftyTwoWeeksPlan.paidWeeksFromData(data).length} sem. guardadas',
                          color: AppColors.success,
                        ),
                        _goalStatPill(
                          icon: Icons.timelapse_rounded,
                          label: '${(52 - FiftyTwoWeeksPlan.paidWeeksFromData(data).length).clamp(0, 52)} sem. faltam',
                          color: Colors.orange,
                        ),
                        _goalStatPill(
                          icon: Icons.savings_rounded,
                          label: 'Total ${CurrencyFormats.formatBRLTight(current)}',
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ],
                  if (target > 0) ...[
                    const SizedBox(height: 14),
                    AppPieChart(
                      title: 'Evolução dos depósitos',
                      segments: [
                        (
                          label: 'Depositado',
                          value: current.clamp(0, double.infinity),
                          color: progressColor,
                        ),
                        (
                          label: 'Faltam',
                          value: faltam,
                          color: Colors.grey.shade300,
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: isCompact ? 12 : 16),
                  if (isCompact)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _registrarDeposito(context, goalDoc),
                          icon: const Icon(Icons.savings_rounded, size: 20),
                          label: const Text('Registrar depósito'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 1,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            minimumSize: const Size(0, 50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
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
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _registrarDeposito(context, goalDoc),
                            icon: const Icon(Icons.savings_rounded, size: 20),
                            label: const Text('Depósito'),
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
