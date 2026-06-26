import 'dart:math' show min;

/// Pós-processamento de texto vindo de OCR (foto de comprovante, PDF escaneado, etc.):
/// - **Pix / EMV** (código começando em `000201` — ex. `00020126…`); agrega dígitos partidos por quebras/ruído
/// - **Boleto** (47 ou 48 dígitos) com separadores; normaliza e agrupa (blocos de 5)
/// - **Linhas de tabela** (data, descrição, valor): `dd/mm/aaaa` colado a letra; `R$` com espaço a mais
///
/// Não chama rede; aplica-se ao texto imediatamente após o reconhecimento.
abstract final class SmartInputOcrRecognizedPostprocess {
  SmartInputOcrRecognizedPostprocess._();

  static const int _kPixEmvMaxDigits = 200;
  static const int _kPixEmvMinDigits = 32;

  static final RegExp _reDataYmdGluedLetter = RegExp(
    r'(\d{2}/\d{2}/\d{4})(?=[A-Za-z])',
  );
  static final RegExp _reRWrongSpaces = RegExp(
    r'R\s{1,3}\$',
    caseSensitive: false,
  );
  /// `1.234,56` imediatamente seguido de (opcional) letra e data: separa em linha (OCR a colar tabela).
  static final RegExp _reTableValueThenDate = RegExp(
    r'(\d{1,3}(?:\.\d{3})*,\d{2})(?=(?:[A-Za-z]?\d{1,2}/\d{1,2}/\d{2,4}))',
  );

  /// Aplica heurísticas ao [text] bruto do reconhecedor.
  static String apply(String text) {
    var t = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (t.isEmpty) return t;

    t = _reflowMultilineRToken(t);
    t = t.replaceAllMapped(_reDataYmdGluedLetter, (m) => '${m[1]} ');
    t = t.replaceAllMapped(_reTableValueThenDate, (m) => '${m[1]}\n');
    t = _reflowPixEmv(t);
    t = _reflowBoletoLinhaDigitavel(t);
    t = _collapseSpacesPerLine(t);
    t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return t.trim();
  }

  static String _reflowMultilineRToken(String t) {
    if (!t.toLowerCase().contains('r')) return t;
    return t
        .split('\n')
        .map(
          (line) => line.replaceAllMapped(
            _reRWrongSpaces,
            (_) => r'R$',
          ),
        )
        .join('\n');
  }

  static String _collapseSpacesPerLine(String t) {
    if (!t.contains(' ')) return t;
    return t
        .split('\n')
        .map(
          (line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim(),
        )
        .join('\n');
  }

  /// Junta o código EMV a partir de `000201`… até [\_kPixEmvMaxDigits] dígitos (OCR a partir em várias linhas).
  static String _reflowPixEmv(String t) {
    if (!t.contains('000201')) return t;
    const head = '000201';
    final b = StringBuffer();
    var pos = 0;
    while (pos < t.length) {
      final at = t.indexOf(head, pos);
      if (at < 0) {
        b.write(t.substring(pos));
        break;
      }
      b.write(t.substring(pos, at));
      var scan = at;
      final buf = StringBuffer();
      const maxWindow = 2200;
      while (scan < t.length && scan < at + maxWindow && buf.length < _kPixEmvMaxDigits) {
        final cu = t.codeUnitAt(scan);
        if (cu >= 0x30 && cu <= 0x39) {
          buf.writeCharCode(cu);
        }
        scan++;
      }
      var digits = buf.toString();
      if (digits.length < _kPixEmvMinDigits || !digits.startsWith('000201')) {
        b.write(t[at]);
        pos = at + 1;
        continue;
      }
      b.write(digits);
      // Reposiciona [scan] de modo a consumir no texto original a mesma quantidade de **dígitos** lida
      var cnt = 0;
      scan = at;
      while (scan < t.length && cnt < digits.length) {
        final cu = t.codeUnitAt(scan);
        if (cu >= 0x30 && cu <= 0x39) cnt++;
        scan++;
      }
      pos = scan;
    }
    return b.toString();
  }

  /// Linha digitável (47/48 dígitos) com lixo; só reformata se o [match] tiver *exatamente* 47 ou 48 após `[^\d]`.
  static String _reflowBoletoLinhaDigitavel(String t) {
    if (t.length < 20) return t;
    return t.replaceAllMapped(
      RegExp(r'(?:^|\b)(\d[\d.\s]{18,200}\d)(?=\D|$)'),
      (m) {
        final raw = m[1]!;
        final d = raw.replaceAll(RegExp(r'[^\d]'), '');
        if (d.length != 47 && d.length != 48) return m[0]!;
        // Evita 44/45+ dígitos de extrato: exige tamanho típico boleto
        return _formatBoletoGroupsOfFive(d);
      },
    );
  }

  static String _formatBoletoGroupsOfFive(String d) {
    final sb = StringBuffer();
    for (var i = 0; i < d.length; i += 5) {
      if (i > 0) sb.write(' ');
      sb.write(d.substring(i, min(i + 5, d.length)));
    }
    return sb.toString();
  }
}
