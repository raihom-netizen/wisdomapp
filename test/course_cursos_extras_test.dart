import 'package:flutter_test/flutter_test.dart';
import 'package:controle_total_premium/services/course_certificate_service.dart';
import 'package:controle_total_premium/utils/course_lessons.dart';
import 'package:controle_total_premium/utils/course_share.dart';

void main() {
  group('CourseLessons.lessonKeyFor', () {
    test('YouTube tem prioridade (o player toca o YouTube)', () {
      final data = {
        'youtubeVideoId': 'dQw4w9WgXcQ',
        'mp4Urls': [
          {'url': 'https://x/a.mp4', 'storagePath': 'wisdomapp/course_videos/c/a.mp4'},
        ],
      };
      expect(CourseLessons.lessonKeyFor(data), 'yt:dQw4w9WgXcQ');
    });

    test('MP4 escolhido vira a chave da aula certa', () {
      final data = {
        'mp4Urls': [
          {'url': 'https://x/a.mp4', 'storagePath': 'p/a.mp4'},
          {'url': 'https://x/b.mp4', 'storagePath': 'p/b.mp4'},
        ],
      };
      expect(CourseLessons.lessonKeyFor(data, mp4Url: 'https://x/b.mp4'),
          'mp4:p/b.mp4');
      expect(CourseLessons.lessonKeyFor(data), 'mp4:p/a.mp4');
    });

    test('legado só no Storage usa o caminho resolvido', () {
      expect(
        CourseLessons.lessonKeyFor(const {}, storagePath: 'p/z.mp4'),
        'mp4:p/z.mp4',
      );
      expect(CourseLessons.lessonKeyFor(const {}), isNull);
    });
  });

  group('Certificado', () {
    test('código estável por aluno + curso', () {
      final a = CourseCertificateService.verificationCode('u1', 'c1');
      expect(a, CourseCertificateService.verificationCode('u1', 'c1'));
      expect(a, isNot(CourseCertificateService.verificationCode('u2', 'c1')));
      expect(a, startsWith('WA-'));
    });

    test('carga horária legível', () {
      expect(CourseCertificateService.workloadLabel(45), '45 min');
      expect(CourseCertificateService.workloadLabel(120), '2 h');
      expect(CourseCertificateService.workloadLabel(95), '1 h 35 min');
      expect(CourseCertificateService.workloadLabel(0), '');
    });

    test('PDF é gerado com acentos', () async {
      final bytes = await CourseCertificateService.buildPdf(
        studentName: 'João da Conceição',
        courseTitle: 'Educação Financeira — Módulo 1',
        lessonCount: 3,
        workloadMinutes: 95,
        issuedAt: DateTime(2026, 10, 2),
        code: 'WA-TEST-123',
      );
      expect(bytes.length, greaterThan(1000));
    });
  });

  test('Compartilhar curso leva nome e convite', () {
    final t = CourseShare.buildText({'title': 'Orçamento', 'type': 'curso'});
    expect(t, contains('Orçamento'));
    expect(t, contains(CourseShare.siteUrl));
  });
}
