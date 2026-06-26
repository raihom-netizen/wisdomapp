import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'notification_sound_catalog.dart';
import 'notification_sound_preferences.dart';

/// Toca o áudio escolhido pelo usuário para uma categoria de notificação.
///
/// Funciona quando o app está em **foreground** (Android/iOS/Web). Em
/// background no celular, o som efetivamente tocado é o do **canal** Android
/// (padrão do sistema), porque tocar arquivo arbitrário em background sem
/// foreground service não é estável.
///
/// Suporta três tipos de "customPath":
///  - `bundled://<id>` — toque embutido no app (catálogo offline).
///  - `web://<nome>` — placeholder web (demonstração).
///  - caminho absoluto em disco — arquivo escolhido / gravado.
class NotificationAudioPlayer {
  NotificationAudioPlayer._();

  static final NotificationAudioPlayer instance = NotificationAudioPlayer._();

  final AudioPlayer _player = AudioPlayer(playerId: 'controletotal_notif');
  bool _playbackConfigured = false;

  /// Android/iOS: contexto de áudio adequado a **efeitos curtos** (preview /
  /// notificação com app aberto) — evita volume zero / rota errada em alguns
  /// aparelhos quando o uso padrão era `media`.
  Future<void> _ensurePlaybackReady() async {
    if (_playbackConfigured) return;
    if (kIsWeb) {
      _playbackConfigured = true;
      return;
    }
    try {
      await _player.setPlayerMode(PlayerMode.lowLatency);
    } catch (_) {}
    try {
      final ctx = AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.notification,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.mixWithOthers},
        ),
      );
      await AudioPlayer.global.setAudioContext(ctx);
      await _player.setAudioContext(ctx);
    } catch (_) {}
    _playbackConfigured = true;
  }

  Future<void> playForCategory(NotificationSoundCategory category) async {
    try {
      await _ensurePlaybackReady();
      final pref = await NotificationSoundPreferences.instance.read(category);
      if (pref.isSilent) return;
      if (!pref.isCustom) {
        // som padrão é tratado pelo canal de notificação
        return;
      }
      await _playPath(pref.customPath!);
    } catch (_) {}
  }

  /// Toca um item do catálogo offline pelo `id`. Útil para preview /
  /// callback de notificação que carrega o id no payload.
  Future<void> playBundledById(String catalogId) async {
    final item = findCatalogItemById(catalogId);
    if (item == null) return;
    try {
      await _ensurePlaybackReady();
      await _player.stop();
      await _player.play(AssetSource(_assetSourcePath(item.assetPath)));
    } catch (_) {}
  }

  /// Preview rápido na tela de configuração / formulário de evento.
  Future<void> preview({String? path}) async {
    if (path == null || path.isEmpty) return;
    await _playPath(path);
  }

  Future<void> _playPath(String path) async {
    try {
      await _ensurePlaybackReady();
      if (path.startsWith(kBundledSoundPathPrefix)) {
        final id = path.substring(kBundledSoundPathPrefix.length);
        await playBundledById(id);
        return;
      }
      if (kIsWeb) {
        await _player.stop();
        await _player.play(UrlSource(path));
        return;
      }
      final f = File(path);
      if (!f.existsSync()) return;
      await _player.stop();
      await _player.play(DeviceFileSource(path));
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  /// O `AssetSource` do `audioplayers` espera o path **sem** o prefixo
  /// `assets/` — ele já assume essa raiz.
  String _assetSourcePath(String fullAssetPath) {
    const prefix = 'assets/';
    if (fullAssetPath.startsWith(prefix)) {
      return fullAssetPath.substring(prefix.length);
    }
    return fullAssetPath;
  }
}
