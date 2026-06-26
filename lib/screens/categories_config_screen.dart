import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import 'package:flutter/services.dart';
import '../constants/default_categories.dart';
import '../constants/finance_category_visuals.dart';
import '../services/user_categories_service.dart';
import '../theme/app_colors.dart';

/// Edição de categorias (receitas e despesas) no módulo financeiro — padrão, renomear, excluir/ocultar.
class CategoriesConfigScreen extends StatefulWidget {
  final String uid;

  const CategoriesConfigScreen({super.key, required this.uid});

  @override
  State<CategoriesConfigScreen> createState() => _CategoriesConfigScreenState();
}

class _CategoriesConfigScreenState extends State<CategoriesConfigScreen> with SingleTickerProviderStateMixin {
  final _service = UserCategoriesService();
  late final TabController _tabController;
  List<String> _income = [];
  List<String> _expense = [];
  List<String> _hiddenIncome = [];
  List<String> _hiddenExpense = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = await _service.load(widget.uid);
    if (mounted) {
      setState(() {
        _income = UserCategoriesService.sortedWithoutIncluirNova(c.income);
        _expense = UserCategoriesService.sortedWithoutIncluirNova(c.expense);
        _hiddenIncome = List<String>.from(c.hiddenDefaultIncome)
          ..sort(UserCategoriesService.compareNamesPt);
        _hiddenExpense = List<String>.from(c.hiddenDefaultExpense)
          ..sort(UserCategoriesService.compareNamesPt);
        _loading = false;
      });
    }
  }

  bool _isDefault(bool isIncome, String name) {
    final list = isIncome ? kDefaultIncomeCategories : kDefaultExpenseCategories;
    return list.any((c) => c.toLowerCase() == name.toLowerCase());
  }

  Future<void> _addCategory(bool isIncome) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _ModernInputDialog(
        title: isIncome ? 'Nova categoria de receita' : 'Nova categoria de despesa',
        hint: 'Ex.: Investimentos, Alimentação',
        controller: ctrl,
        actionLabel: 'Criar',
        accent: isIncome ? AppColors.accent : AppColors.deepBlue,
        icon: isIncome ? Icons.savings_outlined : Icons.payments_outlined,
      ),
    );
    if (name == null || !mounted) return;
    if (name.trim().isEmpty) return;
    await _service.addCustom(widget.uid, isIncome, name.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Categoria adicionada'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.deepBlue,
        ),
      );
      await _load();
    }
  }

  Future<void> _editCategory(bool isIncome, String currentName) async {
    final ctrl = TextEditingController(text: currentName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _ModernInputDialog(
        title: 'Editar categoria',
        hint: 'Nome',
        controller: ctrl,
        actionLabel: 'Guardar',
        accent: AppColors.primary,
        icon: Icons.edit_outlined,
      ),
    );
    if (name == null || !mounted) return;
    final t = name.trim();
    if (t.isEmpty || t.toLowerCase() == currentName.toLowerCase()) return;
    if (_isDefault(isIncome, t) && t.toLowerCase() != currentName.toLowerCase()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Esse nome já é uma categoria padrão. Use outro nome (ou oculte a padrão antes).'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    if (_isDefault(isIncome, currentName)) {
      await _service.hideDefault(widget.uid, isIncome, currentName);
      await _service.addCustom(widget.uid, isIncome, t);
    } else {
      await _service.renameCustom(widget.uid, isIncome, currentName, t);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Categoria actualizada'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.deepBlue,
        ),
      );
      await _load();
    }
  }

  Future<void> _removeCategory(bool isIncome, String name) async {
    final def = _isDefault(isIncome, name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ModernConfirmDialog(
        title: def ? 'Ocultar categoria' : 'Excluir categoria',
        message: def
            ? '«$name» deixa de aparecer nas listas. Os lançamentos antigos mantêm a categoria. Pode repor mais abaixo.'
            : 'A categoria personalizada «$name» será removida. O histórico de lançamentos antigos mantém a designação.',
        confirmLabel: def ? 'Ocultar' : 'Excluir',
        destructive: !def,
        icon: def ? Icons.visibility_off_outlined : Icons.delete_outline_rounded,
      ),
    );
    if (ok != true || !mounted) return;
    if (def) {
      await _service.hideDefault(widget.uid, isIncome, name);
    } else {
      await _service.removeCustom(widget.uid, isIncome, name);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(def ? 'Categoria padrão oculta' : 'Categoria excluída'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    }
  }

  Future<void> _restoreDefault(bool isIncome, String name) async {
    await _service.unhideDefault(widget.uid, isIncome, name);
    if (mounted) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Categoria padrão restaurada'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(strokeWidth: 3, color: AppColors.primary),
              SizedBox(height: 16),
              Text('A carregar categorias…', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F9),
      appBar: AppBar(
        title: const Text('Categorias', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: -0.2)),
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          tooltip: 'Retornar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.maybePop(context),
          style: IconButton.styleFrom(
            foregroundColor: Colors.white,
            minimumSize: const Size(48, 48),
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFE3F2FD),
                    Colors.white,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF1A237E).withValues(alpha: 0.14)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1A237E).withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF1A237E).withValues(alpha: 0.12),
                          AppColors.accent.withValues(alpha: 0.15),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF1A237E), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Edite, oculte categorias padrão ou crie categorias personalizadas.',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A237E),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1A237E).withValues(alpha: 0.25),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: TabBar(
                controller: _tabController,
                onTap: (_) => HapticFeedback.selectionClick(),
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: const Color(0xFF1A237E),
                unselectedLabelColor: Colors.white.withValues(alpha: 0.92),
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                padding: const EdgeInsets.all(5),
                tabs: const [
                  Tab(
                    height: 52,
                    text: 'Receitas',
                    icon: Icon(Icons.trending_up_rounded, size: 20),
                  ),
                  Tab(
                    height: 52,
                    text: 'Despesas',
                    icon: Icon(Icons.trending_down_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const BouncingScrollPhysics(),
              children: [
                _buildTabList(true),
                _buildTabList(false),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.deepBlue, AppColors.primary, AppColors.accent],
          ),
          boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.mediumImpact();
              unawaited(_addCategory(_tabController.index == 0));
            },
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded, size: 22, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    _tabController.index == 0 ? 'Nova receita' : 'Nova despesa',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.25,
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabList(bool isIncome) {
    final list = isIncome ? _income : _expense;
    final hidden = isIncome ? _hiddenIncome : _hiddenExpense;
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF1A237E).withValues(alpha: 0.12)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  isIncome ? Icons.savings_rounded : Icons.receipt_long_rounded,
                  color: isIncome ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                  size: 26,
                ),
                const SizedBox(width: 12),
                Container(
                  width: 4,
                  height: 28,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: LinearGradient(
                      colors: isIncome
                          ? [const Color(0xFF43A047), const Color(0xFF2E7D32)]
                          : [const Color(0xFF1A237E), const Color(0xFF00897B)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    list.isEmpty
                        ? 'Nenhuma categoria listada ainda'
                        : '${list.length} ${list.length == 1 ? 'categoria' : 'categorias'}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final name in list) ...[
            _CategoryTile(
              name: name,
              isIncome: isIncome,
              isDefault: _isDefault(isIncome, name),
              onEdit: () => _editCategory(isIncome, name),
              onRemove: () => _removeCategory(isIncome, name),
            ),
            const SizedBox(height: 8),
          ],
          if (hidden.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
              ),
              child: const Text(
                'Categorias padrão ocultas — pode repor abaixo',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.deepBlue,
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final name in hidden) ...[
              Material(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: () => unawaited(_restoreDefault(isIncome, name)),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.visibility_off_rounded, color: Colors.grey.shade500, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: AppColors.textSecondary,
                              decoration: TextDecoration.lineThrough,
                              decorationColor: AppColors.primary.withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                        FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary.withValues(alpha: 0.14),
                            foregroundColor: AppColors.deepBlue,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => unawaited(_restoreDefault(isIncome, name)),
                          child: const Text('Repor', style: TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }
}

// —— UI auxiliar

class _CategoryTile extends StatelessWidget {
  final String name;
  final bool isIncome;
  final bool isDefault;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _CategoryTile({
    required this.name,
    required this.isIncome,
    required this.isDefault,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final vis = financeCategoryVisualFor(name, isIncome: isIncome);
    const narrowMaxWidth = 400.0;

    final leading = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [
            vis.color,
            Color.lerp(vis.color, Colors.black, 0.12)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: vis.color.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(vis.icon, color: Colors.white, size: 24),
    );

    final titleColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 16,
            height: 1.2,
            letterSpacing: -0.2,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isDefault ? const Color(0xFFE8EAF6) : const Color(0xFFE0F2F1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isDefault ? 'Padrão' : 'Personalizada',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isDefault ? const Color(0xFF3949AB) : const Color(0xFF00695C),
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ],
    );

    final editBtn = _RoundIcon(
      tooltip: 'Editar nome',
      onTap: onEdit,
      icon: Icons.edit_rounded,
      background: const Color(0xFFE3F2FD),
      foreground: const Color(0xFF1565C0),
    );
    final removeBtn = _RoundIcon(
      tooltip: isDefault ? 'Ocultar' : 'Excluir',
      onTap: onRemove,
      icon: isDefault ? Icons.visibility_off_rounded : Icons.delete_outline_rounded,
      background: isDefault ? const Color(0xFFE8EAF6) : AppColors.error.withValues(alpha: 0.12),
      foreground: isDefault ? const Color(0xFF3949AB) : AppColors.error,
    );

    return Material(
      color: Colors.white,
      elevation: 0,
      shadowColor: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1A237E).withValues(alpha: 0.1)),
            boxShadow: [
              BoxShadow(
                color: vis.color.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < narrowMaxWidth;
                if (!narrow) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      leading,
                      const SizedBox(width: 14),
                      Expanded(child: titleColumn),
                      const SizedBox(width: 8),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          editBtn,
                          const SizedBox(height: 8),
                          removeBtn,
                        ],
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        leading,
                        const SizedBox(width: 14),
                        Expanded(child: titleColumn),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        editBtn,
                        removeBtn,
                      ],
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
}

class _RoundIcon extends StatelessWidget {
  final String? tooltip;
  final VoidCallback onTap;
  final IconData icon;
  final Color background;
  final Color foreground;

  const _RoundIcon({
    this.tooltip,
    required this.onTap,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 22, color: foreground),
        ),
      ),
    );
    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}

class _ModernInputDialog extends StatelessWidget {
  final String title;
  final String hint;
  final TextEditingController controller;
  final String actionLabel;
  final Color accent;
  final IconData icon;

  const _ModernInputDialog({
    required this.title,
    required this.hint,
    required this.controller,
    required this.actionLabel,
    required this.accent,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      contentPadding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
        ],
      ),
      content: FastTextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: hint,
          filled: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onSubmitted: (v) {
          if (v.trim().isNotEmpty) Navigator.pop(context, v.trim());
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final t = controller.text.trim();
            if (t.isNotEmpty) Navigator.pop(context, t);
          },
          style: FilledButton.styleFrom(backgroundColor: accent),
          child: Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

class _ModernConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final bool destructive;
  final IconData icon;

  const _ModernConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.destructive,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final c = destructive ? AppColors.error : AppColors.financePendente;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: c, size: 24),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      content: Text(message, style: const TextStyle(height: 1.4, fontWeight: FontWeight.w500, fontSize: 14.5)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(backgroundColor: c),
          child: Text(confirmLabel, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
        ),
      ],
    );
  }
}
