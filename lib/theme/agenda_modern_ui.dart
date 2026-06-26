import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Urgência visual: 🔴 urgente · 🟡 hoje · 🔵 informativo · 🟢 concluído
enum AgendaUrgencyTier {
  urgent,
  today,
  info,
  completed,
}

/// Status de audiência na lista.
enum AgendaAudienciaVisualStatus {
  pendente,
  confirmada,
  cancelada,
}

class AgendaUrgencyStyle {
  const AgendaUrgencyStyle({
    required this.tier,
    required this.color,
    required this.icon,
    required this.label,
    required this.emoji,
  });

  final AgendaUrgencyTier tier;
  final Color color;
  final IconData icon;
  final String label;
  final String emoji;
}

/// Design system moderno — notificações, e-mail, agenda, audiências.
class AgendaModernUI {
  AgendaModernUI._();

  static const Duration fadeDuration = Duration(milliseconds: 280);
  static const Curve fadeCurve = Curves.easeOutCubic;

  static AgendaUrgencyStyle styleFor(AgendaUrgencyTier tier) => switch (tier) {
        AgendaUrgencyTier.urgent => AgendaUrgencyStyle(
            tier: tier,
            color: const Color(0xFFDC2626),
            icon: Icons.priority_high_rounded,
            label: 'Urgente',
            emoji: '🔴',
          ),
        AgendaUrgencyTier.today => AgendaUrgencyStyle(
            tier: tier,
            color: const Color(0xFFEAB308),
            icon: Icons.today_rounded,
            label: 'Hoje',
            emoji: '🟡',
          ),
        AgendaUrgencyTier.info => AgendaUrgencyStyle(
            tier: tier,
            color: const Color(0xFF2563EB),
            icon: Icons.info_outline_rounded,
            label: 'Informativo',
            emoji: '🔵',
          ),
        AgendaUrgencyTier.completed => AgendaUrgencyStyle(
            tier: tier,
            color: const Color(0xFF16A34A),
            icon: Icons.check_circle_rounded,
            label: 'Concluído',
            emoji: '🟢',
          ),
      };

  static AgendaUrgencyTier urgencyFromEventAt(DateTime? eventAt, {bool done = false}) {
    if (done) return AgendaUrgencyTier.completed;
    if (eventAt == null) return AgendaUrgencyTier.info;
    final now = DateTime.now();
    if (eventAt.isBefore(now.subtract(const Duration(hours: 1)))) {
      return AgendaUrgencyTier.urgent;
    }
    final sameDay = eventAt.year == now.year &&
        eventAt.month == now.month &&
        eventAt.day == now.day;
    if (sameDay) return AgendaUrgencyTier.today;
    if (eventAt.difference(now).inHours <= 3) return AgendaUrgencyTier.urgent;
    return AgendaUrgencyTier.info;
  }

  static AgendaUrgencyTier urgencyFromNotifyAt(
    DateTime notifyAt, {
    required bool isSent,
    required bool isPending,
  }) {
    if (isSent) return AgendaUrgencyTier.completed;
    if (!isPending) return AgendaUrgencyTier.info;
    final now = DateTime.now();
    if (!notifyAt.isAfter(now)) return AgendaUrgencyTier.urgent;
    final sameDay = notifyAt.year == now.year &&
        notifyAt.month == now.month &&
        notifyAt.day == now.day;
    if (sameDay) return AgendaUrgencyTier.today;
    return AgendaUrgencyTier.info;
  }

  static AgendaAudienciaVisualStatus audienciaStatus(Map<String, dynamic> data) {
    final st = (data['status'] ?? 'EM_ABERTO').toString().toUpperCase();
    if (st == 'REALIZADO') return AgendaAudienciaVisualStatus.confirmada;
    if (st.contains('CANCEL')) return AgendaAudienciaVisualStatus.cancelada;
    return AgendaAudienciaVisualStatus.pendente;
  }

  static ({Color color, String label, IconData icon}) audienciaStatusStyle(
    AgendaAudienciaVisualStatus s,
  ) =>
      switch (s) {
        AgendaAudienciaVisualStatus.confirmada => (
            color: const Color(0xFF16A34A),
            label: 'Confirmada',
            icon: Icons.check_circle_rounded,
          ),
        AgendaAudienciaVisualStatus.pendente => (
            color: const Color(0xFFEAB308),
            label: 'Pendente',
            icon: Icons.schedule_rounded,
          ),
        AgendaAudienciaVisualStatus.cancelada => (
            color: const Color(0xFFDC2626),
            label: 'Cancelada',
            icon: Icons.cancel_rounded,
          ),
      };

  static BoxDecoration modernCardDecoration({
    required Color accent,
    AgendaUrgencyTier? urgency,
    bool elevated = true,
  }) {
    final border = urgency != null
        ? styleFor(urgency).color.withValues(alpha: 0.45)
        : accent.withValues(alpha: 0.18);
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: border, width: urgency != null ? 2 : 1.5),
      boxShadow: elevated
          ? [
              BoxShadow(
                color: accent.withValues(alpha: 0.1),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ]
          : null,
    );
  }

  static Widget sectionHeader({
    required String title,
    required IconData icon,
    required Color color,
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: AppColors.deepBlueDark,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge de urgência (notificações / cards).
class AgendaUrgencyBadge extends StatelessWidget {
  const AgendaUrgencyBadge({
    super.key,
    required this.tier,
    this.compact = false,
  });

  final AgendaUrgencyTier tier;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = AgendaModernUI.styleFor(tier);
    return Container(
      constraints: const BoxConstraints(minHeight: 26),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: s.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: s.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!compact) Text(s.emoji, style: const TextStyle(fontSize: 11)),
          if (!compact) const SizedBox(width: 4),
          Icon(s.icon, size: 13, color: s.color),
          const SizedBox(width: 4),
          Text(
            s.label,
            style: TextStyle(
              fontSize: compact ? 9 : 10,
              fontWeight: FontWeight.w800,
              color: s.color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Status audiência: 🟢 Confirmada · 🟡 Pendente · 🔴 Cancelada
class AgendaAudienciaStatusBadge extends StatelessWidget {
  const AgendaAudienciaStatusBadge({
    super.key,
    required this.status,
  });

  final AgendaAudienciaVisualStatus status;

  @override
  Widget build(BuildContext context) {
    final s = AgendaModernUI.audienciaStatusStyle(status);
    final emoji = switch (status) {
      AgendaAudienciaVisualStatus.confirmada => '🟢',
      AgendaAudienciaVisualStatus.pendente => '🟡',
      AgendaAudienciaVisualStatus.cancelada => '🔴',
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 26),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: s.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: s.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          Icon(s.icon, size: 13, color: s.color),
          const SizedBox(width: 4),
          Text(
            s.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: s.color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Entrada suave em listas/grids.
class AgendaModernFadeIn extends StatefulWidget {
  const AgendaModernFadeIn({
    super.key,
    required this.child,
    this.index = 0,
  });

  final Widget child;
  final int index;

  @override
  State<AgendaModernFadeIn> createState() => _AgendaModernFadeInState();
}

class _AgendaModernFadeInState extends State<AgendaModernFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: AgendaModernUI.fadeDuration,
    );
    _fade = CurvedAnimation(parent: _c, curve: AgendaModernUI.fadeCurve);
    _scale = Tween<double>(begin: 0.96, end: 1).animate(_fade);
    Future<void>.delayed(
      Duration(milliseconds: 40 * (widget.index % 8)),
      () {
        if (mounted) _c.forward();
      },
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

/// Preview visual dos templates de e-mail (conteúdo real vem do servidor).
class AgendaEmailTemplatePreview extends StatelessWidget {
  const AgendaEmailTemplatePreview({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.actions,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final List<String> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: gradient.last.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 12,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: actions
                  .map(
                    (a) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        a,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}
