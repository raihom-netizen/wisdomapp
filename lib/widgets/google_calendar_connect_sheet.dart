import 'package:flutter/material.dart';

import '../services/google_calendar_auth_helper.dart';
import '../services/google_calendar_sync_service.dart';

/// Autorização Google Calendar **dentro do módulo** (sem abrir aba Firebase).
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

  Future<void> _connect() async {
    if (_busy || widget.userDocId.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await GoogleCalendarSyncService.enable(
        widget.userDocId,
        forceNewCredentials: widget.forceNewCredentials,
        skipSilent: true,
      );
      if (!mounted) return;
      if (result.ok || result.cancelled) {
        Navigator.of(context).pop(result);
        return;
      }
      setState(() {
        _error = result.message?.trim().isNotEmpty == true
            ? result.message!.trim()
            : 'Não foi possível conectar ao Google Calendar.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().split('\n').first;
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
                    borderRadius: BorderRadius.circular(99),
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
                      'Conectar Google Calendar',
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
                    ? 'Você entrou com Apple. Escolha a conta Gmail que deseja '
                        'sincronizar com a agenda — seu login Apple continua igual.'
                    : 'Autorize o WISDOMAPP a ler e enviar compromissos ao seu '
                        'Google Calendar. A janela do Google abre aqui, sem sair do app.',
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
                  'Conta salva: ${widget.preferredEmail!.trim()}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
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
                onPressed: _busy ? null : _connect,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Image.network(
                        'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                        width: 20,
                        height: 20,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.login_rounded, size: 20),
                      ),
                label: Text(
                  _busy
                      ? 'Conectando…'
                      : (widget.forceNewCredentials
                          ? 'Escolher outra conta Google'
                          : 'Continuar com Google'),
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
