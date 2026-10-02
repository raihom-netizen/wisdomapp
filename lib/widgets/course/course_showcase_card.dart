import 'package:flutter/material.dart';

import '../../services/course_progress_service.dart';
import '../../utils/course_lessons.dart';
import '../course_media_preview.dart';
import 'course_yt_palette.dart';

const _kRed = CourseYt.red;
const _kGreen = Color(0xFF22C55E);

/// Resumo de um curso para a vitrine (aulas, progresso, selos).
class CourseShowcaseInfo {
  CourseShowcaseInfo(this.data, CourseProgress progress)
      : lessonKeys = CourseLessons.keysOf(data),
        liked = progress.liked {
    fraction = progress.courseFraction(lessonKeys);
    done = progress.doneCount(lessonKeys);
    completed = progress.isCompleted(lessonKeys);
    started = progress.hasActivity;
    isNew = CourseLessons.isNew(data);
    lastOpenedMs = progress.lastOpenedMs;
    final declared = CourseLessons.declaredMinutes(data);
    if (declared != null) {
      durationLabel = CourseLessons.formatMinutes(declared);
    } else {
      var secs = 0.0;
      var all = lessonKeys.isNotEmpty;
      for (final k in lessonKeys) {
        final d = progress.lesson(k).durationSeconds;
        if (d > 0) {
          secs += d;
        } else {
          all = false;
        }
      }
      durationLabel = (all && secs > 0)
          ? CourseLessons.formatMinutes((secs / 60).ceil())
          : null;
    }
  }

  final Map<String, dynamic> data;
  final List<String> lessonKeys;
  final bool liked;
  late final double fraction;
  late final int done;
  late final bool completed;
  late final bool started;
  late final bool isNew;
  late final int lastOpenedMs;
  late final String? durationLabel;

  String get id => (data['id'] ?? '').toString();
  String get title => (data['title'] ?? 'Curso').toString();
  bool get inProgress => started && !completed;

  String get lessonsLabel {
    final n = lessonKeys.length;
    if (n == 0) return 'Vídeo';
    return '$n ${n == 1 ? 'aula' : 'aulas'}';
  }
}

/// Card moderno da vitrine — capa 16:9, selo Novo/Concluído, aulas, duração e progresso.
class CourseShowcaseCard extends StatelessWidget {
  const CourseShowcaseCard({
    super.key,
    required this.info,
    required this.onTap,
  });

  final CourseShowcaseInfo info;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: CourseYt.cardDecoration(context, radius: 16),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CourseMediaThumbnail.fromData(
                      info.data,
                      fit: BoxFit.cover,
                      showPlayButton: false,
                      fallback: const _CoverFallback(),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0xB3000000)],
                          stops: [0.45, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: info.completed
                          ? const _Seal(
                              label: 'CONCLUÍDO',
                              color: _kGreen,
                              icon: Icons.verified_rounded,
                            )
                          : (info.isNew
                              ? const _Seal(
                                  label: 'NOVO',
                                  color: _kRed,
                                  icon: Icons.fiber_new_rounded,
                                )
                              : const SizedBox.shrink()),
                    ),
                    if (info.liked)
                      const Positioned(
                        right: 8,
                        top: 8,
                        child: Icon(Icons.favorite_rounded,
                            color: Colors.white,
                            size: 18,
                            shadows: [Shadow(blurRadius: 6)]),
                      ),
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Row(
                        children: [
                          _Chip(
                              icon: Icons.video_library_rounded,
                              label: info.lessonsLabel),
                          if (info.durationLabel != null) ...[
                            const SizedBox(width: 6),
                            _Chip(
                                icon: Icons.schedule_rounded,
                                label: info.durationLabel!),
                          ],
                          const Spacer(),
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: _kRed,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                            child: Icon(
                              info.completed
                                  ? Icons.replay_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (info.fraction > 0)
                LinearProgressIndicator(
                  value: info.fraction,
                  minHeight: 3,
                  color: info.completed ? _kGreen : _kRed,
                  backgroundColor: CourseYt.track(context),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: CourseYt.text(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      info.completed
                          ? 'Curso concluído'
                          : (info.inProgress
                              ? '${(info.fraction * 100).round()}% assistido · ${info.done}/${info.lessonKeys.length} aulas'
                              : 'Toque para começar'),
                      style: TextStyle(
                        color: info.completed
                            ? _kGreen
                            : (info.inProgress
                                ? CourseYt.progressText(context)
                                : CourseYt.textSecondary(context)),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card horizontal «Continuar assistindo».
class CourseContinueCard extends StatelessWidget {
  const CourseContinueCard({
    super.key,
    required this.info,
    required this.onTap,
  });

  final CourseShowcaseInfo info;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: DecoratedBox(
        decoration: CourseYt.cardDecoration(context, radius: 14),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CourseMediaThumbnail.fromData(
                        info.data,
                        fit: BoxFit.cover,
                        showPlayButton: false,
                        fallback: const _CoverFallback(),
                      ),
                      const ColoredBox(color: Color(0x40000000)),
                      const Center(
                        child: Icon(Icons.play_circle_fill_rounded,
                            color: Colors.white, size: 46),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: LinearProgressIndicator(
                          value: info.fraction,
                          minHeight: 4,
                          color: _kRed,
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: CourseYt.text(context),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Continuar · ${(info.fraction * 100).round()}%',
                        style: TextStyle(
                          color: CourseYt.progressText(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
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

class _Seal extends StatelessWidget {
  const _Seal({required this.label, required this.color, required this.icon});

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 6),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: CourseYt.coverFallbackGradient(context),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(Icons.school_rounded,
            color: CourseYt.coverFallbackIcon(context), size: 40),
      ),
    );
  }
}
