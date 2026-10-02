import 'package:flutter_test/flutter_test.dart';
import 'package:controle_total_premium/utils/course_lessons.dart';
import 'package:controle_total_premium/utils/course_media_url_resolver.dart';

void main() {
  group('Prévia (quadro) dos vídeos MP4', () {
    test('envio grava o quadro em cada aula e em videoPosterUrl', () {
      final f = CourseMediaUrlResolver.videoFieldsFromUploads(const [
        CourseMediaUploadResult(
          downloadUrl: 'https://x/v0.mp4',
          storagePath: 'wisdomapp/course_videos/c1/video_0_1.mp4',
          posterUrl: 'https://x/p0.jpg',
          posterStoragePath: 'wisdomapp/course_videos/c1/poster_0_1.jpg',
        ),
        CourseMediaUploadResult(
          downloadUrl: 'https://x/v1.mp4',
          storagePath: 'wisdomapp/course_videos/c1/video_1_1.mp4',
        ),
      ]);
      expect(f['videoPosterUrl'], 'https://x/p0.jpg');
      final list = f['mp4Urls'] as List;
      expect((list[0] as Map)['posterUrl'], 'https://x/p0.jpg');
      expect((list[1] as Map).containsKey('posterUrl'), isFalse);
      // Não vira foto da galeria (posterUrl de topo é campo de imagem).
      expect(f.containsKey('posterUrl'), isFalse);
      expect(CourseMediaUrlResolver.hasResolvableImage(f), isFalse);
    });

    test('lê o quadro de volta e mantém ao juntar vídeos novos', () {
      final data = CourseMediaUrlResolver.videoFieldsFromUploads(const [
        CourseMediaUploadResult(
          downloadUrl: 'https://x/v0.mp4',
          storagePath: 'p0',
          posterUrl: 'https://x/p0.jpg',
        ),
      ]);
      final entries = CourseMediaUrlResolver.collectVideoEntries(data);
      expect(entries.single.posterUrl, 'https://x/p0.jpg');
      expect(CourseMediaUrlResolver.videoPosterUrls(data), ['https://x/p0.jpg']);

      final merged = CourseMediaUrlResolver.mergeVideoFields(
        existing: data,
        newUploads: const [
          CourseMediaUploadResult(downloadUrl: 'https://x/v1.mp4', storagePath: 'p1'),
        ],
      );
      final list = merged['mp4Urls'] as List;
      expect(list.length, 2);
      expect((list[0] as Map)['posterUrl'], 'https://x/p0.jpg');
    });

    test('aula MP4 sem capa tem dados para a prévia; YouTube usa o id', () {
      final lessons = CourseLessons.fromData({
        'youtubeVideoId': 'dQw4w9WgXcQ',
        'mp4Urls': [
          {'url': 'https://x/v0.mp4', 'storagePath': 'p0', 'posterUrl': 'https://x/p0.jpg'},
        ],
      });
      expect(lessons.first.thumbData['youtubeVideoId'], 'dQw4w9WgXcQ');
      final mp4 = lessons[1].thumbData;
      expect(mp4['mp4Url'], 'https://x/v0.mp4');
      expect(mp4['videoPosterUrl'], 'https://x/p0.jpg');
      expect(CourseMediaUrlResolver.firstVideoRef(mp4), 'https://x/v0.mp4');
    });

    test('a capa muda de identidade quando muda o vídeo', () {
      final a = CourseMediaUrlResolver.imageFingerprint({'mp4Url': 'https://x/a.mp4'});
      final b = CourseMediaUrlResolver.imageFingerprint({'mp4Url': 'https://x/b.mp4'});
      expect(a, isNot(b));
    });
  });
}
