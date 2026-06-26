import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/fast_text_field.dart';

/// Painel Admin: templates globais de push/e-mail (`app_config/notification_templates`).
class AdminNotificationTemplatesSection extends StatefulWidget {
  const AdminNotificationTemplatesSection({
    super.key,
    required this.brandBlue,
  });

  final Color brandBlue;

  @override
  State<AdminNotificationTemplatesSection> createState() =>
      _AdminNotificationTemplatesSectionState();
}

class _AdminNotificationTemplatesSectionState
    extends State<AdminNotificationTemplatesSection> {
  static final _doc = FirebaseFirestore.instance
      .collection('app_config')
      .doc('notification_templates');

  final _brandCtrl = TextEditingController(text: 'WISDOMAPP');
  final _footerCtrl = TextEditingController();
  final _introCtrl = TextEditingController();
  final _accentAudCtrl = TextEditingController(text: '#5B21B6');
  final _accentCompCtrl = TextEditingController(text: '#2563EB');
  final _accentEscCtrl = TextEditingController(text: '#EA580C');

  bool _richPush = true;
  bool _digestEnabled = true;
  bool _digestPush = true;
  int _digestHour = 20;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _brandCtrl.dispose();
    _footerCtrl.dispose();
    _introCtrl.dispose();
    _accentAudCtrl.dispose();
    _accentCompCtrl.dispose();
    _accentEscCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final snap = await _doc.get();
      final d = snap.data();
      if (d != null && mounted) {
        _brandCtrl.text = (d['brandName'] ?? 'WISDOMAPP').toString();
        _footerCtrl.text = (d['emailFooter'] ?? '').toString();
        _introCtrl.text = (d['emailIntro'] ?? '').toString();
        _accentAudCtrl.text = (d['accentAudiencia'] ?? '#5B21B6').toString();
        _accentCompCtrl.text = (d['accentCompromisso'] ?? '#2563EB').toString();
        _accentEscCtrl.text = (d['accentEscala'] ?? '#EA580C').toString();
        _richPush = d['richPushEnabled'] != false;
        _digestEnabled = d['digestEnabled'] != false;
        _digestPush = d['digestPushEnabled'] != false;
        _digestHour = (d['digestHourBrasilia'] is num)
            ? (d['digestHourBrasilia'] as num).toInt()
            : 20;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _doc.set({
        'brandName': _brandCtrl.text.trim(),
        'emailFooter': _footerCtrl.text.trim(),
        'emailIntro': _introCtrl.text.trim(),
        'accentAudiencia': _accentAudCtrl.text.trim(),
        'accentCompromisso': _accentCompCtrl.text.trim(),
        'accentEscala': _accentEscCtrl.text.trim(),
        'richPushEnabled': _richPush,
        'digestEnabled': _digestEnabled,
        'digestPushEnabled': _digestPush,
        'digestHourBrasilia': _digestHour.clamp(0, 23),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Templates de notificação salvos.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.palette_rounded, color: widget.brandBlue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Templates premium (push e e-mail)',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: widget.brandBlue,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Firestore: app_config/notification_templates — cores, rodapé, resumo diário (20h) e banners rich push.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            FastTextField(
              controller: _brandCtrl,
              decoration: const InputDecoration(
                labelText: 'Nome da marca nos e-mails',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FastTextField(
              controller: _footerCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Rodapé do e-mail',
                hintText: '© WISDOMAPP — …',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FastTextField(
              controller: _introCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Texto introdutório (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text('Cores por tipo', style: TextStyle(fontWeight: FontWeight.w700, color: widget.brandBlue)),
            const SizedBox(height: 8),
            FastTextField(
              controller: _accentAudCtrl,
              decoration: const InputDecoration(
                labelText: 'Audiência (#hex)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FastTextField(
              controller: _accentCompCtrl,
              decoration: const InputDecoration(
                labelText: 'Compromisso (#hex)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FastTextField(
              controller: _accentEscCtrl,
              decoration: const InputDecoration(
                labelText: 'Escala (#hex)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Rich push (banner colorido por tipo)'),
              subtitle: const Text('Android/iOS/Web — imagem em /icons/push-banner-*.png'),
              value: _richPush,
              onChanged: (v) => setState(() => _richPush = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Resumo diário por e-mail (amanhã)'),
              subtitle: Text('Envio automático às $_digestHour:00 (Brasília)'),
              value: _digestEnabled,
              onChanged: (v) => setState(() => _digestEnabled = v),
            ),
            if (_digestEnabled)
              Row(
                children: [
                  const Text('Hora do resumo:'),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: _digestHour.clamp(0, 23),
                    items: List.generate(
                      24,
                      (h) => DropdownMenuItem(value: h, child: Text('$h:00')),
                    ),
                    onChanged: (v) {
                      if (v != null) setState(() => _digestHour = v);
                    },
                  ),
                ],
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Push no resumo diário'),
              value: _digestPush,
              onChanged: _digestEnabled
                  ? (v) => setState(() => _digestPush = v)
                  : null,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('Salvar templates'),
              style: FilledButton.styleFrom(
                backgroundColor: widget.brandBlue,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
