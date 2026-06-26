// Gera PNGs offline em assets/images/bank_brands/ a partir do serviço Google s2 favicons.
// Uso (com rede): na pasta flutter_app executar:
//   dart run tool/fetch_bank_brand_icons.dart
//
// Depois de adicionar banco em [kFinanceBankFaviconHosts], volte a correr este script.

import 'dart:io';

import 'package:controle_total_premium/constants/finance_bank_brand_hosts.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final root = Directory.current.path;
  final outDir = Directory('$root/assets/images/bank_brands');
  outDir.createSync(recursive: true);
  final client = http.Client();
  try {
    for (final e in kFinanceBankFaviconHosts.entries) {
      final id = e.key;
      final domain = e.value;
      // `sz` até 256: ícones mais nítidos em modais / listas em ecrãs HiDPI (antes 128).
      final uri = Uri.https('www.google.com', '/s2/favicons', {
        'sz': '256',
        'domain': domain,
      });
      stdout.writeln('Baixando $id ($domain)...');
      try {
        final res = await client.get(uri);
        if (res.statusCode != 200) {
          stderr.writeln('  HTTP ${res.statusCode}, ignorado.');
          continue;
        }
        final bytes = res.bodyBytes;
        if (bytes.length < 32) {
          stderr.writeln('  resposta muito pequena (${bytes.length} B), ignorado.');
          continue;
        }
        final path = '${outDir.path}/$id.png';
        File(path).writeAsBytesSync(bytes);
        stdout.writeln('  -> $path (${bytes.length} bytes)');
      } catch (err) {
        stderr.writeln('  erro: $err');
      }
    }
  } finally {
    client.close();
  }
  stdout.writeln('Concluído. Faça flutter pub get se for a primeira vez.');
}
