import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/user_feedback_service.dart';
import '../theme/app_colors.dart';
import '../utils/debounced_text_controller.dart';
import '../widgets/fast_text_field.dart';
import '../widgets/module_header_premium.dart';
import '../widgets/admin/admin_page_shell.dart';
import '../utils/admin_responsive.dart';

/// Módulo admin: sugestões e críticas — abas Abertos/Respondidos, filtros, seleção e exclusão.
class AdminSugestoesTab extends StatefulWidget {
  final Color brandBlue;
  final Color brandTeal;

  const AdminSugestoesTab({
    super.key,
    required this.brandBlue,
    required this.brandTeal,
  });

  @override
  State<AdminSugestoesTab> createState() => _AdminSugestoesTabState();
}

class _AdminSugestoesTabState extends State<AdminSugestoesTab>
    with SingleTickerProviderStateMixin {
  final _feedbackService = UserFeedbackService();
  final _searchCtrl = DebouncedTextController();
  late final TabController _tabCtrl;
  final Set<String> _selectedIds = {};
  String _periodFilter = 'todos';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(_onTabChanged);
    _searchCtrl.debouncedText.addListener(_onSearchDebounced);
  }

  void _onSearchDebounced() {
    final q = _searchCtrl.debouncedText.value.trim().toLowerCase();
    if (q == _searchQuery) return;
    setState(() => _searchQuery = q);
  }

  void _onTabChanged() {
    if (_tabCtrl.indexIsChanging) return;
    setState(() => _selectedIds.clear());
  }

  @override
  void dispose() {
    _tabCtrl.removeListener(_onTabChanged);
    _searchCtrl.debouncedText.removeListener(_onSearchDebounced);
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _isRepliedTab() => _tabCtrl.index == 1;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final now = DateTime.now();
    return docs.where((doc) {
      final d = doc.data();
      final replied = UserFeedbackService.isReplied(d);
      if (_isRepliedTab() != replied) return false;

      if (_searchQuery.isNotEmpty) {
        final blob = [
          d['name'],
          d['email'],
          d['message'],
          d['adminReply'],
          d['uid'],
        ].join(' ').toLowerCase();
        if (!blob.contains(_searchQuery)) return false;
      }

      if (_periodFilter != 'todos') {
        final createdAt = d['createdAt'];
        if (createdAt is! Timestamp) return false;
        final days = now.difference(createdAt.toDate()).inDays;
        if (_periodFilter == '7' && days > 7) return false;
        if (_periodFilter == '30' && days > 30) return false;
      }
      return true;
    }).toList();
  }

  void _toggleSelectAll(List<QueryDocumentSnapshot<Map<String, dynamic>>> visible) {
    setState(() {
      if (_selectedIds.length == visible.length && visible.isNotEmpty) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(visible.map((d) => d.id));
      }
    });
  }

  Future<void> _confirmDelete({
    required int count,
    required Future<void> Function() onConfirm,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(count == 1 ? 'Excluir sugestão?' : 'Excluir $count sugestões?'),
        content: Text(
          count == 1
              ? 'Esta mensagem será removida permanentemente. Não pode ser desfeita.'
              : 'As $count mensagens selecionadas serão removidas permanentemente. '
                  'Não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(count == 1 ? 'Excluir' : 'Excluir todas'),
          ),
        ],
      ),
    );
    if (ok == true) await onConfirm();
  }

  Future<void> _deleteOne(String docId) async {
    await _confirmDelete(
      count: 1,
      onConfirm: () async {
        try {
          await _feedbackService.deleteFeedback(docId);
          if (mounted) {
            setState(() => _selectedIds.remove(docId));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Sugestão excluída.')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Erro ao excluir: $e'),
                backgroundColor: AppColors.error,
              ),
            );
          }
        }
      },
    );
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final ids = _selectedIds.toList();
    await _confirmDelete(
      count: ids.length,
      onConfirm: () async {
        try {
          final n = await _feedbackService.deleteFeedbackBulk(ids);
          if (mounted) {
            setState(_selectedIds.clear);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$n sugestão(ões) excluída(s).')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Erro ao excluir: $e'),
                backgroundColor: AppColors.error,
              ),
            );
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = AdminPageShell.listPadding(context, top: 8);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: pad.copyWith(bottom: 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ModuleHeaderPremium(
                title: 'Sugestões e Críticas',
                icon: Icons.feedback_rounded,
                subtitle:
                    'Abertos e respondidos, filtros, seleção múltipla e exclusão para limpar a base.',
              ),
              const SizedBox(height: 12),
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                child: TabBar(
                  controller: _tabCtrl,
                  labelColor: widget.brandBlue,
                  unselectedLabelColor: Colors.grey.shade600,
                  indicatorColor: widget.brandBlue,
                  tabs: const [
                    Tab(text: 'Abertos'),
                    Tab(text: 'Respondidos'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildFiltersCard(),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _feedbackService.watchAllFeedback(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: _errorBox('Erro: ${snap.error}'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final all = snap.data!.docs;
              final abertos = all
                  .where((d) => !UserFeedbackService.isReplied(d.data()))
                  .length;
              final respondidos = all
                  .where((d) => UserFeedbackService.isReplied(d.data()))
                  .length;
              final filtered = _filterDocs(all);

              return ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(
                  pad.left,
                  8,
                  pad.right,
                  pad.bottom,
                ),
                children: [
                  Text(
                    _isRepliedTab()
                        ? '$respondidos respondido(s) no total · ${filtered.length} após filtros'
                        : '$abertos aberto(s) no total · ${filtered.length} após filtros',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildSelectionBar(filtered),
                  const SizedBox(height: 8),
                  if (filtered.isEmpty)
                    _emptyInbox(_isRepliedTab())
                  else
                    ...filtered.map(
                      (doc) => _FeedbackCard(
                        doc: doc,
                        brandTeal: widget.brandTeal,
                        selected: _selectedIds.contains(doc.id),
                        onSelected: (v) => setState(() {
                          if (v) {
                            _selectedIds.add(doc.id);
                          } else {
                            _selectedIds.remove(doc.id);
                          }
                        }),
                        onDelete: () => _deleteOne(doc.id),
                        onReplied: () => setState(() {}),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFiltersCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FastTextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              labelText: 'Buscar (nome, e-mail, mensagem)',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchCtrl.clear();
                        _searchCtrl.flush();
                        setState(() => _searchQuery = '');
                      },
                    ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 400;
              final period = DropdownButtonFormField<String>(
                value: _periodFilter,
                decoration: const InputDecoration(
                  labelText: 'Período',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'todos', child: Text('Todos')),
                  DropdownMenuItem(value: '7', child: Text('Últimos 7 dias')),
                  DropdownMenuItem(value: '30', child: Text('Últimos 30 dias')),
                ],
                onChanged: (v) => setState(() => _periodFilter = v ?? 'todos'),
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [period],
                );
              }
              return Row(
                children: [
                  Expanded(child: period),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionBar(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> visible,
  ) {
    final allSelected =
        visible.isNotEmpty && _selectedIds.length == visible.length;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            SizedBox(
              height: 48,
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: allSelected,
                tristate: true,
                onChanged: visible.isEmpty
                    ? null
                    : (_) => _toggleSelectAll(visible),
                title: Text(
                  visible.isEmpty
                      ? 'Selecionar todos'
                      : allSelected
                          ? 'Desmarcar todos (${visible.length})'
                          : 'Selecionar todos (${visible.length})',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (_selectedIds.isNotEmpty) ...[
              Text(
                '${_selectedIds.length} selecionado(s)',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                  minimumSize: const Size(0, 44),
                ),
                onPressed: _deleteSelected,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Excluir selecionados'),
              ),
              TextButton(
                onPressed: () => setState(_selectedIds.clear),
                child: const Text('Limpar'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _emptyInbox(bool respondedTab) {
    return Container(
      padding: const EdgeInsets.all(28),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox_rounded, size: 52, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            respondedTab
                ? 'Nenhuma sugestão respondida com estes filtros.'
                : 'Nenhuma sugestão em aberto com estes filtros.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _errorBox(String msg) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Text(msg),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final Color brandTeal;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final VoidCallback onDelete;
  final VoidCallback onReplied;

  const _FeedbackCard({
    required this.doc,
    required this.brandTeal,
    required this.selected,
    required this.onSelected,
    required this.onDelete,
    required this.onReplied,
  });

  @override
  Widget build(BuildContext context) {
    final d = doc.data();
    final name = (d['name'] ?? '').toString();
    final email = (d['email'] ?? '').toString();
    final message = (d['message'] ?? '').toString();
    final adminReply = (d['adminReply'] ?? '').toString();
    final isReplied = UserFeedbackService.isReplied(d);
    final createdAt = d['createdAt'] is Timestamp
        ? (d['createdAt'] as Timestamp).toDate()
        : null;
    final repliedAt = d['repliedAt'] is Timestamp
        ? (d['repliedAt'] as Timestamp).toDate()
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.5)
              : Colors.grey.shade200,
          width: selected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Checkbox(
                    value: selected,
                    onChanged: (v) => onSelected(v == true),
                  ),
                ),
                CircleAvatar(
                  child: Text(
                    (name.isNotEmpty ? name[0] : '?').toUpperCase(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isNotEmpty ? name : 'Usuário',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (email.isNotEmpty)
                        Text(
                          email,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Excluir',
                  onPressed: onDelete,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    foregroundColor: AppColors.error,
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            if (createdAt != null)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 2),
                child: Text(
                  DateFormat('dd/MM/yyyy HH:mm').format(createdAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ),
            const SizedBox(height: 10),
            Text(message, style: const TextStyle(fontSize: 14, height: 1.4)),
            if (isReplied && adminReply.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: brandTeal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resposta do admin:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: brandTeal,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(adminReply),
                    if (repliedAt != null)
                      Text(
                        DateFormat('dd/MM/yyyy HH:mm').format(repliedAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (!isReplied)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _ReplyFeedbackButton(
                  docId: doc.id,
                  onReplied: onReplied,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReplyFeedbackButton extends StatefulWidget {
  final String docId;
  final VoidCallback onReplied;

  const _ReplyFeedbackButton({
    required this.docId,
    required this.onReplied,
  });

  @override
  State<_ReplyFeedbackButton> createState() => _ReplyFeedbackButtonState();
}

class _ReplyFeedbackButtonState extends State<_ReplyFeedbackButton> {
  final _replyCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _openReplyDialog() async {
    _replyCtrl.clear();
    final reply = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Responder'),
        content: FastTextField(
          controller: _replyCtrl,
          maxLines: 4,
          textInputAction: TextInputAction.newline,
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          decoration: const InputDecoration(
            labelText: 'Sua resposta',
            hintText: 'Digite sua resposta ao usuário...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _replyCtrl.text.trim()),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (reply == null || reply.isEmpty) return;
    setState(() => _saving = true);
    try {
      await UserFeedbackService().replyToFeedback(widget.docId, reply);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Resposta enviada.')),
        );
        widget.onReplied();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: _saving ? null : _openReplyDialog,
      icon: _saving
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.reply_rounded, size: 18),
      label: Text(_saving ? 'Enviando...' : 'Responder'),
      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
    );
  }
}
