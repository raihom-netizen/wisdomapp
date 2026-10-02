import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../models/despertar_item.dart';
import '../services/notification_audio_player.dart';
import '../services/notification_sound_catalog.dart';
import '../theme/theme_context.dart';
import 'modern_module_ui.dart';

/// Cartão «Despertar» dos formulários de compromisso, audiência, escala/plantão
/// e plantão recorrente: interruptor + «Som» × «Só vibrar» + toque com prévia.
///
/// Padrão DESLIGADO: só o item ligado desperta; o módulo (Notificações ›
/// Despertador e sons) define só como toca (ver [DespertarItem]).
class DespertarItemCard extends StatefulWidget {
  const DespertarItemCard({
    super.key,
    required this.value,
    required this.onChanged,
    this.descricaoItem = 'este item',
  });

  final DespertarItem value;
  final ValueChanged<DespertarItem> onChanged;

  /// «este compromisso», «esta audiência», «este plantão»…
  final String descricaoItem;

  @override
  State<DespertarItemCard> createState() => _DespertarItemCardState();
}

class _DespertarItemCardState extends State<DespertarItemCard> {
  final NotificationAudioPlayer _player = NotificationAudioPlayer.instance;

  DespertarItem get _v => widget.value;

  @override
  void dispose() {
    _player.stop();
    super.dispose();
  }

  bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  String get _nomeDoToque {
    if (_v.som.isEmpty) return 'Padrão do despertador';
    if (_v.som == 'proprio') return 'Meu toque (MP3)';
    return findCatalogItemById(_v.som)?.displayName ?? 'Padrão do despertador';
  }

  /// Toque que a prévia toca: o escolhido, senão o padrão de despertar.
  String get _idDaPrevia =>
      _v.som.isNotEmpty && findCatalogItemById(_v.som) != null
          ? _v.som
          : kDespertarSomPadrao;

  void _set(DespertarItem v) {
    HapticFeedback.selectionClick();
    widget.onChanged(v);
  }

  Future<void> _ouvir() async {
    if (_v.soVibrar) {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 180));
      await HapticFeedback.heavyImpact();
      return;
    }
    if (_player.tocando.value == _idDaPrevia) {
      await _player.stop();
    } else {
      await _player.playBundledById(_idDaPrevia);
    }
  }

  Future<void> _escolherToque() async {
    await _player.stop();
    if (!mounted) return;
    final escolhido = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ListaDeToquesDespertar(
        atual: _v.som,
        player: _player,
      ),
    );
    await _player.stop();
    if (escolhido == null || !mounted) return;
    _set(_v.copyWith(som: escolhido));
  }

  @override
  Widget build(BuildContext context) {
    final neon = context.appNeon;
    final ativo = _v.ativo;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: context.appPanelDecoration(
        radius: 16,
        borderAccent: ativo ? neon : null,
        borderAlpha: 0.45,
        borderWidth: ativo ? 1.4 : 1,
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              if (ativo) _player.stop();
              _set(_v.copyWith(ativo: !ativo));
            },
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: ativo
                        ? neon.withValues(alpha: 0.16)
                        : context.appMutedSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    ativo ? Icons.alarm_on_rounded : Icons.alarm_off_rounded,
                    color: ativo ? neon : context.appTextSecondary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Despertar',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: context.appTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ativo
                            ? (_v.soVibrar
                                ? 'Ligado · só vibrar'
                                : 'Ligado · $_nomeDoToque')
                            : 'Desligado · toque para ligar',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: ativo ? neon : context.appTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: ativo,
                  activeThumbColor: context.appNeonOn,
                  activeTrackColor: neon,
                  onChanged: (v) {
                    if (!v) _player.stop();
                    _set(_v.copyWith(ativo: v));
                  },
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !ativo
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 10, right: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _chipModo(
                                rotulo: 'Som',
                                icone: Icons.music_note_rounded,
                                marcado: !_v.soVibrar,
                                onTap: () => _set(
                                    _v.copyWith(modo: DespertarItem.modoSom)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _chipModo(
                                rotulo: 'Só vibrar',
                                icone: Icons.vibration_rounded,
                                marcado: _v.soVibrar,
                                onTap: () {
                                  _player.stop();
                                  _set(_v.copyWith(
                                      modo: DespertarItem.modoVibrar));
                                },
                              ),
                            ),
                          ],
                        ),
                        if (!_v.soVibrar) ...[
                          const SizedBox(height: 8),
                          _linhaDoToque(),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          'Toca até você tocar em Encerrar (ou Adiar). '
                          'Vale só para ${widget.descricaoItem}. Repetições e '
                          'toque padrão: Notificações › Despertador e sons.'
                          '${_ios ? ' No iPhone cada toque dura até 30 s (limite da Apple).' : ''}',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.3,
                            color: context.appTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chipModo({
    required String rotulo,
    required IconData icone,
    required bool marcado,
    required VoidCallback onTap,
  }) {
    final neon = context.appNeon;
    return Material(
      color: marcado ? neon : context.appChipIdleBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: marcado ? neon : context.appChipIdleBorder,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icone,
                  size: 18,
                  color:
                      marcado ? context.appNeonOn : context.appChipIdleLabel),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  rotulo,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color:
                        marcado ? context.appNeonOn : context.appChipIdleLabel,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _linhaDoToque() {
    return Container(
      decoration: BoxDecoration(
        color: context.appMutedSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
      child: Row(
        children: [
          ValueListenableBuilder<String?>(
            valueListenable: _player.tocando,
            builder: (_, tocando, __) => IconButton(
              tooltip: 'Ouvir',
              onPressed: _ouvir,
              icon: Icon(
                tocando == _idDaPrevia
                    ? Icons.stop_circle_rounded
                    : Icons.play_circle_fill_rounded,
                color: context.appNeon,
                size: 30,
              ),
            ),
          ),
          Expanded(
            child: Text(
              _nomeDoToque,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                color: context.appTextPrimary,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _escolherToque,
            icon: const Icon(Icons.queue_music_rounded, size: 18),
            label: const Text('Trocar'),
            style: TextButton.styleFrom(foregroundColor: context.appNeon),
          ),
        ],
      ),
    );
  }
}

/// Mesmo toque padrão do servidor (`agenda_despertar_item.js` SOM_PADRAO).
const String kDespertarSomPadrao = 'extra_despertar_crescente';

/// Banco de toques do despertar: padrão, extra longos, longos e curtos.
/// Devolve o id escolhido ('' = padrão do despertador).
class _ListaDeToquesDespertar extends StatelessWidget {
  const _ListaDeToquesDespertar({required this.atual, required this.player});

  final String atual;
  final NotificationAudioPlayer player;

  @override
  Widget build(BuildContext context) {
    final neon = context.appNeon;

    Widget linha({
      required String id,
      required String previa,
      required String titulo,
      required String sub,
    }) {
      return ValueListenableBuilder<String?>(
        valueListenable: player.tocando,
        builder: (_, tocando, __) {
          final tocandoEste = previa.isNotEmpty && tocando == previa;
          final marcado = atual == id;
          return ListTile(
            onTap: () => Navigator.of(context).pop(id),
            leading: previa.isEmpty
                ? IconButton.filledTonal(
                    onPressed: null,
                    icon: const Icon(Icons.library_music_rounded),
                  )
                : IconButton.filledTonal(
                    onPressed: () => tocandoEste
                        ? player.stop()
                        : player.playBundledById(previa),
                    icon: Icon(tocandoEste
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded),
                  ),
            title: Text(titulo,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: context.appTextPrimary)),
            subtitle: sub.isEmpty
                ? null
                : Text(sub,
                    style: TextStyle(
                        fontSize: 12, color: context.appTextSecondary)),
            trailing: marcado
                ? Icon(Icons.check_circle_rounded, color: neon)
                : Icon(Icons.radio_button_unchecked_rounded,
                    color: context.appTextMuted),
          );
        },
      );
    }

    Widget grupo(
        String titulo, String sub, List<NotificationSoundCatalogItem> itens) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(titulo,
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: context.appTextPrimary)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text(sub,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.appTextSecondary)),
          ),
          for (final item in itens)
            linha(
              id: item.id,
              previa: item.id,
              titulo: item.displayName,
              sub: [
                if (item.duracaoSeg != null) '${item.duracaoSeg} s',
                item.description ?? '',
              ].where((x) => x.isNotEmpty).join(' · '),
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
              child: Text('Toque do despertar',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: context.appTextPrimary)),
            ),
            const SizedBox(height: 6),
            linha(
              id: '',
              previa: kDespertarSomPadrao,
              titulo: 'Padrão do despertador',
              sub: 'O toque longo do módulo, ou «Despertar crescente».',
            ),
            linha(
              id: 'proprio',
              previa: '',
              titulo: 'Meu toque (MP3 do módulo)',
              sub: 'O áudio próprio escolhido em Despertador e sons para o '
                  'módulo. Sem ele, toca o som padrão do celular.',
            ),
            grupo(
                '🚨 Extra longos',
                'Uns 25 segundos tocando. A prévia para em 15 s; no aviso toca inteiro.',
                kToquesExtraLongos),
            grupo('⏰ Longos', 'De 5 a 10 segundos.', kToquesLongos),
            grupo('🔔 Curtos', 'Discretos, de 1 a 2 segundos.', kToquesCurtos),
          ],
        ),
      ),
    );
  }
}
