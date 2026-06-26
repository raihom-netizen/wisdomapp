import 'package:flutter/material.dart';
import 'fast_text_field.dart';
import 'package:flutter/services.dart';

import '../constants/commitment_presets.dart';
import '../services/commitment_descriptions_service.dart';
import '../services/user_categories_service.dart';
import '../theme/app_colors.dart';
import '../utils/uppercase_text_input_formatter.dart';

/// Linha de chips premium com os 6 compromissos mais comuns. Reutilizada no
/// "Compromisso expresso" e na "Geração automática (Compromisso particular)".
///
/// Toque preenche descrição automaticamente; o caller decide se também
/// aplica a [CommitmentPreset.color] na cor do calendário.
class CommitmentQuickIconsRow extends StatelessWidget {
  /// Nome atual (em qualquer caixa) para destacar o chip selecionado.
  final String currentName;
  final ValueChanged<CommitmentPreset> onPick;
  final bool enabled;
  const CommitmentQuickIconsRow({
    super.key,
    required this.currentName,
    required this.onPick,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in kCommitmentQuickPresets)
          _CommitmentQuickChip(
            preset: p,
            selected: currentName.trim().toLowerCase() ==
                p.name.toLowerCase(),
            onTap: enabled ? () => onPick(p) : null,
          ),
      ],
    );
  }
}

class _CommitmentQuickChip extends StatelessWidget {
  final CommitmentPreset preset;
  final bool selected;
  final VoidCallback? onTap;
  const _CommitmentQuickChip({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  String get _shortName {
    switch (preset.name) {
      case 'Reunião de trabalho':
        return 'Reunião';
      case 'Consulta médica':
        return 'Médico';
      case 'Igreja/culto':
        return 'Igreja';
      case 'Aniversários':
        return 'Aniversário';
      default:
        return preset.name;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? preset.color.withValues(alpha: 0.18)
              : preset.color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? preset.color.withValues(alpha: 0.85)
                : preset.color.withValues(alpha: 0.25),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: preset.color,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: preset.color.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(preset.icon, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 8),
            Text(
              _shortName,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                color: AppColors.textPrimary,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Converte uma [Color] para hex `#RRGGBB` (uppercase).
String hexFromCommitmentColor(Color c) {
  final r = ((c.r * 255).round()).toRadixString(16).padLeft(2, '0');
  final g = ((c.g * 255).round()).toRadixString(16).padLeft(2, '0');
  final b = ((c.b * 255).round()).toRadixString(16).padLeft(2, '0');
  return '#${(r + g + b).toUpperCase()}';
}

/// Picker fullscreen premium para selecionar a descrição de um compromisso.
///
/// Combina presets globais ([kCommitmentPresets]) com descrições customizadas
/// do usuário ([CommitmentDescriptionsService]). Itens em ordem alfabética
/// pt-BR. Topo fixo: campo de pesquisa + botão "+ Incluir nova" (cria e
/// devolve no mesmo gesto). Toque em qualquer item devolve o nome ao
/// chamador via `Navigator.pop(context, name)`.
Future<String?> showCommitmentDescriptionPicker({
  required BuildContext context,
  required String uid,
  String? initialQuery,
}) {
  return Navigator.of(context, rootNavigator: true).push<String>(
    MaterialPageRoute<String>(
      fullscreenDialog: true,
      builder: (_) => _CommitmentDescriptionPickerScreen(
        uid: uid,
        initialQuery: initialQuery ?? '',
      ),
    ),
  );
}

class _CommitmentDescriptionPickerScreen extends StatefulWidget {
  final String uid;
  final String initialQuery;
  const _CommitmentDescriptionPickerScreen({
    required this.uid,
    required this.initialQuery,
  });

  @override
  State<_CommitmentDescriptionPickerScreen> createState() =>
      _CommitmentDescriptionPickerScreenState();
}

class _CommitmentDescriptionPickerScreenState
    extends State<_CommitmentDescriptionPickerScreen> {
  final _searchCtrl = TextEditingController();
  final _service = CommitmentDescriptionsService();
  List<String> _custom = const [];

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = widget.initialQuery;
    _service.listOnce(widget.uid).then((items) {
      if (mounted) setState(() => _custom = items);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Lista combinada (presets + customizadas), únicos por nome
  /// (case-insensitive), ordenada alfabeticamente pt-BR.
  List<_PickerItem> _allItems() {
    final seen = <String>{};
    final out = <_PickerItem>[];
    for (final p in kCommitmentPresets) {
      final k = p.name.toLowerCase();
      if (seen.add(k)) {
        out.add(_PickerItem(name: p.name, icon: p.icon, color: p.color, custom: false));
      }
    }
    for (final c in _custom) {
      final k = c.toLowerCase();
      if (seen.add(k)) {
        out.add(_PickerItem(
          name: c,
          icon: Icons.bookmark_rounded,
          color: AppColors.primary,
          custom: true,
        ));
      }
    }
    out.sort((a, b) => UserCategoriesService.compareNamesPt(a.name, b.name));
    return out;
  }

  List<_PickerItem> _filtered() {
    final q = _searchCtrl.text.trim().toLowerCase();
    final base = _allItems();
    if (q.isEmpty) return base;
    return base
        .where((i) => i.name.toLowerCase().contains(q))
        .toList();
  }

  bool _exactMatchExists(String q) {
    final lower = q.trim().toLowerCase();
    if (lower.isEmpty) return false;
    return _allItems().any((i) => i.name.toLowerCase() == lower);
  }

  Future<void> _incluirNova({String? prefilled}) async {
    final ctrl = TextEditingController(text: (prefilled ?? '').toUpperCase());
    final created = await showDialog<String>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('Nova descrição',
              style: TextStyle(fontWeight: FontWeight.w900)),
          content: FastTextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              UpperCaseTextFormatter(),
              LengthLimitingTextInputFormatter(60),
            ],
            decoration: const InputDecoration(
              labelText: 'Descrição do compromisso',
              hintText: 'EX.: REUNIÃO DE CONDOMÍNIO',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) {
              final n = v.trim();
              if (n.isNotEmpty) Navigator.of(dialogCtx).pop(n);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final n = ctrl.text.trim();
                if (n.isNotEmpty) Navigator.of(dialogCtx).pop(n);
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Adicionar'),
            ),
          ],
        );
      },
    );
    if (created == null || !mounted) return;
    await _service.add(widget.uid, created);
    if (!mounted) return;
    Navigator.of(context).pop(created);
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered();
    final query = _searchCtrl.text.trim();
    final showIncluirNova = query.isNotEmpty && !_exactMatchExists(query);

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
        title: const Text(
          'Descrição do compromisso',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Fechar',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Pesquisa + Incluir nova fixos no topo.
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              children: [
                FastTextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Pesquisar ou digitar nova descrição',
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: AppColors.primary),
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
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _incluirNova(prefilled: query),
                    icon: const Icon(Icons.add_circle_rounded),
                    label: Text(
                      showIncluirNova
                          ? 'Incluir "${query.toUpperCase()}"'
                          : 'Incluir nova descrição',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                          fontSize: 14, letterSpacing: 0.2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: items.isEmpty
                ? _emptyState(query)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: items.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 64),
                    itemBuilder: (_, i) {
                      final it = items[i];
                      return ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: it.color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(it.icon, color: it.color, size: 22),
                        ),
                        title: Text(
                          it.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              color: AppColors.textPrimary),
                        ),
                        subtitle: it.custom
                            ? const Text('Sua descrição',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.textMuted))
                            : null,
                        trailing: it.custom
                            ? IconButton(
                                tooltip: 'Remover',
                                icon: const Icon(Icons.delete_outline_rounded,
                                    color: AppColors.textMuted),
                                onPressed: () async {
                                  await _service.remove(widget.uid, it.name);
                                  if (!mounted) return;
                                  setState(() => _custom = _custom
                                      .where((c) =>
                                          c.toLowerCase() !=
                                          it.name.toLowerCase())
                                      .toList());
                                },
                              )
                            : const Icon(Icons.chevron_right_rounded,
                                color: AppColors.textMuted),
                        onTap: () =>
                            Navigator.of(context).pop(it.name),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String query) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_note_rounded,
                size: 56, color: AppColors.textMuted.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            Text(
              query.isEmpty
                  ? 'Sem descrições disponíveis.'
                  : 'Nenhuma descrição corresponde a "$query".',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13.5,
                  height: 1.4),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => _incluirNova(prefilled: query),
              icon: const Icon(Icons.add_circle_rounded),
              label: const Text('Incluir nova descrição'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerItem {
  final String name;
  final IconData icon;
  final Color color;
  final bool custom;
  const _PickerItem({
    required this.name,
    required this.icon,
    required this.color,
    required this.custom,
  });
}
