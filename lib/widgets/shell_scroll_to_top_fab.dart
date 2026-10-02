import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Botão verde «voltar ao topo» — mesmo visual e comportamento do Controle Total
/// (Android, iOS e Web). Aparece depois de rolar [showAfter] px e anima até o topo.
class ShellScrollToTopFab extends StatefulWidget {
  const ShellScrollToTopFab({
    super.key,
    required this.controller,
    this.showAfter = 100,
  });

  final ScrollController controller;

  /// Exibe o botão após rolar esta distância (px).
  final double showAfter;

  @override
  State<ShellScrollToTopFab> createState() => _ShellScrollToTopFabState();
}

class _ShellScrollToTopFabState extends State<ShellScrollToTopFab> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void didUpdateWidget(ShellScrollToTopFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final c = widget.controller;
    if (c.positions.length != 1) {
      if (_visible && mounted) setState(() => _visible = false);
      return;
    }
    final show = c.offset > widget.showAfter;
    if (show != _visible && mounted) {
      setState(() => _visible = show);
    }
  }

  Future<void> _scrollToTop() async {
    final c = widget.controller;
    if (c.positions.length != 1) return;
    await scrollPositionToTop(c.position);
  }

  @override
  Widget build(BuildContext context) {
    return ScrollToTopButton(visible: _visible, onTap: _scrollToTop);
  }
}

/// Scroll rápido ao topo — salto instantâneo em listas muito longas.
Future<void> scrollPositionToTop(ScrollPosition position) async {
  final offset = position.pixels;
  final min = position.minScrollExtent;
  if (offset <= min) return;
  if (offset - min > 2200) {
    position.jumpTo(min);
    return;
  }
  await position.animateTo(
    min,
    duration: Duration(milliseconds: offset > 900 ? 200 : 160),
    curve: Curves.easeOutCubic,
  );
}

/// Visual do botão (círculo verde com seta) — igual ao do Controle Total.
class ScrollToTopButton extends StatelessWidget {
  const ScrollToTopButton({
    super.key,
    required this.visible,
    required this.onTap,
  });

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Voltar ao topo',
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          child: AnimatedScale(
            scale: visible ? 1 : 0.88,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: Material(
              color: Colors.transparent,
              elevation: visible ? 8 : 0,
              shadowColor: AppColors.success.withValues(alpha: 0.45),
              shape: const CircleBorder(),
              child: InkWell(
                onTap: visible ? onTap : null,
                customBorder: const CircleBorder(),
                child: Ink(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF4ADE80),
                        AppColors.success,
                        Color(0xFF16A34A),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.success.withValues(alpha: 0.48),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.55),
                      width: 1.2,
                    ),
                  ),
                  child: const Icon(
                    Icons.keyboard_arrow_up_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Envolve uma área com rolagem e coloca o botão «voltar ao topo» no canto
/// inferior direito. Descobre sozinho o scroll principal (vertical mais externo)
/// pelas notificações de rolagem — serve para módulos sem [ScrollController]
/// próprio. Se [controller] vier e estiver ligado a uma única lista, ele manda.
class ScrollToTopArea extends StatefulWidget {
  const ScrollToTopArea({
    super.key,
    required this.child,
    this.controller,
    this.resetToken,
    this.showAfter = 100,
    this.right = 12,
    this.bottom = 12,
    this.addBottomSafeArea = false,
  });

  final Widget child;
  final ScrollController? controller;

  /// Quando muda (ex.: troca de módulo/aba), esquece a lista acompanhada.
  final Object? resetToken;
  final double showAfter;
  final double right;
  final double bottom;

  /// Soma o inset inferior do aparelho (telas sem rodapé próprio).
  final bool addBottomSafeArea;

  @override
  State<ScrollToTopArea> createState() => _ScrollToTopAreaState();
}

class _ScrollToTopAreaState extends State<ScrollToTopArea> {
  BuildContext? _trackedContext;
  int _trackedDepth = 1 << 30;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerScroll);
  }

  @override
  void didUpdateWidget(ScrollToTopArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerScroll);
      widget.controller?.addListener(_onControllerScroll);
    }
    if (oldWidget.resetToken != widget.resetToken) {
      _trackedContext = null;
      _trackedDepth = 1 << 30;
      _visible = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _onControllerScroll());
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerScroll);
    super.dispose();
  }

  ScrollController? get _singleController {
    final c = widget.controller;
    if (c != null && c.positions.length == 1) return c;
    return null;
  }

  void _setVisible(bool v) {
    if (v != _visible && mounted) setState(() => _visible = v);
  }

  void _onControllerScroll() {
    final c = _singleController;
    if (c == null) return;
    _setVisible(c.offset > widget.showAfter);
  }

  bool _onNotification(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final ctx = n.context;
    if (ctx == null) return false;
    if (_singleController != null) return false;
    final tracked = _trackedContext;
    final trackedAlive = tracked != null && tracked.mounted;
    if (!trackedAlive || n.depth <= _trackedDepth) {
      _trackedContext = ctx;
      _trackedDepth = n.depth;
    }
    if (identical(_trackedContext, ctx)) {
      _setVisible(n.metrics.pixels - n.metrics.minScrollExtent >
          widget.showAfter);
    }
    return false;
  }

  Future<void> _scrollToTop() async {
    final c = _singleController;
    if (c != null) {
      await scrollPositionToTop(c.position);
      return;
    }
    final ctx = _trackedContext;
    if (ctx == null || !ctx.mounted) return;
    final pos = Scrollable.maybeOf(ctx)?.position;
    if (pos == null) return;
    await scrollPositionToTop(pos);
  }

  @override
  Widget build(BuildContext context) {
    final extra =
        widget.addBottomSafeArea ? MediaQuery.paddingOf(context).bottom : 0.0;
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onNotification,
          child: widget.child,
        ),
        Positioned(
          right: widget.right,
          bottom: widget.bottom + extra,
          child: ScrollToTopButton(visible: _visible, onTap: _scrollToTop),
        ),
      ],
    );
  }
}
