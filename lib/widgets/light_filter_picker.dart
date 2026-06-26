import 'package:flutter/material.dart';

/// Opção de filtro — sem o custo de [DropdownMenuItem] / [FormField].
class LightFilterOption<T> {
  const LightFilterOption({
    required this.value,
    required this.label,
    this.enabled = true,
  });

  final T value;
  final String label;
  final bool enabled;
}

/// Filtro leve: abre bottom sheet só ao toque — evita [DropdownButtonFormField]
/// pesado no build principal (Gboard + listas longas no Admin/Financeiro).
class LightFilterPicker<T> extends StatelessWidget {
  const LightFilterPicker({
    super.key,
    required this.value,
    required this.label,
    required this.options,
    required this.onChanged,
    this.icon,
    this.minWidth,
    this.sheetTitle,
    this.decoration,
    this.enabled = true,
  });

  final T value;
  final String label;
  final List<LightFilterOption<T>> options;
  final ValueChanged<T> onChanged;
  final IconData? icon;
  final double? minWidth;
  final String? sheetTitle;
  final InputDecoration? decoration;
  final bool enabled;

  String _labelFor(T v) {
    for (final o in options) {
      if (o.value == v) return o.label;
    }
    return '—';
  }

  Future<void> _openSheet(BuildContext context) async {
    if (!enabled) return;
    final picked = await showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      isScrollControlled: options.length > 8,
      builder: (ctx) {
        final bottom = MediaQuery.paddingOf(ctx).bottom;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(8, 4, 8, 8 + bottom),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Text(
                  sheetTitle ?? label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ...options.map((o) {
                final selected = o.value == value;
                return ListTile(
                  enabled: o.enabled,
                  selected: selected,
                  title: Text(
                    o.label,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: selected
                      ? Icon(Icons.check_rounded,
                          color: Theme.of(ctx).colorScheme.primary)
                      : null,
                  onTap: o.enabled
                      ? () => Navigator.pop(ctx, o.value)
                      : null,
                );
              }),
            ],
          ),
        );
      },
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final display = _labelFor(value);
    final field = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? () => _openSheet(context) : null,
        borderRadius: BorderRadius.circular(10),
        child: InputDecorator(
          isFocused: false,
          isEmpty: false,
          decoration: (decoration ??
                  InputDecoration(
                    labelText: label,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ))
              .copyWith(
            suffixIcon: const Icon(Icons.arrow_drop_down_rounded, size: 22),
            prefixIcon: icon != null ? Icon(icon, size: 20) : null,
          ),
          child: Text(
            display,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              color: enabled ? null : Theme.of(context).disabledColor,
            ),
          ),
        ),
      ),
    );

    if (minWidth != null) {
      return SizedBox(width: minWidth, child: field);
    }
    return field;
  }
}
