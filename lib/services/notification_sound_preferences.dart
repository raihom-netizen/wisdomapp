import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Categorias de notificação para as quais o usuário pode escolher um som
/// próprio. "all" é um atalho — quando o usuário escolhe um som em "all", ele é
/// aplicado às 4 categorias específicas (a menos que cada uma tenha seu som
/// dedicado).
enum NotificationSoundCategory {
  all,
  escala,
  compromisso,
  audiencia,
  financeiro;

  String get storageKey => switch (this) {
        NotificationSoundCategory.all => 'notif_sound_all',
        NotificationSoundCategory.escala => 'notif_sound_escala',
        NotificationSoundCategory.compromisso => 'notif_sound_compromisso',
        NotificationSoundCategory.audiencia => 'notif_sound_audiencia',
        NotificationSoundCategory.financeiro => 'notif_sound_financeiro',
      };

  String get displayName => switch (this) {
        NotificationSoundCategory.all => 'Todas as categorias',
        NotificationSoundCategory.escala => 'Escala / Plantão',
        NotificationSoundCategory.compromisso => 'Compromisso',
        NotificationSoundCategory.audiencia => 'Audiência',
        NotificationSoundCategory.financeiro => 'Conta a pagar',
      };

  String get shortName => switch (this) {
        NotificationSoundCategory.all => 'Todas',
        NotificationSoundCategory.escala => 'Escala',
        NotificationSoundCategory.compromisso => 'Compromisso',
        NotificationSoundCategory.audiencia => 'Audiência',
        NotificationSoundCategory.financeiro => 'Financeiro',
      };
}

/// Modo do som da notificação por categoria. Determina **como** a
/// notificação é entregue ao usuário (com som, só vibração ou só push).
enum NotificationSoundMode {
  /// Toca o som padrão do sistema (vibração + tom de notificação do device).
  systemDefault,

  /// Sem som, mas **com vibração**. A notificação aparece e o aparelho
  /// vibra — útil em reuniões.
  vibrateOnly,

  /// Só push (sem som, sem vibração). A notificação aparece no popup/badge.
  silent,

  /// Áudio customizado pelo usuário — arquivo MP3/WAV/M4A escolhido, voz
  /// gravada ou tom do **banco do app**. Tocado em foreground; em
  /// background usa o tom padrão do sistema (limitação técnica).
  customAudio;

  String get value => switch (this) {
        NotificationSoundMode.systemDefault => 'system',
        NotificationSoundMode.vibrateOnly => 'vibrate',
        NotificationSoundMode.silent => 'silent',
        NotificationSoundMode.customAudio => 'custom',
      };

  static NotificationSoundMode fromValue(String? v) => switch (v) {
        'silent' => NotificationSoundMode.silent,
        'vibrate' => NotificationSoundMode.vibrateOnly,
        'custom' => NotificationSoundMode.customAudio,
        _ => NotificationSoundMode.systemDefault,
      };
}

/// Origem do áudio customizado.
enum NotificationCustomAudioSource {
  pickedFile, // mp3/wav/m4a escolhido via file_picker
  recordedVoice, // voz gravada pelo próprio usuário (uso futuro)
  bundledAsset, // toque embutido no app (catálogo `notification_sound_catalog.dart`)
}

/// Prefixo dos paths de áudio embutidos no app — `bundled://<catalog_id>`.
/// Útil para diferenciar de um arquivo no disco em `customPath`.
const String kBundledSoundPathPrefix = 'bundled://';

/// Snapshot da preferência de som de UMA categoria.
class NotificationSoundPreference {
  const NotificationSoundPreference({
    required this.mode,
    this.customPath,
    this.customLabel,
    this.customSource,
  });

  final NotificationSoundMode mode;
  final String? customPath;
  final String? customLabel;
  final NotificationCustomAudioSource? customSource;

  static const NotificationSoundPreference systemDefault =
      NotificationSoundPreference(mode: NotificationSoundMode.systemDefault);

  bool get isSilent => mode == NotificationSoundMode.silent;

  /// Modo "Só vibrar" — não toca som, mas o aparelho vibra.
  bool get isVibrateOnly => mode == NotificationSoundMode.vibrateOnly;

  /// O canal Android deve tocar **algum** som (padrão do sistema). Falso
  /// para `silent`, `vibrateOnly` e quando o tom é customizado (o app
  /// toca via [NotificationAudioPlayer] em foreground).
  bool get channelShouldPlaySound =>
      mode == NotificationSoundMode.systemDefault;

  /// O canal Android deve vibrar (compatível com Android 8+).
  bool get channelShouldVibrate => switch (mode) {
        NotificationSoundMode.systemDefault => true,
        NotificationSoundMode.vibrateOnly => true,
        NotificationSoundMode.customAudio => true,
        NotificationSoundMode.silent => false,
      };

  bool get isCustom =>
      mode == NotificationSoundMode.customAudio &&
      customPath != null &&
      customPath!.isNotEmpty;
}

/// Persistência local das escolhas de som por categoria.
///
/// Premium (super premium): o usuário pode escolher um som diferente para
/// Escala, Compromisso, Audiência, Financeiro — ou aplicar o mesmo som em
/// todas (chave "all"). Suporta áudio próprio (mp3/wav/m4a) ou voz gravada
/// (gravação fica em `Documents/notification_sounds/<categoria>.m4a`).
class NotificationSoundPreferences {
  NotificationSoundPreferences._();

  static final NotificationSoundPreferences instance =
      NotificationSoundPreferences._();
  factory NotificationSoundPreferences() => instance;

  static const String _modeSuffix = '_mode';
  static const String _pathSuffix = '_path';
  static const String _labelSuffix = '_label';
  static const String _sourceSuffix = '_src';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// Lê a preferência da categoria. Se a categoria específica estiver em
  /// "systemDefault" e a categoria "all" tiver som customizado, herda o "all".
  Future<NotificationSoundPreference> read(
      NotificationSoundCategory category) async {
    final own = await _readRaw(category);
    if (category == NotificationSoundCategory.all) return own;
    if (own.mode != NotificationSoundMode.systemDefault) return own;
    // Herda do "all" quando o usuário ainda não escolheu nada específico.
    return _readRaw(NotificationSoundCategory.all);
  }

  Future<NotificationSoundPreference> _readRaw(
      NotificationSoundCategory category) async {
    final p = await _prefs;
    final key = category.storageKey;
    final mode = NotificationSoundMode.fromValue(p.getString('$key$_modeSuffix'));
    final path = p.getString('$key$_pathSuffix');
    final label = p.getString('$key$_labelSuffix');
    final srcRaw = p.getString('$key$_sourceSuffix');
    final src = switch (srcRaw) {
      'recorded' => NotificationCustomAudioSource.recordedVoice,
      'bundled' => NotificationCustomAudioSource.bundledAsset,
      'picked' => NotificationCustomAudioSource.pickedFile,
      _ => null,
    };
    return NotificationSoundPreference(
      mode: mode,
      customPath: path,
      customLabel: label,
      customSource: src,
    );
  }

  Future<void> setMode(
      NotificationSoundCategory category, NotificationSoundMode mode) async {
    final p = await _prefs;
    await p.setString('${category.storageKey}$_modeSuffix', mode.value);
    if (mode != NotificationSoundMode.customAudio) {
      await p.remove('${category.storageKey}$_pathSuffix');
      await p.remove('${category.storageKey}$_labelSuffix');
      await p.remove('${category.storageKey}$_sourceSuffix');
    }
  }

  /// Persiste o caminho/rótulo de um áudio customizado para a categoria.
  /// O arquivo já deve estar copiado para uma pasta estável (Documents).
  Future<void> setCustomAudio(
    NotificationSoundCategory category, {
    required String absolutePath,
    required String label,
    required NotificationCustomAudioSource source,
  }) async {
    final p = await _prefs;
    await p.setString(
        '${category.storageKey}$_modeSuffix', NotificationSoundMode.customAudio.value);
    await p.setString('${category.storageKey}$_pathSuffix', absolutePath);
    await p.setString('${category.storageKey}$_labelSuffix', label);
    await p.setString(
      '${category.storageKey}$_sourceSuffix',
      switch (source) {
        NotificationCustomAudioSource.recordedVoice => 'recorded',
        NotificationCustomAudioSource.bundledAsset => 'bundled',
        NotificationCustomAudioSource.pickedFile => 'picked',
      },
    );
  }

  /// Atalho: define um tom embutido (catálogo) para a categoria.
  Future<void> setBundledSound(
    NotificationSoundCategory category, {
    required String catalogId,
    required String displayLabel,
  }) async {
    await setCustomAudio(
      category,
      absolutePath: '$kBundledSoundPathPrefix$catalogId',
      label: displayLabel,
      source: NotificationCustomAudioSource.bundledAsset,
    );
  }

  /// Diretório onde os áudios customizados são guardados (estável entre versões).
  /// Em web retorna null (não há FS local persistente; tudo via DataURL/blob).
  Future<Directory?> ensureAudioDir() async {
    if (kIsWeb) return null;
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}notification_sounds');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return dir;
    } catch (_) {
      return null;
    }
  }

  /// Nome de arquivo padrão por categoria.
  String suggestedFileName(
      NotificationSoundCategory category, String extension) {
    final ext = extension.startsWith('.') ? extension : '.$extension';
    final base = switch (category) {
      NotificationSoundCategory.all => 'todas',
      NotificationSoundCategory.escala => 'escala',
      NotificationSoundCategory.compromisso => 'compromisso',
      NotificationSoundCategory.audiencia => 'audiencia',
      NotificationSoundCategory.financeiro => 'financeiro',
    };
    return '$base$ext';
  }

  /// Apaga áudio customizado da categoria e volta para "padrão do sistema".
  Future<void> clear(NotificationSoundCategory category) async {
    final p = await _prefs;
    final pathKey = '${category.storageKey}$_pathSuffix';
    final filePath = p.getString(pathKey);
    if (filePath != null && filePath.isNotEmpty && !kIsWeb) {
      try {
        final f = File(filePath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    await p.remove(pathKey);
    await p.remove('${category.storageKey}$_labelSuffix');
    await p.remove('${category.storageKey}$_sourceSuffix');
    await p.setString(
        '${category.storageKey}$_modeSuffix', NotificationSoundMode.systemDefault.value);
  }
}
