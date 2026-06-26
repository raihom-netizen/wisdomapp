import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/notification_audio_player.dart';
import '../services/notification_sound_catalog.dart';
import '../theme/app_colors.dart';

/// Modo de entrega da notificação só para este evento.
///
/// - [inherit]: **não personaliza** — usa só o que está em *Preferências →
///   Sons das notificações* para a categoria (áudio / vibrar / só push).
/// - [audio], [vibrate], [pushOnly]: **personalizado** — ignora o padrão
///   geral e aplica só o que foi escolhido neste evento.
enum EventNotificationDeliveryMode {
  /// Usa o padrão definido em Preferências para a categoria.
  inherit,

  /// Áudio ligado (com som — padrão do sistema ou tom do banco do app).
  audio,

  /// Sem som, só vibração.
  vibrate,

  /// Sem som e sem vibração — só popup/badge.
  pushOnly;

  String? get firestoreValue => switch (this) {
        EventNotificationDeliveryMode.inherit => null,
        EventNotificationDeliveryMode.audio => 'audio',
        EventNotificationDeliveryMode.vibrate => 'vibrate',
        EventNotificationDeliveryMode.pushOnly => 'push',
      };

  static EventNotificationDeliveryMode fromFirestore(String? v) {
    switch ((v ?? '').trim().toLowerCase()) {
      case 'audio':
      case 'audio_on':
      case 'on':
        return EventNotificationDeliveryMode.audio;
      case 'vibrate':
      case 'vibration':
      case 'so_vibrar':
        return EventNotificationDeliveryMode.vibrate;
      case 'silent':
      case 'push':
      case 'push_only':
      case 'so_push':
        return EventNotificationDeliveryMode.pushOnly;
      default:
        return EventNotificationDeliveryMode.inherit;
    }
  }
}

/// Escolha completa do usuário para a notificação de um evento.
class EventNotificationChoice {
  const EventNotificationChoice({
    required this.deliveryMode,
    this.soundId,
  });

  final EventNotificationDeliveryMode deliveryMode;

  /// `id` do banco offline; só vale quando [deliveryMode] = `audio`.
  final String? soundId;

  static const EventNotificationChoice inherit = EventNotificationChoice(
    deliveryMode: EventNotificationDeliveryMode.inherit,
  );

  EventNotificationChoice copyWith({
    EventNotificationDeliveryMode? deliveryMode,
    String? soundId,
    bool clearSound = false,
  }) {
    return EventNotificationChoice(
      deliveryMode: deliveryMode ?? this.deliveryMode,
      soundId: clearSound ? null : (soundId ?? this.soundId),
    );
  }
}

/// Cartão **super premium** usado nos formulários de **Escala**,
/// **Compromisso** e **Audiência** para o usuário definir como a
/// notificação deve ser entregue só para aquele item:
///
/// - **Padrão (herdar)** — usa só *Preferências → Sons das notificações*
///   da categoria; o que for escolhido aqui em Áudio/Vibrar/Push **não**
///   vale.
/// - 🔔 **Áudio** — personalizado: som do sistema ou toque do banco **só
///   neste** evento (ignora o modo de entrega global da categoria).
/// - 📳 **Vibrar** / 🔕 **Só push** — personalizado para este evento.
class EventNotificationSoundPicker extends StatefulWidget {
  const EventNotificationSoundPicker({
    super.key,
    required this.value,
    required this.onChanged,
    required this.itemLabel,
    this.dense = false,
  });

  final EventNotificationChoice value;
  final ValueChanged<EventNotificationChoice> onChanged;

  /// Ex.: «plantão», «compromisso», «audiência» — usado nos textos.
  final String itemLabel;
  final bool dense;

  @override
  State<EventNotificationSoundPicker> createState() =>
      _EventNotificationSoundPickerState();
}

class _EventNotificationSoundPickerState
    extends State<EventNotificationSoundPicker> {
  Future<void> _preview(NotificationSoundCatalogItem item) async {
    await NotificationAudioPlayer.instance.playBundledById(item.id);
  }

  /// Pré-visualização tátil ao escolher «Vibrar» (complementa o som no modo áudio).
  Future<void> _previewVibrationPattern() async {
    HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 55));
    HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 55));
    HapticFeedback.lightImpact();
  }

  void _setMode(EventNotificationDeliveryMode mode) {
    if (mode == EventNotificationDeliveryMode.vibrate) {
      _previewVibrationPattern();
    }
    EventNotificationChoice next;
    if (mode == EventNotificationDeliveryMode.audio) {
      next = widget.value.copyWith(deliveryMode: mode);
    } else {
      next =
          widget.value.copyWith(deliveryMode: mode, clearSound: true);
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final dense = widget.dense;
    final mode = widget.value.deliveryMode;
    final selectedSound = findCatalogItemById(widget.value.soundId);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.18)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            const Color(0xFF7C3AED).withValues(alpha: 0.04),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, dense ? 10 : 12, 14, dense ? 12 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(dense),
            SizedBox(height: dense ? 8 : 10),
            _deliveryRow(mode, dense),
            if (mode == EventNotificationDeliveryMode.audio) ...[
              SizedBox(height: dense ? 10 : 12),
              _soundCatalog(dense, selectedSound),
            ],
            if (mode != EventNotificationDeliveryMode.inherit) ...[
              SizedBox(height: dense ? 6 : 8),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textMuted,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () =>
                    _setMode(EventNotificationDeliveryMode.inherit),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(
                  'Voltar ao padrão da categoria',
                  style: TextStyle(fontSize: dense ? 11.5 : 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(bool dense) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7C3AED), Color(0xFF9333EA)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.notifications_active_rounded,
              color: Colors.white, size: 16),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Notificação desta ${widget.itemLabel}',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: dense ? 13.5 : 14.5,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _subtitleFor(widget.value),
                style: TextStyle(
                  fontSize: dense ? 10.5 : 11,
                  color: AppColors.textMuted,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7C3AED), Color(0xFF9333EA)],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'PREMIUM',
            style: TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _deliveryRow(EventNotificationDeliveryMode current, bool dense) {
    final items = const [
      _ModeItemData(
        mode: EventNotificationDeliveryMode.audio,
        icon: Icons.volume_up_rounded,
        title: 'Áudio',
        subtitle: 'com som',
        color: Color(0xFF7C3AED),
      ),
      _ModeItemData(
        mode: EventNotificationDeliveryMode.vibrate,
        icon: Icons.vibration_rounded,
        title: 'Vibrar',
        subtitle: 'sem som',
        color: Color(0xFFB45309),
      ),
      _ModeItemData(
        mode: EventNotificationDeliveryMode.pushOnly,
        icon: Icons.notifications_off_rounded,
        title: 'Só push',
        subtitle: 'silencioso',
        color: Color(0xFF334155),
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _ModeButton(
              data: items[i],
              selected: current == items[i].mode,
              dense: dense,
              onTap: () => _setMode(items[i].mode),
            ),
          ),
        ],
      ],
    );
  }

  Widget _soundCatalog(bool dense, NotificationSoundCatalogItem? selected) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(12, dense ? 8 : 10, 12, dense ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.library_music_rounded,
                  color: Color(0xFF7C3AED), size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  selected == null
                      ? 'Toque (banco do app)'
                      : 'Toque: ${selected.displayName}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: dense ? 12 : 12.5,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (selected != null)
                _PreviewPlayButton(
                  dense: dense,
                  tooltip: 'Ouvir o toque atual',
                  onPressed: () => _preview(selected),
                ),
            ],
          ),
          SizedBox(height: dense ? 6 : 8),
          Text(
            'Toque numa linha para aplicar e ouvir. Use ▶ só para ouvir sem mudar.',
            style: TextStyle(
              fontSize: dense ? 10.5 : 11,
              color: AppColors.textMuted,
              height: 1.25,
            ),
          ),
          SizedBox(height: dense ? 6 : 8),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: (MediaQuery.sizeOf(context).height * 0.38)
                  .clamp(200.0, 320.0),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              itemCount: 1 + kNotificationSoundCatalog.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                indent: 52,
                color: Colors.grey.shade200,
              ),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _padraoListTile(dense);
                }
                final item = kNotificationSoundCatalog[index - 1];
                final isSel = selected?.id == item.id;
                return _bundledSoundListTile(item, dense, isSel);
              },
            ),
          ),
        ],
      ),
    );
  }

  static const Color _accent = Color(0xFF7C3AED);

  Widget _padraoListTile(bool dense) {
    final isSel = widget.value.soundId == null;
    final deep = AppColors.deepBlue;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
        minVerticalPadding: dense ? 12 : 14,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: isSel ? deep.withValues(alpha: 0.1) : null,
        leading: CircleAvatar(
          radius: dense ? 18 : 20,
          backgroundColor: isSel ? deep : deep.withValues(alpha: 0.12),
          child: Icon(
            isSel ? Icons.check_rounded : Icons.tune_rounded,
            color: isSel ? Colors.white : deep,
            size: dense ? 20 : 22,
          ),
        ),
        title: Text(
          'Padrão',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: dense ? 13 : 14,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          'Tom da categoria em Preferências → Sons',
          style: TextStyle(
            fontSize: dense ? 11 : 11.5,
            color: AppColors.textMuted,
          ),
        ),
        onTap: () {
          widget.onChanged(widget.value.copyWith(clearSound: true));
          HapticFeedback.selectionClick();
        },
      ),
    );
  }

  Widget _bundledSoundListTile(
    NotificationSoundCatalogItem item,
    bool dense,
    bool isSelected,
  ) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
        minVerticalPadding: dense ? 12 : 14,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: isSelected ? _accent.withValues(alpha: 0.12) : null,
        leading: CircleAvatar(
          radius: dense ? 18 : 20,
          backgroundColor:
              isSelected ? _accent : _accent.withValues(alpha: 0.12),
          child: Icon(
            isSelected ? Icons.check_rounded : Icons.music_note_rounded,
            color: isSelected ? Colors.white : _accent,
            size: dense ? 20 : 22,
          ),
        ),
        title: Text(
          item.displayName,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: dense ? 13 : 14,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: item.description != null
            ? Text(
                item.description!,
                style: TextStyle(
                  fontSize: dense ? 11 : 11.5,
                  color: AppColors.textMuted,
                ),
              )
            : null,
        trailing: _PreviewPlayButton(
          dense: dense,
          tooltip: 'Só ouvir',
          onPressed: () => _preview(item),
        ),
        onTap: () async {
          widget.onChanged(widget.value.copyWith(soundId: item.id));
          await _preview(item);
        },
      ),
    );
  }

  String _subtitleFor(EventNotificationChoice c) {
    final selected = findCatalogItemById(c.soundId);
    switch (c.deliveryMode) {
      case EventNotificationDeliveryMode.inherit:
        return 'Usa o padrão da categoria (Preferências → Sons).';
      case EventNotificationDeliveryMode.audio:
        return selected != null
            ? 'Áudio: ${selected.displayName}'
            : 'Áudio ligado (tom padrão da categoria).';
      case EventNotificationDeliveryMode.vibrate:
        return 'Sem som, só vibração.';
      case EventNotificationDeliveryMode.pushOnly:
        return 'Sem som e sem vibração — só popup.';
    }
  }
}

class _ModeItemData {
  const _ModeItemData({
    required this.mode,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });
  final EventNotificationDeliveryMode mode;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.data,
    required this.selected,
    required this.dense,
    required this.onTap,
  });
  final _ModeItemData data;
  final bool selected;
  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? data.color
        : data.color.withValues(alpha: 0.08);
    final fg = selected ? Colors.white : data.color;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: BoxConstraints(minHeight: dense ? 56 : 64),
        padding: EdgeInsets.symmetric(
            horizontal: dense ? 8 : 10, vertical: dense ? 8 : 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? data.color
                : data.color.withValues(alpha: 0.25),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(data.icon, size: dense ? 18 : 20, color: fg),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(
                data.title,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: dense ? 11.5 : 12.5,
                  color: fg,
                ),
              ),
            ),
            const SizedBox(height: 1),
            FittedBox(
              child: Text(
                data.subtitle,
                style: TextStyle(
                  fontSize: dense ? 9 : 10,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Colors.white.withValues(alpha: 0.9)
                      : data.color.withValues(alpha: 0.75),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Botão de pré-escuta **super premium** — círculo grande com gradiente roxo
/// e sombra, usado nas listas de toques (picker de evento e bottom sheet de
/// Configurações → Sons). Área de toque mínima 48 × 48 garante acessibilidade
/// em mobile.
class _PreviewPlayButton extends StatelessWidget {
  const _PreviewPlayButton({
    required this.dense,
    required this.tooltip,
    required this.onPressed,
  });

  final bool dense;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final size = dense ? 44.0 : 48.0;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7C3AED), Color(0xFF9333EA)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.45),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: dense ? 26 : 30,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
