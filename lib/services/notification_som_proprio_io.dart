import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_notifications_plugin_holder.dart';

const MethodChannel _canalSons = MethodChannel('controletotal/sons');

/// Converte o áudio escolhido num toque nativo e devolve onde ele ficou:
/// `{ android: <id do canal>, ios: <arquivo em Library/Sounds> }`.
///
/// - Converte para WAV mono 22,05 kHz de no máximo 29 s (limite do iOS: 30 s;
///   o iOS não toca MP3 em notificação).
/// - Android 10+: grava em «Notificações/WisdomApp» pelo MediaStore (o
///   sistema precisa conseguir ler o arquivo) e cria o canal
///   `ct_som_user_<categoria>_<versão>` com esse som — canal novo a cada troca,
///   porque o Android não deixa mudar o som de um canal existente.
/// - iOS: copia para `Library/Sounds`, de onde o `aps.sound` é tocado.
///
/// Devolve `null` se nada pôde ser preparado (o aviso segue com som padrão).
Future<Map<String, String>?> prepararSomProprioNativo({
  required String categoria,
  required String caminho,
  required String rotulo,
}) async {
  if (!(Platform.isAndroid || Platform.isIOS)) return null;
  final origem = File(caminho);
  if (!origem.existsSync()) return null;

  final versao = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final base = 'ct_user_${categoria}_$versao';
  final tmp = await getTemporaryDirectory();
  final wav = File('${tmp.path}/$base.wav');
  final sessao = await FFmpegKit.execute(
    '-y -i "${origem.path}" -t 29 -ac 1 -ar 22050 -c:a pcm_s16le "${wav.path}"',
  );
  if (!ReturnCode.isSuccess(await sessao.getReturnCode()) || !wav.existsSync()) {
    return null;
  }

  final prefs = await SharedPreferences.getInstance();
  final chave = 'notif_som_proprio_$categoria';
  final out = <String, String>{};

  try {
    if (Platform.isAndroid) {
      final uriAnterior = prefs.getString('${chave}_uri');
      final canalAnterior = prefs.getString('${chave}_canal');
      final uri = await _canalSons.invokeMethod<String>('registrarSomProprio', {
        'path': wav.path,
        'nome': 'WisdomApp - $rotulo',
        'anterior': uriAnterior,
      });
      if (uri != null && uri.isNotEmpty) {
        final canal = 'ct_som_user_${categoria}_$versao';
        final android = localNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await android?.createNotificationChannel(
          AndroidNotificationChannel(
            canal,
            'Meu toque: $rotulo',
            description: 'Avisos com o áudio que você escolheu.',
            importance: Importance.max,
            playSound: true,
            sound: UriAndroidNotificationSound(uri),
            enableVibration: true,
            showBadge: true,
          ),
        );
        if (canalAnterior != null && canalAnterior != canal) {
          try {
            await android?.deleteNotificationChannel(channelId: canalAnterior);
          } catch (_) {}
        }
        await prefs.setString('${chave}_uri', uri);
        await prefs.setString('${chave}_canal', canal);
        out['android'] = canal;
      }
    } else {
      final lib = await getLibraryDirectory();
      final dir = Directory('${lib.path}/Sounds');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final anterior = prefs.getString('${chave}_ios');
      if (anterior != null) {
        final f = File('${dir.path}/$anterior');
        if (f.existsSync()) f.deleteSync();
      }
      await wav.copy('${dir.path}/$base.wav');
      await prefs.setString('${chave}_ios', '$base.wav');
      out['ios'] = '$base.wav';
    }
  } finally {
    try {
      wav.deleteSync();
    } catch (_) {}
  }
  return out.isEmpty ? null : out;
}
