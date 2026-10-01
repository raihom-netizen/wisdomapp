import 'package:controle_total_premium/services/course_video_file_service.dart';
import 'package:controle_total_premium/services/youtube_oembed_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const id = 'dQw4w9WgXcQ';

  test('oEmbed: lê título, canal e capa', () async {
    final client = MockClient((req) async {
      expect(req.url.host, 'www.youtube.com');
      expect(req.url.path, '/oembed');
      expect(req.url.queryParameters['url'],
          'https://www.youtube.com/watch?v=$id');
      expect(req.url.queryParameters['format'], 'json');
      return http.Response(
        '{"title":"Aula de finanças","author_name":"Canal X",'
        '"thumbnail_url":"https://i.ytimg.com/vi/$id/hqdefault.jpg"}',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final info = await YoutubeOembedService.fetch(id, client: client);
    expect(info.title, 'Aula de finanças');
    expect(info.author, 'Canal X');
    expect(info.coverUrl, 'https://i.ytimg.com/vi/$id/hqdefault.jpg');
  });

  test('oEmbed falhou (privado/404): segue só com o ID', () async {
    final client = MockClient((_) async => http.Response('Not Found', 404));
    final info = await YoutubeOembedService.fetch('aaaaaaaaaaa', client: client);
    expect(info.videoId, 'aaaaaaaaaaa');
    expect(info.title, isEmpty);
    expect(info.coverUrl, contains('aaaaaaaaaaa/hqdefault.jpg'));
  });

  test('validação de vídeo antes de enviar', () {
    expect(CourseVideoFileService.validate(name: 'aula.mp4', sizeBytes: 1000),
        isNull);
    expect(CourseVideoFileService.validate(name: 'aula.avi', sizeBytes: 1000),
        contains('formato'));
    expect(
        CourseVideoFileService.validate(
            name: 'grande.mp4', sizeBytes: 300 * 1024 * 1024),
        contains('250 MB'));
    expect(CourseVideoFileService.validate(name: 'vazio.mov', sizeBytes: 0),
        contains('vazio'));
  });
}
