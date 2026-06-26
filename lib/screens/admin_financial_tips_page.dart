import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/biblical_finance_tips.dart';
import '../data/financial_tips_firestore_seed_bank.dart';
import '../models/finance_tip_bank_entry.dart';
import '../services/financial_tips_home_sync_service.dart';
import '../services/financial_tips_seed_service.dart';
import '../theme/app_colors.dart';
import '../utils/admin_financial_tip_utils.dart';
import '../utils/insights_engine.dart';
import '../widgets/admin/admin_financial_tip_editor_sheet.dart';
import '../widgets/admin/admin_page_shell.dart';
import '../widgets/admin/admin_tip_grid_card.dart';
import '../widgets/fast_text_field.dart';

/// Painel admin — dicas financeiras (bíblicas + gerais), tempo real, web/mobile.
class AdminFinancialTipsPage extends StatefulWidget {
  const AdminFinancialTipsPage({super.key});

  @override
  State<AdminFinancialTipsPage> createState() => _AdminFinancialTipsPageState();
}

class _AdminFinancialTipsPageState extends State<AdminFinancialTipsPage>
    with SingleTickerProviderStateMixin {
  bool _importing = false;
  bool _syncing = false;
  bool _autoSync = true;
  bool _selectionMode = false;
  bool _offeredBootstrap = false;
  FinancialTipsHomeConfig? _homeConfig;
  final _searchCtrl = TextEditingController();
  String? _bookFilter;
  final Set<String> _selectedIds = {};
  late TabController _tabs;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _tipsStream;

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection(InsightsEngine.kFinancialTipsCollection);

  bool get _isBiblicalTab => _tabs.index == 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(_onTabChanged);
    _searchCtrl.addListener(() => setState(() {}));
    _tipsStream = _col.snapshots();
    _loadHomeConfig();
  }

  void _onTabChanged() {
    if (!_tabs.indexIsChanging) {
      setState(() {
        _bookFilter = null;
        _selectedIds.clear();
        _selectionMode = false;
      });
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHomeConfig() async {
    try {
      final home = await FinancialTipsHomeSyncService().loadOnce();
      if (mounted) setState(() => _homeConfig = home);
    } catch (_) {}
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final list = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    list.sort((a, b) {
      final oa = (a.data()['ordem'] as num?)?.toInt() ?? 999;
      final ob = (b.data()['ordem'] as num?)?.toInt() ?? 999;
      return oa.compareTo(ob);
    });
    return list;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var list = docs.where((d) {
      final data = d.data();
      return _isBiblicalTab
          ? AdminFinancialTipUtils.isBiblical(data)
          : !AdminFinancialTipUtils.isBiblical(data);
    }).toList();
    if (_isBiblicalTab && _bookFilter != null && _bookFilter!.isNotEmpty) {
      list = list
          .where((d) => AdminFinancialTipUtils.biblicalBook(d.data()) == _bookFilter)
          .toList();
    }
    final q = _searchCtrl.text;
    if (q.trim().isNotEmpty) {
      list = list.where((d) => AdminFinancialTipUtils.matchesSearch(d.data(), q)).toList();
    }
    return list;
  }

  List<String> _bookOptions(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final fromDocs = AdminFinancialTipUtils.booksFromDocs(docs.map((d) => d.data()));
    return fromDocs.isNotEmpty ? fromDocs : AdminFinancialTipUtils.biblicalBooksCatalog();
  }

  int _biblicalCount(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) =>
      docs.where((d) => AdminFinancialTipUtils.isBiblical(d.data())).length;

  int _generalCount(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) =>
      docs.length - _biblicalCount(docs);

  Future<void> _maybeAutoSync(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    bool silent = true,
  }) async {
    if (!_autoSync) return;
    final selected =
        docs.where((d) => d.data()['exibirNoInicio'] == true).map((d) => d.id).toList();
    if (selected.isEmpty) return;
    final favorites =
        docs.where((d) => d.data()['favorita'] == true).map((d) => d.id).toList();
    try {
      final email = FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
      await FinancialTipsHomeSyncService().publish(
        homeTipIds: selected,
        favoriteTipIds: favorites,
        syncedByEmail: email,
      );
      InsightsEngine.clearTipsCache();
      await _loadHomeConfig();
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync automático: ${selected.length} dica(s).'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _syncToUsers(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final selected =
        docs.where((d) => d.data()['exibirNoInicio'] == true).map((d) => d.id).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marque «Início» em pelo menos uma dica.')),
      );
      return;
    }
    setState(() => _syncing = true);
    try {
      final favorites =
          docs.where((d) => d.data()['favorita'] == true).map((d) => d.id).toList();
      final email = FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
      await FinancialTipsHomeSyncService().publish(
        homeTipIds: selected,
        favoriteTipIds: favorites,
        syncedByEmail: email,
      );
      InsightsEngine.clearTipsCache();
      await _loadHomeConfig();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sincronizado! ${selected.length} dica(s) no Início.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _toggleField(String docId, String field, bool value) async {
    try {
      await _col.doc(docId).set(
        {field: value, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      InsightsEngine.clearTipsCache();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _openEditor(QueryDocumentSnapshot<Map<String, dynamic>>? existing) async {
    final saved = await AdminFinancialTipEditorSheet.show(
      context,
      col: _col,
      existing: existing,
      biblicalMode: _isBiblicalTab ||
          (existing != null && AdminFinancialTipUtils.isBiblical(existing.data())),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dica salva.'), backgroundColor: AppColors.success),
      );
    }
  }

  Future<void> _openDetail(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final d = doc.data();
    final titulo = (d['titulo'] ?? doc.id).toString();
    final ref = (d['referenciaBiblica'] ?? d['versiculo'] ?? '').toString().trim();
    final verse = (d['textoVersiculo'] ?? d['versiculoTexto'] ?? '').toString().trim();
    final desc = (d['descricao'] ?? '').toString().trim();
    final colorKey = (d['cor'] ?? d['colorKey'] ?? 'primary').toString();
    final iconKey = (d['icone'] ?? d['iconKey'] ?? 'lightbulb').toString();
    final accent = kFinanceTipColorByKey[colorKey] ?? AppColors.primary;
    final icon = kFinanceTipIconByKey[iconKey] ?? Icons.lightbulb_outline_rounded;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (_, scroll) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    colors: [accent, Color.lerp(accent, Colors.black, 0.12)!],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, color: Colors.white, size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            titulo,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (ref.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        ref,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (verse.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        '"$verse"',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.95),
                          fontStyle: FontStyle.italic,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  desc,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade800, height: 1.5),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _openEditor(doc);
                      },
                      icon: const Icon(Icons.edit_rounded),
                      label: const Text('Editar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _confirmDelete(doc.id);
                      },
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Excluir'),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir dica?'),
        content: Text('«$id» será removida permanentemente.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _col.doc(id).delete();
    InsightsEngine.clearTipsCache();
    _selectedIds.remove(id);
    setState(() {});
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final n = _selectedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover em lote?'),
        content: Text('Excluir $n dica(s)?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: Text('Excluir $n'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final id in _selectedIds) {
      batch.delete(_col.doc(id));
    }
    await batch.commit();
    InsightsEngine.clearTipsCache();
    setState(() {
      _selectedIds.clear();
      _selectionMode = false;
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  Future<void> _importFullCatalog({bool silent = false}) async {
    setState(() => _importing = true);
    try {
      final res = await FinancialTipsSeedService().seedFullCatalog(
        skipExisting: true,
        markHomeDefaults: true,
      );
      InsightsEngine.clearTipsCache();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Catálogo importado: ${res.totalCreated} nova(s) · '
              '${res.homeTipsMarked} no Início.',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
      if (!silent) {
        final snap = await _col.get();
        await _maybeAutoSync(snap.docs, silent: false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _maybeOfferBootstrap(int total) {
    if (_offeredBootstrap || total > 0 || _importing) return;
    _offeredBootstrap = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ativar dicas financeiras'),
          content: Text(
            'Nenhuma dica no banco ainda. Importar ${kBiblicalFinanceTips.length} bíblicas + '
            '${kFinancialTipsFirestoreSeedBank.length} gerais e marcar 3 para o Início?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Depois')),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _importFullCatalog();
              },
              child: const Text('Importar agora'),
            ),
          ],
        ),
      );
    });
  }

  String? _lastSyncLabel() {
    final at = _homeConfig?.syncedAt;
    if (at == null) return null;
    return DateFormat('dd/MM/yyyy HH:mm').format(at);
  }

  int _gridCrossAxisCount(double w) {
    if (w >= 1200) return 3;
    if (w >= 720) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _tipsStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return _ErrorState(message: snap.error.toString(), onRetry: () => setState(() {}));
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allDocs = _sortDocs(snap.data?.docs ?? []);
        _maybeOfferBootstrap(allDocs.length);

        final filtered = _filterDocs(allDocs);
        final pad = AdminPageShell.listPadding(context, top: 4);
        final biblical = _biblicalCount(allDocs);
        final general = _generalCount(allDocs);
        final homeCount = allDocs.where((d) => d.data()['exibirNoInicio'] == true).length;
        final favCount = allDocs.where((d) => d.data()['favorita'] == true).length;

        return Stack(
          children: [
            RefreshIndicator(
              onRefresh: () async {
                await _loadHomeConfig();
                await Future<void>.delayed(const Duration(milliseconds: 400));
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverPadding(
                    padding: pad.copyWith(bottom: 0),
                    sliver: SliverToBoxAdapter(child: _HeroHeader(lastSync: _lastSyncLabel())),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(pad.left, 10, pad.right, 8),
                    sliver: SliverToBoxAdapter(
                      child: _StatsRow(
                        total: allDocs.length,
                        biblical: biblical,
                        general: general,
                        homeCount: homeCount,
                        favCount: favCount,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: pad.left),
                    sliver: SliverToBoxAdapter(
                      child: _ModernTabBar(
                        tabs: _tabs,
                        biblicalCount: biblical,
                        generalCount: general,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(pad.left, 10, pad.right, 8),
                    sliver: SliverToBoxAdapter(
                      child: FastTextField(
                        controller: _searchCtrl,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: _isBiblicalTab
                              ? 'Pesquisar título, versículo…'
                              : 'Pesquisar dicas gerais…',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _searchCtrl.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 20),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    HapticFeedback.selectionClick();
                                  },
                                ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_isBiblicalTab)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, 8),
                      sliver: SliverToBoxAdapter(
                        child: DropdownButtonFormField<String?>(
                          value: _bookFilter,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Filtrar por livro bíblico',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Todos os livros')),
                            ..._bookOptions(allDocs)
                                .map((b) => DropdownMenuItem(value: b, child: Text(b))),
                          ],
                          onChanged: (v) => setState(() => _bookFilter = v),
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, 10),
                    sliver: SliverToBoxAdapter(
                      child: _ActionBar(
                        autoSync: _autoSync,
                        syncing: _syncing,
                        importing: _importing,
                        isBiblical: _isBiblicalTab,
                        onAutoSyncChanged: (v) => setState(() => _autoSync = v),
                        onSync: () => _syncToUsers(allDocs),
                        onImportFull: _importFullCatalog,
                        onNew: () => _openEditor(null),
                        onSelectMode: () => setState(() => _selectionMode = true),
                      ),
                    ),
                  ),
                  if (allDocs.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyBootstrap(
                        importing: _importing,
                        onImport: _importFullCatalog,
                        onCreate: () => _openEditor(null),
                      ),
                    )
                  else if (filtered.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          'Nenhum resultado para o filtro.',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ),
                    )
                  else
                    SliverLayoutBuilder(
                      builder: (context, constraints) {
                        final cross = _gridCrossAxisCount(constraints.crossAxisExtent);
                        return SliverPadding(
                          padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, 100),
                          sliver: SliverGrid(
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: cross,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                              childAspectRatio: cross >= 2 ? 0.82 : 0.88,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, i) {
                                final doc = filtered[i];
                                return AdminTipGridCard(
                                  doc: doc,
                                  index: i,
                                  selectionMode: _selectionMode,
                                  selected: _selectedIds.contains(doc.id),
                                  onTap: () {
                                    if (_selectionMode) {
                                      _toggleSelection(doc.id);
                                    } else {
                                      _openDetail(doc);
                                    }
                                  },
                                  onLongPress: () => setState(() {
                                    _selectionMode = true;
                                    _selectedIds.add(doc.id);
                                  }),
                                  onEdit: () => _openEditor(doc),
                                  onDelete: () => _confirmDelete(doc.id),
                                  onToggleFavorite: (v) {
                                    _toggleField(doc.id, 'favorita', v);
                                    _maybeAutoSync(allDocs);
                                  },
                                  onToggleHome: (v) {
                                    _toggleField(doc.id, 'exibirNoInicio', v);
                                    _maybeAutoSync(allDocs);
                                  },
                                );
                              },
                              childCount: filtered.length,
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            if (_selectionMode && _selectedIds.isNotEmpty)
              Positioned(
                left: pad.left,
                right: pad.right,
                bottom: 12 + MediaQuery.paddingOf(context).bottom,
                child: _SelectionBar(
                  count: _selectedIds.length,
                  onSelectVisible: () => setState(() {
                    _selectedIds
                      ..clear()
                      ..addAll(filtered.map((d) => d.id));
                  }),
                  onDelete: _deleteSelected,
                  onCancel: () => setState(() {
                    _selectedIds.clear();
                    _selectionMode = false;
                  }),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({this.lastSync});

  final String? lastSync;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF0B1B4B), Color(0xFF0F766E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B1B4B).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFFE8C547), size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dicas financeiras',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tempo real · bíblicas e gerais · sync automático para o Início',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
                if (lastSync != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Último sync: $lastSync',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.total,
    required this.biblical,
    required this.general,
    required this.homeCount,
    required this.favCount,
  });

  final int total;
  final int biblical;
  final int general;
  final int homeCount;
  final int favCount;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _StatPill(Icons.library_books_rounded, '$total', 'total', const Color(0xFF2563EB)),
          const SizedBox(width: 8),
          _StatPill(Icons.menu_book_rounded, '$biblical', 'bíblicas', const Color(0xFF4F46E5)),
          const SizedBox(width: 8),
          _StatPill(Icons.tips_and_updates_rounded, '$general', 'gerais', const Color(0xFF0EA5E9)),
          const SizedBox(width: 8),
          _StatPill(Icons.home_rounded, '$homeCount', 'Início', const Color(0xFF0F766E)),
          const SizedBox(width: 8),
          _StatPill(Icons.star_rounded, '$favCount', 'favoritas', const Color(0xFFD97706)),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill(this.icon, this.value, this.label, this.color);

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: color),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}

class _ModernTabBar extends StatelessWidget {
  const _ModernTabBar({
    required this.tabs,
    required this.biblicalCount,
    required this.generalCount,
  });

  final TabController tabs;
  final int biblicalCount;
  final int generalCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
      ),
      child: TabBar(
        controller: tabs,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            colors: [Color(0xFF0B1B4B), Color(0xFF0F766E)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0B1B4B).withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey.shade700,
        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        tabs: [
          Tab(text: 'Bíblicas ($biblicalCount)'),
          Tab(text: 'Gerais ($generalCount)'),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.autoSync,
    required this.syncing,
    required this.importing,
    required this.isBiblical,
    required this.onAutoSyncChanged,
    required this.onSync,
    required this.onImportFull,
    required this.onNew,
    required this.onSelectMode,
  });

  final bool autoSync;
  final bool syncing;
  final bool importing;
  final bool isBiblical;
  final ValueChanged<bool> onAutoSyncChanged;
  final VoidCallback onSync;
  final VoidCallback onImportFull;
  final VoidCallback onNew;
  final VoidCallback onSelectMode;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilterChip(
          label: Text(autoSync ? 'Auto-sync ON' : 'Auto-sync OFF'),
          selected: autoSync,
          onSelected: onAutoSyncChanged,
          avatar: Icon(
            autoSync ? Icons.bolt_rounded : Icons.bolt_outlined,
            size: 18,
            color: autoSync ? const Color(0xFF7C3AED) : null,
          ),
          selectedColor: const Color(0xFF7C3AED).withValues(alpha: 0.15),
        ),
        FilledButton.icon(
          onPressed: syncing ? null : onSync,
          icon: syncing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.cloud_upload_rounded, size: 18),
          label: Text(syncing ? 'Sync…' : 'Sync agora'),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
        ),
        OutlinedButton.icon(
          onPressed: importing ? null : onImportFull,
          icon: importing
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                )
              : const Icon(Icons.download_rounded, size: 18),
          label: Text(importing ? 'Importando…' : 'Importar catálogo'),
        ),
        FilledButton.icon(
          onPressed: onNew,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(isBiblical ? 'Nova bíblica' : 'Nova geral'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
        ),
        IconButton(
          tooltip: 'Seleção em lote',
          onPressed: onSelectMode,
          icon: const Icon(Icons.checklist_rounded),
        ),
      ],
    );
  }
}

class _EmptyBootstrap extends StatelessWidget {
  const _EmptyBootstrap({
    required this.importing,
    required this.onImport,
    required this.onCreate,
  });

  final bool importing;
  final VoidCallback onImport;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF4F46E5).withValues(alpha: 0.15),
                  const Color(0xFF0EA5E9).withValues(alpha: 0.12),
                ],
              ),
            ),
            child: const Icon(Icons.lightbulb_rounded, size: 56, color: Color(0xFF4F46E5)),
          ),
          const SizedBox(height: 20),
          const Text(
            'Catálogo vazio',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
          ),
          const SizedBox(height: 8),
          Text(
            'Importe ${kBiblicalFinanceTips.length} dicas bíblicas + '
            '${kFinancialTipsFirestoreSeedBank.length} gerais com um toque. '
            '3 bíblicas já ficam marcadas para o Início.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, height: 1.45),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: importing ? null : onImport,
            icon: importing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.rocket_launch_rounded),
            label: Text(importing ? 'Importando…' : 'Importar catálogo completo'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Ou criar dica manualmente'),
          ),
        ],
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onSelectVisible,
    required this.onDelete,
    required this.onCancel,
  });

  final int count;
  final VoidCallback onSelectVisible;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Text('$count selecionada(s)', style: const TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            TextButton(onPressed: onSelectVisible, child: const Text('Visíveis')),
            TextButton(onPressed: onCancel, child: const Text('Cancelar')),
            FilledButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_sweep_rounded, size: 18),
              label: const Text('Excluir'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: Colors.orange.shade700),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
