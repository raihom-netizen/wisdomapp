import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../constants/app_business_rules.dart';

/// Helpers para evitar o «teclado Android lento» causado por `setState` ou
/// reagendamento de busca em **cada keystroke** do `TextField`/`TextFormField`.
///
/// O problema típico no Flutter Android é fazer:
/// ```dart
/// _filterCtrl.addListener(() => setState(() {}));
/// // ou
/// onChanged: (_) => setState(() {})
/// ```
/// Em listas longas (Admin, Finance, Convênios) cada caractere digitado
/// reconstrói toda a árvore — o IME (Gboard/SwiftKey/Samsung) trava e a
/// digitação fica "engasgada".
///
/// Este utilitário oferece três caminhos rápidos:
///
/// 1. [DebouncedTextController]: substitui o `TextEditingController` em filtros
///    de busca. Tem um `ValueListenable<String>` (`debouncedText`) que
///    dispara só após [debounce] — use-o em vez de chamar `setState`.
/// 2. [attachDebouncedRebuild]: anexa um listener no `TextEditingController`
///    existente que chama `setState` com debounce — útil para hotfix sem
///    refatorar a UI.
/// 3. [debounceMs]: valor padrão alinhado com [AppBusinessRules.searchDebounceMs].
///
/// O debounce padrão (~300 ms) é "humano": rápido o suficiente para parecer
/// instantâneo, e folgado para o IME terminar o frame sem disputar com
/// rebuilds.

/// Tempo padrão usado pelos helpers de busca (alinhado às regras do app).
const int kDefaultSearchDebounceMs = AppBusinessRules.searchDebounceMs;

/// `TextEditingController` com saída debounced em [debouncedText].
///
/// Use no lugar de `TextEditingController` em filtros do tipo
/// "lista que filtra conforme o usuário digita":
/// ```dart
/// final _ctrl = DebouncedTextController();
/// // …
/// ValueListenableBuilder<String>(
///   valueListenable: _ctrl.debouncedText,
///   builder: (_, q, __) => _buildResults(q),
/// )
/// // … TextField(controller: _ctrl, …)
/// // dispose: _ctrl.dispose();
/// ```
class DebouncedTextController extends TextEditingController {
  DebouncedTextController({
    super.text,
    Duration? debounce,
  }) : _debounce = debounce ??
            const Duration(milliseconds: kDefaultSearchDebounceMs) {
    addListener(_onTextChanged);
  }

  final Duration _debounce;
  final ValueNotifier<String> _debounced = ValueNotifier<String>('');
  Timer? _timer;

  /// Última string «firme» após o debounce — não atualiza a cada tecla.
  ValueListenable<String> get debouncedText => _debounced;

  void _onTextChanged() {
    final v = text;
    _timer?.cancel();
    if (v.isEmpty) {
      // Esvaziar é instantâneo (botão «×» / limpar): UX espera resposta na hora.
      _debounced.value = '';
      return;
    }
    _timer = Timer(_debounce, () {
      if (_debounced.value != v) _debounced.value = v;
    });
  }

  /// Força o valor debounced imediatamente — útil em `textInputAction: search`.
  void flush() {
    _timer?.cancel();
    if (_debounced.value != text) _debounced.value = text;
  }

  @override
  void dispose() {
    _timer?.cancel();
    removeListener(_onTextChanged);
    _debounced.dispose();
    super.dispose();
  }
}

/// Anexa um listener com debounce a um `TextEditingController` existente.
///
/// Retorna uma função que **desanexa** — chame em `dispose` para não vazar.
///
/// Use para refatorar locais legados que faziam:
/// ```dart
/// _ctrl.addListener(() => setState(() {}));
/// ```
/// ⇢
/// ```dart
/// _detach = attachDebouncedRebuild(_ctrl, () { if (mounted) setState(() {}); });
/// // dispose: _detach?.call();
/// ```
VoidCallback attachDebouncedRebuild(
  TextEditingController controller,
  VoidCallback onDebouncedChange, {
  Duration debounce =
      const Duration(milliseconds: kDefaultSearchDebounceMs),
}) {
  Timer? timer;
  String last = controller.text;
  void listener() {
    final v = controller.text;
    if (v == last) return;
    last = v;
    timer?.cancel();
    if (v.isEmpty) {
      onDebouncedChange();
      return;
    }
    timer = Timer(debounce, onDebouncedChange);
  }

  controller.addListener(listener);
  return () {
    timer?.cancel();
    controller.removeListener(listener);
  };
}
