import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_version.dart';
import '../constants/app_verse.dart';
import '../theme/app_colors.dart';
import 'official_channels_card.dart';

/// Rodapé sutil com versão e versículo. Use no final das telas (landing, login, etc.).
class AppVersionFooter extends StatelessWidget {
  final bool light;
  final bool showVerse;
  final bool compact;
  /// Barra inferior do [HomeShell]: prioriza área útil do conteúdo (fontes menores, sem linha de build interno).
  final bool shellBottomBar;
  final bool showOfficialChannels;
  /// Versão visível só em Configurações — no rodapé do shell fica desligado.
  final bool showVersion;

  const AppVersionFooter({
    super.key,
    this.light = false,
    this.showVerse = true,
    this.compact = false,
    this.shellBottomBar = false,
    this.showOfficialChannels = false,
    this.showVersion = true,
  });

  @override
  Widget build(BuildContext context) {
    // Cores mais fortes para boa leitura no iPhone/mobile (realçar texto)
    final color = light ? Colors.white70 : AppColors.textSecondary;
    final verseColor = light ? Colors.white60 : AppColors.textMuted;
    final verticalPad = shellBottomBar ? 0.0 : (compact ? 0.0 : 12.0);
    final versionFont = shellBottomBar ? 8.5 : (compact ? 9.5 : 13.0);
    final verseFont = shellBottomBar ? 7.0 : (compact ? 8.5 : 11.0);
    final verseGap = shellBottomBar ? 0.0 : (compact ? 6.0 : 8.0);
    final showInternalRow = showVersion && !shellBottomBar;
    final effectiveShowVersion = showVersion && !shellBottomBar;
    final info = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (effectiveShowVersion) ...[
          Text(
            'v${AppVersion.current} • Online',
            style: TextStyle(
              fontSize: versionFont,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          if (showInternalRow) ...[
            SizedBox(height: compact ? 3 : 2),
            Text(
              AppVersion.internalLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 8 : 10,
                fontWeight: FontWeight.w600,
                color: light ? Colors.white54 : AppColors.textMuted,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ],
        if (showVerse) ...[
          if (effectiveShowVersion) SizedBox(height: verseGap),
          Text(
            AppVerse.full,
            textAlign: TextAlign.center,
            maxLines: shellBottomBar ? 2 : null,
            overflow: shellBottomBar ? TextOverflow.ellipsis : TextOverflow.visible,
            style: TextStyle(
              fontSize: verseFont,
              height: shellBottomBar ? 1.02 : (compact ? 1.15 : 1.3),
              fontWeight: FontWeight.w500,
              color: verseColor,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );

    Widget channels = const SizedBox.shrink();
    if (showOfficialChannels) {
      channels = StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('landing_content')
            .doc('main')
            .snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data() ?? const <String, dynamic>{};
          final youtube = (data['divYoutubeUrl'] ?? '').toString().trim();
          final instagram = (data['divInstagramUrl'] ?? '').toString().trim();
          final whatsapp = (data['divWhatsappUrl'] ?? '').toString().trim();
          if (whatsapp.isEmpty && instagram.isEmpty) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: EdgeInsets.only(top: compact ? 3 : 10),
            child: OfficialChannelsCard(
              title: (data['divChannelsTitle'] ?? 'Canais oficiais').toString(),
              subtitle: (data['divChannelsSubtitle'] ?? '').toString(),
              youtubeUrl: youtube,
              instagramUrl: instagram,
              whatsappUrl: whatsapp,
              youtubeLabel: (data['divYoutubeLabel'] ?? 'YouTube').toString(),
              instagramLabel: (data['divInstagramLabel'] ?? 'Instagram').toString(),
              whatsappLabel: (data['divWhatsappLabel'] ?? 'WhatsApp').toString(),
              compact: true,
              includeYoutubeInstagram: false,
              includeInstagram: true,
            ),
          );
        },
      );
    }

    return Padding(
      padding: shellBottomBar
          ? const EdgeInsets.only(top: 0, bottom: 0)
          : EdgeInsets.symmetric(vertical: verticalPad),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            info,
            channels,
          ],
        ),
      ),
    );
  }
}
