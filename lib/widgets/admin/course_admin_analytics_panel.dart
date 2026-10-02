import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/course_analytics_service.dart';

/// Painel moderno de métricas — visualizações, curtidas e gráfico de engajamento.
class CourseAdminAnalyticsPanel extends StatelessWidget {
  const CourseAdminAnalyticsPanel({
    super.key,
    required this.stats,
    required this.courseTitles,
    this.onOpenViewers,
  });

  final List<CourseStatSummary> stats;
  final Map<String, String> courseTitles;
  final void Function(String courseId, String title)? onOpenViewers;

  int get _totalViews => stats.fold<int>(0, (s, e) => s + e.viewCount);

  int get _totalLikes => stats.fold<int>(0, (s, e) => s + e.likeCount);

  int get _totalPlays => stats.fold<int>(0, (s, e) => s + e.playCount);

  List<CourseStatSummary> get _topByViews {
    final list = List<CourseStatSummary>.from(stats)
      ..sort((a, b) => b.viewCount.compareTo(a.viewCount));
    return list.take(6).toList();
  }

  Map<String, int> get _last7Days {
    final out = <String, int>{};
    final now = DateTime.now();
    for (var i = 6; i >= 0; i--) {
      final d =
          DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final key = DateFormat('yyyy-MM-dd').format(d);
      out[key] = 0;
    }
    for (final s in stats) {
      for (final e in s.daily.entries) {
        if (out.containsKey(e.key)) {
          out[e.key] = out[e.key]! + e.value;
        }
      }
    }
    return out;
  }

  String _labelFor(CourseStatSummary s) {
    final t = (s.title.isNotEmpty
            ? s.title
            : (courseTitles[s.courseId] ?? 'Conteúdo'))
        .trim();
    if (t.length <= 16) return t;
    return '${t.substring(0, 14)}…';
  }

  @override
  Widget build(BuildContext context) {
    final days = _last7Days;
    final dayKeys = days.keys.toList();
    final dayValues = dayKeys.map((k) => days[k]!.toDouble()).toList();
    final maxDay = dayValues.isEmpty
        ? 1.0
        : dayValues.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);
    final top = _topByViews;
    final maxViews = top.isEmpty
        ? 1.0
        : top
            .map((e) => e.viewCount.toDouble())
            .reduce((a, b) => a > b ? a : b)
            .clamp(1.0, double.infinity);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF141414), Color(0xFF1C1C28), Color(0xFF0F0F0F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF0000).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.insights_rounded,
                  color: Color(0xFFFF0000),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Controle de audiência',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Quem assistiu, curtiu e a evolução dos últimos 7 dias',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  icon: Icons.visibility_rounded,
                  label: 'Assistiram',
                  value: '$_totalViews',
                  color: const Color(0xFF3B82F6),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricTile(
                  icon: Icons.thumb_up_alt_rounded,
                  label: 'Curtidas',
                  value: '$_totalLikes',
                  color: const Color(0xFFFF0000),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricTile(
                  icon: Icons.play_circle_rounded,
                  label: 'Reproduções',
                  value: '$_totalPlays',
                  color: const Color(0xFFF59E0B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Atividade · 7 dias',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 160,
            child: dayValues.every((v) => v == 0)
                ? _emptyChart(
                    'Ainda sem visualizações registradas.\nQuando usuários assistirem, o gráfico aparece aqui.',
                  )
                : LineChart(
                    LineChartData(
                      minY: 0,
                      maxY: maxDay * 1.25,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (v) => FlLine(
                          color: Colors.white.withValues(alpha: 0.06),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            getTitlesWidget: (v, _) => Text(
                              v.toInt().toString(),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.35),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (v, _) {
                              final i = v.toInt();
                              if (i < 0 || i >= dayKeys.length) {
                                return const SizedBox.shrink();
                              }
                              final label = DateFormat('E', 'pt_BR')
                                  .format(DateTime.parse(dayKeys[i]));
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  label.substring(0, 1).toUpperCase(),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            for (var i = 0; i < dayValues.length; i++)
                              FlSpot(i.toDouble(), dayValues[i]),
                          ],
                          isCurved: true,
                          barWidth: 3.5,
                          color: const Color(0xFFFF0000),
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                              radius: 3.5,
                              color: Colors.white,
                              strokeWidth: 2,
                              strokeColor: const Color(0xFFFF0000),
                            ),
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFFFF0000).withValues(alpha: 0.35),
                                const Color(0xFFFF0000).withValues(alpha: 0.02),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Top conteúdos por quem assistiu',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 180,
            child: top.isEmpty || top.every((e) => e.viewCount == 0)
                ? _emptyChart(
                    'Publique e compartilhe cursos para ver o ranking.')
                : BarChart(
                    BarChartData(
                      maxY: maxViews * 1.2,
                      alignment: BarChartAlignment.spaceAround,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (v) => FlLine(
                          color: Colors.white.withValues(alpha: 0.05),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 36,
                            getTitlesWidget: (v, _) {
                              final i = v.toInt();
                              if (i < 0 || i >= top.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  _labelFor(top[i]),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < top.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: top[i].viewCount.toDouble(),
                                width: 16,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6),
                                ),
                                gradient: LinearGradient(
                                  colors: top[i].type == 'dica'
                                      ? const [
                                          Color(0xFFF59E0B),
                                          Color(0xFFD97706),
                                        ]
                                      : const [
                                          Color(0xFFFF0000),
                                          Color(0xFFEF4444),
                                        ],
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                ),
                              ),
                            ],
                          ),
                      ],
                      barTouchData: BarTouchData(
                        touchCallback: (event, response) {
                          if (!event.isInterestedForInteractions) return;
                          final spot = response?.spot;
                          if (spot == null) return;
                          final i = spot.touchedBarGroupIndex;
                          if (i < 0 || i >= top.length) return;
                          onOpenViewers?.call(
                            top[i].courseId,
                            top[i].title.isNotEmpty
                                ? top[i].title
                                : (courseTitles[top[i].courseId] ?? 'Conteúdo'),
                          );
                        },
                      ),
                    ),
                  ),
          ),
          if (top.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Toque numa barra para ver quem assistiu / curtiu',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyChart(String msg) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Text(
        msg,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.45),
          fontWeight: FontWeight.w600,
          height: 1.35,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sheet com lista de quem assistiu / curtiu um curso.
Future<void> showCourseViewersSheet(
  BuildContext context, {
  required String courseId,
  required String title,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF121212),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.groups_rounded,
                      color: Color(0xFFFF0000), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const Text(
                          'Usuários que assistiram / curtiram',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _CourseViewersList(courseId: courseId, scroll: scroll),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Lista de quem assistiu: escuta criada UMA vez no State (antes era
/// recriada a cada rebuild do DraggableScrollableSheet) e erro visível com
/// «Tentar de novo» (antes a falha virava «Ninguém assistiu» — 02/10/2026).
class _CourseViewersList extends StatefulWidget {
  const _CourseViewersList({required this.courseId, required this.scroll});

  final String courseId;
  final ScrollController scroll;

  @override
  State<_CourseViewersList> createState() => _CourseViewersListState();
}

class _CourseViewersListState extends State<_CourseViewersList> {
  late Stream<List<CourseViewerRow>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = CourseAnalyticsService.instance.watchViewers(widget.courseId);
  }

  void _tentarDeNovo() {
    setState(() {
      _stream = CourseAnalyticsService.instance.watchViewers(widget.courseId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scroll = widget.scroll;
    return StreamBuilder<List<CourseViewerRow>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError && !snap.hasData) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: Colors.orangeAccent, size: 36),
                  const SizedBox(height: 10),
                  Text(
                    'Não deu para carregar quem assistiu.\n${snap.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _tentarDeNovo,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Tentar de novo'),
                  ),
                ],
              ),
            ),
          );
        }
        final rows = snap.data ?? const [];
        if (snap.connectionState == ConnectionState.waiting && rows.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white54),
          );
        }
        if (rows.isEmpty) {
          return Center(
            child: Text(
              'Ninguém assistiu este conteúdo ainda.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }
        return ListView.separated(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final r = rows[i];
            final when = r.lastWatchedAt == null
                ? ''
                : DateFormat('dd/MM HH:mm').format(r.lastWatchedAt!);
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: r.liked
                        ? const Color(0xFFFF0000).withValues(alpha: 0.2)
                        : Colors.white12,
                    child: Icon(
                      r.liked
                          ? Icons.thumb_up_alt_rounded
                          : Icons.person_rounded,
                      color: r.liked ? const Color(0xFFFF0000) : Colors.white70,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.name.isEmpty ? r.uid : r.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (r.liked) 'Curtiu',
                            if (r.watchCount > 0) '${r.watchCount}x assistiu',
                            if (when.isNotEmpty) when,
                          ].join(' · '),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (r.progressFraction > 0.02) ...[
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: r.progressFraction,
                              minHeight: 4,
                              backgroundColor: Colors.white12,
                              color: const Color(0xFF3B82F6),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
