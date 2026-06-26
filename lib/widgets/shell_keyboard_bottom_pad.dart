import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';

/// iOS: resize nativo do Scaffold (comportamento padrão Apple).
/// Android/Web: [AppKeyboardScope] na raiz — pad isolado sem rebuild pesado do Gboard.
bool get useNativeScaffoldKeyboardResize =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Android: pad isolado na raiz (legado — preferir [AppKeyboardScope] global).
bool get useShellIsolatedKeyboardPad =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Web: padding manual na raiz.
bool get useWebKeyboardBottomPad => kIsWeb;

/// Altura real do IME — use em vez de [MediaQuery.viewInsetsOf] quando
/// [AppKeyboardScope] zera viewInsets nos filhos (Android/Web).
class AppKeyboardInsets extends InheritedWidget {
  const AppKeyboardInsets({
    super.key,
    required this.bottom,
    required super.child,
  });

  final double bottom;

  static double of(BuildContext context) {
    final inherited =
        context.dependOnInheritedWidgetOfExactType<AppKeyboardInsets>();
    if (inherited != null) return inherited.bottom;
    return MediaQuery.viewInsetsOf(context).bottom;
  }

  @override
  bool updateShouldNotify(AppKeyboardInsets oldWidget) =>
      (oldWidget.bottom - bottom).abs() >= 0.5;
}

/// Mantém [bottom] alinhado ao IME sem atraso.
class KeyboardViewportInsetModel {
  final ValueNotifier<double> bottom = ValueNotifier<double>(0);

  double _readBottomFor(BuildContext? context) {
    if (context != null) {
      final v = View.maybeOf(context);
      if (v != null) return MediaQueryData.fromView(v).viewInsets.bottom;
    }
    final views = PlatformDispatcher.instance.views;
    if (views.isEmpty) return 0;
    return MediaQueryData.fromView(views.first).viewInsets.bottom;
  }

  void sync(BuildContext? context) {
    final inset = _readBottomFor(context);
    if ((bottom.value - inset).abs() < 0.5) return;
    bottom.value = inset;
  }

  void dispose() {
    bottom.dispose();
  }
}

/// **Raiz do app** (MaterialApp.builder): teclado leve no Android — só o [Padding]
/// reage ao Gboard; filhos não rebuildam a cada frame. iOS: repassa insets nativos.
class AppKeyboardScope extends StatefulWidget {
  const AppKeyboardScope({super.key, required this.child});

  final Widget child;

  @override
  State<AppKeyboardScope> createState() => _AppKeyboardScopeState();
}

class _AppKeyboardScopeState extends State<AppKeyboardScope>
    with WidgetsBindingObserver {
  final KeyboardViewportInsetModel _model = KeyboardViewportInsetModel();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _model.sync(context));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _model.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _model.sync(context);
  }

  @override
  Widget build(BuildContext context) {
    if (useNativeScaffoldKeyboardResize) {
      final kb = MediaQuery.viewInsetsOf(context).bottom;
      return AppKeyboardInsets(bottom: kb, child: widget.child);
    }

    return ValueListenableBuilder<double>(
      valueListenable: _model.bottom,
      builder: (context, padBottom, child) {
        return AppKeyboardInsets(
          bottom: padBottom,
          child: Padding(
            padding: EdgeInsets.only(bottom: padBottom),
            child: MediaQuery.removeViewInsets(
              context: context,
              removeBottom: true,
              child: child!,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Recuo inferior para o teclado **sem** reconstruir [child].
class ShellKeyboardBottomPad extends StatefulWidget {
  const ShellKeyboardBottomPad({super.key, required this.child});

  final Widget child;

  @override
  State<ShellKeyboardBottomPad> createState() => _ShellKeyboardBottomPadState();
}

class _ShellKeyboardBottomPadState extends State<ShellKeyboardBottomPad>
    with WidgetsBindingObserver {
  final KeyboardViewportInsetModel _model = KeyboardViewportInsetModel();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _model.sync(context));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _model.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _model.sync(context);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: _model.bottom,
      builder: (context, padBottom, child) {
        return Padding(
          padding: EdgeInsets.only(bottom: padBottom),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Legado: use [AppKeyboardScope] na raiz. Evita pad duplo se já houver ancestral.
class ShellKeyboardIsolatedBody extends StatelessWidget {
  const ShellKeyboardIsolatedBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (context.getElementForInheritedWidgetOfExactType<AppKeyboardInsets>() !=
        null) {
      return child;
    }
    return AppKeyboardScope(child: child);
  }
}

/// Para modais / sheets locais (quando o modal não herda o pad da raiz).
class KeyboardViewInsetPad extends StatefulWidget {
  const KeyboardViewInsetPad({
    super.key,
    required this.child,
    this.left = 0,
    this.right = 0,
    this.top = 0,
    this.bottom = 0,
  });

  final Widget child;
  final double left;
  final double right;
  final double top;
  final double bottom;

  @override
  State<KeyboardViewInsetPad> createState() => _KeyboardViewInsetPadState();
}

class _KeyboardViewInsetPadState extends State<KeyboardViewInsetPad>
    with WidgetsBindingObserver {
  final KeyboardViewportInsetModel _model = KeyboardViewportInsetModel();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _model.sync(context));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _model.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _model.sync(context);
  }

  @override
  Widget build(BuildContext context) {
    final inherited =
        context.getElementForInheritedWidgetOfExactType<AppKeyboardInsets>();
    if (inherited != null) {
      return Padding(
        padding: EdgeInsets.only(
          left: widget.left,
          right: widget.right,
          top: widget.top,
          bottom: widget.bottom,
        ),
        child: widget.child,
      );
    }

    return ValueListenableBuilder<double>(
      valueListenable: _model.bottom,
      builder: (context, kb, child) {
        return Padding(
          padding: EdgeInsets.only(
            left: widget.left,
            right: widget.right,
            top: widget.top,
            bottom: widget.bottom + kb,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
