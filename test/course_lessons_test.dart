import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:controle_total_premium/services/course_progress_service.dart';
import 'package:controle_total_premium/utils/course_lessons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = 'dQw4w9WgXcQ';

  test('YouTube + 2 MP4 viram 3 aulas com chaves estáveis', () {
    final data = {
      'youtubeUrl': 'https://youtu.be/$id?si=x',
      'mp4Urls': [
        {
          'url': 'https://x/a.mp4',
          'storagePath': 'wisdomapp/course_videos/c1/video_0.mp4',
          'label': 'Vídeo 1',
        },
        {'url': 'https://x/b.mp4', 'label': 'Introdução'},
      ],
    };
    final l = CourseLessons.fromData(data);
    expect(l.length, 3);
    expect(l[0].key, 'yt:$id');
    expect(l[0].isYoutube, isTrue);
    expect(l[1].key, 'mp4:wisdomapp/course_videos/c1/video_0.mp4');
    expect(l[1].title, 'Aula 2');
    expect(l[2].key, 'mp4:1');
    expect(l[2].title, 'Aula 3 · Introdução');
  });

  test('curso só com YouTube = 1 aula', () {
    final l = CourseLessons.fromData({'youtubeVideoId': id});
    expect(l.single.title, 'Vídeo do curso');
  });

  test('progresso do curso, concluído e merge local × nuvem', () {
    const keys = ['a', 'b'];
    var p = const CourseProgress(lessons: {
      'a': CourseLessonProgress(positionSeconds: 50, durationSeconds: 100),
    });
    expect(p.courseFraction(keys), closeTo(0.25, 0.001));
    expect(p.isCompleted(keys), isFalse);

    p = p.mergeWith(const CourseProgress(
      lessons: {
        'a': CourseLessonProgress(done: true, durationSeconds: 100),
        'b': CourseLessonProgress(done: true),
      },
      lastLessonKey: 'b',
      lastOpenedMs: 10,
    ));
    expect(p.isCompleted(keys), isTrue);
    expect(p.lastLessonKey, 'b');
    expect(p.lesson('a').positionSeconds, 50);

    final round = CourseProgress.fromJson(p.toJson());
    expect(round.isCompleted(keys), isTrue);
    expect(round.lastOpenedMs, 10);
  });

  test('selo novo e formatos de duração', () {
    expect(
      CourseLessons.isNew({'createdAt': Timestamp.fromDate(DateTime.now())}),
      isTrue,
    );
    expect(
      CourseLessons.isNew({
        'createdAt': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(days: 40))),
      }),
      isFalse,
    );
    expect(CourseLessons.formatDuration(75), '1:15');
    expect(CourseLessons.formatMinutes(95), '1h35');
    expect(CourseLessons.declaredMinutes({'durationMinutes': '45'}), 45);
  });
}
