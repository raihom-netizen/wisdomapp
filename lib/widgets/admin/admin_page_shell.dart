import 'package:flutter/material.dart';

import '../../utils/admin_responsive.dart';

/// Fundo e layout padrão do painel admin (iOS, Android, web instalável).
class AdminPageShell {
  AdminPageShell._();

  static const Color background = Color(0xFFF2F4F8);

  /// Padding horizontal + inferior (home indicator / barra gestos).
  static EdgeInsets pagePadding(BuildContext context, {double top = 0}) {
    final h = AdminResponsive.horizontalPadding(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return EdgeInsets.fromLTRB(h, top, h, 12 + bottom);
  }

  /// Para [ListView]/[CustomScrollView] dentro do painel.
  static EdgeInsets listPadding(BuildContext context, {double top = 0}) =>
      pagePadding(context, top: top);

  /// Envolve o módulo ativo: ocupa toda a área abaixo do cabeçalho do admin.
  static Widget wrap({
    required BuildContext context,
    required Widget child,
    bool centerOnWideWeb = true,
  }) {
    return ColoredBox(
      color: background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          Widget body = child;
          if (centerOnWideWeb && constraints.maxWidth > 1280) {
            body = Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 1280,
                  minHeight: constraints.maxHeight,
                  maxHeight: constraints.maxHeight,
                ),
                child: child,
              ),
            );
          }
          return SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: body,
          );
        },
      ),
    );
  }
}

/// Lista admin com rolagem e padding padrão (full height no [Expanded] pai).
class AdminScrollPage extends StatelessWidget {
  final List<Widget> children;
  final double topPadding;
  final ScrollPhysics? physics;

  const AdminScrollPage({
    super.key,
    required this.children,
    this.topPadding = 0,
    this.physics,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: physics ?? const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: AdminPageShell.listPadding(context, top: topPadding),
      children: children,
    );
  }
}
