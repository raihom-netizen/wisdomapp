/// Normaliza texto vindo do ditado ou colado para o campo do lançamento expresso.
abstract final class SmartInputVoiceText {
  SmartInputVoiceText._();

  static final RegExp _reBidiInvis = RegExp(
    r'[\u200B-\u200D\u200E\u200F\u202A-\u202E\u2060\uFEFF\uFFFC]',
  );

  /// Caracteres de controlo inúteis (só mantém tab e newline).
  static String stripBidiAndControlGarbage(String s) {
    if (s.isEmpty) return s;
    var t = s.replaceAll(_reBidiInvis, ' ');
    final b = StringBuffer();
    for (var i = 0; i < t.length; i++) {
      final c = t.codeUnitAt(i);
      if (c == 0x0A || c == 0x0D) {
        b.writeCharCode(c);
        continue;
      }
      if (c == 0x09) {
        b.write(' ');
        continue;
      }
      if (c < 0x20) continue;
      b.writeCharCode(c);
    }
    return b.toString();
  }

  /// - **Grupos de 3** (descrição \| valor \| data) repetidos: vira **uma linha por lançamento**:
  ///   `mercado|10000|24/04` \| `pão|50|25/04` → duas linhas, cada uma com `desc val data` para o parser.
  /// - Se o número de partes **não** for múltiplo de 3, mantém o modo antigo: **cada `|` = nova linha** (cada
  ///   segmento = um resumo a analisar).
  static String expandPipeSeparatorsToNewlines(String s) {
    if (!s.contains('|') && !s.contains('｜') && !s.contains('ǀ')) {
      return s;
    }
    var t = s.replaceAll('｜', '|').replaceAll('ǀ', '|');
    final parts = t.split('|').map((e) => e.replaceAll('\n', ' ').trim()).where((e) => e.isNotEmpty).toList();
    if (parts.length <= 1) return t.trim();
    if (parts.length % 3 == 0) {
      final out = <String>[];
      for (var i = 0; i < parts.length; i += 3) {
        final a = parts[i];
        final b = parts[i + 1];
        final c = parts[i + 2];
        out.add([a, b, c].join(' ').replaceAll(RegExp(r'\s+'), ' ').trim());
      }
      return out.join('\n');
    }
    return parts.join('\n');
  }

  static String _collapseBlankLines(String s) {
    return s.replaceAll(RegExp(r'[\t ]+\n', multiLine: true), '\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  /// Ordem: bidi / controlo → tríades desc|valor|data (linhas) **ou** `|` por trecho simples.
  static String forSmartInputField(String raw) {
    var t = stripBidiAndControlGarbage(raw);
    t = expandPipeSeparatorsToNewlines(t);
    t = _collapseBlankLines(t);
    return t;
  }
}
