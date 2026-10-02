/// Pix «copia e cola» estático (BR Code do Banco Central) com valor.
///
/// Campos EMV: 00 formato · 26 conta Pix (GUI + chave + descrição) · 52 MCC ·
/// 53 moeda (986) · 54 valor · 58 país · 59 nome · 60 cidade · 62 txid ·
/// 63 CRC16-CCITT (0xFFFF). Nome/cidade sem acento e em maiúsculas (limite
/// 25/15 caracteres), como os bancos exigem.
String gerarPixCopiaECola({
  required String chave,
  required String nome,
  required String cidade,
  double valor = 0,
  String txid = '***',
  String descricao = '',
}) {
  String campo(String id, String v) => '$id${v.length.toString().padLeft(2, '0')}$v';
  String limpo(String s, int max) {
    const de = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
    const para = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
    final b = StringBuffer();
    for (final r in s.runes) {
      final c = String.fromCharCode(r);
      final i = de.indexOf(c);
      b.write(i >= 0 ? para[i] : c);
    }
    final t = b
        .toString()
        .replaceAll(RegExp(r'[^A-Za-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toUpperCase();
    return t.length > max ? t.substring(0, max) : t;
  }

  final chaveLimpa = _normalizarChave(chave);
  // Campo 26 tem no máximo 99 caracteres: 18 (GUI) + 4 + chave + 4 + descrição.
  // Chave aleatória/e-mail longo + descrição grande passava de 99 e o banco
  // recusava o código. A descrição é cortada para caber (ou some).
  final maxDesc = 99 - 18 - 4 - chaveLimpa.length - 4;
  final desc = maxDesc <= 0 ? '' : limpo(descricao, maxDesc < 40 ? maxDesc : 40).trim();
  final conta = campo('00', 'br.gov.bcb.pix') + campo('01', chaveLimpa) + (desc.isEmpty ? '' : campo('02', desc));
  final tx = RegExp(r'^[A-Za-z0-9]{1,25}$').hasMatch(txid) ? txid : '***';
  final semCrc = campo('00', '01') +
      campo('26', conta) +
      campo('52', '0000') +
      campo('53', '986') +
      (valor > 0 ? campo('54', valor.toStringAsFixed(2)) : '') +
      campo('58', 'BR') +
      // Nome/cidade só com emoji ou símbolo ficam vazios depois da limpeza —
      // e campo vazio invalida o BR Code. Cai no padrão (igual ao servidor).
      campo('59', _ouPadrao(limpo(nome, 25), 'RECEBEDOR')) +
      campo('60', _ouPadrao(limpo(cidade, 15), 'BRASIL')) +
      campo('62', campo('05', tx)) +
      '6304';
  return '$semCrc${_crc16(semCrc)}';
}

String _ouPadrao(String v, String padrao) => v.isEmpty ? padrao : v;

/// Chave aleatória (EVP) no formato do Banco Central: 8-4-4-4-12, minúsculas.
/// Colada sem hífens (32 hex) ou em maiúsculas, o banco do cliente não achava
/// a chave. null quando não é uma EVP. (Igual a functions/pix_br_code.js.)
String? chavePixAleatoria(String chave) {
  final texto = chave;
  final hex = texto.replaceAll('-', '');
  if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(hex)) return null;
  // Com hífens, só vale nas posições certas (senão não é EVP).
  if (texto.contains('-') &&
      !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(texto)) {
    return null;
  }
  final h = hex.toLowerCase();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Telefone vira +55…; CPF/CNPJ só dígitos; e-mail como veio; chave
/// aleatória no formato 8-4-4-4-12 minúsculo. Mesmo algoritmo de
/// functions/pix_br_code.js (manter os dois iguais).
String _normalizarChave(String chave) {
  final c = chave.trim();
  if (c.contains('@')) return c;
  final evp = chavePixAleatoria(c);
  if (evp != null) return evp;
  if (RegExp(r'^[0-9a-fA-F-]{32,36}$').hasMatch(c)) return c;
  final d = c.replaceAll(RegExp(r'[^0-9+]'), '');
  if (c.startsWith('+')) return d;
  final digitos = d.replaceAll('+', '');
  if (digitos.length == 11) {
    // CPF ou celular: máscara de telefone decide; senão CPF válido fica CPF.
    if (RegExp(r'[()]').hasMatch(c) || RegExp(r'^\d{2}[\s.]\s?9').hasMatch(c)) return '+55$digitos';
    return _cpfValido(digitos) || digitos[2] != '9' ? digitos : '+55$digitos';
  }
  if (digitos.length == 14) return digitos;
  if (digitos.length == 10 || digitos.length == 13) return digitos.startsWith('55') ? '+$digitos' : '+55$digitos';
  return c;
}

/// CPF com dígitos verificadores certos. 11 dígitos todos iguais (000…,
/// 111…) passam no cálculo mas não são CPF — recusados, como no servidor.
bool cpfPixValido(String d) => _cpfValido(d);

bool _cpfValido(String d) {
  final todosIguais = d.isNotEmpty && d.split('').every((ch) => ch == d[0]);
  if (!RegExp(r'^\d{11}$').hasMatch(d) || todosIguais) return false;
  int dv(int n) {
    var soma = 0;
    for (var i = 0; i < n; i++) {
      soma += int.parse(d[i]) * (n + 1 - i);
    }
    final r = (soma * 10) % 11;
    return r == 10 ? 0 : r;
  }

  return dv(9) == int.parse(d[9]) && dv(10) == int.parse(d[10]);
}

/// Chave como vai no BR Code (para mostrar ao usuário o que foi entendido).
String chavePixNormalizada(String chave) => _normalizarChave(chave);

String _crc16(String s) {
  var crc = 0xFFFF;
  for (final b in s.codeUnits) {
    crc ^= b << 8;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) & 0xFFFF : (crc << 1) & 0xFFFF;
    }
  }
  return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
}
