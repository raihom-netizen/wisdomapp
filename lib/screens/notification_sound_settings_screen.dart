import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../theme/app_colors.dart';
import '../services/notification_audio_player.dart';
import '../services/notification_sound_catalog.dart';
import '../services/notification_sound_preferences.dart';
import '../services/scale_notifications_service.dart';

/// Tela Premium de Configurações > Sons das notificações.
///
/// Permite ao usuário escolher um som distinto para cada categoria
/// (Escala/Compromisso/Audiência/Financeiro). Opções por categoria:
///
///  - **Som padrão do sistema** (vibração + tom de notificação do device)
///  - **Silencioso** (só pop-up/badge)
///  - **Áudio personalizado** (música ou voz própria do usuário) — escolhido
///    por arquivo (MP3/WAV/M4A) ou gravado em outro app e selecionado.
///
/// O áudio personalizado toca quando o app está em **foreground**. Em
/// background o sistema usa o tom do canal (padrão) por questão técnica.
class NotificationSoundSettingsScreen extends StatefulWidget {
  const NotificationSoundSettingsScreen({super.key});

  @override
  State<NotificationSoundSettingsScreen> createState() =>
      _NotificationSoundSettingsScreenState();
}

class _NotificationSoundSettingsScreenState
    extends State<NotificationSoundSettingsScreen> {
  final NotificationSoundPreferences _prefs =
      NotificationSoundPreferences.instance;
  final Map<NotificationSoundCategory, NotificationSoundPreference> _state = {};
  bool _loading = true;

  static const List<NotificationSoundCategory> _kCategories = [
    NotificationSoundCategory.all,
    NotificationSoundCategory.escala,
    NotificationSoundCategory.compromisso,
    NotificationSoundCategory.audiencia,
    NotificationSoundCategory.financeiro,
  ];

  static const List<String> _kAllowedExtensions = [
    'mp3',
    'wav',
    'm4a',
    'aac',
    'ogg'
  ];
  static const int _kMaxBytes = 5 * 1024 * 1024; // 5 MB

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final c in _kCategories) {
      _state[c] = await _prefs.read(c);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _previewVibrationPattern() async {
    HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 55));
    HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 55));
    HapticFeedback.lightImpact();
  }

  Future<void> _setMode(
      NotificationSoundCategory cat, NotificationSoundMode mode) async {
    await _prefs.setMode(cat, mode);
    if (mode == NotificationSoundMode.vibrateOnly) {
      await _previewVibrationPattern();
    }
    _state[cat] = await _prefs.read(cat);
    // Recria o canal Android para refletir o novo som (silenciar/voltar a tocar).
    try {
      await ScaleNotificationsService().refreshChannelsAfterSoundChange();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _pickAudioForCategory(NotificationSoundCategory cat) async {
    try {
      final pick = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: _kAllowedExtensions,
      );
      if (pick == null || pick.files.isEmpty) return;
      final f = pick.files.first;
      final bytes = f.bytes;
      final ext = (f.extension ?? '').toLowerCase();
      if (bytes == null || bytes.isEmpty) return;
      if (!_kAllowedExtensions.contains(ext)) {
        _toast('Formato não suportado. Use MP3, WAV, M4A, AAC ou OGG.',
            error: true);
        return;
      }
      if (bytes.length > _kMaxBytes) {
        _toast('Arquivo grande demais. Limite: 5 MB.', error: true);
        return;
      }
      String absolutePath;
      if (kIsWeb) {
        // Na web não há FS persistente — guardamos o nome só para exibição.
        absolutePath = 'web://${f.name}';
        _toast(
            'Na web o áudio personalizado é apenas demonstrativo. No app instalado o som toca normalmente.',
            error: false);
      } else {
        final dir = await _prefs.ensureAudioDir();
        if (dir == null) {
          _toast('Não foi possível salvar o arquivo no aparelho.',
              error: true);
          return;
        }
        final fileName = _prefs.suggestedFileName(cat, ext);
        final dest = File(p.join(dir.path, fileName));
        if (dest.existsSync()) dest.deleteSync();
        await dest.writeAsBytes(bytes, flush: true);
        absolutePath = dest.path;
      }
      await _prefs.setCustomAudio(
        cat,
        absolutePath: absolutePath,
        label: f.name,
        source: NotificationCustomAudioSource.pickedFile,
      );
      _state[cat] = await _prefs.read(cat);
      try {
        await ScaleNotificationsService().refreshChannelsAfterSoundChange();
      } catch (_) {}
      if (mounted) setState(() {});
      _toast('Áudio "${f.name}" definido para ${cat.shortName}.');
    } catch (e) {
      _toast('Erro ao escolher áudio: ${e.toString().split('\n').first}',
          error: true);
    }
  }

  Future<void> _clear(NotificationSoundCategory cat) async {
    await _prefs.clear(cat);
    _state[cat] = await _prefs.read(cat);
    try {
      await ScaleNotificationsService().refreshChannelsAfterSoundChange();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  /// Define um tom **embutido** (catálogo offline) como som da categoria.
  Future<void> _setBundled(NotificationSoundCategory cat,
      NotificationSoundCatalogItem item) async {
    await _prefs.setBundledSound(
      cat,
      catalogId: item.id,
      displayLabel: item.displayName,
    );
    _state[cat] = await _prefs.read(cat);
    try {
      await ScaleNotificationsService().refreshChannelsAfterSoundChange();
    } catch (_) {}
    if (mounted) setState(() {});
    _toast('Som "${item.displayName}" definido para ${cat.shortName}.');
  }

  Future<void> _openBundledPicker(NotificationSoundCategory cat) async {
    final picked = await showModalBottomSheet<NotificationSoundCatalogItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _BundledSoundBottomSheet(
        category: cat,
        selectedId: _state[cat]?.customSource ==
                NotificationCustomAudioSource.bundledAsset
            ? _bundledIdFromPath(_state[cat]?.customPath)
            : null,
      ),
    );
    if (picked != null) {
      await _setBundled(cat, picked);
    }
  }

  String? _bundledIdFromPath(String? path) {
    if (path == null || !path.startsWith(kBundledSoundPathPrefix)) return null;
    return path.substring(kBundledSoundPathPrefix.length);
  }

  Future<void> _preview(NotificationSoundPreference pref) async {
    if (pref.isCustom) {
      await NotificationAudioPlayer.instance.preview(path: pref.customPath);
    } else if (pref.isSilent) {
      _toast('Esta categoria está silenciosa.');
    } else {
      _toast('Som padrão do sistema — toca quando a notificação dispara.');
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.error : null,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('Sons das notificações'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _premiumBanner(),
                  const SizedBox(height: 14),
                  for (final cat in _kCategories) ...[
                    _categoryCard(cat),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 8),
                  _footerNotes(),
                ],
              ),
      ),
    );
  }

  Widget _premiumBanner() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5B21B6), Color(0xFF7C3AED), Color(0xFF9333EA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.music_note_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sons personalizados — Super Premium',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Escolha música ou grave sua própria voz para cada tipo de notificação.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryCard(NotificationSoundCategory cat) {
    final pref = _state[cat] ?? NotificationSoundPreference.systemDefault;
    final isAll = cat == NotificationSoundCategory.all;
    final color = _colorFor(cat);
    final icon = _iconFor(cat);
    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cat.displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isAll
                            ? 'Aplica em todas. Pode ser sobrescrito por categoria.'
                            : _subtitleFor(pref),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade700,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (pref.isCustom)
                  IconButton(
                    tooltip: 'Tocar prévia',
                    icon: Icon(Icons.play_circle_rounded,
                        color: color, size: 30),
                    onPressed: () => _preview(pref),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // PADRÃO SUPER PREMIUM — 3 estados grandes (Áudio / Vibrar / Só push)
            _deliveryModeRow(cat: cat, pref: pref),
            const SizedBox(height: 10),
            // Quando está em "Áudio": escolher banco do app ou meu arquivo.
            if (pref.mode == NotificationSoundMode.systemDefault ||
                pref.mode == NotificationSoundMode.customAudio) ...[
              Text(
                'Som tocado',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _modeChip(
                    cat: cat,
                    pref: pref,
                    mode: NotificationSoundMode.systemDefault,
                    label: 'Padrão do sistema',
                    icon: Icons.smartphone_rounded,
                  ),
                  _appBundledChip(cat: cat, pref: pref),
                  _modeChip(
                    cat: cat,
                    pref: pref,
                    mode: NotificationSoundMode.customAudio,
                    label: pref.isCustom &&
                            pref.customSource !=
                                NotificationCustomAudioSource.bundledAsset
                        ? (pref.customLabel ?? 'Meu áudio')
                        : 'Meu áudio (arquivo)',
                    icon: Icons.folder_open_rounded,
                  ),
                ],
              ),
            ],
            if (pref.mode == NotificationSoundMode.customAudio &&
                pref.customSource !=
                    NotificationCustomAudioSource.bundledAsset) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickAudioForCategory(cat),
                      icon: const Icon(Icons.folder_open_rounded, size: 18),
                      label: Text(
                        pref.isCustom
                            ? 'Trocar áudio'
                            : 'Selecionar áudio (MP3/WAV/M4A)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: color,
                        side: BorderSide(color: color.withValues(alpha: 0.5)),
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  if (pref.isCustom) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Remover',
                      icon: Icon(Icons.delete_outline_rounded,
                          color: AppColors.error),
                      onPressed: () => _clear(cat),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Dica: para usar sua voz, grave em qualquer app de gravador do celular (.m4a) e selecione aqui.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// **Padrão super premium**: linha de 3 botões grandes
  /// (🔔 Áudio · 📳 Vibrar · 🔕 Só push).
  Widget _deliveryModeRow({
    required NotificationSoundCategory cat,
    required NotificationSoundPreference pref,
  }) {
    final isAudio = pref.mode == NotificationSoundMode.systemDefault ||
        pref.mode == NotificationSoundMode.customAudio;
    final isVibrate = pref.mode == NotificationSoundMode.vibrateOnly;
    final isSilent = pref.mode == NotificationSoundMode.silent;
    return Row(
      children: [
        Expanded(
          child: _DeliveryModeButton(
            icon: Icons.volume_up_rounded,
            title: 'Áudio',
            subtitle: 'com som',
            selected: isAudio,
            color: const Color(0xFF7C3AED),
            onTap: () async {
              if (!isAudio) {
                await _setMode(cat, NotificationSoundMode.systemDefault);
              }
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _DeliveryModeButton(
            icon: Icons.vibration_rounded,
            title: 'Vibrar',
            subtitle: 'sem som',
            selected: isVibrate,
            color: const Color(0xFFB45309),
            onTap: () => _setMode(cat, NotificationSoundMode.vibrateOnly),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _DeliveryModeButton(
            icon: Icons.notifications_off_rounded,
            title: 'Só push',
            subtitle: 'silencioso',
            selected: isSilent,
            color: const Color(0xFF334155),
            onTap: () => _setMode(cat, NotificationSoundMode.silent),
          ),
        ),
      ],
    );
  }

  Widget _modeChip({
    required NotificationSoundCategory cat,
    required NotificationSoundPreference pref,
    required NotificationSoundMode mode,
    required String label,
    required IconData icon,
  }) {
    final selected = pref.mode == mode &&
        // Quando o modo é customAudio + bundled, esse chip representa o
        // *arquivo do disco* — não fica selecionado se o atual for bundled.
        !(mode == NotificationSoundMode.customAudio &&
            pref.customSource == NotificationCustomAudioSource.bundledAsset);
    final color = _colorFor(cat);
    return ChoiceChip(
      avatar: Icon(icon,
          size: 16, color: selected ? Colors.white : color),
      label: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: selected ? Colors.white : Colors.grey.shade800,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      selected: selected,
      selectedColor: color,
      backgroundColor: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (_) async {
        if (mode == NotificationSoundMode.customAudio) {
          if (!pref.isCustom ||
              pref.customSource ==
                  NotificationCustomAudioSource.bundledAsset) {
            await _pickAudioForCategory(cat);
          } else {
            await _setMode(cat, mode);
          }
        } else {
          await _setMode(cat, mode);
        }
      },
    );
  }

  /// Chip novo: "Banco do app" — abre o sheet com os toques pré-instalados
  /// (estilo WhatsApp).
  Widget _appBundledChip({
    required NotificationSoundCategory cat,
    required NotificationSoundPreference pref,
  }) {
    final color = _colorFor(cat);
    final isBundled = pref.mode == NotificationSoundMode.customAudio &&
        pref.customSource == NotificationCustomAudioSource.bundledAsset;
    final label = isBundled
        ? (pref.customLabel ?? 'Banco do app')
        : 'Banco do app';
    return ChoiceChip(
      avatar: Icon(Icons.library_music_rounded,
          size: 16, color: isBundled ? Colors.white : color),
      label: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: isBundled ? Colors.white : Colors.grey.shade800,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      selected: isBundled,
      selectedColor: color,
      backgroundColor: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (_) => _openBundledPicker(cat),
    );
  }

  Widget _footerNotes() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDBA74)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.info_outline_rounded, color: Color(0xFFB45309), size: 18),
              SizedBox(width: 6),
              Text('Como funciona o som personalizado',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFB45309),
                      fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '• Áudio — com som (padrão do sistema, banco do app ou seu arquivo) + vibração.\n'
            '• Vibrar — só vibração, sem som. Útil em reuniões e audiências presenciais.\n'
            '• Só push — silencioso, sem som e sem vibração: só popup/badge.\n'
            '• Com o app fechado o tom é o do canal (padrão do sistema) — limitação técnica do Android.\n'
            '• Cada categoria tem seu próprio modo; "Todas as categorias" funciona como atalho.',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF7C2D12), height: 1.35),
          ),
        ],
      ),
    );
  }

  Color _colorFor(NotificationSoundCategory cat) => switch (cat) {
        NotificationSoundCategory.all => const Color(0xFF7C3AED),
        NotificationSoundCategory.escala => const Color(0xFF2563EB),
        NotificationSoundCategory.compromisso => const Color(0xFF0D9488),
        NotificationSoundCategory.audiencia => const Color(0xFFB91C1C),
        NotificationSoundCategory.financeiro => const Color(0xFF059669),
      };

  IconData _iconFor(NotificationSoundCategory cat) => switch (cat) {
        NotificationSoundCategory.all => Icons.tune_rounded,
        NotificationSoundCategory.escala => Icons.calendar_today_rounded,
        NotificationSoundCategory.compromisso => Icons.event_rounded,
        NotificationSoundCategory.audiencia => Icons.gavel_rounded,
        NotificationSoundCategory.financeiro =>
          Icons.account_balance_wallet_rounded,
      };

  String _subtitleFor(NotificationSoundPreference pref) {
    switch (pref.mode) {
      case NotificationSoundMode.systemDefault:
        return 'Áudio: padrão do sistema (com vibração).';
      case NotificationSoundMode.vibrateOnly:
        return 'Sem som — só vibração.';
      case NotificationSoundMode.silent:
        return 'Sem som e sem vibração — só popup/badge.';
      case NotificationSoundMode.customAudio:
        if (pref.customSource == NotificationCustomAudioSource.bundledAsset) {
          return 'Áudio: banco do app — ${pref.customLabel ?? "tom embutido"}';
        }
        return pref.customLabel != null
            ? 'Áudio: ${pref.customLabel}'
            : 'Áudio personalizado — toque para escolher um arquivo.';
    }
  }
}

/// Botão grande do «padrão super premium»: 3 estados (Áudio / Vibrar / Só push).
class _DeliveryModeButton extends StatelessWidget {
  const _DeliveryModeButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? color : color.withValues(alpha: 0.08);
    final fg = selected ? Colors.white : color;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.25),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: fg, size: 24),
            const SizedBox(height: 6),
            FittedBox(
              child: Text(
                title,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              child: Text(
                subtitle,
                style: TextStyle(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.9)
                      : color.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w600,
                  fontSize: 10.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sheet com a lista de toques **embutidos** no app (estilo WhatsApp).
class _BundledSoundBottomSheet extends StatelessWidget {
  const _BundledSoundBottomSheet({
    required this.category,
    required this.selectedId,
  });

  final NotificationSoundCategory category;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.library_music_rounded,
                    color: Color(0xFF7C3AED)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Banco do app — ${category.shortName}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Escolha um toque pré-instalado. Funciona sem internet.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 2),
            Text(
              'Toque na linha para ouvir e aplicar. Use ▶ só para ouvir.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: kNotificationSoundCatalog.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Colors.grey.shade200),
                itemBuilder: (ctx, i) {
                  final item = kNotificationSoundCatalog[i];
                  final isSel = item.id == selectedId;
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
                    leading: CircleAvatar(
                      backgroundColor: isSel
                          ? const Color(0xFF7C3AED)
                          : const Color(0xFF7C3AED).withValues(alpha: 0.12),
                      child: Icon(
                        isSel
                            ? Icons.check_rounded
                            : Icons.music_note_rounded,
                        color: isSel ? Colors.white : const Color(0xFF7C3AED),
                      ),
                    ),
                    title: Text(
                      item.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: item.description != null
                        ? Text(
                            item.description!,
                            style: const TextStyle(fontSize: 12),
                          )
                        : null,
                    trailing: _BundledSheetPlayButton(
                      onPressed: () => NotificationAudioPlayer.instance
                          .playBundledById(item.id),
                    ),
                    onTap: () async {
                      await NotificationAudioPlayer.instance
                          .playBundledById(item.id);
                      if (context.mounted) {
                        Navigator.of(context).pop(item);
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Botão de pré-escuta usado no bottom sheet «Banco do app». Mesmo visual
/// premium do picker dos eventos (círculo roxo grande com sombra).
class _BundledSheetPlayButton extends StatelessWidget {
  const _BundledSheetPlayButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Só ouvir',
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
            child: const SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
