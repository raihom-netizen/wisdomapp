/// Filtro leve para descrições que o OCR/parse interpretam mal (evita categoria
/// ou linha de pré-visualização com lixo bidi, símbolos ou pouquíssimas letras).
abstract final class OcrDescriptionSanity {
  OcrDescriptionSanity._();

  static final RegExp _reBidiGarbage = RegExp(
    r'[\u200e\u200f\u202a\u202b\u202c\u202d\u202e\ufeff]',
  );
  static final RegExp _reLetters = RegExp(r'[A-Za-zÀ-ÿáéíóúãõç]');

  static bool looksLikeOcrNoise(String s) {
    final t = s.replaceAll(_reBidiGarbage, '').trim();
    if (t.length < 2) return true;
    if (_reBidiGarbage.hasMatch(s)) {
      if (_reLetters.allMatches(t).length < 2) return true;
    }
    final letterCount = _reLetters.allMatches(t).length;
    if (t.length >= 4 && letterCount * 3 < t.length) return true;
    if (RegExp(r'^[\d\W_]+$').hasMatch(t) && t.length < 8) return true;
    // ′ e ″ (U+2032/U+2033) com escapes — evita corrupção UTF-8 no compile web
    if (RegExp('^[0-9\\s\\-:/.\\' "'" '\u2032\u2033' r']+$').hasMatch(t) && letterCount < 2) {
      return true;
    }
    if (t.contains('202e') || t.toLowerCase().contains("o'ubm")) {
      return true;
    }
    return false;
  }

  /// Devolve a mesma [desc] ou um rótulo neutro para o utilizador corrigir.
  static String sanitize(String desc) {
    final t = desc.trim();
    if (t.isEmpty) return desc;
    if (looksLikeOcrNoise(t)) {
      return 'Lançamento (revisar descrição)';
    }
    return desc;
  }
}
