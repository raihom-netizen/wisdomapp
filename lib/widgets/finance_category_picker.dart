import 'dart:async';

import 'package:flutter/material.dart';
import 'fast_text_field.dart';

import '../constants/app_business_rules.dart';
import '../constants/finance_category_visuals.dart';
import '../services/user_categories_service.dart';
import '../theme/app_colors.dart';
import '../utils/finance_category_grouping.dart';

/// Abre o picker de categorias para filtros (receitas, despesas ou ambos).
Future<String?> pickFinanceCategoryForFilter({
  required BuildContext context,
  required String uid,
  required String typeFilter,
  String? currentFilter,
  List<String> periodExtraCategories = const [],
}) async {
  var isIncome = typeFilter == 'income';
  final extra = <String>[...periodExtraCategories];

  if (typeFilter == 'all') {
    final r = await UserCategoriesService().load(uid);
    final expenseLower = UserCategoriesService.sortedWithoutIncluirNova(r.expense)
        .map((c) => c.toLowerCase().trim())
        .toSet();
    for (final c in UserCategoriesService.sortedWithoutIncluirNova(r.income)) {
      if (!expenseLower.contains(c.toLowerCase().trim())) extra.add(c);
    }
    isIncome = false;
  }

  if (currentFilter != null && currentFilter.trim().isNotEmpty) {
    final has = extra.any((o) => FinanceCategoryMerger.sameCategoryGroup(o, currentFilter));
    if (!has) extra.add(currentFilter);
  }

  final picked = await showFinanceCategoryPicker(
    context: context,
    isIncome: isIncome,
    uid: uid,
    initialQuery: currentFilter ?? '',
    extraCategories: extra,
  );
  if (picked == null || !context.mounted) return null;
  if (picked != '__outra__') return picked;

  final ctrl = TextEditingController();
  String? typed;
  try {
    typed = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Filtrar por categoria'),
        content: FastTextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Nome da categoria',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(dialogCtx, name);
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
  } finally {
    ctrl.dispose();
  }
  final name = typed?.trim();
  return (name == null || name.isEmpty) ? null : name;
}

/// Resultado: nome da categoria, ou `__outra__` para digitar manualmente.
Future<String?> showFinanceCategoryPicker({
  required BuildContext context,
  required String uid,
  required bool isIncome,
  String? initialQuery,
  /// Categorias extras (ex.: ocultas no perfil mas com lançamentos no período).
  List<String> extraCategories = const [],
}) {
  return Navigator.of(context, rootNavigator: true).push<String>(
    MaterialPageRoute<String>(
      fullscreenDialog: true,
      builder: (_) => _FinanceCategoryPickerScreen(
        uid: uid,
        isIncome: isIncome,
        initialQuery: initialQuery ?? '',
        extraCategories: extraCategories,
      ),
    ),
  );
}

class _FinanceCategoryPickerScreen extends StatefulWidget {
  final String uid;
  final bool isIncome;
  final String initialQuery;
  final List<String> extraCategories;

  const _FinanceCategoryPickerScreen({
    required this.uid,
    required this.isIncome,
    required this.initialQuery,
    this.extraCategories = const [],
  });

  @override
  State<_FinanceCategoryPickerScreen> createState() => _FinanceCategoryPickerScreenState();
}

class _FinanceCategoryPickerScreenState extends State<_FinanceCategoryPickerScreen> {
  final _searchCtrl = TextEditingController();
  List<String> _categories = const [];
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = widget.initialQuery;
    _searchCtrl.addListener(_onSearchChanged);
    UserCategoriesService().load(widget.uid).then((r) {
      if (!mounted) return;
      setState(() {
        _categories = UserCategoriesService.sortedWithoutIncluirNova([
          ...UserCategoriesService.sortedWithoutIncluirNova(
            widget.isIncome ? r.income : r.expense,
          ),
          ...widget.extraCategories,
        ]);
      });
    });
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: AppBusinessRules.searchDebounceMs),
      () {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  List<String> _filtered() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _categories;
    return _categories.where((c) => c.toLowerCase().contains(q)).toList();
  }

  Future<void> _incluirNova() async {
    final ctrl = TextEditingController();
    String name = '';
    bool added = false;
    try {
      added = await showDialog<bool>(
            context: context,
            builder: (dialogCtx) => AlertDialog(
              title: Text(widget.isIncome ? 'Nova categoria de receita' : 'Nova categoria de despesa'),
              content: FastTextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Nome da categoria',
                  border: OutlineInputBorder(),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancelar')),
                FilledButton(
                  onPressed: () {
                    if (ctrl.text.trim().isEmpty) return;
                    Navigator.pop(dialogCtx, true);
                  },
                  child: const Text('Adicionar'),
                ),
              ],
            ),
          ) ??
          false;
      if (added) name = ctrl.text.trim();
    } finally {
      ctrl.dispose();
    }
    if (!added || name.isEmpty || !mounted) return;
    try {
      await UserCategoriesService().addCustom(widget.uid, widget.isIncome, name);
      if (!mounted) return;
      Navigator.of(context).pop(name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: ${e.toString().split('\n').first}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered();
    final title = widget.isIncome ? 'Categoria de receita' : 'Categoria de despesa';

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: AppColors.logoGradient,
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Fechar',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              children: [
                FastTextField(
                  controller: _searchCtrl,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Pesquisar categoria',
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {});
                            },
                          ),
                    filled: true,
                    fillColor: const Color(0xFFF6F8FB),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _incluirNova,
                    icon: const Icon(Icons.add_circle_rounded),
                    label: const Text('Incluir nova categoria', style: TextStyle(fontWeight: FontWeight.w900)),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                Material(
                  color: Colors.white,
                  child: ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.edit_note_rounded, color: Colors.blueGrey.shade700, size: 22),
                    ),
                    title: const Text(
                      'Outra (digitar nome)',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppColors.textPrimary),
                    ),
                    subtitle: const Text(
                      'Use quando a categoria não estiver na lista',
                      style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                    onTap: () => Navigator.of(context).pop('__outra__'),
                  ),
                ),
                const Divider(height: 1),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        _searchCtrl.text.trim().isEmpty
                            ? 'Carregando categorias…'
                            : 'Nenhuma categoria corresponde à pesquisa.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
                      ),
                    ),
                  )
                else
                  ...List.generate(items.length * 2 - 1, (i) {
                    if (i.isOdd) return const Divider(height: 1, indent: 64);
                    final c = items[i ~/ 2];
                    final vis = financeCategoryVisualFor(c, isIncome: widget.isIncome);
                    return ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: vis.color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(vis.icon, color: vis.color, size: 22),
                      ),
                      title: Text(
                        c,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                      onTap: () => Navigator.of(context).pop(c),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
