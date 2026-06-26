import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/google_calendar_auth_helper.dart';
import '../services/google_calendar_sync_service.dart';

/// Liga/desliga **Calendário Google** (Configurações e módulo Agenda).
class GoogleCalendarIntegrationToggle extends StatefulWidget {
  const GoogleCalendarIntegrationToggle({
    super.key,
    required this.userDocId,
    this.onChanged,
    this.compact = false,
  });

  final String userDocId;
  final VoidCallback? onChanged;
  final bool compact;

  @override
  State<GoogleCalendarIntegrationToggle> createState() =>
      _GoogleCalendarIntegrationToggleState();
}

class _GoogleCalendarIntegrationToggleState
    extends State<GoogleCalendarIntegrationToggle> {
  bool _busy = false;

  Color _hexToColor(String? raw, Color fallback) {
    if (raw == null) return fallback;
    final cleaned = raw.trim().replaceAll('#', '');
    if (cleaned.length != 6 && cleaned.length != 8) return fallback;
    final value = int.tryParse(
      cleaned.length == 6 ? 'FF$cleaned' : cleaned,
      radix: 16,
    );
    if (value == null) return fallback;
    return Color(value);
  }

  Future<void> _onToggle(bool v) async {
    if (_busy || widget.userDocId.isEmpty) return;
    setState(() => _busy = true);
    try {
      if (v) {
        final res = await GoogleCalendarSyncService.enable(widget.userDocId);
        if (!mounted) return;
        if (!res.ok) {
          if (!res.cancelled && (res.message ?? '').isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(res.message!)),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Calendário Google ativo${res.email != null ? ' · ${res.email}' : ''}. '
                'Sincronizando compromissos…',
              ),
            ),
          );
        }
      } else {
        await GoogleCalendarSyncService.disable(widget.userDocId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Calendário Google desativado.')),
          );
        }
      }
      widget.onChanged?.call();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userDocId.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('landing_content')
          .doc('main')
          .snapshots(),
      builder: (context, cfgSnap) {
        final cfg = cfgSnap.data?.data() ?? const <String, dynamic>{};
        if (cfg['googleAgendaEnabled'] == false) {
          return const SizedBox.shrink();
        }

        final primary = _hexToColor(
          cfg['divThemePrimaryColor']?.toString(),
          const Color(0xFF0B1B4B),
        );
        final accent = _hexToColor(
          cfg['divThemeAccentColor']?.toString(),
          const Color(0xFFE8C547),
        );
        final hint = (cfg['googleAgendaHintText'] ?? '')
                .toString()
                .trim()
                .isEmpty
            ? (GoogleCalendarAuthHelper.isApplePrimaryLogin()
                ? 'Entrou com Apple? Escolha qualquer conta Gmail para sincronizar a agenda. '
                    'Seu login Apple continua igual.'
                : 'Sincroniza automaticamente com o Gmail da sua conta. '
                    'Compromissos coloridos no calendário e envio ao Google ao adicionar.')
            : (cfg['googleAgendaHintText'] as String).trim();

        return StreamBuilder<bool>(
          stream: GoogleCalendarSyncService.enabledStream(widget.userDocId),
          builder: (context, enabledSnap) {
            final enabled = enabledSnap.data ?? false;
            return StreamBuilder<String?>(
              stream: GoogleCalendarSyncService.connectedEmailStream(
                widget.userDocId,
              ),
              builder: (context, emailSnap) {
                final email = emailSnap.data;
                return Container(
                  width: double.infinity,
                  margin: EdgeInsets.only(bottom: widget.compact ? 8 : 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      colors: [primary, primary.withValues(alpha: 0.92)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: primary.withValues(alpha: 0.28),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        14,
                        widget.compact ? 10 : 12,
                        10,
                        widget.compact ? 10 : 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: _busy
                                ? SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: accent,
                                    ),
                                  )
                                : Icon(
                                    Icons.calendar_month_rounded,
                                    color: accent,
                                    size: 26,
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'CALENDÁRIO GOOGLE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  hint,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.88),
                                    fontSize: 11.5,
                                    height: 1.35,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (enabled) ...[
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.22),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: accent.withValues(alpha: 0.55),
                                      ),
                                    ),
                                    child: Text(
                                      email != null && email.isNotEmpty
                                          ? 'ATIVO · $email'
                                          : 'ATIVO — dias coloridos e sync automático',
                                      style: TextStyle(
                                        color: accent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Switch.adaptive(
                            value: enabled,
                            onChanged: _busy ? null : _onToggle,
                            activeTrackColor: accent.withValues(alpha: 0.45),
                            activeThumbColor: accent,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
