import 'package:controle_total_premium/utils/youtube_url_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = 'dQw4w9WgXcQ';

  group('YoutubeUrlHelper.extractVideoId — formatos aceitos', () {
    final validos = <String>[
      id,
      '  $id  ',
      'https://www.youtube.com/watch?v=$id',
      'http://www.youtube.com/watch?v=$id',
      'www.youtube.com/watch?v=$id',
      'youtube.com/watch?v=$id',
      'https://youtube.com/watch?v=$id',
      'https://m.youtube.com/watch?v=$id',
      'https://music.youtube.com/watch?v=$id&feature=share',
      'https://www.youtube.com/watch?v=$id&t=42s',
      'https://www.youtube.com/watch?v=$id&t=1m30s',
      'https://www.youtube.com/watch?v=$id&list=PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG&index=3',
      'https://www.youtube.com/watch?app=desktop&v=$id',
      'https://www.youtube.com/watch?feature=youtu.be&v=$id&si=abc123',
      'https://www.youtube.com/watch?v=$id#t=30',
      'https://youtu.be/$id',
      'youtu.be/$id',
      'https://youtu.be/$id?si=AbCdEfGhIjKlMn',
      'https://youtu.be/$id?t=90',
      'https://www.youtube.com/shorts/$id',
      'https://youtube.com/shorts/$id?si=xyz',
      'https://www.youtube.com/embed/$id',
      'https://www.youtube.com/embed/$id?autoplay=1&rel=0',
      'https://www.youtube-nocookie.com/embed/$id',
      'https://www.youtube.com/live/$id',
      'https://www.youtube.com/live/$id?si=abc&feature=shared',
      'https://www.youtube.com/v/$id',
      'https://www.youtube.com/e/$id',
      '<iframe width="560" height="315" src="https://www.youtube.com/embed/$id?si=x" '
          'title="YouTube video player" frameborder="0" allowfullscreen></iframe>',
      '"https://youtu.be/$id"',
      '<https://youtu.be/$id>',
      'https://www.youtube.com/attribution_link?a=x&u=%2Fwatch%3Fv%3D$id%26feature%3Dshare',
    ];

    for (final raw in validos) {
      test('aceita: $raw', () {
        expect(YoutubeUrlHelper.extractVideoId(raw), id);
        expect(YoutubeUrlHelper.isValidYoutubeUrl(raw), isTrue);
        expect(YoutubeUrlHelper.validationMessage(raw), isNull);
      });
    }

    test('IDs com hífen e sublinhado', () {
      expect(
        YoutubeUrlHelper.extractVideoId('https://youtu.be/a-B_c-D_e1F'),
        'a-B_c-D_e1F',
      );
      expect(YoutubeUrlHelper.extractVideoId('_-_-_-_-_-_'), '_-_-_-_-_-_');
    });
  });

  group('YoutubeUrlHelper.extractVideoId — rejeita', () {
    final invalidos = <String>[
      '',
      '   ',
      'abc',
      '${id}X', // 12 caracteres
      'https://www.youtube.com/',
      'https://www.youtube.com/watch',
      'https://www.youtube.com/watch?v=curto',
      'https://www.youtube.com/watch?v=${id}EXTRA',
      'https://www.youtube.com/playlist?list=PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG',
      'https://www.youtube.com/embed/videoseries?list=PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG',
      'https://www.youtube.com/embed/live_stream?channel=UC123',
      'https://www.youtube.com/@canaloficial',
      'https://www.youtube.com/channel/UCxxxxxxxxxxxxxxxxxxxxxx',
      'https://vimeo.com/123456789',
      'https://example.com/watch?v=$id',
      'https://notyoutube.com/watch?v=$id',
      'id com espaço',
    ];

    for (final raw in invalidos) {
      test('rejeita: "$raw"', () {
        expect(YoutubeUrlHelper.extractVideoId(raw), isNull);
        expect(YoutubeUrlHelper.isValidYoutubeUrl(raw), isFalse);
        expect(YoutubeUrlHelper.validationMessage(raw), isNotNull);
      });
    }

    test('mensagem específica para playlist e canal', () {
      expect(
        YoutubeUrlHelper.validationMessage(
            'https://www.youtube.com/playlist?list=PLabc'),
        contains('playlist'),
      );
      expect(
        YoutubeUrlHelper.validationMessage('https://www.youtube.com/@canal'),
        contains('canal'),
      );
    });
  });

  group('formato canônico', () {
    test('normalizeYoutubeUrl devolve watch?v=ID', () {
      expect(
        YoutubeUrlHelper.normalizeYoutubeUrl('https://youtu.be/$id?si=abc&t=3'),
        'https://www.youtube.com/watch?v=$id',
      );
      expect(
        YoutubeUrlHelper.normalizeYoutubeUrl('https://www.youtube.com/shorts/$id'),
        'https://www.youtube.com/watch?v=$id',
      );
    });

    test('canonicalFields grava id + url', () {
      final f = YoutubeUrlHelper.canonicalFields('https://m.youtube.com/watch?v=$id&list=X');
      expect(f, isNotNull);
      expect(f!['youtubeVideoId'], id);
      expect(f['youtubeUrl'], 'https://www.youtube.com/watch?v=$id');
      expect(f['videoUrl'], 'https://www.youtube.com/watch?v=$id');
      expect(YoutubeUrlHelper.canonicalFields('https://vimeo.com/1'), isNull);
    });

    test('videoIdFromData limpa ID gravado sujo e cai para os links', () {
      expect(
        YoutubeUrlHelper.videoIdFromData({'youtubeVideoId': '$id&t=10'}),
        isNull,
      );
      expect(
        YoutubeUrlHelper.videoIdFromData(
            {'youtubeVideoId': 'https://youtu.be/$id?si=x'}),
        id,
      );
      expect(
        YoutubeUrlHelper.videoIdFromData({
          'youtubeVideoId': 'lixo',
          'youtubeUrl': 'https://www.youtube.com/live/$id',
        }),
        id,
      );
      expect(
        YoutubeUrlHelper.videoIdFromData({'linkUrl': 'https://site.com/x'}),
        isNull,
      );
    });

    test('embedUrl usa youtube-nocookie com playsinline e origin', () {
      final u = YoutubeUrlHelper.embedUrl(id,
          autoplay: true, origin: 'https://wisdomapp.com.br', startSeconds: 30);
      expect(u, startsWith('https://www.youtube-nocookie.com/embed/$id?'));
      expect(u, contains('playsinline=1'));
      expect(u, contains('autoplay=1'));
      expect(u, contains('start=30'));
      expect(u, contains('origin=https%3A%2F%2Fwisdomapp.com.br'));
    });

    test('thumbnails em cascata terminam numa que sempre existe', () {
      final list = YoutubeUrlHelper.thumbnailUrls(id);
      expect(list.first, contains('maxresdefault'));
      expect(list, contains(YoutubeUrlHelper.safeThumbnailUrl(id)));
    });
  });

  group('startSecondsFromUrl', () {
    test('t em segundos, com s, em m/s e start=', () {
      expect(YoutubeUrlHelper.startSecondsFromUrl('https://youtu.be/$id?t=90'), 90);
      expect(
          YoutubeUrlHelper.startSecondsFromUrl(
              'https://www.youtube.com/watch?v=$id&t=42s'),
          42);
      expect(
          YoutubeUrlHelper.startSecondsFromUrl(
              'https://www.youtube.com/watch?v=$id&t=1m30s'),
          90);
      expect(
          YoutubeUrlHelper.startSecondsFromUrl(
              'https://www.youtube.com/watch?v=$id&t=1h2m3s'),
          3723);
      expect(
          YoutubeUrlHelper.startSecondsFromUrl(
              'https://www.youtube.com/embed/$id?start=45'),
          45);
      expect(YoutubeUrlHelper.startSecondsFromUrl('https://youtu.be/$id'), 0);
    });
  });
}
