import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/admin_audit_query_service.dart';
import '../../services/admin_user_internal_notes_service.dart';
import '../../services/billing_service.dart';
import '../../services/admin_audit_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_context.dart';
import '../../utils/admin_load_guard.dart';

/// Histórico de auditoria + notas internas + renovar 1 ano na ficha 360°.
class AdminUser360ExtrasPanel extends StatefulWidget {
  final String uid;
  final String userEmail;
  final bool canEdit;

  const AdminUser360ExtrasPanel({
    super.key,
    required this.uid,
    required this.userEmail,
    required this.canEdit,
  });

  @override
  State<AdminUser360ExtrasPanel> createState() => _AdminUser360ExtrasPanelState();
}

class _AdminUser360ExtrasPanelState extends State<AdminUser360ExtrasPanel> {
  final _notesCtrl = TextEditingController();
  bool _savingNote = false;
  bool _renewing = false;

  /// Escutas guardadas por uid (antes criadas no build a cada rebuild).
  late Stream<String> _noteStream;
  late Stream<List<AdminAuditEntry>> _auditStream;

  void _bindStreams() {
    _noteStream = AdminLoadGuard.primeiroDadoComPrazo(
      AdminUserInternalNotesService().watchNote(widget.uid),
      oQue: 'a nota interna',
    );
    _auditStream = AdminLoadGuard.primeiroDadoComPrazo(
      AdminAuditQueryService().watchForUser(widget.uid),
      oQue: 'o histórico',
    );
  }

  @override
  void initState() {
    super.initState();
    _bindStreams();
  }

  @override
  void didUpdateWidget(covariant AdminUser360ExtrasPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _notesCtrl.clear();
      _bindStreams();
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _renewOneYear() async {
    if (!widget.canEdit || _renewing) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renovar 1 ano?'),
        content: Text(
          'Prorroga a licença de ${widget.userEmail} em 365 dias a partir da data atual de vencimento (ou de hoje, se já venceu).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Renovar 1 ano'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _renewing = true);
    try {
      await BillingService().prorrogarPrazo(widget.uid, 365);
      await AdminAuditService().logAdminAction(
        action: prorrogarPrazo,
        targetUserId: widget.uid,
        targetUserEmail: widget.userEmail,
        details: 'Renovação assistida +365 dias',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Licença renovada por 1 ano.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Falha: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _renewing = false);
    }
  }

  Future<void> _saveNote() async {
    if (!widget.canEdit || _savingNote) return;
    setState(() => _savingNote = true);
    try {
      await AdminUserInternalNotesService()
          .saveNote(widget.uid, _notesCtrl.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nota interna guardada.')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingNote = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy HH:mm');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.canEdit)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FilledButton.tonalIcon(
              onPressed: _renewing ? null : _renewOneYear,
              icon: _renewing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.autorenew_rounded),
              label: Text(_renewing ? 'A renovar…' : 'Renovar 1 ano'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
              ),
            ),
          ),
        Text(
          'Notas internas (só admin)',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: context.isDarkMode ? context.appTextPrimary : Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 8),
        StreamBuilder<String>(
          stream: _noteStream,
          builder: (context, snap) {
            if (snap.hasData &&
                _notesCtrl.text.isEmpty &&
                snap.data!.isNotEmpty) {
              _notesCtrl.text = snap.data!;
            }
            // Só edita depois de ler a nota atual — antes dava para digitar
            // e «Guardar» por cima de uma nota que ainda não tinha chegado.
            final pronta = snap.hasData;
            return TextField(
              controller: _notesCtrl,
              readOnly: !widget.canEdit || !pronta,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: snap.hasError
                    ? 'Nota não carregou: ${AdminLoadGuard.mensagem(snap.error)}'
                    : (pronta
                        ? 'Observações de suporte, acordos, etc.'
                        : 'Carregando a nota…'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          },
        ),
        if (widget.canEdit) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _savingNote ? null : _saveNote,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: Text(_savingNote ? 'A guardar…' : 'Guardar nota'),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          'Histórico administrativo',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: context.isDarkMode ? context.appTextPrimary : Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<AdminAuditEntry>>(
          stream: _auditStream,
          builder: (context, snap) {
            if (snap.hasError && !snap.hasData) {
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      AdminLoadGuard.mensagem(snap.error),
                      style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(_bindStreams),
                    child: const Text('Tentar de novo'),
                  ),
                ],
              );
            }
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final entries = snap.data ?? [];
            if (entries.isEmpty) {
              return Text(
                'Sem registos de auditoria para este utilizador.',
                style: TextStyle(fontSize: 12, color: context.isDarkMode ? context.appTextSecondary : Colors.grey.shade600),
              );
            }
            return Column(
              children: entries.take(25).map((e) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  minVerticalPadding: 8,
                  leading: Icon(Icons.history_rounded,
                      color: context.isDarkMode ? context.appTextSecondary : Colors.grey.shade600, size: 22),
                  title: Text(
                    e.action.replaceAll('_', ' '),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    [
                      if (e.adminEmail.isNotEmpty) e.adminEmail,
                      if (e.details.isNotEmpty) e.details,
                      if (e.at != null) df.format(e.at!),
                    ].join(' · '),
                    style: TextStyle(fontSize: 11, color: context.isDarkMode ? context.appTextSecondary : Colors.grey.shade700),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}
