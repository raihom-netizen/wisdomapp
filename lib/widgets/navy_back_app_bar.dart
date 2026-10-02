import 'package:flutter/material.dart';

/// Azul-marinho das barras de topo das páginas em tela cheia (Financeiro/Início).
const Color kAppNavyBar = Color(0xFF0D1B4C);

/// Volta para a tela anterior; aberta por link direto (sem tela anterior)
/// volta ao início do app. Respeita o [PopScope] da página (ex.: «descartar
/// alterações?»), a não ser que [bypassPopScope] seja true — use isso só
/// quando o próprio PopScope chama esta função (senão entra em laço).
void navyPopOrGoHome(
  BuildContext context, {
  Object? result,
  bool bypassPopScope = false,
}) {
  final nav = Navigator.of(context);
  if (nav.canPop()) {
    if (bypassPopScope) {
      nav.pop(result);
    } else {
      nav.maybePop(result);
    }
    return;
  }
  nav.pushNamedAndRemoveUntil('/', (_) => false);
}

/// Botão «← Voltar» com texto branco — para barras azul-marinho.
class NavyBackButton extends StatelessWidget {
  const NavyBackButton({super.key, this.onPressed});

  /// Padrão: [navyPopOrGoHome].
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: onPressed ?? () => navyPopOrGoHome(context),
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        label: const Text(
          'Voltar',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

/// AppBar padrão: fundo azul-marinho, texto/ícones brancos e «← Voltar».
PreferredSizeWidget navyBackAppBar(
  BuildContext context, {
  String? titleText,
  Widget? title,
  List<Widget>? actions,
  PreferredSizeWidget? bottom,
  VoidCallback? onBack,
  bool showBack = true,
  double? toolbarHeight,
}) {
  return AppBar(
    backgroundColor: kAppNavyBar,
    foregroundColor: Colors.white,
    iconTheme: const IconThemeData(color: Colors.white),
    actionsIconTheme: const IconThemeData(color: Colors.white),
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
    elevation: 0,
    toolbarHeight: toolbarHeight,
    automaticallyImplyLeading: false,
    leadingWidth: showBack ? 118 : null,
    leading: showBack ? NavyBackButton(onPressed: onBack) : null,
    titleSpacing: showBack ? 4 : null,
    titleTextStyle: const TextStyle(
      color: Colors.white,
      fontSize: 18,
      fontWeight: FontWeight.w800,
    ),
    title: title ??
        (titleText == null
            ? null
            : Text(titleText, maxLines: 1, overflow: TextOverflow.ellipsis)),
    actions: actions,
    bottom: bottom,
  );
}

/// Botão «← Voltar» visível no topo de painéis que sobem (bottom sheets):
/// pílula azul-marinho com texto branco, legível no tema claro e no escuro.
class SheetBackButton extends StatelessWidget {
  const SheetBackButton({super.key, this.onPressed});

  /// Padrão: fecha o painel.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: kAppNavyBar,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed ?? () => Navigator.of(context).maybePop(),
          child: const Padding(
            padding: EdgeInsets.fromLTRB(10, 6, 14, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_rounded, color: Colors.white, size: 18),
                SizedBox(width: 6),
                Text(
                  'Voltar',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
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
