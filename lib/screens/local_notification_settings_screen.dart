import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_colors.dart';
import '../services/agenda_notifications_refresher.dart';
import '../services/local_notification_preferences.dart';
import '../services/scale_notifications_service.dart';
import '../utils/agenda_delivery_channel_prefs.dart';
import '../utils/firestore_user_doc_id.dart';

/// Tela em Configurações: avisos de Financeiro e novos Cursos; antecedência dos lembretes.
class LocalNotificationSettingsScreen extends StatefulWidget {
  const LocalNotificationSettingsScreen({super.key});

  @override
  State<LocalNotificationSettingsScreen> createState() => _LocalNotificationSettingsScreenState();
}

class _LocalNotificationSettingsScreenState extends State<LocalNotificationSettingsScreen> {
  final LocalNotificationPreferences _prefs = LocalNotificationPreferences();
  Timer? _localRefreshDebounce;
  bool _pendingLocalRefresh = false;

  /// UID Firestore (pode diferir do auth.uid em contas vinculadas).
  String? get _settingsUid {
    final auth = FirebaseAuth.instance.currentUser?.uid;
    if (auth == null || auth.isEmpty) return null;
    final fs = firestoreUserDocIdForAppShell(auth);
    return fs.isEmpty ? null : fs;
  }

  bool _loading = true;
  // Defaults — padrão definido pelo admin: e-mail marcado, todos os tipos
  // ativados, e antecedência de 1 dia + 60 minutos antes (ambos marcados).
  bool _receberPorEmail = true;
  bool _resumoDiario = true;
  bool _financeiro = true;
  bool _cursos = true;
  bool _escalas = false;
  bool _compromissos = true;
  bool _audiencias = true;
  AgendaTypeDeliveryMode _deliveryEscala = AgendaTypeDeliveryMode.both;
  AgendaTypeDeliveryMode _deliveryCompromisso = AgendaTypeDeliveryMode.both;
  AgendaTypeDeliveryMode _deliveryAudiencia = AgendaTypeDeliveryMode.both;
  AgendaTypeDeliveryMode _deliveryFinanceiro = AgendaTypeDeliveryMode.both;
  bool _ant1dia = true;
  bool _ant60min = true;
  bool _ant30min = false;
  bool _ant15min = false;
  bool _antPersonalizado = false;
  int? _personalizadoMinutos;
  final TextEditingController _personalizadoController = TextEditingController();
  bool _showAsPopupOnPhone = true;

  static const int _min60 = 60;
  static const int _min1dia = 1440;
  static const int _min30 = 30;
  static const int _min15 = 15;
  static const Set<int> _presets = {_min1dia, _min60, _min30, _min15};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _localRefreshDebounce?.cancel();
    if (_pendingLocalRefresh && !kIsWeb) {
      final uid = _settingsUid;
      if (uid != null && uid.isNotEmpty) {
        unawaited(AgendaNotificationsRefresher.refresh(uid: uid));
      }
    }
    _personalizadoController.dispose();
    super.dispose();
  }

  /// Push/e-mail: Cloud Function `onAgendaNotificationSettingsWritten` no servidor.
  /// Aqui só reagenda alarmes locais do celular, em segundo plano (sem travar a UI).
  void _scheduleLocalNotificationRefresh() {
    if (kIsWeb) return;
    _pendingLocalRefresh = true;
    _localRefreshDebounce?.cancel();
    _localRefreshDebounce = Timer(const Duration(seconds: 5), () {
      _pendingLocalRefresh = false;
      final uid = _settingsUid;
      if (uid == null || uid.isEmpty) return;
      unawaited(
        AgendaNotificationsRefresher.refresh(
          uid: uid,
          coalesceWithin: const Duration(seconds: 3),
        ),
      );
      ScaleNotificationsService().checkDueNow();
    });
  }

  Future<void> _load() async {
    final uid = _settingsUid;
    final localBundle = await _prefs.loadBundle();
    Map<String, dynamic>? d;
    if (uid != null) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('settings')
            .doc('notifications')
            .get(const GetOptions(source: Source.serverAndCache));
        d = snap.data();
      } catch (_) {}
    }

    var f = localBundle.financeiro;
    var cur = localBundle.cursos;
    var e = false;
    var c = false;
    var a = false;
    final list = List<int>.from(localBundle.antecedenciaMinutosList);

    bool receberPorEmail = true;
    var resumoDiario = true;
    var firestoreLeadsMissing = false;

    if (d != null) {
      if (d.containsKey('emailReminderEnabled')) {
        receberPorEmail = d['emailReminderEnabled'] != false;
      }
      if (d.containsKey('dailyDigestEnabled')) {
        resumoDiario = d['dailyDigestEnabled'] != false;
      }
      if (d.containsKey('notifFinanceiro')) f = d['notifFinanceiro'] != false;
      if (d.containsKey('notifCursos')) cur = d['notifCursos'] != false;
      if (d.containsKey('notifEscalas')) e = d['notifEscalas'] == true;
      if (d.containsKey('notifCompromissosAudiencias')) {
        c = d['notifCompromissosAudiencias'] != false;
        a = c;
      }
      if (d.containsKey('notifCompromissos')) {
        c = d['notifCompromissos'] != false;
      }
      if (d.containsKey('notifAudiencias')) {
        a = d['notifAudiencias'] != false;
      } else {
        a = true;
      }
      _deliveryEscala = agendaTypeDeliveryModeFromFirestore(d['deliveryEscala']);
      _deliveryCompromisso =
          agendaTypeDeliveryModeFromFirestore(d['deliveryCompromisso']);
      _deliveryAudiencia =
          defaultAudienciaDeliveryFromFirestore(d['deliveryAudiencia']);
      _deliveryFinanceiro =
          agendaTypeDeliveryModeFromFirestore(d['deliveryFinanceiro']);
      final firestoreLeads = d['scaleReminderLeads'];
      if (firestoreLeads is List && firestoreLeads.isNotEmpty) {
        list
          ..clear()
          ..addAll(
            firestoreLeads
                .map((x) => x is num ? x.toInt() : int.tryParse('$x'))
                .whereType<int>()
                .where((m) => m > 0),
          );
        list.sort();
      } else {
        firestoreLeadsMissing = true;
        list
          ..clear()
          ..addAll(LocalNotificationPreferences.kDefaultLeads);
      }
    }

    if (!mounted) return;
    setState(() {
      _showAsPopupOnPhone = localBundle.showAsPopupOnPhone;
      _receberPorEmail = receberPorEmail;
      _resumoDiario = resumoDiario;
      _financeiro = f;
      _cursos = cur;
      _escalas = false;
      _compromissos = false;
      _audiencias = false;
      if (!_receberPorEmail) {
        if (_deliveryEscala == AgendaTypeDeliveryMode.emailOnly) {
          _deliveryEscala = AgendaTypeDeliveryMode.pushOnly;
        }
        if (_deliveryCompromisso == AgendaTypeDeliveryMode.emailOnly) {
          _deliveryCompromisso = AgendaTypeDeliveryMode.pushOnly;
        }
        if (_deliveryAudiencia == AgendaTypeDeliveryMode.emailOnly) {
          _deliveryAudiencia = AgendaTypeDeliveryMode.pushOnly;
        }
        if (_deliveryFinanceiro == AgendaTypeDeliveryMode.emailOnly) {
          _deliveryFinanceiro = AgendaTypeDeliveryMode.pushOnly;
        }
      }
      _ant1dia = list.contains(_min1dia);
      _ant60min = list.contains(_min60);
      _ant30min = false;
      _ant15min = false;
      _antPersonalizado = false;
      _personalizadoMinutos = null;
      _personalizadoController.clear();
      _loading = false;
    });

    if (firestoreLeadsMissing && uid != null) {
      unawaited(() async {
        await _prefs.setAntecedenciaList(
          List<int>.from(LocalNotificationPreferences.kDefaultLeads),
        );
        await _syncToFirestore();
      }());
    }
  }

  Future<void> _setReceberPorEmail(bool v) async {
    final uid = _settingsUid;
    if (uid == null || !mounted) return;
    setState(() {
      _receberPorEmail = v;
      if (!v) {
        _resumoDiario = false;
        if (_deliveryEscala == AgendaTypeDeliveryMode.emailOnly) {
          _deliveryEscala = AgendaTypeDeliveryMode.pushOnly;
        }
        if (_deliveryCompromisso == AgendaTypeDeliveryMode.emailOnly) {
          _deliveryCompromisso = AgendaTypeDeliveryMode.pushOnly;
        }
        if (_deliveryAudiencia == AgendaTypeDeliveryMode.emailOnly) {
          _deliveryAudiencia = AgendaTypeDeliveryMode.pushOnly;
        }
        if (_deliveryFinanceiro == AgendaTypeDeliveryMode.emailOnly) {
          _deliveryFinanceiro = AgendaTypeDeliveryMode.pushOnly;
        }
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          v ? 'Notificações por e-mail ativadas.' : 'Notificações por e-mail desativadas.',
        ),
      ),
    );
    unawaited(() async {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('settings')
            .doc('notifications')
            .set({
          'emailReminderEnabled': v,
          if (!v) 'dailyDigestEnabled': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await _syncToFirestore();
        _scheduleLocalNotificationRefresh();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }());
  }

  Future<void> _setResumoDiario(bool v) async {
    final uid = _settingsUid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('notifications')
          .set({
        'dailyDigestEnabled': v,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        setState(() => _resumoDiario = v);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              v
                  ? 'Resumo diário (20h) ativado — e-mail com a agenda de amanhã.'
                  : 'Resumo diário desativado.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _setFinanceiro(bool v) async {
    if (!mounted) return;
    setState(() => _financeiro = v);
    unawaited(() async {
      await _prefs.setFinanceiro(v);
      await _syncToFirestore();
      _scheduleLocalNotificationRefresh();
    }());
  }

  Future<void> _setCursos(bool v) async {
    if (!mounted) return;
    setState(() => _cursos = v);
    unawaited(() async {
      await _prefs.setCursos(v);
      await _syncToFirestore();
    }());
  }

  Future<void> _setEscalas(bool v) async {
    if (!mounted) return;
    setState(() => _escalas = v);
    unawaited(() async {
      await _prefs.setEscalas(v);
      await _syncToFirestore();
      _scheduleLocalNotificationRefresh();
    }());
  }

  Future<void> _setCompromissos(bool v) async {
    if (!mounted) return;
    setState(() => _compromissos = v);
    unawaited(() async {
      await _prefs.setCompromissosAudiencias(v);
      await _syncToFirestore();
      _scheduleLocalNotificationRefresh();
    }());
  }

  Future<void> _setAudiencias(bool v) async {
    if (!mounted) return;
    setState(() => _audiencias = v);
    unawaited(() async {
      await _syncToFirestore();
      _scheduleLocalNotificationRefresh();
    }());
  }

  Future<void> _setDeliveryMode({
    required String label,
    required void Function(AgendaTypeDeliveryMode) apply,
    required AgendaTypeDeliveryMode mode,
  }) async {
    if (mode == AgendaTypeDeliveryMode.emailOnly && !_receberPorEmail) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ative «Receber por e-mail» para usar «Só e-mail» neste tipo.',
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => apply(mode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label: ${_deliveryModeLabel(mode)}')),
    );
    unawaited(() async {
      try {
        await _syncToFirestore();
        _scheduleLocalNotificationRefresh();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }());
  }

  String _deliveryModeLabel(AgendaTypeDeliveryMode mode) {
    switch (mode) {
      case AgendaTypeDeliveryMode.both:
        return 'Celular + e-mail';
      case AgendaTypeDeliveryMode.pushOnly:
        return 'Só no celular (push)';
      case AgendaTypeDeliveryMode.emailOnly:
        return 'Só e-mail';
    }
  }

  Widget _deliveryModeSelector({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required bool typeEnabled,
    required AgendaTypeDeliveryMode value,
    required void Function(AgendaTypeDeliveryMode) onChanged,
  }) {
    if (!typeEnabled) return const SizedBox.shrink();
    final allowEmail = _receberPorEmail;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              Widget chip({
                required AgendaTypeDeliveryMode mode,
                required IconData icon,
                required String title,
                required String subtitle,
                required Color color,
                bool enabled = true,
              }) {
                return _AgendaDeliveryChannelChip(
                  icon: icon,
                  title: title,
                  subtitle: subtitle,
                  selected: value == mode,
                  color: color,
                  enabled: enabled,
                  onTap: enabled ? () => onChanged(mode) : null,
                );
              }

              final both = chip(
                mode: AgendaTypeDeliveryMode.both,
                icon: Icons.devices_rounded,
                title: 'Ambos',
                subtitle: 'celular + e-mail',
                color: accent,
              );
              final phone = chip(
                mode: AgendaTypeDeliveryMode.pushOnly,
                icon: Icons.notifications_active_rounded,
                title: 'Celular',
                subtitle: 'só push',
                color: const Color(0xFF0284C7),
              );
              final email = chip(
                mode: AgendaTypeDeliveryMode.emailOnly,
                icon: Icons.email_rounded,
                title: 'E-mail',
                subtitle: 'só e-mail',
                color: const Color(0xFF059669),
                enabled: allowEmail,
              );

              if (constraints.maxWidth < 340) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    both,
                    const SizedBox(height: 8),
                    phone,
                    const SizedBox(height: 8),
                    email,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: both),
                  const SizedBox(width: 8),
                  Expanded(child: phone),
                  const SizedBox(width: 8),
                  Expanded(child: email),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryByTypeSection() {
    if (!_escalas && !_compromissos && !_audiencias && !_financeiro) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Text(
          'Como avisar (por tipo)',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Ex.: financeiro só no celular e cursos só por e-mail. O servidor respeita na hora do lembrete.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.35),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.1)),
          ),
          color: const Color(0xFFF8FAFC),
          child: Column(
            children: [
              _deliveryModeSelector(
                title: 'Escalas',
                subtitle: 'Plantões e escalas na agenda',
                icon: Icons.calendar_today_rounded,
                accent: const Color(0xFFEA580C),
                typeEnabled: _escalas,
                value: _deliveryEscala,
                onChanged: (m) => _setDeliveryMode(
                  label: 'Escalas',
                  apply: (v) => _deliveryEscala = v,
                  mode: m,
                ),
              ),
              if (_escalas && (_compromissos || _audiencias)) const Divider(height: 1),
              _deliveryModeSelector(
                title: 'Compromissos',
                subtitle: 'Lembretes de compromisso',
                icon: Icons.event_note_rounded,
                accent: const Color(0xFF2563EB),
                typeEnabled: _compromissos,
                value: _deliveryCompromisso,
                onChanged: (m) => _setDeliveryMode(
                  label: 'Compromissos',
                  apply: (v) => _deliveryCompromisso = v,
                  mode: m,
                ),
              ),
              if (_compromissos && _audiencias) const Divider(height: 1),
              _deliveryModeSelector(
                title: 'Audiências',
                subtitle:
                    'Padrão: celular + e-mail (recomendado). Você pode deixar só e-mail.',
                icon: Icons.gavel_rounded,
                accent: const Color(0xFF5B21B6),
                typeEnabled: _audiencias,
                value: _deliveryAudiencia,
                onChanged: (m) => _setDeliveryMode(
                  label: 'Audiências',
                  apply: (v) => _deliveryAudiencia = v,
                  mode: m,
                ),
              ),
              if (_financeiro && (_escalas || _compromissos || _audiencias))
                const Divider(height: 1),
              _deliveryModeSelector(
                title: 'Financeiro',
                subtitle: 'Contas a pagar e a receber pendentes',
                icon: Icons.account_balance_wallet_rounded,
                accent: const Color(0xFF0D9488),
                typeEnabled: _financeiro,
                value: _deliveryFinanceiro,
                onChanged: (m) => _setDeliveryMode(
                  label: 'Financeiro',
                  apply: (v) => _deliveryFinanceiro = v,
                  mode: m,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _syncToFirestore() async {
    final uid = _settingsUid;
    if (uid == null) return;
    try {
      final list = _buildAntecedenciaList();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('notifications')
          .set({
        'scaleReminderLeads': list.isNotEmpty
            ? list
            : List<int>.from(LocalNotificationPreferences.kDefaultLeads),
        'scaleReminderEnabled': false,
        'notifFinanceiro': _financeiro,
        'notifCursos': _cursos,
        'notifEscalas': false,
        'notifCompromissos': false,
        'notifAudiencias': false,
        'notifCompromissosAudiencias': false,
        'emailReminderEnabled': false,
        'dailyDigestEnabled': false,
        ...agendaDeliveryModesToFirestore(
          escala: _deliveryEscala,
          compromisso: _deliveryCompromisso,
          audiencia: _deliveryAudiencia,
          financeiro: _deliveryFinanceiro,
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  List<int> _buildAntecedenciaList() {
    final list = <int>[];
    if (_ant1dia) list.add(_min1dia);
    if (_ant60min) list.add(_min60);
    if (list.isEmpty) {
      list.addAll(LocalNotificationPreferences.kDefaultLeads);
    }
    return list.toSet().toList()..sort();
  }

  Widget _simpleSwitch({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon, color: color, size: 26),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      value: value,
      onChanged: onChanged,
      activeColor: AppColors.primary,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Voltar',
          ),
          title: const Text('Notificações'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificações'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Ative ou desative cada tipo de aviso. Simples e direto.',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.4),
            ),
            const SizedBox(height: 20),
            Text(
              'O que avisar',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  _simpleSwitch(
                    icon: Icons.account_balance_wallet_rounded,
                    color: const Color(0xFF0D9488),
                    title: 'Financeiro',
                    subtitle: 'Contas a pagar e a receber',
                    value: _financeiro,
                    onChanged: _setFinanceiro,
                  ),
                  const Divider(height: 1),
                  _simpleSwitch(
                    icon: Icons.ondemand_video_rounded,
                    color: const Color(0xFF6366F1),
                    title: 'Novos cursos publicados',
                    subtitle: 'Quando sair vídeo novo no módulo Cursos',
                    value: _cursos,
                    onChanged: _setCursos,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Quando avisar (financeiro)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: Icon(Icons.today_rounded, color: AppColors.primary, size: 26),
                    title: const Text('1 dia antes', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Lembrete no dia anterior ao vencimento'),
                    value: _ant1dia,
                    onChanged: (v) => _toggle1dia(v),
                    activeColor: AppColors.primary,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: Icon(Icons.schedule_rounded, color: AppColors.primary, size: 26),
                    title: const Text('1 hora antes', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Lembrete uma hora antes do vencimento'),
                    value: _ant60min,
                    onChanged: (v) => _toggle60min(v),
                    activeColor: AppColors.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Preferências salvas neste aparelho e na sua conta.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _persistAntecedenciaList() async {
    final list = _buildAntecedenciaList();
    if (list.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Mantenha pelo menos uma antecedência (1 dia ou 1 hora).',
            ),
          ),
        );
      }
      setState(() {
        _ant1dia = true;
        _ant60min = true;
      });
    }
    unawaited(() async {
      await _prefs.setAntecedenciaList(_buildAntecedenciaList());
      await _syncToFirestore();
      _scheduleLocalNotificationRefresh();
    }());
  }

  Future<void> _togglePersonalizado(bool v) async {
    setState(() => _antPersonalizado = v);
    await _persistAntecedenciaList();
  }

  Future<void> _onPersonalizadoMinutosChanged(String v) async {
    final m = int.tryParse(v.trim());
    if (m != null && m > 0) {
      setState(() => _personalizadoMinutos = m);
    }
  }

  Future<void> _toggle1dia(bool v) async {
    setState(() => _ant1dia = v);
    await _persistAntecedenciaList();
  }

  Future<void> _toggle60min(bool v) async {
    setState(() => _ant60min = v);
    await _persistAntecedenciaList();
  }

  Future<void> _toggle30min(bool v) async {
    setState(() => _ant30min = v);
    await _persistAntecedenciaList();
  }

  Future<void> _toggle15min(bool v) async {
    setState(() => _ant15min = v);
    await _persistAntecedenciaList();
  }
}

/// Botão colorido — padrão super premium (Sons das notificações).
class _AgendaDeliveryChannelChip extends StatelessWidget {
  const _AgendaDeliveryChannelChip({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final effective = enabled ? 1.0 : 0.42;
    final bg = selected ? color : color.withValues(alpha: 0.1);
    final fg = selected ? Colors.white : color;
    return Opacity(
      opacity: effective,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? color : color.withValues(alpha: 0.28),
                width: selected ? 1.8 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : const [],
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: fg, size: 22),
                    const SizedBox(height: 5),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w900,
                        fontSize: 12.5,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected
                            ? Colors.white.withValues(alpha: 0.92)
                            : color.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
