import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import 'package:flutter/services.dart';

import '../services/admin_audit_service.dart';
import '../services/functions_service.dart';
import '../services/logs_service.dart';
import '../theme/app_colors.dart';
import '../widgets/module_header_premium.dart';

/// Migração premium: transferir todos os dados de um e-mail para outro (licença, lançamentos, etc.).
class AdminMigracaoEmailTab extends StatefulWidget {
  const AdminMigracaoEmailTab({super.key});

  @override
  State<AdminMigracaoEmailTab> createState() => _AdminMigracaoEmailTabState();
}

class _AdminMigracaoEmailTabState extends State<AdminMigracaoEmailTab> {
  static const Color _pageBg = Color(0xFFF0F4F9);

  final _sourceCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();

  String _mode = 'full_migration';
  bool _createTarget = true;
  bool _deactivateSource = true;
  bool _deleteSourceAfter = false;
  bool _busy = false;
  bool _busyIsSimulate = false;
  Map<String, dynamic>? _preview;

  @override
  void dispose() {
    _sourceCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _payload({required bool dryRun}) => {
        'sourceEmail': _sourceCtrl.text.trim(),
        'targetEmail': _targetCtrl.text.trim(),
        'mode': _mode,
        'dryRun': dryRun,
        'createTargetIfMissing': _createTarget,
        'deactivateSource': _deactivateSource,
        'deleteSourceAfter': _deleteSourceAfter,
      };

  Future<Map<String, dynamic>> _call({required bool dryRun}) async {
    return FunctionsService().migrateUserEmailPremium(
      payload: _payload(dryRun: dryRun),
    );
  }

  Future<void> _simulate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyIsSimulate = true;
      _preview = null;
    });
    try {
      final res = await _call(dryRun: true);
      if (!mounted) return;
      setState(() => _preview = res);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Simulação concluída — nenhum dado foi alterado.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _showError(e.message ?? e.code);
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString().split('\n').first);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _execute() async {
    if (_busy) return;
    final source = _sourceCtrl.text.trim().toLowerCase();
    final target = _targetCtrl.text.trim().toLowerCase();
    if (source.isEmpty || target.isEmpty) {
      _showError('Informe o e-mail de origem e o de destino.');
      return;
    }
    if (source == target) {
      _showError('Origem e destino devem ser diferentes.');
      return;
    }

    final modeLabel = _mode == 'same_account'
        ? 'Trocar e-mail na mesma conta (mesmo login/UID)'
        : 'Migração completa (copiar tudo para a conta nova)';
    final warnDelete = _deleteSourceAfter
        ? '\n\nA conta antiga será EXCLUÍDA permanentemente após a migração.'
        : (_deactivateSource
            ? '\n\nA conta antiga será desativada (login bloqueado).'
            : '');

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Confirmar migração premium'),
        content: Text(
          '$modeLabel\n\n'
          'De: $source\n'
          'Para: $target$warnDelete\n\n'
          'Serão transferidos: lançamentos, escalas, agenda, contas, metas, '
          'comprovantes (Storage), licença (data de vencimento), convênio e CPF.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Migrar agora'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _busy = true;
      _busyIsSimulate = false;
      _preview = null;
    });
    try {
      final res = await _call(dryRun: false);
      if (!mounted) return;
      setState(() => _preview = res);
      final sourceUid = (res['sourceUid'] ?? res['uid'] ?? '').toString();
      final targetUid = (res['targetUid'] ?? '').toString();
      await AdminAuditService().logAdminAction(
        action: migrarEmailUsuario,
        targetUserId: targetUid.isNotEmpty ? targetUid : sourceUid,
        targetUserEmail: target,
        details: '$source → $target • modo=$_mode',
        before: {'sourceEmail': source, 'sourceUid': sourceUid},
        after: res,
      );
      await LogsService().saveLog(
        modulo: 'Admin',
        acao: 'Migração e-mail premium',
        detalhes: '$source → $target',
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (res['message'] ?? 'Migração concluída.').toString(),
          ),
          duration: const Duration(seconds: 8),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _showError(e.message ?? e.code);
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString().split('\n').first);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _statsBlock(String title, Map<String, dynamic>? stats) {
    if (stats == null) return const SizedBox.shrink();
    final cols = stats['collections'];
    final colMap = cols is Map ? Map<String, dynamic>.from(cols) : <String, dynamic>{};
    final storageNote = (stats['storageFilesNote'] ?? '').toString();
    final lines = <String>[
      'UID: ${stats['uid'] ?? '—'}',
      storageNote.isNotEmpty
          ? 'Arquivos Storage: $storageNote'
          : 'Arquivos Storage: ${stats['storageFiles'] ?? 0}',
    ];
    if (colMap.isNotEmpty) {
      final parts = colMap.entries
          .map((e) => '${e.key}: ${e.value}')
          .toList()
        ..sort();
      lines.add(parts.join(' • '));
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 6),
          Text(lines.join('\n'), style: TextStyle(fontSize: 12, color: Colors.grey.shade800, height: 1.35)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _pageBg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ModuleHeaderPremium(
              title: 'Migração de e-mail',
              icon: Icons.swap_horiz_rounded,
              subtitle:
                  'Premium: transfira lançamentos, escalas, licença (vencimento), convênio e anexos de uma conta para outra.',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.12),
                    const Color(0xFF7C4DFF).withValues(alpha: 0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.workspace_premium_rounded, color: AppColors.primary, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'Super Premium',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Use quando o cliente quer passar a usar um e-mail novo mantendo todo o histórico. '
                    'Recomendado: simular antes de executar.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'full_migration',
                  label: Text('Migração completa'),
                  icon: Icon(Icons.cloud_sync_rounded, size: 18),
                ),
                ButtonSegment(
                  value: 'same_account',
                  label: Text('Só trocar e-mail'),
                  icon: Icon(Icons.alternate_email_rounded, size: 18),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _busy
                  ? null
                  : (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              _mode == 'same_account'
                  ? 'Mesmo UID: apenas atualiza o e-mail de login (dados já estão na conta).'
                  : 'Copia todas as subcoleções e Storage para a conta do e-mail novo.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.3),
            ),
            const SizedBox(height: 16),
            FastTextField(
              controller: _sourceCtrl,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'E-mail de origem (conta antiga)',
                hintText: 'usuario.antigo@email.com',
                prefixIcon: Icon(Icons.mail_outline_rounded),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            FastTextField(
              controller: _targetCtrl,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'E-mail de destino (conta nova)',
                hintText: 'usuario.novo@email.com',
                prefixIcon: Icon(Icons.mark_email_read_outlined),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            if (_mode == 'full_migration') ...[
              const SizedBox(height: 16),
              SwitchListTile(
                value: _createTarget,
                onChanged: _busy ? null : (v) => setState(() => _createTarget = v),
                title: const Text('Criar conta destino se não existir'),
                subtitle: const Text(
                  'Cria login Firebase com senha temporária; envie link de redefinição ao cliente.',
                ),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                value: _deactivateSource,
                onChanged: _busy ? null : (v) => setState(() => _deactivateSource = v),
                title: const Text('Desativar conta antiga'),
                subtitle: const Text('Bloqueia login do e-mail antigo após migrar.'),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                value: _deleteSourceAfter,
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                          _deleteSourceAfter = v;
                          if (v) _deactivateSource = true;
                        }),
                title: const Text(
                  'Excluir conta antiga após migrar',
                  style: TextStyle(color: Color(0xFFB91C1C)),
                ),
                subtitle: const Text('Irreversível — igual exclusão total no painel.'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
            const SizedBox(height: 20),
            if (_busy)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(
                      _busyIsSimulate
                          ? 'Simulando volumes (servidor otimizado) — costuma levar poucos segundos…'
                          : 'Migrando dados no servidor — Firestore, Storage e índices em paralelo…',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.35),
                    ),
                  ],
                ),
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: _simulate,
                    icon: const Icon(Icons.preview_rounded),
                    label: const Text('Simular'),
                  ),
                  FilledButton.icon(
                    onPressed: _execute,
                    icon: const Icon(Icons.rocket_launch_rounded),
                    label: const Text('Executar migração'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                  ),
                ],
              ),
            if (_preview != null) ...[
              const SizedBox(height: 20),
              Text(
                (_preview!['dryRun'] == true) ? 'Resultado da simulação' : 'Resultado',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              _statsBlock('Origem', _preview!['sourceStats'] is Map
                  ? Map<String, dynamic>.from(_preview!['sourceStats'] as Map)
                  : null),
              _statsBlock('Destino', _preview!['targetStats'] is Map
                  ? Map<String, dynamic>.from(_preview!['targetStats'] as Map)
                  : null),
              if (_preview!['docsCopied'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Documentos copiados: ${_preview!['docsCopied']} • '
                    'Storage: ${_preview!['storageCopied'] ?? 0}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
