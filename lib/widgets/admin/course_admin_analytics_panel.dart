import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/course_analytics_service.dart';
import '../../theme/theme_context.dart';
import '../../utils/admin_load_guard.dart';

/// Painel moderno de métricas — visualizações, curtidas e gráfico de engajamento.
class CourseAdminAnalyticsPanel extends StatelessWidget {
  const CourseAdminAnalyticsPanel({
    super.key,
    required this.stats,
    required this.courseTitles,
    this.onOpenViewers,
    this.error,
  });

  final List<CourseStatSummary> stats;

  /// Falha ao ler `course_stats` (regra/rede) — mostrada no painel em vez de
  /// deixar os contadores em 0 como se não houvesse audiência.
  final Object? error;
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

    // Claro no modo claro, grafite só no escuro (antes era preto fixo).
    final dark = context.isDarkMode;
    final fg = dark ? Colors.white : context.appTextPrimary;
    Color fgA(double a) => dark
        ? Colors.white.withValues(alpha: a)
        : context.appTextPrimary.withValues(alpha: (a + 0.25).clamp(0.0, 1.0));
    final gridLine = dark
        ? Colors.white.withValues(alpha: 0.06)
        : context.appChipIdleBorder;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: dark
            ? const LinearGradient(
                colors: [
                  Color(0xFF141414),
                  Color(0xFF1C1C28),
                  Color(0xFF0F0F0F),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Colors.white, Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.08)
              : context.appChipIdleBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.35 : 0.06),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Controle de audiência',
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Quem assistiu, curtiu e a evolução dos últimos 7 dias',
                      style: TextStyle(
                        color: dark ? Colors.white54 : context.appTextSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration:
                  context.appInfoBannerDecoration(const Color(0xFFDC2626)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: Color(0xFFDC2626), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Não deu para ler a audiência — os números abaixo podem '
                      'estar zerados por isso.\n$error',
                      style: TextStyle(
                        color: fg,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
          Text(
            'Atividade · 7 dias',
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 160,
            child: dayValues.every((v) => v == 0)
                ? _emptyChart(
                    context,
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
                          color: gridLine,
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
                                color: fgA(0.35),
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
                                    color: fgA(0.45),
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
          Text(
            'Top conteúdos por quem assistiu',
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 180,
            child: top.isEmpty || top.every((e) => e.viewCount == 0)
                ? _emptyChart(
                    context,
                    'Publique e compartilhe cursos para ver o ranking.')
                : BarChart(
                    BarChartData(
                      maxY: maxViews * 1.2,
                      alignment: BarChartAlignment.spaceAround,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (v) => FlLine(
                          color: gridLine,
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
                                    color: fgA(0.5),
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
                color: fgA(0.4),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyChart(BuildContext context, String msg) {
    final dark = context.isDarkMode;
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.03)
            : context.appChipIdleBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.06)
              : context.appChipIdleBorder,
        ),
      ),
      child: Text(
        msg,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: dark
              ? Colors.white.withValues(alpha: 0.45)
              : context.appTextSecondary,
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
    final dark = context.isDarkMode;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        // No claro: tom claro da própria cor (azul/vermelho/âmbar) sobre branco.
        color: dark
            ? color.withValues(alpha: 0.1)
            : context.appAccentSurface(color, lightAlpha: 0.08),
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
            style: TextStyle(
              color: context.appTextPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: dark
                  ? Colors.white.withValues(alpha: 0.55)
                  : context.appTextSecondary,
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
      builder: (sheetCtx, scroll) => Container(
        decoration: BoxDecoration(
          color: sheetCtx.isDarkMode ? const Color(0xFF121212) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: sheetCtx.isDarkMode
                    ? Colors.white24
                    : sheetCtx.appChipIdleBorder,
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
                          style: TextStyle(
                            color: sheetCtx.appTextPrimary,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Usuários que assistiram / curtiram',
                          style: TextStyle(
                            color: sheetCtx.appTextSecondary,
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
    _stream = _escuta();
  }

  Stream<List<CourseViewerRow>> _escuta() => AdminLoadGuard.primeiroDadoComPrazo(
        CourseAnalyticsService.instance.watchViewers(widget.courseId),
        oQue: 'quem assistiu',
      );

  void _tentarDeNovo() {
    setState(() {
      _stream = _escuta();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scroll = widget.scroll;
    final dark = context.isDarkMode;
    Color fgA(double a) => dark
        ? Colors.white.withValues(alpha: a)
        : context.appTextPrimary.withValues(alpha: (a + 0.25).clamp(0.0, 1.0));
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
                    'Não deu para carregar quem assistiu.\n${AdminLoadGuard.mensagem(snap.error)}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: fgA(0.7),
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
          return Center(
            child: CircularProgressIndicator(
              color: dark ? Colors.white54 : context.appTextMuted,
            ),
          );
        }
        if (rows.isEmpty) {
          return Center(
            child: Text(
              'Ninguém assistiu este conteúdo ainda.',
              style: TextStyle(
                color: fgA(0.5),
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
                color: dark ? const Color(0xFF1A1A1A) : context.appChipIdleBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.06)
                      : context.appChipIdleBorder,
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: r.liked
                        ? const Color(0xFFFF0000).withValues(alpha: 0.2)
                        : (dark ? Colors.white12 : context.appChipIdleBorder),
                    child: Icon(
                      r.liked
                          ? Icons.thumb_up_alt_rounded
                          : Icons.person_rounded,
                      color: r.liked
                          ? const Color(0xFFFF0000)
                          : (dark ? Colors.white70 : context.appTextSecondary),
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
                          style: TextStyle(
                            color: context.appTextPrimary,
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
                            color: fgA(0.45),
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
                              backgroundColor: dark
                                  ? Colors.white12
                                  : context.appChipIdleBorder,
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
