import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import '../constants/link_utils_icons.dart';
import '../models/icon_model.dart';
import '../services/link_utils_preference_service.dart';
import '../theme/app_colors.dart';
import '../theme/gemini_theme.dart';

/// Botão Voltar (ícone + texto) para todas as telas do módulo Minhas Anotações — visível no iPhone.
Widget _buildVoltarButton(BuildContext context) {
  final color = Theme.of(context).appBarTheme.foregroundColor ?? Colors.white;
  return Semantics(
    label: 'Voltar',
    button: true,
    child: InkWell(
      onTap: () => Navigator.of(context).pop(),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back_rounded, size: 24, color: color),
            const SizedBox(width: 6),
            Text('Voltar', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: color)),
          ],
        ),
      ),
    ),
  );
}

/// Tela para o usuário editar, incluir e remover seus links úteis. Padrão = lista do app; cada um personaliza o seu.
class LinkUtilsEditorScreen extends StatefulWidget {
  final String uid;
  final List<LinkUtilItem> initialItems;

  const LinkUtilsEditorScreen({
    super.key,
    required this.uid,
    required this.initialItems,
  });

  @override
  State<LinkUtilsEditorScreen> createState() => _LinkUtilsEditorScreenState();
}

class _LinkUtilsEditorScreenState extends State<LinkUtilsEditorScreen> {
  late List<LinkUtilItem> _items;
  final LinkUtilsPreferenceService _service = LinkUtilsPreferenceService();

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.initialItems);
  }

  Future<void> _save() async {
    await _service.save(widget.uid, _items);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Links salvos.')));
      Navigator.of(context).pop(_items);
    }
  }

  Future<void> _restoreDefault() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restaurar padrão'),
        content: const Text(
          'Substituir sua lista pela lista padrão do sistema? O padrão do app será restaurado. Você pode personalizar de novo depois.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Restaurar')),
        ],
      ),
    );
    if (confirm == true && mounted) {
      setState(() => _items = List.from(LinkUtilsPreferenceService.defaultList()));
      await _service.save(widget.uid, _items);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lista padrão restaurada.')));
      }
    }
  }

  Future<void> _addOrEditItem([int? index]) async {
    final existing = index != null && index >= 0 && index < _items.length ? _items[index] : null;
    final result = await Navigator.of(context).push<LinkUtilItem>(
      MaterialPageRoute(
        builder: (_) => _LinkUtilFormScreen(item: existing),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        if (index != null && index < _items.length) {
          _items[index] = result;
        } else {
          _items.add(result);
        }
      });
      try {
        await _service.save(widget.uid, _items);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Link salvo permanentemente.')),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Erro ao salvar. Tente novamente.')),
          );
        }
      }
    }
  }

  Future<void> _removeItem(int index) async {
    if (index < 0 || index >= _items.length) return;
    final item = _items[index];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Remover "${item.title}" da sua lista?'),
            const SizedBox(height: 12),
            Text(
              'O padrão do sistema não muda. Só a sua lista é alterada. Você pode restaurar o padrão a qualquer momento.',
              style: TextStyle(fontSize: 13, color: GeminiTheme.textMuted, height: 1.35),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      setState(() => _items.removeAt(index));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: GeminiTheme.background,
        appBar: AppBar(
          leadingWidth: 80,
          leading: _buildVoltarButton(context),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Personalizar Links Úteis'),
              Text(
                'Padrão do sistema permanece; alterações só na sua lista.',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal, color: Colors.white70),
              ),
            ],
          ),
          actions: [
          TextButton(
            onPressed: _items.isEmpty ? null : _save,
            child: const Text('Salvar'),
          ),
          IconButton(
            icon: const Icon(Icons.restore_rounded),
            tooltip: 'Restaurar padrão',
            onPressed: _restoreDefault,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ReorderableListView.builder(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + bottomPadding + 80),
          itemCount: _items.length,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex--;
              final item = _items.removeAt(oldIndex);
              _items.insert(newIndex, item);
            });
          },
          proxyDecorator: (child, index, animation) => Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(GeminiTheme.cardRadius),
            color: GeminiTheme.surface,
            child: child,
          ),
          itemBuilder: (context, i) {
            final item = _items[i];
            return Card(
              key: ValueKey(item.title + item.url + i.toString()),
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 2,
              shadowColor: Colors.black12,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GeminiTheme.cardRadius)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.drag_handle_rounded, color: GeminiTheme.textMuted, size: 24),
                    const SizedBox(width: 8),
                    Icon(kLinkUtilIcons[item.iconIndex.clamp(0, kLinkUtilIcons.length - 1)], color: AppColors.primary, size: 28),
                  ],
                ),
                title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700, color: GeminiTheme.textPrimary)),
                subtitle: Text(
                  item.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: GeminiTheme.textMuted, fontSize: 13),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        item.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                        color: item.isFavorite ? AppColors.amber : GeminiTheme.textMuted,
                        size: 26,
                      ),
                      onPressed: () {
                        setState(() => _items[i] = item.copyWith(isFavorite: !item.isFavorite));
                      },
                      tooltip: item.isFavorite ? 'Desmarcar favorito' : 'Marcar favorito',
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded),
                      tooltip: 'Opções',
                      onSelected: (value) {
                        if (value == 'edit') _addOrEditItem(i);
                        if (value == 'delete') _removeItem(i);
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_rounded, size: 22), SizedBox(width: 12), Text('Editar')])),
                        PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_rounded, color: AppColors.error, size: 22), const SizedBox(width: 12), Text('Excluir', style: TextStyle(color: AppColors.error))])),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
        floatingActionButton: Padding(
          padding: EdgeInsets.only(bottom: bottomPadding + 16),
          child: FloatingActionButton.extended(
            onPressed: () => _addOrEditItem(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Incluir link'),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GeminiTheme.buttonRadius)),
          ),
        ),
      ),
    );
  }
}

/// Quantidade de ícones no formulário (10). Conjunto Moderno; modal tem toggle Moderno/Colorido.
const int _kIconsPreviewCount = 10;

/// Formulário para adicionar ou editar um link (e seus sub-itens).
class _LinkUtilFormScreen extends StatefulWidget {
  final LinkUtilItem? item;

  const _LinkUtilFormScreen({this.item});

  @override
  State<_LinkUtilFormScreen> createState() => _LinkUtilFormScreenState();
}

class _LinkUtilFormScreenState extends State<_LinkUtilFormScreen> {
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _urlCtrl;
  late int _iconIndex;
  late List<SubLinkItem> _subLinks;

  /// Exibir ícone/erro nos campos vazios após tentativa de salvar (validação blindada).
  bool _showFieldErrors = false;

  /// Objeto que armazena o ícone escolhido na grade; exibido no topo da tela. Nunca nulo: sempre há ícone padrão.
  late CustomIconData _iconeSelecionado;

  Widget _buildIconChip(int i, bool selected) {
    if (i >= iconesModernos.length) return const SizedBox.shrink();
    final item = iconesModernos[i];
    final color = item.color;
    final isActive = selected ||
        (_iconeSelecionado.icon.codePoint == item.icon.codePoint &&
            _iconeSelecionado.color.value == item.color.value);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        _iconIndex = item.linkUtilIconIndex;
        _iconeSelecionado = item;
      }),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isActive
                  ? color.withValues(alpha: 0.3)
                  : color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(_kIconCellRadius),
              border: Border.all(
                  color: isActive ? color : Colors.transparent,
                  width: isActive ? 3 : 1),
            ),
            child: Icon(
                item.icon,
                color: isActive ? color : color.withValues(alpha: 0.85),
                size: 24),
          ),
          if (isActive)
            Positioned(
              right: 0,
              top: 0,
              child: CircleAvatar(
                radius: 7,
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.check_circle,
                  color: Colors.green.shade700,
                  size: 14,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Abre a grade de ícones; o await espera o usuário clicar em um ícone e o modal fechar.
  /// O Navigator.pop(context, item) na grade envia o objeto para cá; setState faz o ícone aparecer na hora.
  Future<void> _abrirSeletorDeIcones() async {
    final resultado = await showModalBottomSheet<CustomIconData>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _IconPickerSheet(
          currentIndex: _iconIndex,
          selectedItem: _iconeSelecionado,
        ),
    );
    if (resultado != null && mounted) {
      setState(() {
        _iconeSelecionado = resultado;
        _iconIndex = resultado.linkUtilIconIndex;
      });
    }
  }

  /// Decoração dos campos com ícone de prefixo e estado de erro (blindado: sempre mostra ícone).
  InputDecoration _fieldDecoration(String label, IconData prefixIcon, {String? errorText}) {
    final hasError = errorText != null && errorText.isNotEmpty;
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(
        hasError ? Icons.error_outline_rounded : prefixIcon,
        color: hasError ? AppColors.error : GeminiTheme.textMuted,
        size: 22,
      ),
      errorText: hasError ? errorText : null,
      filled: true,
      fillColor: hasError ? AppColors.error.withValues(alpha: 0.06) : const Color(0xFFF1F5F9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GeminiTheme.inputRadius),
        borderSide: BorderSide.none,
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GeminiTheme.inputRadius),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    );
  }

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.item?.title ?? '');
    _descCtrl = TextEditingController(text: widget.item?.description ?? '');
    _urlCtrl = TextEditingController(text: widget.item?.url ?? '');
    _iconIndex = widget.item?.iconIndex ?? 0;
    _subLinks = List.from(widget.item?.subLinks ?? []);
    final item = widget.item;
    if (item != null && item.iconCodePoint != null && item.iconColorValue != null) {
      // Não usar IconData(codePoint, fontFamily: ...) — quebra tree-shake de ícones no release iOS.
      final restoredIcon = linkUtilIconForDisplay(
        codePoint: item.iconCodePoint,
        index: item.iconIndex,
      );
      final restoredColor = Color(item.iconColorValue!);
      int idx = item.iconIndex;
      bool found = false;
      for (int i = 0; i < iconesModernos.length; i++) {
        if (iconesModernos[i].icon.codePoint == item.iconCodePoint &&
            iconesModernos[i].color.value == item.iconColorValue) {
          idx = i;
          found = true;
          break;
        }
      }
      if (!found) {
        for (int i = 0; i < iconesColoridos.length; i++) {
          if (iconesColoridos[i].icon.codePoint == item.iconCodePoint &&
              iconesColoridos[i].color.value == item.iconColorValue) {
            idx = i;
            found = true;
            break;
          }
        }
      }
      if (!found) {
        for (int i = 0; i < iconGridList.length; i++) {
          final cell = iconGridList[i];
          if (cell != null && cell.icon.codePoint == item.iconCodePoint) {
            idx = i;
            break;
          }
        }
      }
      _iconIndex = idx.clamp(0, _kIconsPreviewCount - 1);
      _iconeSelecionado = CustomIconData(
        icon: restoredIcon,
        color: restoredColor,
        linkUtilIconIndex: _iconIndex,
      );
    } else {
      final idx = _iconIndex.clamp(0, _kIconsPreviewCount - 1);
      _iconeSelecionado = (idx >= 0 && idx < iconesModernos.length)
          ? iconesModernos[idx]
          : iconesModernos[0];
      if (idx < 0 || idx >= iconesModernos.length) _iconIndex = 0;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final title = _titleCtrl.text.trim();
    final url = _urlCtrl.text.trim();
    final titleError = title.isEmpty ? 'Informe o título.' : null;
    final urlError = url.isEmpty ? 'Informe a URL.' : null;
    if (titleError != null || urlError != null) {
      setState(() => _showFieldErrors = true);
      if (titleError != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(titleError)));
      } else if (urlError != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(urlError)));
      }
      return;
    }
    final subLinks = _subLinks
        .where((s) => s.title.trim().isNotEmpty || s.url.trim().isNotEmpty)
        .map((s) => SubLinkItem(title: s.title.trim(), url: s.url.trim()))
        .toList();
    Navigator.of(context).pop(LinkUtilItem(
      title: title,
      description: _descCtrl.text.trim(),
      url: url,
      iconIndex: _iconeSelecionado.linkUtilIconIndex,
      iconCodePoint: _iconeSelecionado.icon.codePoint,
      iconColorValue: _iconeSelecionado.color.value,
      subLinks: subLinks,
      isFavorite: widget.item?.isFavorite ?? false,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: GeminiTheme.background,
        appBar: AppBar(
          leadingWidth: 80,
          leading: _buildVoltarButton(context),
          title: Text(widget.item != null ? 'Editar link' : 'Incluir link'),
          actions: [
            TextButton(onPressed: _save, child: const Text('Salvar')),
          ],
        ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _abrirSeletorDeIcones,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _iconeSelecionado.color.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _iconeSelecionado.icon,
                      color: _iconeSelecionado.color,
                      size: 40,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Toque para escolher ícone',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: GeminiTheme.textMuted),
              ),
              const SizedBox(height: 20),
              FastTextField(
                controller: _titleCtrl,
                decoration: _fieldDecoration(
                  'Título',
                  Icons.title_rounded,
                  errorText: _showFieldErrors && _titleCtrl.text.trim().isEmpty ? 'Informe o título.' : null,
                ),
                textCapitalization: TextCapitalization.words,
                onChanged: (_) {
                  if (_showFieldErrors) setState(() {});
                },
              ),
              const SizedBox(height: 16),
              FastTextField(
                controller: _descCtrl,
                decoration: _fieldDecoration('Descrição', Icons.notes_rounded),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              FastTextField(
                controller: _urlCtrl,
                decoration: _fieldDecoration(
                  'URL',
                  Icons.link_rounded,
                  errorText: _showFieldErrors && _urlCtrl.text.trim().isEmpty ? 'Informe a URL.' : null,
                ),
                keyboardType: TextInputType.url,
                onChanged: (_) {
                  if (_showFieldErrors) setState(() {});
                },
              ),
              const SizedBox(height: 20),
              const Text('Ícone', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: GeminiTheme.textPrimary)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ...List.generate(_kIconsPreviewCount, (i) {
                    final selected = _iconIndex == i;
                    return _buildIconChip(i, selected);
                  }),
                  Material(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(GeminiTheme.inputRadius),
                      child: InkWell(
                        onTap: _abrirSeletorDeIcones,
                        borderRadius: BorderRadius.circular(GeminiTheme.inputRadius),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.grid_view_rounded, size: 22, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Text('Ver mais ícones', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Sub-itens (opcional)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: GeminiTheme.textPrimary)),
                  TextButton.icon(
                    onPressed: () => setState(() => _subLinks.add(const SubLinkItem(title: '', url: ''))),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('Adicionar'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ...List.generate(_subLinks.length, (i) {
              return _SubLinkRow(
                title: _subLinks[i].title,
                url: _subLinks[i].url,
                onChanged: (t, u) {
                  setState(() => _subLinks[i] = SubLinkItem(title: t, url: u));
                },
                onRemove: () => setState(() => _subLinks.removeAt(i)),
              );
            }),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_rounded, size: 22),
                  label: const Text('Salvar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GeminiTheme.buttonRadius)),
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
}

/// Raio das bordas arredondadas no grid (design pastel).
const double _kIconCellRadius = 12.0;

/// Modal "Escolher ícone" com toggle Moderno / Colorido. Retorno: Navigator.pop(context, item) com objeto completo.
class _IconPickerSheet extends StatefulWidget {
  final int currentIndex;
  final CustomIconData? selectedItem;

  const _IconPickerSheet({required this.currentIndex, this.selectedItem});

  @override
  State<_IconPickerSheet> createState() => _IconPickerSheetState();
}

class _IconPickerSheetState extends State<_IconPickerSheet> {
  /// 0 = Moderno (pastel), 1 = Colorido (vibrante/glossy).
  late int _estiloSelecionado;

  List<CustomIconData> get _listaAtual =>
      _estiloSelecionado == 0 ? iconesModernos : iconesColoridos;

  bool _itemMatches(CustomIconData item, CustomIconData? selected) {
    if (selected == null) return false;
    return item.icon.codePoint == selected.icon.codePoint &&
        item.color.value == selected.color.value;
  }

  @override
  void initState() {
    super.initState();
    _estiloSelecionado = 0;
    if (widget.selectedItem != null) {
      for (int i = 0; i < iconesColoridos.length; i++) {
        if (_itemMatches(iconesColoridos[i], widget.selectedItem)) {
          _estiloSelecionado = 1;
          break;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const crossAxisCount = 5;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.5;
    final isColorido = _estiloSelecionado == 1;

    return Container(
      decoration: BoxDecoration(
        color: GeminiTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 16,
        right: 16,
        bottom: MediaQuery.paddingOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Escolher ícone',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700, color: GeminiTheme.textPrimary),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Fechar',
              ),
            ],
          ),
          const SizedBox(height: 10),
          ToggleButtons(
            isSelected: [_estiloSelecionado == 0, _estiloSelecionado == 1],
            onPressed: (index) {
              setState(() => _estiloSelecionado = index);
            },
            borderRadius: BorderRadius.circular(10),
            children: const [
              Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Text('Moderno')),
              Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Text('Colorido')),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: (maxHeight - 80).clamp(180.0, 320.0),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.0,
              ),
              itemCount: _listaAtual.length,
              itemBuilder: (context, index) {
                final item = _listaAtual[index];
                final isSelected = item.linkUtilIconIndex == widget.currentIndex ||
                    _itemMatches(item, widget.selectedItem);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.pop(context, item),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: item.color.withValues(
                              alpha: isSelected ? 0.3 : 0.15),
                          shape: isColorido
                              ? BoxShape.circle
                              : BoxShape.rectangle,
                          borderRadius: isColorido
                              ? null
                              : BorderRadius.circular(_kIconCellRadius),
                          border: Border.all(
                            color: isSelected
                                ? item.color
                                : item.color.withValues(alpha: 0.4),
                            width: isSelected ? 3 : 1,
                          ),
                        ),
                        child: Center(
                          child: Icon(item.icon, color: item.color, size: 24),
                        ),
                      ),
                      if (isSelected)
                        Positioned(
                          right: 2,
                          top: 2,
                          child: CircleAvatar(
                            radius: 8,
                            backgroundColor: Colors.white,
                            child: Icon(
                              Icons.check_circle,
                              color: Colors.green.shade700,
                              size: 16,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SubLinkRow extends StatefulWidget {
  final String title;
  final String url;
  final void Function(String title, String url) onChanged;
  final VoidCallback onRemove;

  const _SubLinkRow({
    required this.title,
    required this.url,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_SubLinkRow> createState() => _SubLinkRowState();
}

class _SubLinkRowState extends State<_SubLinkRow> {
  late TextEditingController _tCtrl;
  late TextEditingController _uCtrl;

  @override
  void initState() {
    super.initState();
    _tCtrl = TextEditingController(text: widget.title);
    _uCtrl = TextEditingController(text: widget.url);
  }

  @override
  void dispose() {
    _tCtrl.dispose();
    _uCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: FastTextField(
              controller: _tCtrl,
              decoration: InputDecoration(
                labelText: 'Nome',
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(GeminiTheme.inputRadius), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                isDense: true,
              ),
              onChanged: (_) => widget.onChanged(_tCtrl.text.trim(), _uCtrl.text.trim()),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FastTextField(
              controller: _uCtrl,
              decoration: InputDecoration(
                labelText: 'URL',
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(GeminiTheme.inputRadius), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                isDense: true,
              ),
              keyboardType: TextInputType.url,
              onChanged: (_) => widget.onChanged(_tCtrl.text.trim(), _uCtrl.text.trim()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.error),
            onPressed: widget.onRemove,
          ),
        ],
      ),
    );
  }
}
