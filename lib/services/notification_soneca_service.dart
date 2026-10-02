import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/firestore_user_doc_id.dart';
import 'local_notifications_plugin_holder.dart';
import 'notification_som_proprio.dart';
import 'notification_sound_catalog.dart';
import 'notification_sound_preferences.dart';

/// Despertador (soneca) dos avisos de agenda + toques nativos.
///
/// **Soneca** — o servidor repete o aviso 3 ou 5 vezes. A notificação traz
/// «Adiar 3 min», «Adiar 5 min» e «Encerrar»; cada botão chama a função HTTP
/// `ctSonecaAcao` com o token que veio no push (funciona com o app fechado:
/// o handler de segundo plano roda num isolate sem Firebase). Tocar no corpo
/// da notificação também encerra — é o «já vi» do despertador.
///
/// **Toques nativos** — os `.wav` do catálogo vão em `res/raw` (Android) e são
/// copiados para `Library/Sounds` (iOS). O servidor escolhe o canal
/// `ct_som_<id>` / `aps.sound = <id>.wav`; aqui só garantimos que existam.
class NotificationSonecaService {
  NotificationSonecaService._();

  static const String acaoAdiar3 = 'ct_adiar_3';
  static const String acaoAdiar5 = 'ct_adiar_5';
  static const String acaoEncerrar = 'ct_encerrar';
  static const String categoriaIos = 'CT_SONECA';
  static const String prefixoCanalSom = 'ct_som_';
  static const String canalVibrar = 'ct_vibrar';
  static const String canalSilencio = 'ct_silencio';

  /// Canal pelo modo que veio no push (`modoAviso`) e pelo toque (`soundId`).
  /// `null` = canal padrão do módulo.
  static ({String id, String nome})? canalPara({
    required String modoAviso,
    required String soundId,
    String canalAndroid = '',
  }) {
    if (modoAviso == 'vibrar') return (id: canalVibrar, nome: 'Avisos só vibrando');
    if (modoAviso == 'silencio') return (id: canalSilencio, nome: 'Avisos silenciosos');
    // Toque próprio (MP3/voz): canal criado neste aparelho ao escolher o áudio.
    if (canalAndroid.startsWith('ct_som_user_')) {
      return (id: canalAndroid, nome: 'Meu toque');
    }
    final item = findCatalogItemById(soundId);
    if (item == null) return null;
    return (
      id: canalDoSom(item.id),
      nome: item.longo
          ? 'Despertador: ${item.displayName}'
          : 'Toque: ${item.displayName}',
    );
  }

  /// Canais do DESPERTADOR (soneca): mesmo toque do catálogo, mas com áudio de
  /// ALARME (volume de alarme, toca mesmo com a campainha baixa). O Android
  /// fixa o áudio no canal ao criar, por isso é um canal novo com versão no id
  /// — os `ct_som_<id>` antigos continuam valendo para os avisos comuns.
  static const String prefixoCanalDespertador = 'ct_desp1_';

  static final Set<String> _canaisDespertadorCriados = {};

  /// Troca o canal do toque do catálogo pelo equivalente de despertador
  /// (criado na hora, uma vez). «Só vibrar», silencioso, toque próprio e o
  /// canal padrão do módulo ficam como estão. Nunca lança.
  static Future<({String id, String nome})?> canalDoDespertador(
    ({String id, String nome})? canal,
  ) async {
    if (canal == null || !canal.id.startsWith(prefixoCanalSom)) return canal;
    if (canal.id.startsWith('ct_som_user_')) return canal;
    final soundId = canal.id.substring(prefixoCanalSom.length);
    final item = findCatalogItemById(soundId);
    if (item == null) return canal;
    final id = '$prefixoCanalDespertador${item.id}';
    final nome = 'Despertador (alarme): ${item.displayName}';
    if (_canaisDespertadorCriados.contains(id)) return (id: id, nome: nome);
    try {
      final androidImpl = localNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl == null) return canal;
      await androidImpl.createNotificationChannel(
        AndroidNotificationChannel(
          id,
          nome,
          description:
              'Despertador com o toque «${item.displayName}». Toca até você '
              'tocar em Encerrar ou Adiar.',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound(item.id),
          enableVibration: true,
          showBadge: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
        ),
      );
      _canaisDespertadorCriados.add(id);
      return (id: id, nome: nome);
    } catch (_) {
      return canal;
    }
  }

  static const List<int> vezesValidas = [3, 5];
  static const List<int> intervalosValidos = [3, 5];

  /// Os três botões do despertador (Android).
  static List<AndroidNotificationAction> get acoesAndroid => const [
        AndroidNotificationAction(acaoAdiar3, '⏰ Adiar 3 min',
            showsUserInterface: false, cancelNotification: true),
        AndroidNotificationAction(acaoAdiar5, '⏰ Adiar 5 min',
            showsUserInterface: false, cancelNotification: true),
        AndroidNotificationAction(acaoEncerrar, '✔️ Encerrar',
            showsUserInterface: false, cancelNotification: true),
      ];

  static bool temSoneca(Map<String, dynamic> data) =>
      (data['soneca'] ?? '').toString() == '1' &&
      (data['sonecaToken'] ?? '').toString().isNotEmpty;

  /// Campos da soneca que o payload local precisa carregar até o botão.
  static Map<String, String> camposDoPayload(Map<String, dynamic> data) {
    const chaves = [
      'soneca',
      'sonecaAvisoId',
      'sonecaUid',
      'sonecaToken',
      'sonecaUrl',
      'sonecaIndice',
      'sonecaTotal',
    ];
    return {
      for (final k in chaves)
        if ((data[k] ?? '').toString().isNotEmpty) k: data[k].toString(),
    };
  }

  /// Id estável da notificação por aviso: a repetição SUBSTITUI a anterior
  /// na bandeja em vez de empilhar cinco iguais. (FNV-1a — `Object.hash` muda
  /// entre execuções.)
  static int idDaNotificacao(String avisoId) {
    var h = 0x811c9dc5;
    for (final c in utf8.encode(avisoId)) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return 900000 + (h % 90000000);
  }

  static Map<String, dynamic>? _dadosDoPayload(String? payload) {
    if (payload == null || !payload.trimLeft().startsWith('{')) return null;
    try {
      final m = jsonDecode(payload);
      return m is Map ? Map<String, dynamic>.from(m) : null;
    } catch (_) {
      return null;
    }
  }

  /// Executa «adiar» / «encerrar» no servidor. Nunca lança.
  static Future<bool> executar(
    Map<String, dynamic> data,
    String acao, {
    int? minutos,
  }) async {
    if (!temSoneca(data)) return false;
    final url = (data['sonecaUrl'] ?? '').toString();
    if (!url.startsWith('https://')) return false;
    try {
      final resp = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'u': data['sonecaUid'],
              'a': data['sonecaAvisoId'],
              't': data['sonecaToken'],
              'acao': acao,
              if (minutos != null) 'min': minutos,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Trata a resposta de uma notificação com soneca (botão ou toque).
  /// Devolve `true` quando era um botão da soneca (nada mais a fazer).
  static Future<bool> tratarResposta(NotificationResponse resp) async {
    final data = _dadosDoPayload(resp.payload);
    if (data == null || !temSoneca(data)) return false;
    final acao = resp.actionId ?? '';
    if (acao == acaoAdiar3) {
      await executar(data, 'adiar', minutos: 3);
      return true;
    }
    if (acao == acaoAdiar5) {
      await executar(data, 'adiar', minutos: 5);
      return true;
    }
    if (acao == acaoEncerrar) {
      await executar(data, 'encerrar');
      return true;
    }
    // Toque no corpo: a pessoa viu o aviso — encerra as repetições e segue
    // para a navegação normal (abre o app).
    await executar(data, 'encerrar');
    return false;
  }

  /// Toque num push remoto (iOS / Android com o sistema desenhando): encerra.
  static void encerrarAoAbrir(Map<String, dynamic> data) {
    if (temSoneca(data)) unawaited(executar(data, 'encerrar'));
  }

  // ── Toques nativos ────────────────────────────────────────────────────────

  static String canalDoSom(String soundId) => '$prefixoCanalSom$soundId';

  /// Um canal por toque do catálogo (Android fixa o som no canal). Nunca
  /// apaga: o id do canal carrega o som, então não há o que atualizar.
  static Future<void> garantirCanaisDeSom(
    AndroidFlutterLocalNotificationsPlugin androidImpl,
  ) async {
    // «Só vibrar» e «silencioso» escolhidos no módulo — o servidor manda o
    // aviso direto para estes canais, então valem com o app fechado.
    try {
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          canalVibrar,
          'Avisos só vibrando',
          description: 'Avisos dos módulos configurados para só vibrar.',
          importance: Importance.max,
          playSound: false,
          enableVibration: true,
          showBadge: true,
        ),
      );
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          canalSilencio,
          'Avisos silenciosos',
          description: 'Avisos sem som e sem vibração.',
          importance: Importance.high,
          playSound: false,
          enableVibration: false,
          showBadge: true,
        ),
      );
    } catch (_) {}
    for (final item in kNotificationSoundCatalog) {
      try {
        await androidImpl.createNotificationChannel(
          AndroidNotificationChannel(
            canalDoSom(item.id),
            item.longo
                ? 'Despertador: ${item.displayName}'
                : 'Toque: ${item.displayName}',
            description: 'Avisos com o toque «${item.displayName}».',
            importance: Importance.max,
            playSound: true,
            sound: RawResourceAndroidNotificationSound(item.id),
            enableVibration: true,
            showBadge: true,
          ),
        );
      } catch (_) {}
    }
  }

  static bool _sonsIosCopiados = false;

  /// iOS toca `aps.sound` a partir de `Library/Sounds` do app — copia os
  /// `.wav` do catálogo para lá (uma vez por versão do arquivo).
  static Future<void> instalarSonsIos() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    if (_sonsIosCopiados) return;
    _sonsIosCopiados = true;
    try {
      final lib = await getLibraryDirectory();
      final dir = Directory('${lib.path}/Sounds');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      for (final item in kNotificationSoundCatalog) {
        final destino = File('${dir.path}/${item.id}.wav');
        final dados = await rootBundle.load(item.assetPath);
        if (destino.existsSync() &&
            destino.lengthSync() == dados.lengthInBytes) {
          continue;
        }
        await destino.writeAsBytes(dados.buffer.asUint8List(), flush: true);
      }
    } catch (_) {
      _sonsIosCopiados = false;
    }
  }

  // ── Configuração no Firestore ─────────────────────────────────────────────

  /// Mesmo doc que a tela de notificações usa (titular no acesso delegado).
  static DocumentReference<Map<String, dynamic>>? docNotificacoes() {
    final auth = FirebaseAuth.instance.currentUser?.uid;
    if (auth == null || auth.isEmpty) return null;
    final uid = firestoreUserDocIdForAppShell(auth);
    if (uid.isEmpty) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('notifications');
  }

  /// Converte o MP3/voz da categoria em toque nativo e avisa o servidor.
  static Future<void> prepararSomProprio(
    NotificationSoundCategory cat, {
    required String caminho,
    required String rotulo,
  }) async {
    try {
      await prepararSomProprioNativo(
        categoria: cat.name,
        caminho: caminho,
        rotulo: rotulo,
      );
    } catch (_) {}
    await sincronizarSonsNoServidor();
  }

  /// Leva ao servidor, por categoria, COMO avisar e COM QUAL toque:
  /// - `modoNotificacao`: som | vibrar | silencio (vale com o app fechado);
  /// - `somNotificacao`: id do catálogo ou «proprio» (MP3/voz);
  /// - `somProprio`: canal Android / arquivo iOS do toque próprio deste
  ///   aparelho (outro aparelho sem o arquivo cai no som padrão).
  static Future<void> sincronizarSonsNoServidor() async {
    final ref = docNotificacoes();
    if (ref == null) return;
    try {
      final prefs = NotificationSoundPreferences.instance;
      final sp = await SharedPreferences.getInstance();
      final sons = <String, String>{};
      final modos = <String, String>{};
      final proprios = <String, Map<String, String>>{};
      for (final cat in NotificationSoundCategory.values) {
        final raw = await prefs.readOwn(cat);
        var id = '';
        final path = raw.customPath ?? '';
        if (raw.mode == NotificationSoundMode.customAudio &&
            raw.customSource == NotificationCustomAudioSource.bundledAsset &&
            path.startsWith(kBundledSoundPathPrefix)) {
          final candidato = path.substring(kBundledSoundPathPrefix.length);
          if (findCatalogItemById(candidato) != null) id = candidato;
        } else if (raw.mode == NotificationSoundMode.customAudio &&
            path.isNotEmpty) {
          final chave = 'notif_som_proprio_${cat.name}';
          final android = sp.getString('${chave}_canal') ?? '';
          final ios = sp.getString('${chave}_ios') ?? '';
          if (android.isNotEmpty || ios.isNotEmpty) {
            id = 'proprio';
            proprios[cat.name] = {
              if (android.isNotEmpty) 'android': android,
              if (ios.isNotEmpty) 'ios': ios,
            };
          }
        }
        sons[cat.name] = id;
        modos[cat.name] = switch (raw.mode) {
          NotificationSoundMode.vibrateOnly => 'vibrar',
          NotificationSoundMode.silent => 'silencio',
          // «padrão do sistema» na categoria herda «Todas» no servidor.
          NotificationSoundMode.systemDefault => '',
          NotificationSoundMode.customAudio => 'som',
        };
      }
      await ref.set({
        'somNotificacao': sons,
        'modoNotificacao': modos,
        'somProprio': proprios,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}

/// Handler de segundo plano dos botões (isolate próprio, sem Flutter UI).
/// Espera a chamada HTTP terminar — o isolate não pode morrer no meio.
@pragma('vm:entry-point')
Future<void> notificacaoSonecaEmSegundoPlano(NotificationResponse resp) async {
  await NotificationSonecaService.tratarResposta(resp);
}
