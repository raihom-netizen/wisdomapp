import 'package:flutter/material.dart';

import '../utils/compromisso_contact_links.dart';

/// Chips modernos de localização e WhatsApp nos cartões de compromisso.
/// Aparece no resumo do dia/mês, painel inicial e central de notificações.
class CompromissoContactChips extends StatelessWidget {
  const CompromissoContactChips({
    super.key,
    this.linkLocalizacao = '',
    this.contatoWhatsApp = '',
    this.compact = false,
  });

  final String linkLocalizacao;
  final String contatoWhatsApp;
  final bool compact;

  bool get hasAny =>
      linkLocalizacao.trim().isNotEmpty || contatoWhatsApp.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final loc = linkLocalizacao.trim();
    final wa = contatoWhatsApp.trim();
    if (loc.isEmpty && wa.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: compact ? 6 : 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (loc.isNotEmpty)
            _ContactChip(
              icon: Icons.location_on_rounded,
              label: CompromissoContactLinks.locationDisplayLabel(loc),
              subtitle: 'Localização',
              gradient: const [Color(0xFF1D4ED8), Color(0xFF38BDF8)],
              onTap: () => CompromissoContactLinks.openLocation(loc),
              compact: compact,
            ),
          if (wa.isNotEmpty)
            _ContactChip(
              icon: Icons.chat_rounded,
              label: CompromissoContactLinks.whatsappDisplayLabel(wa),
              subtitle: 'WhatsApp',
              gradient: const [Color(0xFF128C7E), Color(0xFF25D366)],
              onTap: () => CompromissoContactLinks.openWhatsApp(wa),
              compact: compact,
            ),
        ],
      ),
    );
  }
}

class _ContactChip extends StatelessWidget {
  const _ContactChip({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
    required this.compact,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final List<Color> gradient;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final h = compact ? 44.0 : 48.0;
    final iconBox = compact ? 28.0 : 32.0;
    final iconSize = compact ? 13.0 : 15.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          height: h,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: gradient.first.withValues(alpha: 0.32),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 6 : 7,
              5,
              compact ? 12 : 14,
              5,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: iconBox,
                  height: iconBox,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    size: iconSize,
                    color: gradient.first,
                  ),
                ),
                SizedBox(width: compact ? 8 : 10),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: compact ? 160 : 200),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontWeight: FontWeight.w700,
                          fontSize: compact ? 9.5 : 10,
                          height: 1.05,
                          letterSpacing: 0.2,
                        ),
                      ),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: compact ? 12 : 13,
                          height: 1.1,
                        ),
                      ),
                    ],
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
