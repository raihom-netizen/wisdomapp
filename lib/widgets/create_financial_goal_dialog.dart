import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide showDatePicker;
import 'package:intl/intl.dart';

import '../constants/app_business_rules.dart';
import '../constants/currency_formats.dart';
import '../models/financial_goal.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../theme/theme_context.dart';
import '../utils/date_picker_a11y.dart';
import '../utils/fifty_two_weeks_plan.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/goal_objective_visuals.dart';
import '../utils/premium_upgrade.dart';
import '../widgets/brl_amount_text_field.dart';
import '../widgets/goal_form_validation_alert.dart';
import '../widgets/goal_finance_account_field.dart';
import '../widgets/fast_text_field.dart';

/// Abre o formulário «Criar objetivo» (mesmo do módulo Objetivo Financeiro).
Future<void> showCreateFinancialGoalDialog(
  BuildContext context, {
  required UserProfile profile,
  required String uid,
}) async {
  if (!profile.hasActiveLicense) {
    mostrarAvisoSeLicencaInativa(context, profile);
    return;
  }
  final userDocId = firestoreUserDocIdForAppShell(uid);
  if (userDocId.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A sincronizar sessão… tente novamente em instantes.'),
        ),
      );
    }
    return;
  }

  final goals = FirebaseFirestore.instance
      .collection('users')
      .doc(userDocId)
      .collection('goals');

  final titleCtrl = TextEditingController();
  final targetCtrl = TextEditingController();
  DateTime? dueDate;
  var reminderAporte = false;
  var category = GoalCategory.personalizada;
  var priority = GoalPriority.media;
  final interestCtrl = TextEditingController(text: '0.5');
  var hasInterest = false;
  var use52WeeksPlan = true;
  var selectedEmoji = '🎯';
  String? financeAccountId;
  Timer? metaSuggestDebounce;

  String? atalhoSel;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final target = CurrencyFormats.parseBRLInput(targetCtrl.text) ?? 0;
        var monthsLeft = 0;
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
            suggestedMonthly = denom > 0
                ? (target * i / denom).toStringAsFixed(2)
                : (target / monthsLeft).toStringAsFixed(2);
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
        // Cor/ícone do tipo escolhido pintam o cabeçalho e o valor.
        var accent = const Color(0xFF6366F1);
        var accentIcon = Icons.savings_rounded;
        for (final at in atalhosMeta) {
          if (at.$3 == atalhoSel) {
            accent = at.$2;
            accentIcon = at.$1;
          }
        }
        final accentDeep = Color.lerp(accent, const Color(0xFF0F172A), 0.35)!;
        final dark = ctx.isDarkMode;
        final screenW = MediaQuery.sizeOf(ctx).width;
        final fullScreen = screenW < 640;

        Widget sectionCard({
          required Widget child,
          Color? tint,
          EdgeInsets padding = const EdgeInsets.all(14),
        }) {
          final t = tint ?? accent;
          return Container(
            padding: padding,
            decoration: BoxDecoration(
              color: ctx.appAccentSurface(t, darkAlpha: 0.12, lightAlpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: t.withValues(alpha: dark ? 0.40 : 0.22)),
            ),
            child: child,
          );
        }

        Widget sectionTitle(IconData icon, String text, Color c) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 16, color: c),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: ctx.appTextPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            );

        final header = AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.fromLTRB(
            20,
            fullScreen ? MediaQuery.paddingOf(ctx).top + 14 : 18,
            10,
            20,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [accent, accentDeep],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: fullScreen
                ? null
                : const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Container(
                  key: ValueKey(accentIcon),
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                  child: Icon(accentIcon, color: Colors.white, size: 30),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Novo objetivo financeiro',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      target > 0
                          ? 'Meta de ${CurrencyFormats.formatBRL(target)}'
                          : 'Defina a meta e onde o dinheiro será guardado.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Fechar',
                onPressed: () => Navigator.pop(ctx, false),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ],
          ),
        );

        final tipoGrid = LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 520 ? 4 : (c.maxWidth >= 330 ? 3 : 2);
            const gap = 10.0;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final at in atalhosMeta)
                  SizedBox(
                    width: w,
                    child: _goalTypeTile(
                      ctx,
                      icon: at.$1,
                      color: at.$2,
                      label: at.$3,
                      selected: atalhoSel == at.$3,
                      onTap: () {
                        titleCtrl.text = at.$3;
                        category = GoalCategory.fromId(at.$4);
                        final preset = presetForCategory(at.$4);
                        selectedEmoji = preset?.visual.emoji ?? '🎯';
                        atalhoSel = at.$3;
                        setState(() {});
                      },
                    ),
                  ),
              ],
            );
          },
        );

        final valorCard = Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: dark ? 0.26 : 0.12),
                accentDeep.withValues(alpha: dark ? 0.18 : 0.06),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accent.withValues(alpha: dark ? 0.5 : 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'VALOR ALVO',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w900,
                  color: dark ? ctx.appTextSecondary : accentDeep,
                ),
              ),
              BrlAmountTextField(
                controller: targetCtrl,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: dark ? Colors.white : accentDeep,
                  letterSpacing: -0.5,
                ),
                decoration: InputDecoration(
                  hintText: '0,00',
                  prefixText: 'R\$ ',
                  prefixStyle: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: dark ? ctx.appTextSecondary : accent,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.only(top: 6, bottom: 2),
                ),
                onChanged: (_) {
                  metaSuggestDebounce?.cancel();
                  metaSuggestDebounce = Timer(
                    Duration(milliseconds: AppBusinessRules.searchDebounceMs),
                    () {
                      if (ctx.mounted) setState(() {});
                    },
                  );
                },
              ),
            ],
          ),
        );

        Widget weekPill(String label, double value, Color c) => Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.withValues(alpha: 0.30)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: ctx.appTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        CurrencyFormats.formatBRL(value),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: dark ? Colors.white : c,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );

        const c52 = Color(0xFF6366F1);
        final card52 = Container(
          padding: const EdgeInsets.fromLTRB(14, 6, 10, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                c52.withValues(alpha: dark ? 0.24 : 0.12),
                const Color(0xFFEC4899).withValues(alpha: dark ? 0.18 : 0.08),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c52.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: use52WeeksPlan,
                onChanged: (v) => setState(() => use52WeeksPlan = v),
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [c52, Color(0xFFEC4899)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.calendar_view_week_rounded,
                      color: Colors.white, size: 20),
                ),
                title: Text(
                  'Projeto 52 semanas',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: ctx.appTextPrimary,
                  ),
                ),
                subtitle: Text(
                  'Programação semanal automática (incremento progressivo até a meta).',
                  style: TextStyle(fontSize: 12, color: ctx.appTextSecondary),
                ),
                activeThumbColor: c52,
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: use52WeeksPlan
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              weekPill(
                                'Semana 1',
                                target > 0
                                    ? FiftyTwoWeeksPlan.amountForWeek(target, 1)
                                    : 0,
                                c52,
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.trending_up_rounded,
                                  color: c52.withValues(alpha: 0.8), size: 20),
                              const SizedBox(width: 8),
                              weekPill(
                                'Semana 52',
                                target > 0
                                    ? FiftyTwoWeeksPlan.amountForWeek(target, 52)
                                    : 0,
                                const Color(0xFFDB2777),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            target > 0
                                ? 'Total programado: ${CurrencyFormats.formatBRL(target)} em 52 semanas'
                                : 'Informe o valor alvo para ver a prévia semanal.',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: ctx.appTextSecondary,
                            ),
                          ),
                        ],
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        );

        final body = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            sectionTitle(Icons.auto_awesome_rounded, 'O que você quer conquistar?', accent),
            tipoGrid,
            const SizedBox(height: 16),
            FastTextField(
              controller: titleCtrl,
              decoration: _inputDecoration(
                ctx,
                labelText: 'Nome da meta',
                hintText: 'Ex: Comprar um carro, Reserva de emergência, Viagem',
                prefixIcon: Icon(Icons.flag_rounded, color: accent, size: 20),
                focusColor: accent,
              ),
            ),
            const SizedBox(height: 12),
            valorCard,
            if (suggestedMonthly != null && !use52WeeksPlan) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline_rounded,
                        size: 20, color: AppColors.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sugestão: guarde ${CurrencyFormats.formatBRL(double.tryParse(suggestedMonthly) ?? 0)}/mês para atingir no prazo${hasInterest && rate > 0 ? " (com juros)" : ""}.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: dark ? ctx.appTextPrimary : Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            card52,
            if (!use52WeeksPlan) ...[
              const SizedBox(height: 12),
              sectionCard(
                tint: AppColors.accent,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.event_rounded, color: AppColors.accent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        dueDate == null
                            ? 'Sem prazo'
                            : 'Prazo: ${DateFormat('dd/MM/yyyy').format(dueDate!)}',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: ctx.appTextPrimary,
                        ),
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
                        backgroundColor: AppColors.accent.withValues(alpha: 0.16),
                        foregroundColor: AppColors.accent,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            GoalFinanceAccountField(
              uid: uid,
              selectedAccountId: financeAccountId,
              onChanged: (v) => setState(() => financeAccountId = v),
            ),
            const SizedBox(height: 14),
            sectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  sectionTitle(Icons.tune_rounded, 'Prioridade e opções', accent),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: GoalPriority.values.map((p) {
                      final sel = priority == p;
                      return _priorityChip(
                        ctx,
                        label: p.label,
                        selected: sel,
                        onTap: () => setState(() => priority = p),
                        active: _priorityColor(p),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: hasInterest,
                    onChanged: (v) => setState(() => hasInterest = v ?? false),
                    title: const Text(
                      'Meta com rendimento (juros compostos)',
                      style: TextStyle(fontSize: 14),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (hasInterest) ...[
                    const SizedBox(height: 4),
                    FastTextField(
                      controller: interestCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: _inputDecoration(
                        ctx,
                        labelText: 'Taxa mensal estimada (%)',
                        hintText: 'Ex: 0.5 (CDI)',
                        suffixText: '%',
                        prefixIcon: const Icon(Icons.trending_up_rounded, size: 20),
                        focusColor: accent,
                      ),
                      onChanged: (_) {
                        metaSuggestDebounce?.cancel();
                        metaSuggestDebounce = Timer(
                          Duration(milliseconds: AppBusinessRules.searchDebounceMs),
                          () {
                            if (ctx.mounted) setState(() {});
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                  ],
                  CheckboxListTile(
                    value: reminderAporte,
                    onChanged: (v) => setState(() => reminderAporte = v ?? false),
                    title: const Text('Lembrar de aportar todo mês',
                        style: TextStyle(fontSize: 14)),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ],
        );

        final footer = Container(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            12 + (fullScreen ? MediaQuery.paddingOf(ctx).bottom : 0),
          ),
          decoration: BoxDecoration(
            color: dark ? ctx.appDarkModuleSurface : Colors.white,
            border: Border(top: BorderSide(color: ctx.appBorderSubtle)),
            borderRadius: fullScreen
                ? null
                : const BorderRadius.vertical(bottom: Radius.circular(26)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Cancelar',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _gradientButton(
                  colors: [accent, accentDeep],
                  icon: Icons.rocket_launch_rounded,
                  label: 'Criar meta',
                  onTap: () async {
                    final ok = await validateGoalFormOrShowAlert(
                      ctx,
                      title: titleCtrl.text,
                      targetText: targetCtrl.text,
                      financeAccountId: financeAccountId,
                    );
                    if (ok && ctx.mounted) Navigator.pop(ctx, true);
                  },
                ),
              ),
            ],
          ),
        );

        final layout = Column(
          mainAxisSize: fullScreen ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Flexible(
              fit: fullScreen ? FlexFit.tight : FlexFit.loose,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 360),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, child) => Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, 14 * (1 - t)),
                      child: child,
                    ),
                  ),
                  child: body,
                ),
              ),
            ),
            footer,
          ],
        );

        if (fullScreen) {
          return Dialog.fullscreen(
            backgroundColor: ctx.appScaffold,
            child: layout,
          );
        }
        return Dialog(
          backgroundColor: ctx.appScaffold,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 680,
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.92,
            ),
            child: layout,
          ),
        );
      },
    ),
  ).whenComplete(() => metaSuggestDebounce?.cancel());

  try {
    if (ok != true) return;
    final title = titleCtrl.text.trim();
    final target = CurrencyFormats.parseBRLInput(targetCtrl.text) ?? 0;
    if (title.isEmpty || target <= 0 || (financeAccountId ?? '').trim().isEmpty) {
      return;
    }

    final planStart = FiftyTwoWeeksPlan.normalizePlanStart(DateTime.now());
    await goals.add({
      'title': title,
      'targetAmount': target,
      'financeAccountId': financeAccountId,
      'dueDate': use52WeeksPlan
          ? Timestamp.fromDate(planStart.add(const Duration(days: 52 * 7)))
          : (dueDate != null ? Timestamp.fromDate(dueDate!) : null),
      'reminderAporte': reminderAporte,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'active',
      'category': category.id,
      'priority': priority.name,
      'interestRateMonthly':
          hasInterest ? (double.tryParse(interestCtrl.text.replaceAll(',', '.')) ?? 0) : 0,
      'planType': use52WeeksPlan ? '52weeks' : 'classic',
      if (use52WeeksPlan) ...{
        'planStartDate': Timestamp.fromDate(planStart),
        'weeklyIncrement': FiftyTwoWeeksPlan.weeklyIncrementForTarget(target),
        'weeksPaid': <int>[],
      },
      'emoji': selectedEmoji,
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            use52WeeksPlan
                ? 'Objetivo "$title" criado com Projeto 52 semanas!'
                : 'Objetivo "$title" criado! Acompanhe o progresso abaixo.',
          ),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao criar meta: ${e.toString().split('\n').first}')),
      );
    }
  } finally {
    titleCtrl.dispose();
    targetCtrl.dispose();
    interestCtrl.dispose();
  }
}

InputDecoration _inputDecoration(
  BuildContext context, {
  required String labelText,
  String? hintText,
  Widget? prefixIcon,
  String? prefixText,
  String? suffixText,
  Color? focusColor,
}) {
  final r = BorderRadius.circular(14);
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    prefixIcon: prefixIcon,
    prefixText: prefixText,
    suffixText: suffixText,
    filled: true,
    fillColor:
        context.isDarkMode ? context.appInputFill : const Color(0xFFF8FAFC),
    border: OutlineInputBorder(borderRadius: r),
    enabledBorder: OutlineInputBorder(
      borderRadius: r,
      borderSide: BorderSide(
          color: context.isDarkMode
              ? context.appChipIdleBorder
              : Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: r,
      borderSide: BorderSide(color: focusColor ?? AppColors.accent, width: 2),
    ),
  );
}

/// Tipo de meta em cartão colorido com ícone grande.
Widget _goalTypeTile(
  BuildContext context, {
  required IconData icon,
  required Color color,
  required String label,
  required bool selected,
  required VoidCallback onTap,
}) {
  final dark = context.isDarkMode;
  final deep = Color.lerp(color, const Color(0xFF0F172A), 0.3)!;
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: 104,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  colors: [color, deep],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: selected
              ? null
              : context.appAccentSurface(color, darkAlpha: 0.16, lightAlpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? Colors.transparent
                : color.withValues(alpha: dark ? 0.45 : 0.30),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.38),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: selected ? 1.12 : 1,
              duration: const Duration(milliseconds: 220),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.22)
                      : color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon,
                    size: 26, color: selected ? Colors.white : color),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: selected
                    ? Colors.white
                    : (dark ? context.appTextPrimary : deep),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Botão principal com gradiente (Criar meta).
Widget _gradientButton({
  required List<Color> colors,
  required IconData icon,
  required String label,
  required VoidCallback onTap,
}) {
  return DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: colors),
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: colors.first.withValues(alpha: 0.35),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Color _priorityColor(GoalPriority p) {
  return switch (p) {
    GoalPriority.alta => AppColors.error,
    GoalPriority.media => AppColors.primary,
    GoalPriority.baixa => const Color(0xFF64748B),
  };
}

Widget _priorityChip(
  BuildContext context, {
  required String label,
  required bool selected,
  required VoidCallback onTap,
  required Color active,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? active
              : (context.isDarkMode ? context.appChipIdleBg : Colors.white),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected
                ? active
                : (context.isDarkMode
                    ? context.appChipIdleBorder
                    : Colors.grey.shade300),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: selected
                ? Colors.white
                : (context.isDarkMode
                    ? context.appChipIdleLabel
                    : Colors.grey.shade700),
          ),
        ),
      ),
    ),
  );
}
