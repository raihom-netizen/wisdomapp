import 'package:flutter/material.dart';

import 'pwa_install.dart';

/// Card "Toque para instalar": Android/Chrome = 1 toque (prompt nativo); iPhone = modal com 3 passos.
/// Some quando já estiver instalado (standalone).
class InstallPwaCard extends StatefulWidget {
  /// Exibir o card (ex.: quando não está em standalone e usuário não dispensou).
  final bool visible;

  /// Chamado quando o usuário dispensa o card (opcional).
  final VoidCallback? onDismiss;

  const InstallPwaCard({
    super.key,
    this.visible = true,
    this.onDismiss,
  });

  @override
  State<InstallPwaCard> createState() => _InstallPwaCardState();
}

class _InstallPwaCardState extends State<InstallPwaCard> {
  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    if (PwaInstall.supported && PwaInstall.isInstalled) return const SizedBox.shrink();
    if (!PwaInstall.supported) return const SizedBox.shrink();
    if (!PwaInstall.isIos && !PwaInstall.canPrompt) {
      return const SizedBox.shrink();
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _onInstallTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Color(0xFF0B3B6F), Color(0xFF15B8A6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: const [
              BoxShadow(blurRadius: 16, offset: Offset(0, 8), color: Color(0x22000000)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.20),
                  borderRadius: BorderRadius.circular(14),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  'assets/images/icon.png',
                  width: 46,
                  height: 46,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.install_mobile_rounded, color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Instalar app',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Abre como um app pelo ícone na tela inicial — mais rápido no dia a dia. Android/Chrome: um toque; iPhone: passo a passo no Safari.',
                      style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.25),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Instalar',
                  style: TextStyle(
                    color: Color(0xFF0B3B6F),
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              if (widget.onDismiss != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
                  onPressed: widget.onDismiss,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showIosHowTo() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 6),
                const Text(
                  'Instalar no iPhone',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                _step('1', 'Toque no botão "Compartilhar" do Safari (quadrado com seta pra cima).'),
                _step('2', 'Role e toque em "Adicionar à Tela de Início".'),
                _step('3', 'Confirme em "Adicionar".'),
                const SizedBox(height: 10),
                const Text(
                  'No iPhone o Safari não permite instalação com 1 clique.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _step(String n, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              n,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Future<void> _onInstallTap() async {
    if (PwaInstall.isInstalled) {
      if (mounted) setState(() {});
      return;
    }

    if (PwaInstall.isIos) {
      _showIosHowTo();
      return;
    }

    if (!PwaInstall.canPrompt) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Instalação ainda não disponível. Aguarde e tente novamente.'),
          ),
        );
      }
      return;
    }

    final outcome = await PwaInstall.promptInstall();
    if (!mounted) return;

    if (outcome == 'accepted') {
      setState(() {});
    }
  }
}
