import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/notification_audio_player.dart';
import '../services/notification_soneca_service.dart';
import '../services/notification_sound_catalog.dart';
import '../services/notification_sound_preferences.dart';
import '../theme/app_colors.dart';
import '../theme/theme_context.dart';
import '../widgets/modern_module_ui.dart';

/// Despertador dos avisos, por módulo: como avisar (som ou só vibrar), qual
/// toque (banco do app — curtos e longos — ou MP3 próprio) e a soneca
/// (repetir 3 ou 5 vezes, a cada 3 ou 5 min, com «Adiar» e «Encerrar»).
///
/// Soneca vai para `settings/notifications.sonecaModulos`; som/modo ficam nas
/// preferências locais, que já sincronizam com o servidor
/// ([NotificationSonecaService.sincronizarSonsNoServidor]).
///
/// Áudio nunca fica tocando: a prévia para ao sair da tela, ao fechar a lista,
/// ao minimizar o app e depois de 15 s ([NotificationAudioPlayer]).
class NotificationDespertadorScreen extends StatefulWidget {
  const NotificationDespertadorScreen({super.key});

  @override
  State<NotificationDespertadorScreen> createState() =>
      _NotificationDespertadorScreenState();
}

class _Modulo {
  const _Modulo({
    required this.chave,
    required this.titulo,
    required this.icone,
    required this.cores,
    required this.categoria,
    required this.exemploTitulo,
    required this.exemploCorpo,
  });

  final String chave;
  final String titulo;
  final IconData icone;
  final List<Color> cores;
  final NotificationSoundCategory categoria;
  final String exemploTitulo;
  final String exemploCorpo;
}

// WisdomApp: a UI só tem Compromissos e Contas — escalas e audiências não
// aparecem nas telas (ver `local_notification_settings_screen.dart`).
const List<_Modulo> _kModulos = [
  _Modulo(
    chave: 'compromisso',
    titulo: 'Compromissos particulares',
    icone: Icons.event_available_rounded,
    cores: [Color(0xFF3B82F6), Color(0xFF2563EB)],
    categoria: NotificationSoundCategory.compromisso,
    exemploTitulo: 'Compromisso em 30 minutos',
    exemploCorpo: 'Dentista · 14:00 · Clínica Sorriso',
  ),
  _Modulo(
    chave: 'financeiro',
    titulo: 'Contas a pagar',
    icone: Icons.receipt_long_rounded,
    cores: [Color(0xFF14B8A6), Color(0xFF0D9488)],
    categoria: NotificationSoundCategory.financeiro,
    exemploTitulo: 'Conta vence hoje',
    exemploCorpo: 'Energia · R\$ 150,00',
  ),
];

class _Soneca {
  _Soneca({this.ativa = false, this.vezes = 3, this.intervalo = 3});
  bool ativa;
  int vezes;
  int intervalo;

  Map<String, dynamic> toMap() =>
      {'ativa': ativa, 'vezes': vezes, 'intervaloMin': intervalo};
}

class _NotificationDespertadorScreenState
    extends State<NotificationDespertadorScreen> {
  static const _kExtensoes = ['mp3', 'wav', 'm4a', 'aac', 'ogg'];
  static const _kMaxBytes = 5 * 1024 * 1024;

  final _prefs = NotificationSoundPreferences.instance;
  final _player = NotificationAudioPlayer.instance;
  final Map<String, _Soneca> _soneca = {
    for (final m in _kModulos) m.chave: _Soneca(),
  };
  final Map<String, NotificationSoundPreference> _som = {};
  bool _carregando = true;

  /// Interruptor geral do despertador — opcional, nasce DESLIGADO.
  bool _geral = false;
  bool _salvando = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    unawaited(_carregar());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_salvando) unawaited(_salvarSoneca());
    unawaited(_player.stop());
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final ref = NotificationSonecaService.docNotificacoes();
      final snap = await ref?.get();
      _geral = snap?.data()?['sonecaAtiva'] == true;
      final mods = (snap?.data()?['sonecaModulos'] as Map?) ?? const {};
      for (final m in _kModulos) {
        final raw = mods[m.chave];
        if (raw is Map) {
          final v = (raw['vezes'] as num?)?.toInt() ?? 3;
          final i = (raw['intervaloMin'] as num?)?.toInt() ?? 3;
          _soneca[m.chave] = _Soneca(
            ativa: raw['ativa'] == true,
            vezes: NotificationSonecaService.vezesValidas.contains(v) ? v : 3,
            intervalo:
                NotificationSonecaService.intervalosValidos.contains(i) ? i : 3,
          );
        }
      }
    } catch (_) {}
    for (final m in _kModulos) {
      _som[m.chave] = await _prefs.readOwn(m.categoria);
    }
    if (mounted) setState(() => _carregando = false);
  }

  void _mudarSoneca(String chave, void Function(_Soneca s) mudar) {
    setState(() => mudar(_soneca[chave]!));
    _salvando = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _salvarSoneca);
  }

  Future<void> _salvarSoneca() async {
    _salvando = false;
    final ref = NotificationSonecaService.docNotificacoes();
    if (ref == null) return;
    try {
      await ref.set({
        'sonecaAtiva': _geral,
        'sonecaModulos': {
          for (final e in _soneca.entries) e.key: e.value.toMap(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      _toast('Não consegui salvar agora. Confira a internet.', erro: true);
    }
  }

  Future<void> _recarregarSom(_Modulo m) async {
    final pref = await _prefs.readOwn(m.categoria);
    if (mounted) setState(() => _som[m.chave] = pref);
  }

  // ── Som / vibrar ─────────────────────────────────────────────────────────

  String _chaveUltimoToque(_Modulo m) => 'desp_ultimo_toque_${m.chave}';

  bool _soVibrar(_Modulo m) {
    final mode = _som[m.chave]?.mode;
    return mode == NotificationSoundMode.vibrateOnly ||
        mode == NotificationSoundMode.silent;
  }

  Future<void> _usarSom(_Modulo m) async {
    await _player.stop();
    final sp = await SharedPreferences.getInstance();
    final ultimo = sp.getString(_chaveUltimoToque(m));
    final item = findCatalogItemById(ultimo);
    if (item != null) {
      await _prefs.setBundledSound(m.categoria,
          catalogId: item.id, displayLabel: item.displayName);
    } else {
      await _prefs.setMode(m.categoria, NotificationSoundMode.systemDefault);
    }
    await _recarregarSom(m);
  }

  Future<void> _usarVibrar(_Modulo m) async {
    await _player.stop();
    final atual = _idDoCatalogo(_som[m.chave]);
    if (atual != null) {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_chaveUltimoToque(m), atual);
    }
    await _prefs.setMode(m.categoria, NotificationSoundMode.vibrateOnly);
    await _recarregarSom(m);
    unawaited(HapticFeedback.heavyImpact());
  }

  String? _idDoCatalogo(NotificationSoundPreference? pref) {
    final path = pref?.customPath ?? '';
    if (pref?.mode != NotificationSoundMode.customAudio ||
        !path.startsWith(kBundledSoundPathPrefix)) {
      return null;
    }
    return path.substring(kBundledSoundPathPrefix.length);
  }

  String _rotuloDoToque(_Modulo m) {
    final pref = _som[m.chave];
    if (pref == null) return 'Padrão do celular';
    if (_soVibrar(m)) return 'Sem som — só vibra';
    final item = findCatalogItemById(_idDoCatalogo(pref));
    if (item != null) {
      return item.longo
          ? '${item.displayName} · ${item.duracaoSeg ?? ''} s'
          : item.displayName;
    }
    if (pref.isCustom) return '🎵 ${pref.customLabel ?? 'Meu áudio'}';
    return 'Padrão do celular';
  }

  Future<void> _ouvir(_Modulo m) async {
    final pref = _som[m.chave];
    if (_soVibrar(m)) {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 180));
      await HapticFeedback.heavyImpact();
      return;
    }
    final id = _idDoCatalogo(pref);
    if (id != null) {
      await _player.playBundledById(id);
    } else if (pref != null && pref.isCustom) {
      await _player.preview(path: pref.customPath);
    } else {
      _toast('Usa o som padrão de notificação do seu celular.');
    }
  }

  Future<void> _escolherToque(_Modulo m) async {
    await _player.stop();
    if (!mounted) return;
    final escolhido = await showModalBottomSheet<NotificationSoundCatalogItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ListaDeToques(
        modulo: m,
        atual: _idDoCatalogo(_som[m.chave]),
        player: _player,
      ),
    );
    // A lista pode ter deixado uma prévia tocando.
    await _player.stop();
    if (escolhido == null) return;
    await _prefs.setBundledSound(m.categoria,
        catalogId: escolhido.id, displayLabel: escolhido.displayName);
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_chaveUltimoToque(m), escolhido.id);
    await _recarregarSom(m);
    _toast('Toque «${escolhido.displayName}» em ${m.titulo}.');
  }

  Future<void> _meuMp3(_Modulo m) async {
    await _player.stop();
    try {
      final pick = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: _kExtensoes,
      );
      if (pick == null || pick.files.isEmpty) return;
      final f = pick.files.first;
      final bytes = f.bytes;
      final ext = (f.extension ?? '').toLowerCase();
      if (bytes == null || bytes.isEmpty || !_kExtensoes.contains(ext)) {
        _toast('Formato não suportado. Use MP3, WAV, M4A, AAC ou OGG.', erro: true);
        return;
      }
      if (bytes.length > _kMaxBytes) {
        _toast('Arquivo grande demais. Limite: 5 MB.', erro: true);
        return;
      }
      if (kIsWeb) {
        _toast('O áudio próprio funciona no app instalado no celular.', erro: true);
        return;
      }
      final dir = await _prefs.ensureAudioDir();
      if (dir == null) {
        _toast('Não foi possível salvar o arquivo no aparelho.', erro: true);
        return;
      }
      final destino = File(p.join(dir.path, _prefs.suggestedFileName(m.categoria, ext)));
      if (destino.existsSync()) destino.deleteSync();
      await destino.writeAsBytes(bytes, flush: true);
      await _prefs.setCustomAudio(
        m.categoria,
        absolutePath: destino.path,
        label: f.name,
        source: NotificationCustomAudioSource.pickedFile,
      );
      await _recarregarSom(m);
      _toast('«${f.name}» definido. Toca até 29 s, também com o app fechado.');
    } catch (e) {
      _toast('Erro ao escolher o áudio.', erro: true);
    }
  }

  void _toast(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: erro ? const Color(0xFFDC2626) : null,
      ));
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ModernModuleUI.scaffoldBgOf(context),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: AppColors.logoGradient),
          ),
        ),
        title: const Text('Despertador e sons',
            style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _banner(),
                const SizedBox(height: 16),
                for (final m in _kModulos) ...[
                  _cardModulo(m),
                  const SizedBox(height: 16),
                ],
                _notas(),
              ],
            ),
    );
  }

  /// Explica a regra: o «Despertar» é ligado em cada item (padrão desligado);
  /// esta tela só define COMO ele toca em cada módulo. O antigo interruptor
  /// geral + «o que deve despertar» saiu da tela porque o servidor não liga
  /// mais o despertador do módulo inteiro (o valor `sonecaAtiva` continua
  /// gravado como estava).
  Widget _banner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF97316), Color(0xFFDB2777), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        children: [
          Text('⏰', style: TextStyle(fontSize: 34)),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Despertar por item',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Ligue o Despertar em cada compromisso; aqui você '
                  'escolhe como ele toca. Item com o Despertar desligado '
                  'chega como notificação normal.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardModulo(_Modulo m) {
    final s = _soneca[m.chave]!;
    final vibrar = _soVibrar(m);
    final cor = m.cores.last;
    return Container(
      decoration: context.appPanelDecoration(radius: 22),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabeçalho colorido do módulo.
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: m.cores),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(m.icone, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.titulo,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 15.5)),
                      const SizedBox(height: 2),
                      Text(
                        'Com Despertar: ${s.vezes}× a cada ${s.intervalo} min',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _rotulo('Como avisar'),
                Row(
                  children: [
                    Expanded(
                      child: _opcao(
                        texto: '🔊 Com som',
                        marcado: !vibrar,
                        cor: cor,
                        onTap: () => _usarSom(m),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _opcao(
                        texto: '📳 Só vibrar',
                        marcado: vibrar,
                        cor: cor,
                        onTap: () => _usarVibrar(m),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _rotulo('Toque'),
                _linhaDoToque(m, vibrar),
                // Vezes/intervalo valem para os itens com o Despertar ligado.
                Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 14),
                            _rotulo('Repetir'),
                            Row(
                              children: [
                                for (final v in NotificationSonecaService.vezesValidas) ...[
                                  Expanded(
                                    child: _opcao(
                                      texto: '$v vezes',
                                      marcado: s.vezes == v,
                                      cor: cor,
                                      onTap: () => _mudarSoneca(m.chave, (x) => x.vezes = v),
                                    ),
                                  ),
                                  if (v != NotificationSonecaService.vezesValidas.last)
                                    const SizedBox(width: 8),
                                ],
                              ],
                            ),
                            const SizedBox(height: 10),
                            _rotulo('Intervalo'),
                            Row(
                              children: [
                                for (final i in NotificationSonecaService.intervalosValidos) ...[
                                  Expanded(
                                    child: _opcao(
                                      texto: 'a cada $i min',
                                      marcado: s.intervalo == i,
                                      cor: cor,
                                      onTap: () =>
                                          _mudarSoneca(m.chave, (x) => x.intervalo = i),
                                    ),
                                  ),
                                  if (i != NotificationSonecaService.intervalosValidos.last)
                                    const SizedBox(width: 8),
                                ],
                              ],
                            ),
                          ],
                        ),
                const SizedBox(height: 16),
                _rotulo('Prévia'),
                _PreviaNotificacao(
                  modulo: m,
                  soneca: _Soneca(
                    ativa: true,
                    vezes: s.vezes,
                    intervalo: s.intervalo,
                  ),
                  vibrar: vibrar,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _linhaDoToque(_Modulo m, bool vibrar) {
    final cor = m.cores.last;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(vibrar ? Icons.vibration_rounded : Icons.music_note_rounded,
                  color: cor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _rotuloDoToque(m),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: context.appTextPrimary,
                  ),
                ),
              ),
              ValueListenableBuilder<String?>(
                valueListenable: _player.tocando,
                builder: (_, tocando, __) {
                  final tocandoEste = tocando != null &&
                      (tocando == _idDoCatalogo(_som[m.chave]) ||
                          tocando == _som[m.chave]?.customPath);
                  return IconButton.filledTonal(
                    tooltip: tocandoEste ? 'Parar' : 'Ouvir',
                    onPressed: () =>
                        tocandoEste ? _player.stop() : _ouvir(m),
                    icon: Icon(tocandoEste
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded),
                  );
                },
              ),
            ],
          ),
          if (!vibrar)
            Wrap(
              spacing: 6,
              children: [
                TextButton.icon(
                  onPressed: () => _escolherToque(m),
                  icon: const Icon(Icons.library_music_rounded, size: 18),
                  label: const Text('Banco de toques'),
                  style: TextButton.styleFrom(foregroundColor: cor),
                ),
                TextButton.icon(
                  onPressed: () => _meuMp3(m),
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: const Text('Meu MP3'),
                  style: TextButton.styleFrom(foregroundColor: cor),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _rotulo(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(
          t.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w900,
            color: context.appTextMuted,
          ),
        ),
      );

  Widget _opcao({
    required String texto,
    required bool marcado,
    required Color cor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: marcado ? cor : cor.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: marcado ? cor : cor.withValues(alpha: 0.25)),
            boxShadow: marcado
                ? [BoxShadow(color: cor.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))]
                : null,
          ),
          child: Text(
            texto,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: marcado ? Colors.white : context.appTextPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _notas() {
    final estilo = TextStyle(
      fontSize: 12,
      height: 1.4,
      fontWeight: FontWeight.w600,
      color: context.appTextSecondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('• O despertador repete só o push. O e-mail avisa uma vez.', style: estilo),
        Text('• Tocar no aviso (ou concluir o evento) também encerra as repetições.', style: estilo),
        Text('• Nenhuma repetição passa do horário do evento.', style: estilo),
        Text('• Android: para os botões funcionarem com o app fechado, deixe o '
            'WisdomApp sem restrição de bateria.', style: estilo),
        Text('• iPhone: aviso sem som também não vibra (regra da Apple). O MP3 '
            'próprio toca até 29 s.', style: estilo),
      ],
    );
  }
}

/// Como o aviso vai aparecer no celular — com os botões do despertador e a
/// linha do tempo das repetições.
class _PreviaNotificacao extends StatelessWidget {
  const _PreviaNotificacao({
    required this.modulo,
    required this.soneca,
    required this.vibrar,
  });

  final _Modulo modulo;
  final _Soneca soneca;
  final bool vibrar;

  @override
  Widget build(BuildContext context) {
    final cor = modulo.cores.last;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: cor.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: modulo.cores),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(modulo.icone, size: 14, color: Colors.white),
              ),
              const SizedBox(width: 8),
              const Text('WisdomApp',
                  style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w700)),
              const Text(' · agora', style: TextStyle(color: Colors.white38, fontSize: 11.5)),
              const Spacer(),
              Icon(vibrar ? Icons.vibration_rounded : Icons.volume_up_rounded,
                  size: 15, color: Colors.white54),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${soneca.ativa ? '⏰ ' : ''}${modulo.exemploTitulo}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 2),
          Text(modulo.exemploCorpo,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          if (soneca.ativa) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (final b in const ['⏰ Adiar 3 min', '⏰ Adiar 5 min', '✔️ Encerrar']) ...[
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: FittedBox(
                        child: Text(b,
                            style: TextStyle(
                                color: b.startsWith('✔️') ? const Color(0xFF6EE7B7) : Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12)),
                      ),
                    ),
                  ),
                  if (!b.startsWith('✔️')) const SizedBox(width: 6),
                ],
              ],
            ),
            const SizedBox(height: 12),
            _LinhaDoTempo(vezes: soneca.vezes, intervalo: soneca.intervalo, cor: cor),
          ],
        ],
      ),
    );
  }
}

class _LinhaDoTempo extends StatelessWidget {
  const _LinhaDoTempo({required this.vezes, required this.intervalo, required this.cor});

  final int vezes;
  final int intervalo;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    final marcos = ['Aviso', for (var k = 1; k <= vezes; k++) '+${k * intervalo}'];
    return Row(
      children: [
        for (var i = 0; i < marcos.length; i++) ...[
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: i == 0 ? cor : cor.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
              ),
              const SizedBox(height: 4),
              Text(marcos[i],
                  style: const TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w700)),
            ],
          ),
          if (i < marcos.length - 1)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.only(bottom: 16),
                color: cor.withValues(alpha: 0.35),
              ),
            ),
        ],
      ],
    );
  }
}

/// Banco de toques: «Despertador (longos)» e «Curtos», cada um com ▶/■.
class _ListaDeToques extends StatelessWidget {
  const _ListaDeToques({
    required this.modulo,
    required this.atual,
    required this.player,
  });

  final _Modulo modulo;
  final String? atual;
  final NotificationAudioPlayer player;

  @override
  Widget build(BuildContext context) {
    final cor = modulo.cores.last;
    Widget grupo(String titulo, String sub, List<NotificationSoundCatalogItem> itens) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(titulo,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: context.appTextPrimary)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text(sub,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.appTextSecondary)),
          ),
          for (final item in itens)
            ValueListenableBuilder<String?>(
              valueListenable: player.tocando,
              builder: (_, tocando, __) {
                final tocandoEste = tocando == item.id;
                final marcado = atual == item.id;
                return ListTile(
                  onTap: () => Navigator.of(context).pop(item),
                  leading: IconButton.filledTonal(
                    onPressed: () =>
                        tocandoEste ? player.stop() : player.playBundledById(item.id),
                    icon: Icon(tocandoEste ? Icons.stop_rounded : Icons.play_arrow_rounded),
                  ),
                  title: Text(item.displayName,
                      style: TextStyle(fontWeight: FontWeight.w800, color: context.appTextPrimary)),
                  subtitle: Text(
                    [
                      if (item.duracaoSeg != null) '${item.duracaoSeg} s',
                      item.description ?? '',
                    ].where((x) => x.isNotEmpty).join(' · '),
                    style: TextStyle(fontSize: 12, color: context.appTextSecondary),
                  ),
                  trailing: marcado
                      ? Icon(Icons.check_circle_rounded, color: cor)
                      : Icon(Icons.radio_button_unchecked_rounded, color: context.appTextMuted),
                );
              },
            ),
        ],
      );
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: ModernModuleUI.scaffoldBgOf(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10),
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: context.appTextMuted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Text('Toque de ${modulo.titulo}',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: context.appTextPrimary)),
            ),
            grupo('🚨 Despertador — extra longos', 'Uns 25 segundos tocando. A prévia aqui para em 15 s; no aviso toca inteiro.', kToquesExtraLongos),
            grupo('⏰ Despertador — toques longos', 'De 5 a 10 segundos, para não passar batido.', kToquesLongos),
            grupo('🔔 Toques curtos', 'Discretos, de 1 a 2 segundos.', kToquesCurtos),
          ],
        ),
      ),
    );
  }
}
