import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/course_comments_service.dart';
import '../../theme/theme_context.dart';
import '../../utils/course_lessons.dart';
import '../course_video/course_comments_section.dart' show courseCommentWhen;

/// Moderação dos comentários de um curso (admin / editor de conteúdo).
Future<void> showCourseCommentsModeration(
  BuildContext context, {
  required Map<String, dynamic> data,
}) {
  final courseId = (data['id'] ?? '').toString();
  if (courseId.isEmpty) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.85,
      child: _CourseCommentsModeration(courseId: courseId, data: data),
    ),
  );
}

class _CourseCommentsModeration extends StatefulWidget {
  const _CourseCommentsModeration({required this.courseId, required this.data});

  final String courseId;
  final Map<String, dynamic> data;

  @override
  State<_CourseCommentsModeration> createState() =>
      _CourseCommentsModerationState();
}

class _CourseCommentsModerationState extends State<_CourseCommentsModeration> {
  late final Stream<List<CourseComment>> _stream =
      CourseCommentsService.watchCourse(widget.courseId);
  late final Map<String, String> _lessonTitles = {
    for (final l in CourseLessons.fromData(widget.data)) l.key: l.title,
  };

  Future<void> _delete(CourseComment c) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir comentário?'),
        content: Text('«${c.text}»\n\nde ${c.authorName}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CourseCommentsService.delete(widget.courseId, c.id);
      messenger?.showSnackBar(
          const SnackBar(content: Text('Comentário excluído.')));
    } catch (e) {
      messenger?.showSnackBar(
          SnackBar(content: Text(CourseCommentsService.friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = (widget.data['title'] ?? 'Curso').toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 8, 8),
          child: Row(
            children: [
              Icon(Icons.forum_rounded, color: context.appTheme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Comentários',
                      style: TextStyle(
                        color: context.appTextPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.appTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Fechar',
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close_rounded, color: context.appTextSecondary),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<List<CourseComment>>(
            stream: _stream,
            builder: (context, snap) {
              if (snap.hasError) {
                return _message(
                    context, CourseCommentsService.friendlyError(snap.error!));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final list = snap.data!;
              if (list.isEmpty) {
                return _message(context, 'Nenhum comentário neste curso.');
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final c = list[i];
                  final lesson = _lessonTitles[c.lessonKey] ?? 'Aula';
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                    title: Text(
                      c.text,
                      style: TextStyle(color: context.appTextPrimary),
                    ),
                    subtitle: Text(
                      '${c.authorName} · $lesson · ${courseCommentWhen(c.createdAt)}',
                      style: TextStyle(
                        color: context.appTextSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: 'Excluir',
                      onPressed: () => unawaited(_delete(c)),
                      icon: Icon(Icons.delete_outline_rounded,
                          color: Colors.red.shade400),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _message(BuildContext context, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.appTextSecondary),
          ),
        ),
      );
}
