import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:share_plus/share_plus.dart';

/// «Compartilhar curso» — o app ainda não tem rota pública por curso, então
/// manda o nome, um trecho da descrição e o convite para o WisdomApp.
class CourseShare {
  CourseShare._();

  static const siteUrl = 'https://wisdomapp.com.br';

  static String buildText(Map<String, dynamic> data) {
    final isDica =
        (data['type'] ?? 'curso').toString().trim().toLowerCase() == 'dica';
    final title = (data['title'] ?? (isDica ? 'Dica' : 'Curso')).toString().trim();
    var desc = (data['description'] ?? data['bodyText'] ?? '').toString().trim();
    if (desc.length > 180) desc = '${desc.substring(0, 177).trimRight()}…';
    final b = StringBuffer()
      ..writeln(isDica
          ? 'Olha esta dica no WisdomApp: «$title»'
          : 'Estou fazendo o curso «$title» no WisdomApp!');
    if (desc.isNotEmpty) {
      b
        ..writeln()
        ..writeln(desc);
    }
    b
      ..writeln()
      ..writeln(isDica
          ? 'Baixe o app ou acesse e confira em Cursos › Dicas:'
          : 'Baixe o app ou acesse e assista em Cursos:')
      ..write(siteUrl);
    return b.toString();
  }

  /// Abre a folha de compartilhamento; se o aparelho não tiver (algumas
  /// webs), copia o texto e avisa.
  static Future<void> share(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final text = buildText(data);
    final title = (data['title'] ?? 'Curso').toString();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await Share.share(text, subject: 'WisdomApp · $title');
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      messenger?.showSnackBar(const SnackBar(
        content: Text('Convite copiado — cole onde quiser enviar.'),
      ));
    }
  }
}
