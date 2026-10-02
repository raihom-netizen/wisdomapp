import 'package:cloud_firestore/cloud_firestore.dart';

import 'course_certificate_service.dart' show CourseStudentName;

/// Comentário de uma aula (`course_videos/{courseId}/comments/{id}`).
class CourseComment {
  const CourseComment({
    required this.id,
    required this.courseId,
    required this.lessonKey,
    required this.authorUid,
    required this.authorName,
    required this.text,
    this.createdAt,
  });

  final String id;
  final String courseId;
  final String lessonKey;
  final String authorUid;
  final String authorName;
  final String text;
  final DateTime? createdAt;

  factory CourseComment.fromDoc(
    String courseId,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    DateTime? at;
    final raw = d['createdAt'];
    if (raw is Timestamp) {
      at = raw.toDate();
    } else if (d['createdAtMs'] is num) {
      at = DateTime.fromMillisecondsSinceEpoch((d['createdAtMs'] as num).toInt());
    }
    return CourseComment(
      id: doc.id,
      courseId: courseId,
      lessonKey: (d['lessonKey'] ?? '').toString(),
      authorUid: (d['authorUid'] ?? '').toString(),
      authorName: (d['authorName'] ?? 'Aluno').toString(),
      text: (d['text'] ?? '').toString(),
      createdAt: at,
    );
  }
}

/// Erro com mensagem pronta para o usuário.
class CourseCommentException implements Exception {
  const CourseCommentException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CourseCommentsService {
  CourseCommentsService._();

  static const maxLength = 1000;

  static CollectionReference<Map<String, dynamic>> _col(String courseId) =>
      FirebaseFirestore.instance
          .collection('course_videos')
          .doc(courseId)
          .collection('comments');

  /// Mensagem amigável para erros do Firestore (regras ainda não publicadas,
  /// sem rede…).
  static String friendlyError(Object e) {
    if (e is CourseCommentException) return e.message;
    if (e is FirebaseException) {
      switch (e.code) {
        case 'permission-denied':
          return 'Os comentários ainda não estão liberados para a sua conta. '
              'Tente de novo mais tarde.';
        case 'unavailable':
        case 'deadline-exceeded':
          return 'Sem conexão no momento. Tente de novo em instantes.';
        case 'failed-precondition':
          return 'Os comentários estão sendo preparados. Tente mais tarde.';
      }
    }
    return 'Não foi possível carregar/enviar o comentário agora.';
  }

  /// Comentários da aula, do mais novo para o mais antigo.
  ///
  /// Filtra só por igualdade (`lessonKey`) e ordena no aparelho — não exige
  /// índice composto no Firestore.
  static Stream<List<CourseComment>> watchLesson(
    String courseId,
    String lessonKey, {
    int limit = 300,
  }) {
    return _col(courseId)
        .where('lessonKey', isEqualTo: lessonKey)
        .limit(limit)
        .snapshots()
        .map((s) {
      final list =
          s.docs.map((d) => CourseComment.fromDoc(courseId, d)).toList();
      list.sort((a, b) {
        final ta = a.createdAt?.millisecondsSinceEpoch ?? 0;
        final tb = b.createdAt?.millisecondsSinceEpoch ?? 0;
        return tb.compareTo(ta);
      });
      return list;
    });
  }

  /// Todos os comentários do curso (moderação no admin).
  static Stream<List<CourseComment>> watchCourse(
    String courseId, {
    int limit = 300,
  }) {
    return _col(courseId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => CourseComment.fromDoc(courseId, d)).toList());
  }

  static Future<void> add({
    required String courseId,
    required String lessonKey,
    required String uid,
    required String text,
  }) async {
    final t = text.trim();
    if (t.isEmpty) throw const CourseCommentException('Escreva o comentário.');
    if (t.length > maxLength) {
      throw const CourseCommentException(
          'Comentário muito longo (máximo de $maxLength caracteres).');
    }
    if (courseId.isEmpty || lessonKey.isEmpty || uid.isEmpty) {
      throw const CourseCommentException('Abra uma aula para comentar.');
    }
    final name = await CourseStudentName.resolve(uid);
    await _col(courseId).add({
      'lessonKey': lessonKey,
      'authorUid': uid,
      'authorName': name,
      'text': t,
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static Future<void> delete(String courseId, String commentId) =>
      _col(courseId).doc(commentId).delete();
}
