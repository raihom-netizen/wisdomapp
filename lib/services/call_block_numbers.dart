/// Comparação de telefones do «Bloquear chamadas de desconhecidos».
///
/// Espelho EXATO de `CallBlockNumbers.kt` (Android) — é o nativo que decide a
/// ligação; esta cópia serve à tela (não deixar o mesmo número duas vezes nas
/// listas) e aos testes em `test/call_block_numbers_test.dart`. Mudou um, mude
/// o outro.
///
/// Regra (Brasil): só dígitos; `+55`/`0055`, o `0` de longa distância e o
/// código da operadora saem; sobra DDD (opcional) + assinante, do qual valem os
/// ÚLTIMOS 8 dígitos (o 9º dígito não atrapalha). Mesmo número = 8 finais iguais
/// e DDD igual (ou um dos dois sem DDD). Curtos (190, 1052…) só iguais;
/// estrangeiros comparam os dígitos completos.
library;

/// Serviços de emergência / utilidade pública do Brasil + 112/911.
const Set<String> callBlockEmergencia = {
  '100', '112', '128', '136', '153', '180', '181', '185', '188', '190', '191', '192',
  '193', '194', '197', '198', '199', '911',
};

class CallBlockCanon {
  const CallBlockCanon({
    required this.ddd,
    required this.sub8,
    required this.sub,
    required this.digits,
    required this.foreign,
  });

  final String? ddd;
  final String? sub8;
  final String? sub;
  final String digits;
  final bool foreign;
}

String callBlockDigitos(String s) => s.replaceAll(RegExp(r'\D'), '');

String _ultimos(String s, int n) => s.length <= n ? s : s.substring(s.length - n);

CallBlockCanon? callBlockCanon(String? raw) {
  final t = (raw ?? '').trim();
  var d = callBlockDigitos(t);
  if (d.isEmpty) return null;
  var intl = t.startsWith('+');
  if (!intl && d.startsWith('00') && d.length > 4) {
    intl = true;
    d = d.substring(2);
  }
  if (intl) {
    if (!d.startsWith('55')) {
      return CallBlockCanon(ddd: null, sub8: null, sub: null, digits: d, foreign: true);
    }
    d = d.substring(2);
  } else if (d.startsWith('0') && d.length >= 10) {
    d = d.substring(1);
    if (d.length == 12 || d.length == 13) d = d.substring(2); // operadora
  } else if (d.startsWith('55') && (d.length == 12 || d.length == 13)) {
    d = d.substring(2);
  }
  switch (d.length) {
    case 10:
    case 11:
      final sub = d.substring(2);
      return CallBlockCanon(
          ddd: d.substring(0, 2), sub8: _ultimos(sub, 8), sub: sub, digits: d, foreign: false);
    case 8:
    case 9:
      return CallBlockCanon(ddd: null, sub8: _ultimos(d, 8), sub: d, digits: d, foreign: false);
    default:
      return CallBlockCanon(ddd: null, sub8: null, sub: null, digits: d, foreign: d.length > 11);
  }
}

/// Mesmo telefone? Ver a regra no topo do arquivo.
bool callBlockMesmoNumero(String? a, String? b) {
  final ca = callBlockCanon(a);
  final cb = callBlockCanon(b);
  if (ca == null || cb == null) return false;
  if (ca.sub8 != null && cb.sub8 != null) {
    if (ca.sub8 != cb.sub8) return false;
    return ca.ddd == null || cb.ddd == null || ca.ddd == cb.ddd;
  }
  if (ca.digits == cb.digits) return true;
  if (ca.foreign || cb.foreign) {
    final curto = ca.digits.length <= cb.digits.length ? ca.digits : cb.digits;
    final longo = ca.digits.length <= cb.digits.length ? cb.digits : ca.digits;
    return curto.length >= 8 && longo.endsWith(curto);
  }
  return false;
}

/// Número de emergência/utilidade pública (o nativo nunca bloqueia).
bool callBlockEhEmergencia(String? raw) {
  final d = callBlockDigitos(raw ?? '');
  return d.isNotEmpty && d.length <= 3 && callBlockEmergencia.contains(d);
}

/// Formas do número usadas no PhoneLookup do nativo (a 1ª é a original).
List<String> callBlockVariantesBusca(String raw) {
  final out = <String>{};
  final t = raw.trim();
  if (t.isNotEmpty) out.add(t);
  final c = callBlockCanon(t);
  if (c == null || c.foreign || c.sub == null) return out.toList();
  final sub = c.sub!;
  final subs = <String>{sub};
  if (sub.length == 9 && sub.startsWith('9')) subs.add(sub.substring(1));
  if (sub.length == 8 && '6789'.contains(sub[0])) subs.add('9$sub');
  for (final s in subs) {
    if (c.ddd != null) {
      out.add('+55${c.ddd}$s');
      out.add('${c.ddd}$s');
      out.add('0${c.ddd}$s');
    }
    out.add(s);
  }
  return out.toList();
}
