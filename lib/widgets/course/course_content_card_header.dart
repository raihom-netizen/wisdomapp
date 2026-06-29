import 'package:flutter/material.dart';

/// Faixa superior colorida (gradiente) nos cards de curso/dica — admin e módulo Cursos.
class CourseContentCardHeader extends StatelessWidget {
  const CourseContentCardHeader({
    super.key,
    required this.title,
    required this.accent,
    required this.accent2,
    this.icon = Icons.movie_creation_rounded,
    this.subtitle,
    this.trailing,
    this.topBadges = const [],
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final Color accent;
  final Color accent2;
  final IconData icon;
  final Widget? trailing;
  final List<Widget> topBadges;
  final bool compact;

  static const cardGradients = <List<Color>>[
    [Color(0xFF2563EB), Color(0xFF1D4ED8)],
    [Color(0xFF0F766E), Color(0xFF14B8A6)],
    [Color(0xFF7C3AED), Color(0xFFA855F7)],
    [Color(0xFFF59E0B), Color(0xFFD97706)],
    [Color(0xFF4338CA), Color(0xFF6366F1)],
    [Color(0xFFBE123C), Color(0xFFE11D48)],
    [Color(0xFF047857), Color(0xFF10B981)],
  ];

  static (Color, Color) colorsFor({
    required String type,
    int index = 0,
  }) {
    if (type == 'dica') {
      return (const Color(0xFFF59E0B), const Color(0xFFD97706));
    }
    final grad = cardGradients[index % cardGradients.length];
    return (grad[0], grad[1]);
  }

  static IconData iconForType(String type) {
    return type == 'dica' ? Icons.lightbulb_rounded : Icons.school_rounded;
  }

  static Widget badge(
    String label, {
    Color? bg,
    Color text = Colors.white,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg ?? Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 12,
        compact ? 8 : 10,
        compact ? 10 : 12,
        compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent, accent2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(compact ? 6 : 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(compact ? 10 : 12),
            ),
            child: Icon(icon, color: Colors.white, size: compact ? 18 : 22),
          ),
          SizedBox(width: compact ? 8 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (topBadges.isNotEmpty) ...[
                  Wrap(spacing: 4, runSpacing: 4, children: topBadges),
                  SizedBox(height: compact ? 3 : 4),
                ],
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: compact ? 12 : 14,
                    height: 1.2,
                    letterSpacing: compact ? 0.1 : 0.2,
                  ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontWeight: FontWeight.w600,
                      fontSize: compact ? 10 : 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
