import 'package:flutter/material.dart';

import '../widgets/shell_keyboard_bottom_pad.dart';

export '../widgets/shell_keyboard_bottom_pad.dart' show AppKeyboardInsets, AppKeyboardScope;

/// [resizeToAvoidBottomInset] do Scaffold.
///
/// Com [AppKeyboardScope] na raiz (Android/Web), o Scaffold **não** deve redimensionar
/// — evita pad duplo e rebuild lento do Gboard. iOS: resize nativo.
bool scaffoldKeyboardResizeToAvoidBottomInset({
  bool embeddedInHomeShell = false,
  bool standaloneFullPageForm = false,
}) {
  return useNativeScaffoldKeyboardResize;
}

/// Legado: o pad global está em [AppKeyboardScope] — retorna [child] sem envolver.
Widget keyboardScaffoldBody(
  Widget child, {
  bool embeddedInHomeShell = false,
  bool standaloneFullPageForm = false,
}) {
  return child;
}

/// Padding / rolagem com IME — usa [AppKeyboardInsets] quando viewInsets estão zerados.
class KeyboardFormInsets {
  KeyboardFormInsets._();

  static double bottom(BuildContext context) => AppKeyboardInsets.of(context);

  static double scrollBottomExtra(
    BuildContext context, {
    double extra = 16,
    bool standaloneFullPageForm = false,
    bool embeddedInHomeShell = false,
  }) {
    return extra;
  }

  /// Rolagem ao focar campo — cobre rodapé fixo (teclado já levantou a tela na raiz).
  static EdgeInsets fieldScrollPadding(
    BuildContext context, {
    double footerEstimate = 100,
    bool standaloneFullPageForm = false,
    bool embeddedInHomeShell = false,
  }) {
    return EdgeInsets.fromLTRB(20, 20, 20, 20 + footerEstimate);
  }

  /// [AlertDialog] — espaço para botões de ação.
  static EdgeInsets dialogFieldScrollPadding(
    BuildContext context, {
    double footerEstimate = 140,
  }) {
    return EdgeInsets.fromLTRB(20, 20, 20, 20 + footerEstimate);
  }
}

/// Diálogo dentro de [AppKeyboardScope] — a raiz já sobe com o IME.
Widget wrapKeyboardAwareDialog(BuildContext context, Widget dialog) => dialog;

/// Margem padrão para `AlertDialog`.
EdgeInsets keyboardAwareDialogInsetPadding(BuildContext context) =>
    const EdgeInsets.all(16);

/// Conteúdo rolável de diálogo com altura máxima segura.
class KeyboardAwareDialogScrollBody extends StatelessWidget {
  const KeyboardAwareDialogScrollBody({
    super.key,
    required this.child,
    this.maxHeightFactor = 0.62,
    this.extraBottom = 12,
  });

  final Widget child;
  final double maxHeightFactor;
  final double extraBottom;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * maxHeightFactor;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.only(bottom: extraBottom),
        child: child,
      ),
    );
  }
}

/// Rodapé fixo de formulário (a raiz [AppKeyboardScope] já empurra a tela).
class KeyboardAwareFormBar extends StatelessWidget {
  const KeyboardAwareFormBar({
    super.key,
    required this.child,
    this.backgroundColor = Colors.white,
    this.elevation = 12,
    this.standaloneFullPageForm = false,
  });

  final Widget child;
  final Color backgroundColor;
  final double elevation;
  final bool standaloneFullPageForm;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: elevation,
      color: backgroundColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: child,
        ),
      ),
    );
  }
}
