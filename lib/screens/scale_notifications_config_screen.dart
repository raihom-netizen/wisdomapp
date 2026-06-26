import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/theme.dart';
import '../theme/app_colors.dart';
import '../services/scale_notifications_service.dart';

/// Opções de antecedência do lembrete (minutos).
final List<Map<String, dynamic>> kReminderLeadOptions = [
  {'minutes': 30, 'label': '30 minutos antes'},
  {'minutes': 60, 'label': '1 hora antes'},
  {'minutes': 120, 'label': '2 horas antes'},
  {'minutes': 720, 'label': '12 horas (noite anterior)'},
  {'minutes': 1440, 'label': '1 dia antes'},
];

class ScaleNotificationsConfigScreen extends StatefulWidget {
  final String uid;

  const ScaleNotificationsConfigScreen({super.key, required this.uid});

  DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('settings').doc('notifications');

  @override
  State<ScaleNotificationsConfigScreen> createState() => _ScaleNotificationsConfigScreenState();
}

class _ScaleNotificationsConfigScreenState extends State<ScaleNotificationsConfigScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _reminderEnabled = true;
  bool _emailReminderEnabled = true;
  int _reminderMinutes = 60;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snap = await widget._ref.get();
    if (snap.exists && snap.data() != null) {
      final d = snap.data()!;
      setState(() {
        _reminderEnabled = d['scaleReminderEnabled'] != false;
        _emailReminderEnabled = d['emailReminderEnabled'] != false;
        final leads = d['scaleReminderLeads'];
        if (leads is List && leads.isNotEmpty) {
          final first = leads.first;
          final m = first is num ? first.toInt() : int.tryParse(first.toString());
          if (m != null && kReminderLeadOptions.any((o) => o['minutes'] == m)) _reminderMinutes = m;
          else if (m != null) _reminderMinutes = m;
        }
        if (_reminderMinutes == 0 || !kReminderLeadOptions.any((o) => o['minutes'] == _reminderMinutes)) {
          final m = d['scaleReminderMinutes'];
          if (m is int) _reminderMinutes = m;
          if (m is num) _reminderMinutes = m.toInt();
          if (!kReminderLeadOptions.any((o) => o['minutes'] == _reminderMinutes)) _reminderMinutes = 60;
        }
      });
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final snap = await widget._ref.get();
      final existingLeads = <int>{};
      if (snap.exists && snap.data() != null) {
        final raw = snap.data()!['scaleReminderLeads'];
        if (raw is List && raw.isNotEmpty) {
          for (final e in raw) {
            final m = e is num ? e.toInt() : int.tryParse(e.toString());
            if (m != null && m > 0) existingLeads.add(m);
          }
        }
      }
      existingLeads.add(_reminderMinutes);
      final scaleReminderLeads = existingLeads.toList()..sort();
      await widget._ref.set({
        'scaleReminderEnabled': _reminderEnabled,
        'scaleReminderMinutes': _reminderMinutes,
        'scaleReminderLeads': scaleReminderLeads,
        'emailReminderEnabled': _emailReminderEnabled,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuração de avisos salva.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Avisos de plantão'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.notifications_active_rounded, color: AppColors.primary, size: 28),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Lembrete de plantão',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Switch(
                        value: _reminderEnabled,
                        onChanged: (v) => setState(() => _reminderEnabled = v),
                        activeColor: AppColors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(Icons.email_rounded, color: AppColors.primary, size: 24),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Receber lembretes por e-mail',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Switch(
                        value: _emailReminderEnabled,
                        onChanged: (v) => setState(() => _emailReminderEnabled = v),
                        activeColor: AppColors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Lembretes de plantão, compromissos e audiências também são enviados por e-mail (além do aviso na tela).',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Avise-me antes (plantão, compromisso ou audiência) — ex.: 1 dia antes',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                  if (_reminderEnabled) ...[
                    const SizedBox(height: 20),
                    const Text('Antecedência', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 10),
                    ...kReminderLeadOptions.map((opt) {
                      final min = opt['minutes'] as int;
                      final label = opt['label'] as String;
                      final selected = _reminderMinutes == min;
                      return RadioListTile<int>(
                        value: min,
                        groupValue: _reminderMinutes,
                        onChanged: (v) => setState(() => _reminderMinutes = v ?? 60),
                        title: Text(label),
                        activeColor: AppColors.primary,
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_rounded),
            label: const Text('Salvar'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: AppColors.primary,
            ),
          ),
          if (!ScaleNotificationsService().isSupported) ...[
            const SizedBox(height: 16),
            Text(
              'Lembretes locais estão disponíveis no app instalado (dispositivos suportados).',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
          if (ScaleNotificationsService().isSupported && kIsWeb) ...[
            const SizedBox(height: 12),
            Text(
              'Na web e no atalho do celular, os avisos aparecem quando o app está aberto. Conceda permissão quando o navegador solicitar.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
      ),
    );
  }
}
