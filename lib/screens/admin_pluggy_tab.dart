import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';

import '../theme/app_colors.dart';
import '../widgets/module_header_premium.dart';
import '../widgets/admin/admin_page_shell.dart';

/// Painel Admin: credenciais Pluggy em `app_config/pluggy` (Client ID / Secret, webhook opcional).
///
/// **Segurança:** o documento `pluggy` só pode ser lido por admin (Firestore rules). Nunca exponha
/// Client Secret no app do usuário final nem em repositório público.
class AdminPluggyTab extends StatefulWidget {
  final Color brandBlue;
  final Color brandTeal;

  const AdminPluggyTab({
    super.key,
    required this.brandBlue,
    required this.brandTeal,
  });

  @override
  State<AdminPluggyTab> createState() => _AdminPluggyTabState();
}

class _AdminPluggyTabState extends State<AdminPluggyTab> {
  static final _doc = FirebaseFirestore.instance.collection('app_config').doc('pluggy');

  final _clientIdCtrl = TextEditingController();
  final _clientSecretCtrl = TextEditingController();
  final _webhookUrlCtrl = TextEditingController();
  final _oauthRedirectCtrl = TextEditingController();
  bool _includeSandbox = true;
  bool _hydrated = false;
  bool _saving = false;
  bool _testingToken = false;
  String? _lastTestMessage;

  @override
  void dispose() {
    _clientIdCtrl.dispose();
    _clientSecretCtrl.dispose();
    _webhookUrlCtrl.dispose();
    _oauthRedirectCtrl.dispose();
    super.dispose();
  }

  void _hydrateFromSnapshot(DocumentSnapshot<Map<String, dynamic>>? doc) {
    if (_hydrated) return;
    if (doc == null || !doc.exists) return;
    final d = doc.data() ?? {};
    _hydrated = true;
    _clientIdCtrl.text = (d['clientId'] ?? '').toString();
    _webhookUrlCtrl.text = (d['defaultWebhookUrl'] ?? d['webhookUrl'] ?? '').toString();
    _oauthRedirectCtrl.text = (d['oauthRedirectUri'] ?? '').toString();
    _includeSandbox = d['includeSandbox'] is bool ? d['includeSandbox'] as bool : true;
    _clientSecretCtrl.text = '';
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _lastTestMessage = null;
    });
    try {
      final clientId = _clientIdCtrl.text.trim();
      final secret = _clientSecretCtrl.text.trim();
      final payload = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
        'clientId': clientId,
        'defaultWebhookUrl': _webhookUrlCtrl.text.trim(),
        'oauthRedirectUri': _oauthRedirectCtrl.text.trim(),
        'includeSandbox': _includeSandbox,
      };
      if (secret.isNotEmpty) {
        payload['clientSecret'] = secret;
      }
      await _doc.set(payload, SetOptions(merge: true));
      if (mounted) {
        _clientSecretCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configuração Pluggy salva no Firestore (app_config/pluggy).'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: ${e.toString().split('\n').first}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnectToken() async {
    setState(() {
      _testingToken = true;
      _lastTestMessage = null;
    });
    try {
      final res = await FirebaseFunctions.instance.httpsCallable('ctCreatePluggyConnectToken').call();
      final data = Map<String, dynamic>.from(res.data as Map);
      final ok = data['ok'] == true;
      final msg = (data['message'] ?? '').toString();
      final tok = (data['accessToken'] ?? '').toString();
      if (mounted) {
        setState(() {
          _lastTestMessage = ok && tok.isNotEmpty
              ? 'Connect token gerado com sucesso (${tok.length} caracteres). Válido por poucos minutos.'
              : (msg.isNotEmpty ? msg : 'Não foi possível gerar token (verifique credenciais e plano PRO).');
        });
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() => _lastTestMessage = e.message ?? e.code);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _lastTestMessage = e.toString());
      }
    } finally {
      if (mounted) setState(() => _testingToken = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _doc.snapshots(),
      builder: (context, snap) {
        final doc = snap.data;
        _hydrateFromSnapshot(doc);
        final d = (doc != null && doc.exists) ? (doc.data() ?? <String, dynamic>{}) : <String, dynamic>{};
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: AdminPageShell.listPadding(context, top: 8),
          children: [
            ModuleHeaderPremium(
              title: 'Integração Pluggy (Open Finance)',
              icon: Icons.hub_rounded,
              subtitle: 'Credenciais do dashboard Pluggy; o app chama a Cloud Function para obter connectToken.',
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.orange.shade200),
              ),
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange.shade900),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Não use o webhook do Mercado Pago para a Pluggy. Crie uma Cloud Function HTTPS dedicada '
                        '(ex.: pluggyWebhook) que valide o evento e responda 2xx em até 5 segundos. '
                        'A URL opcional abaixo pode ser a mesma para itens criados via connect token.',
                        style: TextStyle(fontSize: 12.5, height: 1.4, color: Colors.orange.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FastTextField(
              controller: _clientIdCtrl,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              decoration: const InputDecoration(
                labelText: 'Client ID (Pluggy)',
                border: OutlineInputBorder(),
                helperText: 'UUID exibido em Your Credentials no dashboard Pluggy',
              ),
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            FastTextField(
              controller: _clientSecretCtrl,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              decoration: InputDecoration(
                labelText: 'Client Secret',
                border: const OutlineInputBorder(),
                helperText: (d['clientSecret'] ?? '').toString().trim().isEmpty
                    ? 'Obrigatório na primeira configuração'
                    : 'Deixe em branco para manter o secret já salvo; preencha apenas para alterar',
              ),
              obscureText: true,
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            FastTextField(
              controller: _webhookUrlCtrl,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              decoration: const InputDecoration(
                labelText: 'Webhook URL (opcional, por item)',
                border: OutlineInputBorder(),
                helperText: 'HTTPS público; enviado em options.webhookUrl ao criar o connect token',
              ),
              autocorrect: false,
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            FastTextField(
              controller: _oauthRedirectCtrl,
              textInputAction: TextInputAction.done,
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              decoration: const InputDecoration(
                labelText: 'OAuth redirect URI (opcional)',
                border: OutlineInputBorder(),
                helperText: 'URL de retorno após o fluxo no banco (Pluggy)',
              ),
              autocorrect: false,
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('includeSandbox (retorno para o app)'),
              subtitle: const Text(
                'O widget web/mobile pode usar este flag; a Pluggy usa credenciais de sandbox no ambiente deles.',
                style: TextStyle(fontSize: 12),
              ),
              value: _includeSandbox,
              onChanged: (v) => setState(() => _includeSandbox = v),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(_saving ? 'Salvando...' : 'Salvar no Firestore'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testingToken ? null : _testConnectToken,
                    icon: _testingToken
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bolt_rounded),
                    label: const Text('Testar connect token'),
                  ),
                ),
              ],
            ),
            if (_lastTestMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _lastTestMessage!,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade800, height: 1.35),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'Sincronização agendada: Cloud Function `pluggyScheduledItemsSync` (12:00 e 23:00 America/Sao_Paulo) '
              'chama PATCH /items. Para desligar: `scheduledItemSyncEnabled: false` no mesmo documento.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.35),
            ),
            const SizedBox(height: 8),
            Text(
              'Documento: app_config/pluggy — leitura restrita a administradores.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        );
      },
    );
  }
}
