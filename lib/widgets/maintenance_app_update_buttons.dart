import 'package:flutter/material.dart';

import '../utils/maintenance_app_update_links.dart';
import '../utils/url_launcher_helper.dart';

/// Botões modernos de atualização — só Play (Android) ou só TestFlight (iOS).
class MaintenanceAppUpdateButtons extends StatelessWidget {
  final MaintenanceAppUpdateLinks links;
  final bool compact;
  final Color? androidForegroundOnLight;
  final Color? iosForegroundOnLight;

  const MaintenanceAppUpdateButtons({
    super.key,
    required this.links,
    this.compact = false,
    this.androidForegroundOnLight,
    this.iosForegroundOnLight,
  });

  Future<void> _open(BuildContext context, String url, String platform) async {
    try {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              platform == 'ios' ? 'Abrindo TestFlight…' : 'Abrindo Google Play…',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      await openUrlPreferChrome(url);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o link.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!links.hasAnyButton) return const SizedBox.shrink();

    final children = <Widget>[];
    if (links.showAndroidButton) {
      children.add(
        _StoreUpdateButton(
          compact: compact,
          icon: Icons.shop_rounded,
          label: 'Atualizar na Google Play',
          subtitle: 'Versão mais recente com melhorias',
          gradient: const [Color(0xFF34A853), Color(0xFF1B8E3E)],
          foreground: Colors.white,
          onPressed: () => _open(context, links.androidUrl, 'android'),
        ),
      );
    }
    if (links.showIosButton) {
      if (children.isNotEmpty) children.add(SizedBox(height: compact ? 8 : 10));
      children.add(
        _StoreUpdateButton(
          compact: compact,
          icon: Icons.apple_rounded,
          label: 'Atualizar no TestFlight',
          subtitle: 'Instale a build mais recente no iPhone',
          gradient: const [Color(0xFF2C2C2E), Color(0xFF000000)],
          foreground: Colors.white,
          onPressed: () => _open(context, links.iosUrl, 'ios'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _StoreUpdateButton extends StatelessWidget {
  final bool compact;
  final IconData icon;
  final String label;
  final String subtitle;
  final List<Color> gradient;
  final Color foreground;
  final VoidCallback onPressed;

  const _StoreUpdateButton({
    required this.compact,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.gradient,
    required this.foreground,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      elevation: compact ? 0 : 2,
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: gradient.last.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 14 : 18,
              vertical: compact ? 12 : 16,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: foreground, size: compact ? 22 : 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.w800,
                          fontSize: compact ? 14 : 15,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: foreground.withValues(alpha: 0.88),
                          fontSize: compact ? 11 : 12,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: foreground.withValues(alpha: 0.9),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Variante para banner escuro (Início): fundo claro nos botões.
class MaintenanceAppUpdateButtonsOnDarkBanner extends StatelessWidget {
  final MaintenanceAppUpdateLinks links;

  const MaintenanceAppUpdateButtonsOnDarkBanner({super.key, required this.links});

  @override
  Widget build(BuildContext context) {
    return MaintenanceAppUpdateButtons(
      links: links,
      compact: true,
    );
  }
}
