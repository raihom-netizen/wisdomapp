import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/apple_calendar_sync_service.dart';
import '../services/google_calendar_auth_helper.dart';
import '../services/google_calendar_oauth_return.dart';
import '../services/google_calendar_sync_service.dart';
import '../utils/firestore_web_guard.dart';
import 'google_calendar_connect_sheet.dart';

/// Painel unificado: **Google Calendar** (OAuth — web/Android/iOS) +
/// **Calendário Apple** (EventKit nativo — iPhone/iPad).
///
/// Na web não há API REST da Apple; iCloud na web exigiria CalDAV no servidor.
/// Por isso EventKit só no app nativo iOS.
class ExternalCalendarIntegrationPanel extends StatefulWidget {
  const ExternalCalendarIntegrationPanel({
    super.key,
    required this.userDocId,
    this.compact = false,
    this.showChangeGoogleAccountAction = false,
    this.onGoogleChanged,
    this.onAppleChanged,
  });

  final String userDocId;
  final bool compact;
  final bool showChangeGoogleAccountAction;
  final VoidCallback? onGoogleChanged;
  final VoidCallback? onAppleChanged;

  @override
  State<ExternalCalendarIntegrationPanel> createState() =>
      _ExternalCalendarIntegrationPanelState();
}

class _ExternalCalendarIntegrationPanelState
    extends State<ExternalCalendarIntegrationPanel> {
  static const _googleBlue = Color(0xFF4285F4);
  static const _primary = Color(0xFF0B1B4B);
  static const _accent = Color(0xFFE8C547);

  bool _loading = true;
  bool _googleBusy = false;
  bool _appleBusy = false;
  bool? _googleOverride;
  bool _googleEnabled = false;
  String? _googleEmail;
  bool _hasRefreshToken = false;
  bool _appleEnabled = false;
  Map<String, dynamic> _landingCfg = const {};
  StreamSubscription<GoogleCalendarEnableResult>? _oauthSub;

  @override
  void initState() {
    super.initState();
    _oauthSub = GoogleCalendarOAuthReturn.stream.listen(_onOAuthReturn);
    unawaited(_bootstrapOAuthReturn());
    _refresh();
  }

  @override
  void dispose() {
    _oauthSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrapOAuthReturn() async {
    if (widget.userDocId.isEmpty) return;
    final result =
        await GoogleCalendarSyncService.completeWebOAuthReturnIfNeeded();
    if (!mounted || result == null) return;
    await _finishGoogleEnable(result);
    widget.onGoogleChanged?.call();
  }

  void _onOAuthReturn(GoogleCalendarEnableResult result) {
    if (!mounted) return;
    unawaited(_finishGoogleEnable(result));
    widget.onGoogleChanged?.call();
  }

  Future<void> _refresh() async {
    if (widget.userDocId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final futures = <Future<Object?>>[
        GoogleCalendarSyncService.readLandingAgendaConfig(),
        GoogleCalendarSyncService.readIntegrationState(widget.userDocId),
      ];
      if (AppleCalendarSyncService.isPlatformSupported) {
        futures.add(AppleCalendarSyncService.readState(widget.userDocId));
      }
      final results = await Future.wait(futures);
      if (!mounted) return;
      final g = results[1] as ({bool enabled, String? email, bool hasRefreshToken});
      var appleOn = false;
      if (AppleCalendarSyncService.isPlatformSupported && results.length > 2) {
        final a = results[2] as ({bool enabled, bool permissionGranted});
        appleOn = a.enabled;
      }
      setState(() {
        _landingCfg = results[0] as Map<String, dynamic>;
        _googleEnabled = g.enabled;
        _googleEmail = g.email;
        _hasRefreshToken = g.hasRefreshToken;
        _appleEnabled = appleOn;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _hex(String? raw, Color fallback) {
    if (raw == null) return fallback;
    final c = raw.trim().replaceAll('#', '');
    if (c.length != 6 && c.length != 8) return fallback;
    final v = int.tryParse(c.length == 6 ? 'FF$c' : c, radix: 16);
    return v == null ? fallback : Color(v);
  }

  bool get _googleOn => _googleOverride ?? _googleEnabled;

  Future<void> _finishGoogleEnable(GoogleCalendarEnableResult res) async {
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _googleOverride = false);
      if (res.cancelled) return;
      final msg = res.message?.trim().isNotEmpty == true
          ? res.message!.trim()
          : 'Não foi possível ativar o Google Calendar.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    setState(() {
      _googleOverride = true;
      _googleEnabled = true;
      _googleEmail = res.email?.trim().isNotEmpty == true ? res.email!.trim() : _googleEmail;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _googleEmail != null && _googleEmail!.isNotEmpty
              ? 'Google Calendar ativo · $_googleEmail'
              : 'Google Calendar ativo — sync automática.',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _toggleGoogle(bool v) async {
    if (_googleBusy || widget.userDocId.isEmpty) return;
    setState(() => _googleBusy = true);
    try {
      if (v) {
        final res = await GoogleCalendarSyncService.tryEnableSilent(widget.userDocId);
        if (!mounted) return;
        if (res.needsInteractiveAuth) {
          setState(() => _googleBusy = false);
          if (kIsWeb) {
            GoogleCalendarAuthHelper.startWebOAuthRedirect(
              preferredEmail: res.email,
              enableUserDocId: widget.userDocId,
              promptNone: _hasRefreshToken,
              forceConsent: !_hasRefreshToken,
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _hasRefreshToken
                      ? 'Reconectando ao Google…'
                      : 'Autorize o Google uma vez — depois fica silencioso.',
                ),
              ),
            );
            widget.onGoogleChanged?.call();
            return;
          }
          final sheet = await GoogleCalendarConnectSheet.show(
            context,
            userDocId: widget.userDocId,
            preferredEmail: res.email,
          );
          if (sheet != null) await _finishGoogleEnable(sheet);
        } else {
          await _finishGoogleEnable(res);
        }
      } else {
        await GoogleCalendarSyncService.disable(widget.userDocId);
        if (mounted) {
          setState(() {
            _googleOverride = false;
            _googleEnabled = false;
          });
        }
      }
      widget.onGoogleChanged?.call();
    } catch (e) {
      if (mounted && FirestoreWebGuard.isClientTerminatedError(e)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Atualize a página (F5) e tente de novo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  Future<void> _toggleApple(bool v) async {
    if (_appleBusy || widget.userDocId.isEmpty) return;
    setState(() => _appleBusy = true);
    try {
      if (v) {
        final r = await AppleCalendarSyncService.enable(widget.userDocId);
        if (!mounted) return;
        if (r.ok) {
          setState(() => _appleEnabled = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Calendário Apple (EventKit) ativo — sync no app Calendário.',
              ),
              duration: Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(r.message ?? 'Não foi possível ativar.')),
          );
        }
      } else {
        await AppleCalendarSyncService.disable(widget.userDocId);
        if (mounted) setState(() => _appleEnabled = false);
      }
      widget.onAppleChanged?.call();
    } finally {
      if (mounted) setState(() => _appleBusy = false);
    }
  }

  Future<void> _changeGoogleAccount() async {
    if (_googleBusy) return;
    final email = _googleEmail;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trocar conta Google?'),
        content: Text(
          email != null && email.isNotEmpty
              ? 'A conta $email será desvinculada. Ao ativar de novo, escolha outro Gmail.'
              : 'Credenciais removidas. Ao ativar, escolha qual Gmail usar.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Trocar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _googleBusy = true);
    try {
      await GoogleCalendarSyncService.prepareGoogleAccountChange(widget.userDocId);
      if (mounted) {
        setState(() {
          _googleOverride = false;
          _googleEnabled = false;
          _googleEmail = null;
        });
      }
      widget.onGoogleChanged?.call();
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.35,
        ),
      ),
    );
  }

  Widget _providerTile({
    required Widget leading,
    required String title,
    required String subtitle,
    required bool value,
    required bool busy,
    required ValueChanged<bool> onChanged,
    Color? activeColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: widget.compact ? 8 : 10,
          horizontal: 4,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.86),
                      fontSize: 11.5,
                      height: 1.32,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (busy)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: activeColor ?? _accent,
                  ),
                ),
              )
            else
              Switch.adaptive(
                value: value,
                onChanged: onChanged,
                activeTrackColor: (activeColor ?? _accent).withValues(alpha: 0.42),
                activeThumbColor: activeColor ?? _accent,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userDocId.isEmpty) return const SizedBox.shrink();
    if (_landingCfg['googleAgendaEnabled'] == false) {
      return const SizedBox.shrink();
    }

    if (_loading) {
      return SizedBox(
        height: widget.compact ? 88 : 120,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final primary = _hex(_landingCfg['divThemePrimaryColor']?.toString(), _primary);
    final accent = _hex(_landingCfg['divThemeAccentColor']?.toString(), _accent);
    final appleHint = GoogleCalendarAuthHelper.isApplePrimaryLogin()
        ? 'Entrou com Apple? Use Google para Gmail ou EventKit abaixo para o Calendário do iPhone.'
        : 'Ative um ou os dois — compromissos sincronizam automaticamente.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          margin: EdgeInsets.only(bottom: widget.compact ? 8 : 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [primary, primary.withValues(alpha: 0.92)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: primary.withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              14,
              widget.compact ? 12 : 14,
              12,
              widget.compact ? 10 : 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.sync_rounded, color: accent, size: 24),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'SINCRONIZAR CALENDÁRIOS',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          letterSpacing: 0.55,
                        ),
                      ),
                    ),
                    if (_googleOn || _appleEnabled)
                      _statusChip(
                        _googleOn && _appleEnabled ? 'GOOGLE + APPLE' : _googleOn ? 'GOOGLE' : 'APPLE',
                        accent,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  appleHint,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                Divider(color: Colors.white.withValues(alpha: 0.14), height: 20),
                _providerTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _googleBlue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.calendar_month_rounded, color: _googleBlue, size: 22),
                  ),
                  title: 'Google Calendar',
                  subtitle: _googleOn
                      ? (_googleEmail != null && _googleEmail!.isNotEmpty
                          ? 'Ativo · $_googleEmail · OAuth silencioso após 1ª autorização'
                          : 'Ativo · web, Android e iPhone')
                      : 'Gmail / Google — ideal na web e em qualquer aparelho',
                  value: _googleOn,
                  busy: _googleBusy,
                  onChanged: _toggleGoogle,
                  activeColor: _googleBlue,
                ),
                if (AppleCalendarSyncService.isPlatformSupported) ...[
                  Divider(color: Colors.white.withValues(alpha: 0.12), height: 8),
                  _providerTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppleCalendarSyncService.appleEventColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.apple,
                        color: AppleCalendarSyncService.appleEventColor,
                        size: 22,
                      ),
                    ),
                    title: 'Calendário Apple',
                    subtitle: _appleEnabled
                        ? 'Ativo · EventKit (nativo) — lê e grava no app Calendário'
                        : 'iPhone/iPad · permissão iOS uma vez, depois silencioso',
                    value: _appleEnabled,
                    busy: _appleBusy,
                    onChanged: _toggleApple,
                    activeColor: AppleCalendarSyncService.appleEventColor,
                  ),
                ],
                if (kIsWeb)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 2, right: 2),
                    child: Text(
                      'Na web: Google Calendar (OAuth). Calendário Apple/iCloud usa EventKit '
                      'no app iOS — a Apple não oferece API REST; iCloud na web seria CalDAV no servidor.',
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.35,
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (widget.showChangeGoogleAccountAction && (_googleOn || (_googleEmail?.isNotEmpty ?? false)))
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: TextButton.icon(
              onPressed: _googleBusy ? null : _changeGoogleAccount,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text('Trocar conta Google'),
            ),
          ),
      ],
    );
  }
}
