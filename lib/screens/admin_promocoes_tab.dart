import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import 'package:intl/intl.dart';

import '../constants/currency_formats.dart';
import '../constants/promo_site_urls.dart';
import '../services/functions_service.dart';
import '../theme/app_colors.dart';
import '../utils/debounced_text_controller.dart';
import '../utils/user_export_csv_save.dart';
import '../widgets/brl_amount_text_field.dart';
import '../widgets/module_header_premium.dart';
import '../widgets/admin/admin_page_shell.dart';
import '../utils/admin_responsive.dart';

class _PromoEmailRecipient {
  final String uid;
  final String label;
  final String? email;
  const _PromoEmailRecipient({required this.uid, required this.label, this.email});
}

/// CRUD de promoções: estoque, vigência, preço, duração da licença (+30 / +180 / +365 dias).
class AdminPromocoesTab extends StatelessWidget {
  const AdminPromocoesTab({super.key});

  static const List<String> kPlanCodes = [
    'premium_monthly',
    'premium_annual',
  ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('promotions').snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
                child: Text('Erro: ${snap.error}', style: const TextStyle(color: Colors.red)));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs.toList()
            ..sort((a, b) {
              final ca = a.data()['createdAt'] as Timestamp?;
              final cb = b.data()['createdAt'] as Timestamp?;
              if (ca == null && cb == null) return 0;
              if (ca == null) return 1;
              if (cb == null) return -1;
              return cb.compareTo(ca);
            });
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: ModuleHeaderPremium(
                  title: 'Promoções',
                  icon: Icons.local_offer_rounded,
                  subtitle:
                      'Campanhas, checkout e site. E-mail em massa só quando você enviar manualmente.',
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        'Com «Exibir quadro no site» e promo ativa: banner no app e aviso no iPhone. '
                        'E-mail: configure o texto e destinatários e use «Enviar e-mails» ou o ícone na lista.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.35),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _openEditor(context, null),
                        borderRadius: BorderRadius.circular(14),
                        child: Ink(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              colors: AppColors.logoGradient,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.deepBlueDark.withValues(alpha: 0.28),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_rounded, color: Colors.white, size: 22),
                                SizedBox(width: 8),
                                Text(
                                  'Nova promoção',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: docs.isEmpty
                    ? Center(
                        child: Text(
                          'Nenhuma promoção cadastrada.',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: docs.length,
                        itemBuilder: (context, i) {
                          final d = docs[i];
                          final m = d.data();
                          final active = m['active'] != false;
                          final total = (m['quantityTotal'] as num?)?.toInt() ?? 0;
                          final sold = (m['quantitySold'] as num?)?.toInt() ?? 0;
                          final mkt = (m['quantityMarketingDisplay'] as num?)?.toInt();
                          final days = (m['durationDays'] as num?)?.toInt() ?? 30;
                          final title = (m['title'] ?? d.id).toString();
                          final price = m['priceBrl'];
                          final linhaVagas = mkt != null && mkt > 0
                              ? 'Vendas: $sold / $total (limite real) · Divulgação (só admin): $mkt'
                              : 'Vendas: $sold / $total';
                          final noSite = m['showOnDivulgacaoWeb'] == true ? ' · Quadro no site' : '';
                          final lb = m['lastEmailBroadcast'];
                          var emailHist = '';
                          if (lb is Map) {
                            final ts = lb['at'];
                            if (ts is Timestamp) {
                              final sent = lb['sent'];
                              final failed = lb['failed'];
                              final mode = lb['recipientMode']?.toString() ?? '';
                              emailHist =
                                  '\nÚltimo e-mail: ${DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate())}'
                                  ' · $sent ok'
                                  '${failed != null && (failed is num) && failed > 0 ? ' · $failed falhas' : ''}'
                                  '${mode.isNotEmpty ? ' · $mode' : ''}';
                            }
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.deepBlue.withValues(alpha: 0.32),
                                    AppColors.accent.withValues(alpha: 0.2),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.deepBlueDark.withValues(alpha: 0.1),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(2),
                              child: Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                clipBehavior: Clip.antiAlias,
                                child: ListTile(
                                  contentPadding:
                                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                    'ID: ${d.id}\n'
                                    '$linhaVagas · +$days dias · plano ${m['planCode'] ?? 'premium_monthly'}\n'
                                    '${price != null ? 'Preço R\$ $price · ' : 'Preço padrão do plano · '}'
                                    '${active ? 'Ativa' : 'Inativa'}$noSite$emailHist',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey.shade700, height: 1.35),
                                  ),
                                  isThreeLine: false,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (active &&
                                          m['showOnDivulgacaoWeb'] == true)
                                        IconButton(
                                          tooltip:
                                              'Enviar e-mail (toda a base — texto editável)',
                                          icon: Icon(
                                            Icons.mark_email_unread_outlined,
                                            color: AppColors.accent,
                                          ),
                                          onPressed: () =>
                                              _openPromoListBroadcastDialog(
                                                  context, d.id),
                                        ),
                                      IconButton(
                                        tooltip: 'Duplicar',
                                        icon: Icon(Icons.copy_all_rounded, color: AppColors.deepBlue),
                                        onPressed: () => _openDuplicate(context, d.id),
                                      ),
                                      IconButton(
                                        tooltip: 'Editar',
                                        icon: Icon(Icons.edit_rounded, color: AppColors.deepBlue),
                                        onPressed: () => _openEditor(context, d.id),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
    );
  }

  static Future<void> _openEditor(BuildContext context, String? docId) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PromoEditorDialog(docId: docId),
    );
  }

  static Future<void> _openDuplicate(BuildContext context, String sourceId) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PromoEditorDialog(duplicateFromId: sourceId),
    );
  }

  static Future<void> _openPromoListBroadcastDialog(
      BuildContext context, String promoId) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _PromoListBroadcastDialog(promoId: promoId),
    );
  }
}

/// Limite de destinatários por envio de promo (validação ao enviar manualmente).
const int _kPromoEmailMaxRecipients = 2000;

/// Lista usuários com seleção múltipla, filtros e paginação para e-mail da promoção.
class _PromoUserPickerDialog extends StatefulWidget {
  const _PromoUserPickerDialog();

  @override
  State<_PromoUserPickerDialog> createState() => _PromoUserPickerDialogState();
}

class _PromoUserPickerDialogState extends State<_PromoUserPickerDialog> {
  final _localFilter = TextEditingController();
  final _serverQ = TextEditingController();
  VoidCallback? _detachFilterListener;

  final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> _byId = {};
  final Set<String> _selectedUids = {};

  QueryDocumentSnapshot<Map<String, dynamic>>? _pageCursor;
  bool _loadingPage = false;
  bool _hasMorePages = true;
  bool _searchingServer = false;
  String? _hint;

  String _planFilter = 'todos';
  bool _onlyWithEmail = true;

  @override
  void initState() {
    super.initState();
    // Debounce no filtro local — evita rebuild a cada tecla na lista grande.
    _detachFilterListener = attachDebouncedRebuild(_localFilter, () {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNextPage());
  }

  @override
  void dispose() {
    _detachFilterListener?.call();
    _localFilter.dispose();
    _serverQ.dispose();
    super.dispose();
  }

  static String _planOf(Map<String, dynamic>? m) =>
      (m?['plan'] ?? m?['planCode'] ?? 'free').toString().toLowerCase().trim();

  static String _labelFor(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data();
    final name = (m['name'] ?? '').toString().trim();
    final em = (m['email'] ?? '').toString().trim();
    return name.isNotEmpty ? '$name ($em)' : (em.isNotEmpty ? em : doc.id);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _visibleDocs {
    var list = _byId.values.toList();
    if (_onlyWithEmail) {
      list = list
          .where((d) => (d.data()['email'] ?? '').toString().trim().isNotEmpty)
          .toList();
    }
    if (_planFilter != 'todos') {
      list = list.where((d) => _planOf(d.data()) == _planFilter).toList();
    }
    final q = _localFilter.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((d) {
        final m = d.data();
        final name = (m['name'] ?? '').toString().toLowerCase();
        final em = (m['email'] ?? '').toString().toLowerCase();
        return name.contains(q) || em.contains(q) || d.id.toLowerCase().contains(q);
      }).toList();
    }
    list.sort((a, b) {
      final ea = (a.data()['email'] ?? a.id).toString().toLowerCase();
      final eb = (b.data()['email'] ?? b.id).toString().toLowerCase();
      return ea.compareTo(eb);
    });
    return list;
  }

  Future<void> _loadNextPage() async {
    if (_loadingPage || !_hasMorePages) return;
    setState(() {
      _loadingPage = true;
      _hint = null;
    });
    try {
      Query<Map<String, dynamic>> qb = FirebaseFirestore.instance
          .collection('users')
          .orderBy(FieldPath.documentId)
          .limit(120);
      if (_pageCursor != null) {
        qb = qb.startAfterDocument(_pageCursor!);
      }
      final snap = await qb.get();
      if (!mounted) return;
      if (snap.docs.isEmpty) {
        setState(() {
          _hasMorePages = false;
          _loadingPage = false;
          if (_byId.isEmpty) {
            _hint = 'Nenhum usuário retornado.';
          }
        });
        return;
      }
      _pageCursor = snap.docs.last;
      for (final d in snap.docs) {
        _byId[d.id] = d;
      }
      setState(() {
        _loadingPage = false;
        _hint = '${_byId.length} conta(s) carregada(s). Use “Carregar mais” ou busca no servidor.';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingPage = false;
          _hint = e.toString().split('\n').first;
        });
      }
    }
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _searchUsersServer(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.length < 2) return [];
    final qLower = trimmed.toLowerCase();
    final out = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    final errors = <String>[];

    Future<void> addEqEmail(String emailTry) async {
      try {
        final eq = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: emailTry)
            .limit(8)
            .get();
        for (final d in eq.docs) {
          out[d.id] = d;
        }
      } catch (e) {
        errors.add(e.toString().split('\n').first);
      }
    }

    await addEqEmail(trimmed);
    if (trimmed != qLower) await addEqEmail(qLower);

    try {
      final pref = await FirebaseFirestore.instance
          .collection('users')
          .orderBy('email')
          .startAt([qLower])
          .endAt(['$qLower\uf8ff'])
          .limit(45)
          .get();
      for (final d in pref.docs) {
        out[d.id] = d;
      }
    } catch (e) {
      errors.add(e.toString().split('\n').first);
    }

    if (out.length < 60) {
      try {
        QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
        for (var page = 0; page < 6 && out.length < 60; page++) {
          Query<Map<String, dynamic>> qb =
              FirebaseFirestore.instance.collection('users').orderBy(FieldPath.documentId).limit(500);
          if (cursor != null) {
            qb = qb.startAfterDocument(cursor);
          }
          final bulk = await qb.get();
          if (bulk.docs.isEmpty) break;
          for (final d in bulk.docs) {
            final m = d.data();
            final name = (m['name'] ?? '').toString().toLowerCase();
            final em = (m['email'] ?? '').toString().toLowerCase();
            if (name.contains(qLower) || em.contains(qLower)) {
              out[d.id] = d;
              if (out.length >= 60) break;
            }
          }
          cursor = bulk.docs.last;
        }
      } catch (e) {
        errors.add(e.toString().split('\n').first);
      }
    }

    if (out.isEmpty && errors.isNotEmpty) {
      throw Exception(errors.first);
    }

    final list = out.values.toList()
      ..sort((a, b) {
        final ea = (a.data()['email'] ?? '').toString();
        final eb = (b.data()['email'] ?? '').toString();
        return ea.compareTo(eb);
      });
    return list;
  }

  Future<void> _runServerSearch() async {
    final raw = _serverQ.text.trim();
    if (raw.length < 2) {
      setState(() => _hint = 'Na busca no servidor use pelo menos 2 caracteres.');
      return;
    }
    setState(() {
      _searchingServer = true;
      _hint = null;
    });
    try {
      final list = await _searchUsersServer(raw);
      if (!mounted) return;
      for (final d in list) {
        _byId[d.id] = d;
      }
      setState(() {
        _searchingServer = false;
        _hint = list.isEmpty
            ? 'Nenhum resultado no servidor para “$raw”.'
            : '${list.length} resultado(s) mesclado(s) à lista (por ID).';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchingServer = false;
          _hint = e.toString().split('\n').first;
        });
      }
    }
  }

  void _selectAllVisible() {
    final vis = _visibleDocs;
    var n = 0;
    setState(() {
      for (final d in vis) {
        if (_selectedUids.length >= _kPromoEmailMaxRecipients) break;
        if (_selectedUids.add(d.id)) n++;
      }
      if (n == 0 && vis.isNotEmpty) {
        _hint = 'Limite de $_kPromoEmailMaxRecipients selecionados atingido.';
      } else if (vis.isEmpty) {
        _hint = 'Nenhuma linha visível com os filtros atuais.';
      } else {
        _hint = '$n marcado(s) nesta ação (${_selectedUids.length} no total).';
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedUids.clear();
      _hint = 'Seleção limpa.';
    });
  }

  void _confirm() {
    final docs = _byId.values.where((d) => _selectedUids.contains(d.id)).toList();
    Navigator.of(context).pop(docs);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleDocs;
    final visibleSelected =
        visible.where((d) => _selectedUids.contains(d.id)).length;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                gradient: LinearGradient(
                  colors: [
                    AppColors.deepBlueDark,
                    AppColors.deepBlue,
                    AppColors.accent.withValues(alpha: 0.95),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.people_outline_rounded, color: Colors.white.withValues(alpha: 0.95)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Escolher destinatários',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(<QueryDocumentSnapshot<Map<String, dynamic>>>[]),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FastTextField(
                    controller: _localFilter,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    spellCheckConfiguration:
                        const SpellCheckConfiguration.disabled(),
                    smartDashesType: SmartDashesType.disabled,
                    smartQuotesType: SmartQuotesType.disabled,
                    textInputAction: TextInputAction.search,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: const InputDecoration(
                      labelText: 'Filtrar lista (nome, e-mail ou UID)',
                      hintText: 'Refina só entre os já carregados',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    // Sem onChanged: setState — debounce via listener.
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 200,
                        child: DropdownButtonFormField<String>(
                          value: _planFilter,
                          decoration: const InputDecoration(
                            labelText: 'Plano',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'todos', child: Text('Todos')),
                            DropdownMenuItem(value: 'free', child: Text('Free')),
                            DropdownMenuItem(value: 'basic', child: Text('Básico')),
                            DropdownMenuItem(value: 'premium', child: Text('Premium')),
                            DropdownMenuItem(value: 'master', child: Text('Master')),
                          ],
                          onChanged: (v) => setState(() => _planFilter = v ?? 'todos'),
                        ),
                      ),
                      FilterChip(
                        label: const Text('Só com e-mail'),
                        selected: _onlyWithEmail,
                        onSelected: (v) => setState(() => _onlyWithEmail = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _loadingPage ? null : _loadNextPage,
                          icon: _loadingPage
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.cloud_download_rounded, size: 18),
                          label: Text(_hasMorePages ? 'Carregar mais' : 'Fim da lista'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _selectAllVisible,
                        child: const Text('Marcar todos\nvisíveis', textAlign: TextAlign.center),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _clearSelection,
                        child: const Text('Limpar\nseleção', textAlign: TextAlign.center),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: FastTextField(
                          controller: _serverQ,
                          autocorrect: false,
                          textInputAction: TextInputAction.search,
                          onTapOutside: (_) =>
                              FocusManager.instance.primaryFocus?.unfocus(),
                          decoration: const InputDecoration(
                            labelText: 'Busca no Firestore',
                            hintText: '≥2 caracteres (e-mail ou nome)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _runServerSearch(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: FilledButton(
                          onPressed: _searchingServer ? null : _runServerSearch,
                          child: _searchingServer
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Buscar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_hint != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(_hint!, style: TextStyle(fontSize: 12, color: Colors.orange.shade900)),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'Visíveis: ${visible.length} · Selecionados: ${_selectedUids.length}'
                    '${visible.isNotEmpty ? ' ($visibleSelected nesta lista)' : ''}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _byId.isEmpty
                              ? 'Carregando usuários… ou use “Buscar” no servidor.'
                              : 'Nenhum usuário com os filtros atuais. Ajuste plano / e-mail / texto.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      itemCount: visible.length,
                      itemBuilder: (context, i) {
                        final doc = visible[i];
                        final m = doc.data();
                        final plan = _planOf(m);
                        final sel = _selectedUids.contains(doc.id);
                        return CheckboxListTile(
                          value: sel,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                if (_selectedUids.length < _kPromoEmailMaxRecipients) {
                                  _selectedUids.add(doc.id);
                                } else {
                                  _hint = 'Máximo $_kPromoEmailMaxRecipients selecionados.';
                                }
                              } else {
                                _selectedUids.remove(doc.id);
                              }
                            });
                          },
                          secondary: CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.deepBlue.withValues(alpha: 0.12),
                            child: Text(
                              plan.isNotEmpty ? plan.substring(0, 1).toUpperCase() : '?',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppColors.deepBlueDark,
                              ),
                            ),
                          ),
                          title: Text(
                            _labelFor(doc),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${doc.id} · $plan',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop(<QueryDocumentSnapshot<Map<String, dynamic>>>[]),
                    child: const Text('Cancelar'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _selectedUids.isEmpty ? null : _confirm,
                    icon: const Icon(Icons.add_task_rounded, size: 20),
                    label: Text('Adicionar ${_selectedUids.length} à promoção'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromoEditorDialog extends StatefulWidget {
  final String? docId;
  /// Carrega campos deste documento mas grava como promoção nova.
  final String? duplicateFromId;

  const _PromoEditorDialog({this.docId, this.duplicateFromId});

  @override
  State<_PromoEditorDialog> createState() => _PromoEditorDialogState();
}

class _PromoEditorDialogState extends State<_PromoEditorDialog> {
  final _titleCtrl = TextEditingController();
  final _totalCtrl = TextEditingController(text: '10');
  /// Só controle interno no painel (ex.: “falo 30 na campanha”). Não altera o limite de vendas.
  final _marketingDisplayCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _addEmailCtrl = TextEditingController();
  final _addUidCtrl = TextEditingController();
  final _promoEmailSubjectCtrl = TextEditingController();
  final _promoEmailBodyCtrl = TextEditingController();
  String _planCode = 'premium_monthly';
  int _durationDays = 30;
  bool _active = true;
  /// Quadro público na landing e em /divulgacao (só web). Marque só numa promoção por vez.
  bool _showOnDivulgacaoWeb = false;
  /// false = todos (exceto admin/master no servidor); true = só [_promoEmailRecipients].
  bool _restrictPromoEmailRecipients = false;
  final List<_PromoEmailRecipient> _promoEmailRecipients = [];
  bool _lookingUpPromoUser = false;
  bool _sendingTestEmail = false;
  bool _sendingBroadcast = false;
  DateTime? _validFrom;
  DateTime? _validUntil;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.docId != null;

  String _defaultPromoEmailSubject() => 'WISDOMAPP — nova promoção disponível';

  String _defaultPromoEmailBody(String titleLine) =>
      'Nova promoção: $titleLine. Abra o site oficial no link abaixo para ver o valor e concluir com PIX ou cartão.';

  void _syncPromoEmailDefaultsFromTitle() {
    final t = _titleCtrl.text.trim();
    final line = t.isEmpty ? '… (informe o título acima)' : t;
    if (_promoEmailSubjectCtrl.text.trim().isEmpty) {
      _promoEmailSubjectCtrl.text = _defaultPromoEmailSubject();
    }
    if (_promoEmailBodyCtrl.text.trim().isEmpty) {
      _promoEmailBodyCtrl.text = _defaultPromoEmailBody(line);
    }
  }

  String _promoLinkPreview() {
    if (_isEdit && widget.docId != null) {
      return buildMaintenancePromoSiteUrl(
        promoFirestoreId: widget.docId,
        source: 'email_promocao_admin_promo',
      );
    }
    return '(o link com ?promo=… será gerado após salvar — copie da lista ou reabra a edição)';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loadId = widget.docId ?? widget.duplicateFromId;
    if (loadId == null) {
      if (mounted) {
        _syncPromoEmailDefaultsFromTitle();
        setState(() => _loading = false);
      }
      return;
    }
    try {
      final snap =
          await FirebaseFirestore.instance.collection('promotions').doc(loadId).get();
      final m = snap.data();
      if (m != null) {
        _titleCtrl.text = (m['title'] ?? '').toString();
        _totalCtrl.text = ((m['quantityTotal'] as num?) ?? 10).toString();
        final qm = (m['quantityMarketingDisplay'] as num?)?.toInt();
        _marketingDisplayCtrl.text = (qm != null && qm > 0) ? qm.toString() : '';
        final pb = m['priceBrl'];
        _priceCtrl.text =
            pb != null ? CurrencyFormats.formatBRLInput((pb as num).toDouble()) : '';
        _planCode = (m['planCode'] ?? 'premium_monthly').toString();
        if (AdminPromocoesTab.kPlanCodes.contains(_planCode) == false) {
          _planCode = 'premium_monthly';
        }
        _durationDays = (m['durationDays'] as num?)?.toInt() ?? 30;
        _active = m['active'] != false;
        _showOnDivulgacaoWeb = m['showOnDivulgacaoWeb'] == true;
        final vf = m['validFrom'] as Timestamp?;
        final vu = m['validUntil'] as Timestamp?;
        _validFrom = vf?.toDate();
        _validUntil = vu?.toDate();
        if (widget.duplicateFromId != null && widget.docId == null) {
          final base = _titleCtrl.text.trim();
          _titleCtrl.text = base.isEmpty ? 'Promoção (cópia)' : '$base (cópia)';
        }
      }
    } catch (e) {
      _error = e.toString();
    }
    _promoEmailSubjectCtrl.text = _defaultPromoEmailSubject();
    _promoEmailBodyCtrl.text = _defaultPromoEmailBody(_titleCtrl.text.trim().isEmpty ? '…' : _titleCtrl.text.trim());
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _totalCtrl.dispose();
    _marketingDisplayCtrl.dispose();
    _priceCtrl.dispose();
    _addEmailCtrl.dispose();
    _addUidCtrl.dispose();
    _promoEmailSubjectCtrl.dispose();
    _promoEmailBodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _validFrom : _validUntil;
    final d = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );
    if (d != null) {
      setState(() {
        if (isStart) {
          _validFrom = d;
        } else {
          _validUntil = d;
        }
      });
    }
  }

  void _mergeRecipientsBatch(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (docs.isEmpty) return;
    var added = 0;
    var skipped = 0;
    setState(() {
      _restrictPromoEmailRecipients = true;
      for (final doc in docs) {
        final uid = doc.id;
        if (_promoEmailRecipients.any((r) => r.uid == uid)) {
          skipped++;
          continue;
        }
        final ud = doc.data();
        final name = (ud['name'] ?? '').toString().trim();
        final em = (ud['email'] ?? '').toString().trim();
        final label = name.isNotEmpty ? '$name ($em)' : (em.isNotEmpty ? em : uid);
        _promoEmailRecipients.add(_PromoEmailRecipient(
          uid: uid,
          label: label,
          email: em.isNotEmpty ? em : null,
        ));
        added++;
      }
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added > 0
              ? '$added destinatário(s) adicionado(s).'
                  '${skipped > 0 ? ' $skipped já estavam na lista.' : ''}'
              : 'Nenhum novo (todos já estavam na lista).',
        ),
      ),
    );
  }

  Future<void> _openUserPickerDialog() async {
    final list = await showDialog<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      context: context,
      builder: (ctx) => const _PromoUserPickerDialog(),
    );
    if (list == null || list.isEmpty || !mounted) return;
    _mergeRecipientsBatch(list);
  }

  Future<void> _addRecipientByEmail() async {
    final email = _addEmailCtrl.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Informe um e-mail válido.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }
    setState(() => _lookingUpPromoUser = true);
    try {
      final q = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(5)
          .get();
      if (!mounted) return;
      if (q.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Nenhum usuário com e-mail "$email".'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      _mergeRecipientFromDoc(q.docs.first);
      _addEmailCtrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao buscar: ${e.toString().split('\n').first}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _lookingUpPromoUser = false);
    }
  }

  Future<void> _addRecipientByUid() async {
    final uid = _addUidCtrl.text.trim();
    if (uid.length < 8) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('UID inválido (cole o ID do usuário no Firebase).'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }
    setState(() => _lookingUpPromoUser = true);
    try {
      final snap = await FirebaseFirestore.instance.doc('users/$uid').get();
      if (!mounted) return;
      if (!snap.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Usuário não encontrado para este UID.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      _mergeRecipientFromDoc(snap);
      _addUidCtrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString().split('\n').first}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _lookingUpPromoUser = false);
    }
  }

  void _mergeRecipientFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final uid = doc.id;
    if (_promoEmailRecipients.any((r) => r.uid == uid)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usuário já está na lista.')),
      );
      return;
    }
    final ud = doc.data();
    final name = (ud?['name'] ?? '').toString().trim();
    final em = (ud?['email'] ?? '').toString().trim();
    final label = name.isNotEmpty ? '$name ($em)' : (em.isNotEmpty ? em : uid);
    setState(() {
      _restrictPromoEmailRecipients = true;
      _promoEmailRecipients.add(_PromoEmailRecipient(
        uid: uid,
        label: label,
        email: em.isNotEmpty ? em : null,
      ));
    });
  }

  Future<void> _exportRecipientsCsv() async {
    if (_promoEmailRecipients.isEmpty) return;
    final lines = <String>['uid,email,rotulo'];
    for (final r in _promoEmailRecipients) {
      final esc = r.label.replaceAll('"', '""');
      lines.add('"${r.uid}","${r.email ?? ''}","$esc"');
    }
    final ok = await saveUserExportCsv(
      'promo_destinatarios_${DateTime.now().millisecondsSinceEpoch}.csv',
      lines.join('\n'),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'CSV gerado.' : 'Exportação cancelada.'),
        backgroundColor: ok ? AppColors.success : AppColors.error,
      ),
    );
  }

  Future<void> _sendTestPromoEmail() async {
    if (!_isEdit || widget.docId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Salve a promoção uma vez para obter o link e poder enviar o teste.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    final me = FirebaseAuth.instance.currentUser?.email?.trim();
    if (me == null || !me.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Faça login com uma conta que tenha e-mail para receber o teste.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    _syncPromoEmailDefaultsFromTitle();
    final linkUrl = buildMaintenancePromoSiteUrl(
      promoFirestoreId: widget.docId!,
      source: 'email_promocao_admin_promo',
    );
    final subj = _promoEmailSubjectCtrl.text.trim().isNotEmpty
        ? _promoEmailSubjectCtrl.text.trim()
        : _defaultPromoEmailSubject();
    final body = _promoEmailBodyCtrl.text.trim().isNotEmpty
        ? _promoEmailBodyCtrl.text.trim()
        : _defaultPromoEmailBody(_titleCtrl.text.trim().isEmpty ? 'Promoção' : _titleCtrl.text.trim());
    setState(() => _sendingTestEmail = true);
    try {
      await FunctionsService().sendMaintenancePromoTestEmail(
        linkUrl: linkUrl,
        messageText: body,
        testEmail: me,
        subject: subj,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('E-mail de teste enviado para $me.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Teste não enviado: ${e.toString().split('\n').first}'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingTestEmail = false);
    }
  }

  Future<void> _sendPromoBroadcastNow() async {
    final pid = widget.docId;
    if (pid == null || !_active || !_showOnDivulgacaoWeb) return;
    if (_restrictPromoEmailRecipients) {
      if (_promoEmailRecipients.isEmpty) {
        setState(() {
          _error = 'Adicione destinatários ou escolha “Todos os usuários”.';
        });
        return;
      }
      if (_promoEmailRecipients.length > _kPromoEmailMaxRecipients) {
        setState(() {
          _error =
              'Máximo $_kPromoEmailMaxRecipients destinatários por envio. Reduza a lista.';
        });
        return;
      }
    }
    setState(() {
      _sendingBroadcast = true;
      _error = null;
    });
    final title = _titleCtrl.text.trim();
    final linkUrl = buildMaintenancePromoSiteUrl(
      promoFirestoreId: pid,
      source: 'email_promocao_admin_promo',
    );
    _syncPromoEmailDefaultsFromTitle();
    final subj = _promoEmailSubjectCtrl.text.trim().isNotEmpty
        ? _promoEmailSubjectCtrl.text.trim()
        : _defaultPromoEmailSubject();
    final bodyText = _promoEmailBodyCtrl.text.trim().isNotEmpty
        ? _promoEmailBodyCtrl.text.trim()
        : _defaultPromoEmailBody(title.isEmpty ? 'Promoção' : title);
    try {
      final targetUids = _restrictPromoEmailRecipients && _promoEmailRecipients.isNotEmpty
          ? _promoEmailRecipients.map((e) => e.uid).toList()
          : null;
      final er = await FunctionsService().sendMaintenancePromoEmails(
        linkUrl: linkUrl,
        messageText: bodyText,
        subject: subj,
        targetUids: targetUids,
      );
      if (!mounted) return;
      final sent = er['sent'] ?? 0;
      final failed = er['failed'] ?? 0;
      final totalRecipients = er['total'] ?? sent + failed;
      final scope =
          targetUids != null ? '${targetUids.length} na lista' : 'toda a base (filtro servidor)';
      await FirebaseFirestore.instance.collection('promotions').doc(pid).set({
        'lastEmailBroadcast': {
          'at': FieldValue.serverTimestamp(),
          'sent': sent,
          'failed': failed,
          'total': totalRecipients,
          'recipientMode': targetUids != null ? 'selected' : 'all',
        },
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'E-mail: $sent ok, $totalRecipients destinatários ($scope)${failed > 0 ? ' · $failed falhas' : ''}.',
          ),
          duration: const Duration(seconds: 9),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().split('\n').first;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('E-mail não enviado: ${e.toString().split('\n').first}'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingBroadcast = false);
    }
  }

  void _removeRecipient(String uid) {
    setState(() {
      _promoEmailRecipients.removeWhere((r) => r.uid == uid);
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() {
        _error = 'Informe um título.';
        _saving = false;
      });
      return;
    }
    final total = int.tryParse(_totalCtrl.text.trim());
    if (total == null || total < 1) {
      setState(() {
        _error = 'Limite real de vendas deve ser ≥ 1.';
        _saving = false;
      });
      return;
    }
    int? marketingDisplay;
    final mktTxt = _marketingDisplayCtrl.text.trim();
    if (mktTxt.isNotEmpty) {
      marketingDisplay = int.tryParse(mktTxt);
      if (marketingDisplay == null || marketingDisplay < 1) {
        setState(() {
          _error = '“Quantidade divulgação” deve ser um número ≥ 1 ou fique vazio.';
          _saving = false;
        });
        return;
      }
    }
    double? priceBrl;
    final ptxt = _priceCtrl.text.trim();
    if (ptxt.isNotEmpty) {
      priceBrl = CurrencyFormats.parseBRLInput(ptxt);
      if (priceBrl == null || priceBrl <= 0) {
        setState(() {
          _error = 'Preço inválido (use ponto ou vírgula).';
          _saving = false;
        });
        return;
      }
    }

    try {
      final col = FirebaseFirestore.instance.collection('promotions');
      final ref = _isEdit ? col.doc(widget.docId) : col.doc();
      final now = FieldValue.serverTimestamp();
      final payload = <String, dynamic>{
        'title': title,
        'active': _active,
        'quantityTotal': total,
        'durationDays': _durationDays,
        'planCode': _planCode,
        'updatedAt': now,
        'showOnDivulgacaoWeb': _showOnDivulgacaoWeb,
      };
      if (marketingDisplay != null) {
        payload['quantityMarketingDisplay'] = marketingDisplay;
      } else {
        payload['quantityMarketingDisplay'] = FieldValue.delete();
      }
      if (!_isEdit) {
        payload['quantitySold'] = 0;
        payload['createdAt'] = now;
      }
      if (priceBrl != null) {
        payload['priceBrl'] = priceBrl;
      } else {
        payload['priceBrl'] = FieldValue.delete();
      }
      if (_validFrom != null) {
        payload['validFrom'] =
            Timestamp.fromDate(DateTime(_validFrom!.year, _validFrom!.month, _validFrom!.day));
      } else {
        payload['validFrom'] = FieldValue.delete();
      }
      if (_validUntil != null) {
        payload['validUntil'] = Timestamp.fromDate(
            DateTime(_validUntil!.year, _validUntil!.month, _validUntil!.day, 23, 59, 59));
      } else {
        payload['validUntil'] = FieldValue.delete();
      }
      await ref.set(payload, SetOptions(merge: true));
      if (!mounted) return;

      final scaffold = ScaffoldMessenger.maybeOf(context);
      final resumo = StringBuffer('Limite real: $total vendas.');
      if (marketingDisplay != null) {
        resumo.write(' Divulgação (painel): $marketingDisplay.');
      }
      if (_active && _showOnDivulgacaoWeb) {
        resumo.write(
            ' E-mail: use «Enviar e-mails» no rodapé ou o ícone na lista quando quiser disparar.');
      }

      if (mounted) Navigator.of(context).pop();
      if (scaffold != null) {
        scaffold.showSnackBar(
          SnackBar(
            content: Text('Promoção salva. ${resumo.toString()}'),
            duration: const Duration(seconds: 8),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 8, 18),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                gradient: LinearGradient(
                  colors: [
                    AppColors.deepBlueDark,
                    AppColors.deepBlue,
                    AppColors.accent.withValues(alpha: 0.92),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.local_offer_rounded, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isEdit ? 'Editar promoção' : 'Nova promoção',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: _loading
                  ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FastTextField(
                            controller: _titleCtrl,
                            textInputAction: TextInputAction.next,
                            onSubmitted: (_) =>
                                FocusScope.of(context).nextFocus(),
                            onTapOutside: (_) =>
                                FocusManager.instance.primaryFocus?.unfocus(),
                            decoration: const InputDecoration(
                              labelText: 'Título (aparece no checkout)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FastTextField(
                            controller: _totalCtrl,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            onSubmitted: (_) =>
                                FocusScope.of(context).nextFocus(),
                            onTapOutside: (_) =>
                                FocusManager.instance.primaryFocus?.unfocus(),
                            decoration: const InputDecoration(
                              labelText: 'Limite real de vendas (sistema)',
                              border: OutlineInputBorder(),
                              helperText:
                                  'O checkout e o servidor usam este número (ex.: aceita até 60 vendas).',
                            ),
                          ),
                          const SizedBox(height: 12),
                          FastTextField(
                            controller: _marketingDisplayCtrl,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            onSubmitted: (_) =>
                                FocusScope.of(context).nextFocus(),
                            onTapOutside: (_) =>
                                FocusManager.instance.primaryFocus?.unfocus(),
                            decoration: const InputDecoration(
                              labelText: 'Quantidade divulgação (só painel admin)',
                              border: OutlineInputBorder(),
                              helperText:
                                  'Opcional. Ex.: você divulga “30 vagas” mas o limite real acima é 60. Não aparece no app/site para o cliente.',
                            ),
                          ),
                          const SizedBox(height: 12),
                          BrlAmountTextField(
                            controller: _priceCtrl,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: 'Valor R\$ (vazio = preço padrão do plano)',
                              border: OutlineInputBorder(),
                              helperText: 'Deve bater com o valor enviado ao Mercado Pago.',
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _planCode,
                            decoration: const InputDecoration(
                              labelText: 'Plano (tier)',
                              border: OutlineInputBorder(),
                            ),
                            items: AdminPromocoesTab.kPlanCodes
                                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                .toList(),
                            onChanged: (v) => setState(() => _planCode = v ?? _planCode),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            value: _durationDays,
                            decoration: const InputDecoration(
                              labelText: 'Extensão da licença após pagamento',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 30, child: Text('+30 dias (mensal)')),
                              DropdownMenuItem(value: 180, child: Text('+180 dias (~6 meses)')),
                              DropdownMenuItem(value: 365, child: Text('+365 dias (anual)')),
                            ],
                            onChanged: (v) => setState(() => _durationDays = v ?? 30),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _pickDate(isStart: true),
                                  child: Text(_validFrom == null
                                      ? 'Início vigência'
                                      : 'De: ${df.format(_validFrom!)}'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _pickDate(isStart: false),
                                  child: Text(_validUntil == null
                                      ? 'Fim vigência'
                                      : 'Até: ${df.format(_validUntil!)}'),
                                ),
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              _validFrom = null;
                              _validUntil = null;
                            }),
                            child: const Text('Limpar datas de vigência'),
                          ),
                          SwitchListTile(
                            title: const Text('Promoção ativa'),
                            value: _active,
                            activeThumbColor: AppColors.primary,
                            onChanged: (v) => setState(() => _active = v),
                          ),
                          SwitchListTile(
                            title: const Text('Exibir quadro no site (divulgação)'),
                            subtitle: const Text(
                              'Landing, /divulgacao e banner no app (Android/web). No iPhone: aviso com link para o site. Uma promo “no site” por vez evita confusão.',
                              style: TextStyle(fontSize: 12),
                            ),
                            value: _showOnDivulgacaoWeb,
                            activeThumbColor: AppColors.primary,
                            onChanged: (v) => setState(() => _showOnDivulgacaoWeb = v),
                          ),
                          if (_active && _showOnDivulgacaoWeb) ...[
                            const SizedBox(height: 8),
                            Card(
                              margin: EdgeInsets.zero,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(color: Colors.grey.shade200),
                              ),
                              child: ExpansionTile(
                                title: const Text('E-mail em massa (envio manual)'),
                                subtitle: Text(
                                  'Assunto, corpo e destinatários — só envia ao tocar em «Enviar e-mails» no rodapé.',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                children: [
                                  FastTextField(
                                    controller: _promoEmailSubjectCtrl,
                                    textInputAction: TextInputAction.next,
                                    onSubmitted: (_) =>
                                        FocusScope.of(context).nextFocus(),
                                    onTapOutside: (_) =>
                                        FocusManager.instance.primaryFocus?.unfocus(),
                                    decoration: const InputDecoration(
                                      labelText: 'Assunto',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                  const SizedBox(height: 10),
                                  FastTextField(
                                    controller: _promoEmailBodyCtrl,
                                    maxLines: 5,
                                    textInputAction: TextInputAction.newline,
                                    onTapOutside: (_) =>
                                        FocusManager.instance.primaryFocus?.unfocus(),
                                    decoration: const InputDecoration(
                                      labelText: 'Mensagem (corpo do e-mail)',
                                      alignLabelWithHint: true,
                                      border: OutlineInputBorder(),
                                      helperText: 'Aparece no HTML acima do botão “Abrir site oficial”.',
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Link no e-mail',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.grey.shade800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  SelectableText(
                                    _promoLinkPreview(),
                                    style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: _sendingTestEmail ? null : _sendTestPromoEmail,
                                        icon: _sendingTestEmail
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              )
                                            : const Icon(Icons.mark_email_read_rounded, size: 20),
                                        label: const Text('Enviar teste para meu e-mail'),
                                      ),
                                      if (_restrictPromoEmailRecipients &&
                                          _promoEmailRecipients.isNotEmpty)
                                        OutlinedButton.icon(
                                          onPressed: _exportRecipientsCsv,
                                          icon: const Icon(Icons.table_chart_rounded, size: 20),
                                          label: const Text('Exportar lista (CSV)'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (!_isEdit)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Salve a promoção uma vez; depois reabra para usar «Enviar e-mails» no rodapé, ou o ícone na lista (envio rápido para toda a base).',
                                  style:
                                      TextStyle(fontSize: 11, color: Colors.teal.shade800),
                                ),
                              ),
                            const SizedBox(height: 8),
                            Text(
                              'Destinatários do e-mail',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            RadioListTile<bool>(
                              value: false,
                              groupValue: _restrictPromoEmailRecipients,
                              title: const Text('Todos os usuários'),
                              subtitle: const Text(
                                'Exceto admin/master — mesmo critério do servidor.',
                                style: TextStyle(fontSize: 11),
                              ),
                              onChanged: (_) => setState(() {
                                _restrictPromoEmailRecipients = false;
                                _promoEmailRecipients.clear();
                              }),
                              contentPadding: EdgeInsets.zero,
                            ),
                            RadioListTile<bool>(
                              value: true,
                              groupValue: _restrictPromoEmailRecipients,
                              title: const Text('Somente selecionados'),
                              subtitle: const Text(
                                'Lista com filtros e marcar vários, busca no servidor, e-mail ou UID. Máx. 2000 por envio.',
                                style: TextStyle(fontSize: 11),
                              ),
                              onChanged: (_) =>
                                  setState(() => _restrictPromoEmailRecipients = true),
                              contentPadding: EdgeInsets.zero,
                            ),
                            if (_restrictPromoEmailRecipients) ...[
                              const SizedBox(height: 8),
                              FilledButton.tonalIcon(
                                onPressed: _lookingUpPromoUser ? null : _openUserPickerDialog,
                                icon: const Icon(Icons.checklist_rounded),
                                label: const Text('Lista de usuários (marcar vários)'),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: FastTextField(
                                      controller: _addEmailCtrl,
                                      keyboardType: TextInputType.emailAddress,
                                      autocorrect: false,
                                      textInputAction: TextInputAction.next,
                                      onSubmitted: (_) =>
                                          FocusScope.of(context).nextFocus(),
                                      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                                      decoration: const InputDecoration(
                                        labelText: 'E-mail do usuário',
                                        hintText: 'nome@exemplo.com',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    onPressed:
                                        _lookingUpPromoUser ? null : _addRecipientByEmail,
                                    child: _lookingUpPromoUser
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text('Add'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: FastTextField(
                                      controller: _addUidCtrl,
                                      autocorrect: false,
                                      textInputAction: TextInputAction.done,
                                      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                                      decoration: const InputDecoration(
                                        labelText: 'UID (opcional)',
                                        hintText: 'Documento em users/',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton(
                                    onPressed: _lookingUpPromoUser ? null : _addRecipientByUid,
                                    child: const Text('Add UID'),
                                  ),
                                ],
                              ),
                              if (_promoEmailRecipients.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Selecionados (${_promoEmailRecipients.length}):',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _promoEmailRecipients
                                      .map(
                                        (r) => InputChip(
                                          label: Text(
                                            r.label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          onDeleted: () => _removeRecipient(r.uid),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ] else
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    'Nenhum na lista — use a lista (marcar vários), e-mail ou UID.',
                                    style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                                  ),
                                ),
                            ],
                          ],
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(_error!,
                                  style: const TextStyle(color: Colors.red, fontSize: 13)),
                            ),
                        ],
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: (_saving || _sendingBroadcast || _loading)
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  if (_isEdit && _active && _showOnDivulgacaoWeb)
                    FilledButton.tonalIcon(
                      onPressed: (_saving || _sendingBroadcast || _loading)
                          ? null
                          : _sendPromoBroadcastNow,
                      icon: _sendingBroadcast
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.mark_email_unread_outlined, size: 20),
                      label: Text(_sendingBroadcast ? 'Enviando…' : 'Enviar e-mails'),
                    ),
                  FilledButton(
                    onPressed: (_saving || _sendingBroadcast || _loading) ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Salvar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Envio rápido «toda a base» a partir do ícone na lista de promoções.
class _PromoListBroadcastDialog extends StatefulWidget {
  final String promoId;

  const _PromoListBroadcastDialog({required this.promoId});

  @override
  State<_PromoListBroadcastDialog> createState() => _PromoListBroadcastDialogState();
}

class _PromoListBroadcastDialogState extends State<_PromoListBroadcastDialog> {
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _loading = true;
  bool _sending = false;
  String? _error;
  String _titleLine = '';

  static String _defaultSubject() => 'WISDOMAPP — nova promoção disponível';

  static String _defaultBody(String titleLine) =>
      'Nova promoção: $titleLine. Abra o site oficial no link abaixo para ver o valor e concluir com PIX ou cartão.';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('promotions')
          .doc(widget.promoId)
          .get();
      final m = snap.data();
      _titleLine = (m?['title'] ?? widget.promoId).toString();
      _subjectCtrl.text = _defaultSubject();
      _bodyCtrl.text = _defaultBody(_titleLine);
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    final linkUrl = buildMaintenancePromoSiteUrl(
      promoFirestoreId: widget.promoId,
      source: 'email_promocao_admin_promo',
    );
    final subj = _subjectCtrl.text.trim().isNotEmpty
        ? _subjectCtrl.text.trim()
        : _defaultSubject();
    final body = _bodyCtrl.text.trim().isNotEmpty
        ? _bodyCtrl.text.trim()
        : _defaultBody(_titleLine);
    try {
      final er = await FunctionsService().sendMaintenancePromoEmails(
        linkUrl: linkUrl,
        messageText: body,
        subject: subj,
        targetUids: null,
      );
      if (!mounted) return;
      final sent = er['sent'] ?? 0;
      final failed = er['failed'] ?? 0;
      final totalRecipients = er['total'] ?? sent + failed;
      await FirebaseFirestore.instance.collection('promotions').doc(widget.promoId).set({
        'lastEmailBroadcast': {
          'at': FieldValue.serverTimestamp(),
          'sent': sent,
          'failed': failed,
          'total': totalRecipients,
          'recipientMode': 'all',
        },
      }, SetOptions(merge: true));
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            'E-mail: $sent ok, $totalRecipients destinatários (toda a base)${failed > 0 ? ' · $failed falhas' : ''}.',
          ),
          duration: const Duration(seconds: 9),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().split('\n').first;
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.mark_email_unread_outlined, color: AppColors.deepBlue),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Enviar e-mail promocional',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _titleLine,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Envio para toda a base (exceto admin/master). Para lista restrita, abra Editar na promoção.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.35),
                    ),
                    const SizedBox(height: 14),
                    FastTextField(
                      controller: _subjectCtrl,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      decoration: const InputDecoration(
                        labelText: 'Assunto',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    FastTextField(
                      controller: _bodyCtrl,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      decoration: const InputDecoration(
                        labelText: 'Mensagem',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: (_loading || _sending) ? null : _send,
          child: _sending
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Enviar'),
        ),
      ],
    );
  }
}
