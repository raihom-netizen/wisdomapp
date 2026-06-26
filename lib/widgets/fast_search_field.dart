import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Campo de busca/filtro **otimizado para o IME do Android**.
///
/// Por que existe: em filtros de listas longas (Admin, Convênios, Finance),
/// o teclado parece "engasgar" no Android. As principais causas são duas:
///
/// 1. `setState` em **cada keystroke** — resolvido com debounce
///    (`DebouncedTextController` / `attachDebouncedRebuild`).
/// 2. **Sugestões / autocorreção / spellcheck / IME learning** ligados —
///    o Gboard processa cada tecla com dicionário grande e devolve frames
///    atrasados ao Flutter. Em filtro de UID/e-mail/CPF, **não há nada
///    para sugerir**, então desativar essas features é puro ganho.
///
/// Este widget aplica as duas otimizações já por padrão. Use em filtros e
/// buscas (não em campos de redação livre).
class FastSearchField extends StatelessWidget {
  const FastSearchField({
    super.key,
    required this.controller,
    this.hintText,
    this.prefixIcon = Icons.search_rounded,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.enabled = true,
    this.keyboardType = TextInputType.text,
    this.textCapitalization = TextCapitalization.none,
    this.dense = true,
    this.borderRadius = 10,
    this.contentPadding =
        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.isNumeric = false,
  });

  final TextEditingController controller;
  final String? hintText;
  final IconData prefixIcon;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final bool enabled;
  final TextInputType keyboardType;
  final TextCapitalization textCapitalization;
  final bool dense;
  final double borderRadius;
  final EdgeInsetsGeometry contentPadding;

  /// Atalho: usa teclado numérico com filtros para dígitos. Útil para CPF,
  /// telefone, valor monetário simples.
  final bool isNumeric;

  @override
  Widget build(BuildContext context) {
    final type = isNumeric
        ? const TextInputType.numberWithOptions(decimal: false, signed: false)
        : keyboardType;
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: type,
      textInputAction: TextInputAction.search,
      textCapitalization: textCapitalization,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      inputFormatters: isNumeric
          ? <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly]
          : null,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: Icon(prefixIcon, size: 22),
        suffixIcon: suffix,
        isDense: dense,
        contentPadding: contentPadding,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}
