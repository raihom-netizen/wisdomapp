import 'package:flutter/material.dart';
import 'fast_text_field.dart';

import '../services/delegate_access_service.dart';
import '../theme/app_colors.dart';

/// Painel admin: e-mail autorizado (sub-login) vinculado ao titular da licença.
class AdminDelegateEmailSection extends StatefulWidget {
  final String principalUid;
  final String principalEmail;
  final String? authorizedEmail;
  final Future<void> Function(String action, String? email)? onAudit;

  const AdminDelegateEmailSection({
    super.key,
    required this.principalUid,
    required this.principalEmail,
    this.authorizedEmail,
    this.onAudit,
  });

  @override
  State<AdminDelegateEmailSection> createState() =>
      _AdminDelegateEmailSectionState();
}

class _AdminDelegateEmailSectionState extends State<AdminDelegateEmailSection> {
  bool _busy = false;

  Future<void> _editEmail({String? initial}) async {
    final ctrl = TextEditingController(text: initial ?? '');
    final saved = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(initial == null
            ? 'Cadastrar e-mail autorizado'
            : 'Editar e-mail autorizado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Titular: ${widget.principalEmail.isNotEmpty ? widget.principalEmail : widget.principalUid}',
              style: const TextStyle(fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 6),
            const Text(
              'Não cria usuário/licença nova. O e-mail entra com login próprio '
              'e acessa os dados deste titular (escalas, lançamentos, edição).',
              style: TextStyle(fontSize: 12, height: 1.35, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            FastTextField(
              controller: ctrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'E-mail autorizado (sub-login)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final e = ctrl.text.trim();
              if (!DelegateAccessService.isValidEmail(e)) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Informe um e-mail válido.')),
                );
                return;
              }
              Navigator.pop(ctx, e);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (saved == null || !mounted) return;

    setState(() => _busy = true);
    final err = await DelegateAccessService.saveAuthorizedEmail(
      principalUid: widget.principalUid,
      principalEmail: widget.principalEmail,
      newEmail: saved,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: Colors.red.shade700),
      );
      return;
    }
    await widget.onAudit?.call('admin_delegate_email_save', saved);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('E-mail autorizado atualizado.')),
    );
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover e-mail autorizado?'),
        content: Text(
          '${widget.authorizedEmail ?? ''} deixará de acessar os dados de '
          '${widget.principalEmail.isNotEmpty ? widget.principalEmail : 'este titular'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await DelegateAccessService.removeAuthorizedEmail(widget.principalUid);
      await widget.onAudit?.call('admin_delegate_email_remove', null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-mail autorizado removido.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.authorizedEmail?.trim().toLowerCase() ?? '';
    final hasEmail = email.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.group_add_rounded,
                  size: 18, color: Colors.amber.shade900),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sub-login (compartilhamento)',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
              if (_busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hasEmail
                ? 'E-mail autorizado: $email'
                : 'Nenhum e-mail autorizado cadastrado.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
          ),
          const SizedBox(height: 4),
          Text(
            'Permissão total sobre escalas, lançamentos e documentos do titular. '
            'Não cria licença separada.',
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (hasEmail)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _editEmail(initial: email),
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('Editar e-mail'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppColors.primary,
                  ),
                )
              else
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _editEmail(),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Adicionar e-mail'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              if (hasEmail)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _remove,
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 16, color: Colors.red.shade700),
                  label: Text('Remover',
                      style: TextStyle(color: Colors.red.shade700)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
