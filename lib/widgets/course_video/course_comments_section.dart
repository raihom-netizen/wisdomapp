import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/course_comments_service.dart';
import '../course/course_yt_palette.dart';

String courseCommentWhen(DateTime? at) {
  if (at == null) return 'agora';
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'agora';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'há ${diff.inHours} h';
  if (diff.inDays < 30) {
    return diff.inDays == 1 ? 'há 1 dia' : 'há ${diff.inDays} dias';
  }
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(at.day)}/${two(at.month)}/${at.year}';
}

/// Comentários de uma aula — lista + campo para enviar. O autor exclui o
/// próprio comentário; a moderação geral fica no admin (aba Cursos).
class CourseCommentsSection extends StatefulWidget {
  const CourseCommentsSection({
    super.key,
    required this.courseId,
    required this.lessonKey,
    required this.uid,
    this.lessonTitle,
  });

  final String courseId;
  final String lessonKey;
  final String uid;
  final String? lessonTitle;

  @override
  State<CourseCommentsSection> createState() => _CourseCommentsSectionState();
}

class _CourseCommentsSectionState extends State<CourseCommentsSection> {
  final _ctrl = TextEditingController();
  Stream<List<CourseComment>>? _stream;
  var _sending = false;
  var _showAll = false;

  static const _collapsedCount = 3;

  @override
  void initState() {
    super.initState();
    _bindStream();
  }

  @override
  void didUpdateWidget(covariant CourseCommentsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.courseId != widget.courseId ||
        oldWidget.lessonKey != widget.lessonKey) {
      _showAll = false;
      _bindStream();
    }
  }

  /// Stream guardado no estado — criar `.snapshots()` dentro do build
  /// recriaria a escuta a cada rebuild.
  void _bindStream() {
    _stream = (widget.courseId.isEmpty || widget.lessonKey.isEmpty)
        ? null
        : CourseCommentsService.watchLesson(widget.courseId, widget.lessonKey);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _send() async {
    if (_sending) return;
    final text = _ctrl.text;
    if (text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await CourseCommentsService.add(
        courseId: widget.courseId,
        lessonKey: widget.lessonKey,
        uid: widget.uid,
        text: text,
      );
      _ctrl.clear();
      if (mounted) FocusScope.of(context).unfocus();
    } catch (e) {
      _snack(CourseCommentsService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(CourseComment c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir comentário?'),
        content: const Text('O comentário some para todos os alunos.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: CourseYt.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CourseCommentsService.delete(widget.courseId, c.id);
      _snack('Comentário excluído.');
    } catch (e) {
      _snack(CourseCommentsService.friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = CourseYt.text(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: CourseYt.cardDecoration(context, radius: 16),
      child: StreamBuilder<List<CourseComment>>(
        stream: _stream,
        builder: (context, snap) {
          final list = snap.data ?? const <CourseComment>[];
          final visible =
              _showAll ? list : list.take(_collapsedCount).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.forum_outlined, color: CourseYt.red, size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      snap.hasData
                          ? 'Comentários · ${list.length}'
                          : 'Comentários',
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                ],
              ),
              if ((widget.lessonTitle ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    widget.lessonTitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: CourseYt.textMuted(context),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              _composer(context),
              const SizedBox(height: 6),
              if (snap.hasError)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    CourseCommentsService.friendlyError(snap.error!),
                    style: TextStyle(
                      color: CourseYt.textSecondary(context),
                      fontSize: 12.5,
                    ),
                  ),
                )
              else if (!snap.hasData)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: CourseYt.red),
                    ),
                  ),
                )
              else if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Seja o primeiro a comentar esta aula.',
                    style: TextStyle(
                      color: CourseYt.textSecondary(context),
                      fontSize: 12.5,
                    ),
                  ),
                )
              else ...[
                for (final c in visible)
                  _CommentTile(
                    comment: c,
                    mine: c.authorUid == widget.uid,
                    onDelete: () => _delete(c),
                  ),
                if (list.length > _collapsedCount)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(foregroundColor: CourseYt.red),
                      onPressed: () => setState(() => _showAll = !_showAll),
                      child: Text(_showAll
                          ? 'Mostrar menos'
                          : 'Ver todos os ${list.length} comentários'),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _composer(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            minLines: 1,
            maxLines: 4,
            maxLength: CourseCommentsService.maxLength,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(color: CourseYt.text(context), fontSize: 13.5),
            decoration: InputDecoration(
              counterText: '',
              isDense: true,
              hintText: 'Adicione um comentário…',
              hintStyle: TextStyle(color: CourseYt.textMuted(context)),
              filled: true,
              fillColor: CourseYt.surfaceAlt(context),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (_) => _send(),
          ),
        ),
        const SizedBox(width: 6),
        IconButton.filled(
          tooltip: 'Enviar',
          style: IconButton.styleFrom(
            backgroundColor: CourseYt.red,
            foregroundColor: Colors.white,
          ),
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.send_rounded, size: 20),
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.mine,
    required this.onDelete,
  });

  final CourseComment comment;
  final bool mine;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final name = comment.authorName.trim().isEmpty ? 'Aluno' : comment.authorName;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: CourseYt.red.withValues(alpha: 0.14),
            child: Text(
              name.characters.first.toUpperCase(),
              style: const TextStyle(
                color: CourseYt.red,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: mine ? '$name (você)' : name,
                      style: TextStyle(
                        color: CourseYt.text(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                    TextSpan(
                      text: '  ·  ${courseCommentWhen(comment.createdAt)}',
                      style: TextStyle(
                        color: CourseYt.textMuted(context),
                        fontSize: 11.5,
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 2),
                Text(
                  comment.text,
                  style: TextStyle(
                    color: CourseYt.textSecondary(context),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (mine)
            IconButton(
              tooltip: 'Excluir meu comentário',
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline_rounded,
                  size: 19, color: CourseYt.textMuted(context)),
            ),
        ],
      ),
    );
  }
}
