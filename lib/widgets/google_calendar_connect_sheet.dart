import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/google_calendar_auth_helper.dart';
import '../services/google_calendar_sync_service.dart';

/// Autorização Google Calendar — Web: redirect OAuth; mobile: sheet in-app.
class GoogleCalendarConnectSheet extends StatefulWidget {
  const GoogleCalendarConnectSheet({
    super.key,
    required this.userDocId,
    this.preferredEmail,
    this.forceNewCredentials = false,
  });

  final String userDocId;
  final String? preferredEmail;
  final bool forceNewCredentials;

  static Future<GoogleCalendarEnableResult?> show(
    BuildContext context, {
    required String userDocId,
    String? preferredEmail,
    bool forceNewCredentials = false,
  }) {
    if (kIsWeb) {
      GoogleCalendarAuthHelper.startWebOAuthRedirect(
        preferredEmail: preferredEmail,
        enableUserDocId: userDocId,
        selectAccount: forceNewCredentials,
      );
      return Future.value(null);
    }
    return showModalBottomSheet<GoogleCalendarEnableResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GoogleCalendarConnectSheet(
        userDocId: userDocId,
        preferredEmail: preferredEmail,
        forceNewCredentials: forceNewCredentials,
      ),
    );
  }

  @override
  State<GoogleCalendarConnectSheet> createState() =>
      _GoogleCalendarConnectSheetState();
}

class _GoogleCalendarConnectSheetState extends State<GoogleCalendarConnectSheet> {
  bool _busy = false;
  String? _error;
  String _status = 'Verificando sessão Google…';

  @override
  void initState() {
    super.initState();
    if (!widget.forceNewCredentials) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _connect(silentFirst: true));
    } else {
      _status = 'Escolha a conta Gmail para sincronizar.';
    }
  }

  Future<void> _connect({bool silentFirst = false}) async {
    if (_busy || widget.userDocId.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = silentFirst
          ? 'Verificando credencial salva…'
          : 'Abrindo autorização Google…';
    });
    try {
      final result = await GoogleCalendarSyncService.enable(
        widget.userDocId,
        forceNewCredentials: widget.forceNewCredentials,
        skipSilent: !silentFirst && !widget.forceNewCredentials,
      ).timeout(
        const Duration(seconds: 45),
        onTimeout: () => GoogleCalendarEnableResult.fail(
          'Tempo esgotado. Tente de novo.',
        ),
      );
      if (!mounted) return;
      if (result.ok || result.cancelled) {
        Navigator.of(context).pop(result);
        return;
      }
      if (result.needsInteractiveAuth &&
          silentFirst &&
          !widget.forceNewCredentials) {
        setState(() {
          _busy = false;
          _status = 'Toque para autorizar';
        });
        return;
      }
      setState(() {
        _error = result.message?.trim().isNotEmpty == true
            ? result.message!.trim()
            : 'Não foi possível conectar ao Google Calendar.';
        _status = 'Autorização necessária';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().split('\n').first;
        _status = 'Erro ao conectar';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appleLogin = GoogleCalendarAuthHelper.isApplePrimaryLogin();
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4285F4).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.calendar_month_rounded,
                      color: Color(0xFF4285F4),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Google Calendar',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                appleLogin
                    ? 'Escolha o Gmail que deseja sincronizar.'
                    : 'Se já autorizou antes, reconectamos com a credencial salva. '
                        'Caso contrário, abra a autorização Google.',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: Colors.grey.shade700,
                ),
              ),
              if (widget.preferredEmail != null &&
                  widget.preferredEmail!.trim().isNotEmpty &&
                  !widget.forceNewCredentials) ...[
                const SizedBox(height: 10),
                Text(
                  'Conta vinculada: ${widget.preferredEmail!.trim()}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (_busy)
                Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _status,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy ? null : () => _connect(silentFirst: false),
                icon: _busy
                    ? const SizedBox.shrink()
                    : const Icon(Icons.login_rounded, size: 20),
                label: Text(
                  _busy ? 'Conectando…' : 'Autorizar Google Calendar',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: const Color(0xFF4285F4),
                ),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).pop(
                          GoogleCalendarEnableResult.cancelledByUser(),
                        ),
                child: const Text('Agora não'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
