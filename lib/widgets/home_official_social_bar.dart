import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/landing_public_content.dart';
import 'keyed_stream_builder.dart';
import 'official_social_top_buttons.dart';

/// Ícones Instagram / YouTube / WhatsApp no Início (app iOS e Android).
/// URLs vêm de `landing_content/main` — editável no Admin.
class HomeOfficialSocialBar extends StatelessWidget {
  const HomeOfficialSocialBar({super.key});

  @override
  Widget build(BuildContext context) {
    // Escuta guardada (antes `.snapshots()` no build abria uma nova a cada
    // rebuild do Início).
    return KeyedStreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      streamKey: 'landing_content/main',
      create: () => FirebaseFirestore.instance
          .collection('landing_content')
          .doc('main')
          .snapshots(),
      builder: (context, snap) {
        final content = LandingPublicContent.fromMap(snap.data?.data());
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Align(
            alignment: Alignment.center,
            child: OfficialSocialTopButtons.fromLanding(content),
          ),
        );
      },
    );
  }
}
