import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/notification_center_entry.dart';
import '../services/agenda_alerts_queue_service.dart';
import '../services/notification_center_service.dart';
import '../services/notification_center_store.dart';
import '../theme/app_colors.dart';
import '../theme/theme_context.dart';
import '../utils/agenda_alerts_archive_policy.dart';
import '../utils/firestore_user_doc_id.dart';
import '../widgets/compromisso_contact_chips.dart';

enum NotificationCenterTab {
  escalas,
  compromissos,
  audiencias, // legado — redirecionado para compromissos na UI
  contas,
}

/// Abas visíveis na central (sem audiências — o app só tem compromissos).
const List<NotificationCenterTab> kNotificationCenterVisibleTabs = [
  NotificationCenterTab.escalas,
  NotificationCenterTab.compromissos,
  NotificationCenterTab.contas,
];

/// Paleta WISDOMAPP por aba da central.
class _NotificationCenterTabPalette {
  const _NotificationCenterTabPalette({
    required this.shortLabel,
    required this.icon,
    required this.gradient,
    required this.accent,
  });

  final String shortLabel;
  final IconData icon;
  final List<Color> gradient;
  final Color accent;

  static _NotificationCenterTabPalette of(NotificationCenterTab tab) {
    return switch (tab) {
      NotificationCenterTab.escalas => const _NotificationCenterTabPalette(
          shortLabel: 'Agenda',
          icon: Icons.calendar_month_rounded,
          gradient: [Color(0xFF059669), Color(0xFF10B981)],
          accent: Color(0xFF059669),
        ),
      NotificationCenterTab.compromissos => const _NotificationCenterTabPalette(
          shortLabel: 'Compromissos',
          icon: Icons.event_rounded,
          gradient: [Color(0xFF2563EB), Color(0xFF6366F1)],
          accent: Color(0xFF2563EB),
        ),
      NotificationCenterTab.audiencias => const _NotificationCenterTabPalette(
          shortLabel: 'Compromissos',
          icon: Icons.event_rounded,
          gradient: [Color(0xFF2563EB), Color(0xFF6366F1)],
          accent: Color(0xFF2563EB),
        ),
      NotificationCenterTab.contas => const _NotificationCenterTabPalette(
          shortLabel: 'Contas',
          icon: Icons.payments_outlined,
          gradient: [Color(0xFFDC2626), Color(0xFFF97316)],
          accent: Color(0xFFDC2626),
        ),
    };
  }
}

enum NotificationCenterStatusFilter {
  todos,
  pendentes,
  notificados,
}

/// Central de notificações — abas por tipo, ordem cronológica, visual WISDOMAPP.
/// Swipe-to-dismiss, pull-to-refresh, animações de entrada e navegação
/// direta para abas específicas via deep link de push/local.
class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({
    super.key,
    this.initialTab,
  });

  /// Aba inicial (deep link a partir de push/local notification tap).
  final NotificationCenterTab? initialTab;

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen>
    with SingleTickerProviderStateMixin {
  bool _selectionMode = false;
  final Set<String> _selected = {};
  late TabController _tabController;
  NotificationCenterStatusFilter _statusFilter =
      NotificationCenterStatusFilter.todos;

  String get _uid => firestoreUserDocIdForAppShell(
        FirebaseAuth.instance.currentUser?.uid ?? '',
      );

  @override
  void initState() {
    super.initState();
    var initialTab = widget.initialTab;
    if (initialTab == NotificationCenterTab.audiencias) {
      initialTab = NotificationCenterTab.compromissos;
    }
    final initialIndex = initialTab != null
        ? kNotificationCenterVisibleTabs.indexOf(initialTab)
        : 0;
    _tabController = TabController(
      length: kNotificationCenterVisibleTabs.length,
      vsync: this,
      initialIndex: initialIndex.clamp(
        0,
        kNotificationCenterVisibleTabs.length - 1,
      ),
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
        if (_selected.isEmpty) _selectionMode = false;
      } else {
        _selected.add(id);
      }
    });
  }

  void _enterSelection(String id) {
    setState(() {
      _selectionMode = true;
      _selected.add(id);
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  Future<void> _dismissSelected() async {
    if (_selected.isEmpty) return;
    await NotificationCenterStore.instance.dismissAll(_selected);
    if (mounted) _exitSelection();
  }

  Future<void> _dismissOne(String id) async {
    await NotificationCenterStore.instance.dismiss([id]);
    if (mounted && _selected.contains(id)) {
      setState(() => _selected.remove(id));
    }
  }

  static NotificationCenterKind _kindForTab(NotificationCenterTab tab) {
    return switch (tab) {
      NotificationCenterTab.escalas => NotificationCenterKind.escala,
      NotificationCenterTab.compromissos => NotificationCenterKind.compromisso,
      NotificationCenterTab.audiencias => NotificationCenterKind.audiencia,
      NotificationCenterTab.contas => NotificationCenterKind.financeiro,
    };
  }

  static List<NotificationCenterEntry> _filterEntries(
    List<NotificationCenterEntry> all, {
    required NotificationCenterTab tab,
    required NotificationCenterStatusFilter status,
  }) {
    return all.where((e) {
      final matchKind = tab == NotificationCenterTab.compromissos
          ? (e.kind == NotificationCenterKind.compromisso ||
              e.kind == NotificationCenterKind.audiencia)
          : e.kind == _kindForTab(tab);
      if (!matchKind) return false;
      return switch (status) {
        NotificationCenterStatusFilter.pendentes => e.isPending,
        NotificationCenterStatusFilter.notificados => !e.isPending,
        NotificationCenterStatusFilter.todos => true,
      };
    }).toList();
  }

  static int _countForTab(
    List<NotificationCenterEntry> all,
    NotificationCenterTab tab,
  ) {
    if (tab == NotificationCenterTab.compromissos) {
      return all
          .where((e) =>
              e.kind == NotificationCenterKind.compromisso ||
              e.kind == NotificationCenterKind.audiencia)
          .length;
    }
    return all.where((e) => e.kind == _kindForTab(tab)).length;
  }

  static List<({DateTime day, List<NotificationCenterEntry> items})>
      _groupByDay(List<NotificationCenterEntry> entries) {
    final sorted = List<NotificationCenterEntry>.from(entries)
      ..sort((a, b) {
        final cmp = _sortKey(a).compareTo(_sortKey(b));
        if (cmp != 0) return cmp;
        return a.title.compareTo(b.title);
      });

    final groups = <({DateTime day, List<NotificationCenterEntry> items})>[];
    DateTime? currentDay;
    List<NotificationCenterEntry>? bucket;

    for (final entry in sorted) {
      final key = _sortKey(entry);
      final day = DateTime(key.year, key.month, key.day);
      if (currentDay == null ||
          day.year != currentDay.year ||
          day.month != currentDay.month ||
          day.day != currentDay.day) {
        if (bucket != null && currentDay != null) {
          groups.add((day: currentDay, items: bucket));
        }
        currentDay = day;
        bucket = [entry];
      } else {
        bucket!.add(entry);
      }
    }
    if (bucket != null && currentDay != null) {
      groups.add((day: currentDay, items: bucket));
    }
    return groups;
  }

  static DateTime _sortKey(NotificationCenterEntry e) =>
      e.eventAt ?? e.notifiedAt ?? DateTime(2100);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = _selectionMode
        ? '${_selected.length} selecionada${_selected.length == 1 ? '' : 's'}'
        : 'Central de notificações';

    return Scaffold(
      backgroundColor:
          isDark ? context.appScaffold : const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: AppColors.logoGradient,
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        title: Text(
          title,
          style:
              const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2),
        ),
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
          style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
        actions: [
          if (_selectionMode)
            IconButton(
              tooltip: 'Limpar selecionadas',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _selected.isEmpty ? null : _dismissSelected,
            )
          else
            IconButton(
              tooltip: 'Selecionar',
              icon: const Icon(Icons.checklist_rounded),
              onPressed: () => setState(() => _selectionMode = true),
            ),
          if (_selectionMode)
            TextButton(
              onPressed: _exitSelection,
              child: const Text('Cancelar',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: StreamBuilder<NotificationCenterSnapshot>(
        stream: NotificationCenterService.watch(_uid),
        initialData: NotificationCenterService.peek(_uid) ??
            NotificationCenterSnapshot.empty,
        builder: (context, snap) {
          final hasCached = (snap.data?.entries.isNotEmpty ?? false);
          // A escuta é compartilhada (broadcast): se já estava ativa e a
          // central está vazia, não chega evento novo — o peek já vale como
          // «carregado» (antes girava para sempre para quem não tinha avisos).
          if (snap.connectionState == ConnectionState.waiting &&
              !hasCached &&
              NotificationCenterService.peek(_uid) == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final allEntries = snap.data?.entries ?? const [];
          final tabCounts = kNotificationCenterVisibleTabs
              .map((t) => _countForTab(allEntries, t))
              .toList();
          final activeTab =
              kNotificationCenterVisibleTabs[_tabController.index];
          final activePalette = _NotificationCenterTabPalette.of(activeTab);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Info strip
              Material(
                color: isDark
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : const Color(0xFFE8F4FD),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 20,
                        color: AppColors.primary.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Ordem: data menor → maior. Compromissos somem no dia seguinte '
                          '(banco e central). Notificados: ${AgendaAlertsArchivePolicy.daysUntilArchiveTab} dias após o envio.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.7)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Tab pills
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: _buildTabPills(tabCounts),
              ),
              // Status filter
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: _buildStatusFilter(activePalette),
              ),
              // Selection mode bar
              if (_selectionMode)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          final tab = kNotificationCenterVisibleTabs[
                              _tabController.index];
                          final filtered = _filterEntries(
                            allEntries,
                            tab: tab,
                            status: _statusFilter,
                          );
                          setState(() {
                            _selected
                              ..clear()
                              ..addAll(filtered.map((e) => e.id));
                          });
                        },
                        child: const Text('Marcar aba'),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _selected.isEmpty ? null : _dismissSelected,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.error,
                        ),
                        icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                        label: const Text('Limpar'),
                      ),
                    ],
                  ),
                ),
              // Tab content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: kNotificationCenterVisibleTabs.map((tab) {
                    final filtered = _filterEntries(
                      allEntries,
                      tab: tab,
                      status: _statusFilter,
                    );
                    if (filtered.isEmpty) {
                      return _buildEmptyTab(tab);
                    }
                    final groups = _groupByDay(filtered);
                    return RefreshIndicator(
                      color: _NotificationCenterTabPalette.of(tab).accent,
                      onRefresh: () async {
                        NotificationCenterService.silentResyncAfterReconnect(
                            _uid);
                        await Future<void>.delayed(
                            const Duration(milliseconds: 400));
                      },
                      child: ListView.builder(
                        key: PageStorageKey<String>('nc_${tab.name}'),
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        itemCount: groups.length,
                        itemBuilder: (context, gi) {
                          final group = groups[gi];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                                child: Text(
                                  AgendaAlertsQueueService.formatDayHeader(
                                      group.day),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.9)
                                        : const Color(0xFF334155),
                                  ),
                                ),
                              ),
                              ...group.items.asMap().entries.map(
                                (mapEntry) {
                                  final idx = mapEntry.key;
                                  final entry = mapEntry.value;
                                  return _AnimatedNotificationCard(
                                    delay: Duration(
                                        milliseconds: (idx * 40).clamp(0, 300)),
                                    child: Dismissible(
                                      key: ValueKey('nc_dismiss_${entry.id}'),
                                      direction: DismissDirection.endToStart,
                                      background: Container(
                                        alignment: Alignment.centerRight,
                                        padding:
                                            const EdgeInsets.only(right: 20),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFDC2626)
                                              .withValues(alpha: 0.9),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        child: const Icon(
                                            Icons.delete_outline_rounded,
                                            color: Colors.white,
                                            size: 22),
                                      ),
                                      onDismissed: (_) => _dismissOne(entry.id),
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 10),
                                        child: _NotificationCard(
                                          entry: entry,
                                          selected:
                                              _selected.contains(entry.id),
                                          selectionMode: _selectionMode,
                                          onTap: () {
                                            if (_selectionMode) {
                                              _toggleSelection(entry.id);
                                            }
                                          },
                                          onLongPress: () =>
                                              _enterSelection(entry.id),
                                          onDismiss: () =>
                                              _dismissOne(entry.id),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTabPills(List<int> tabCounts) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.isDarkMode ? context.appSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appChipIdleBorder),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(kNotificationCenterVisibleTabs.length, (i) {
            final tab = kNotificationCenterVisibleTabs[i];
            final palette = _NotificationCenterTabPalette.of(tab);
            final selected = _tabController.index == i;
            return Padding(
              padding: EdgeInsets.only(
                right: i == kNotificationCenterVisibleTabs.length - 1 ? 0 : 6,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    _tabController.animateTo(i);
                    setState(() {});
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: selected
                          ? LinearGradient(colors: palette.gradient)
                          : null,
                      color: selected ? null : context.appInputFill,
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: palette.accent.withValues(alpha: 0.25),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          palette.icon,
                          size: 16,
                          color: selected ? Colors.white : palette.accent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${palette.shortLabel} (${tabCounts[i]})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: selected
                                ? Colors.white
                                : (context.isDarkMode
                                    ? context.appChipIdleLabel
                                    : const Color(0xFF334155)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildStatusFilter(_NotificationCenterTabPalette activePalette) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: NotificationCenterStatusFilter.values.map((f) {
        final selected = _statusFilter == f;
        final label = switch (f) {
          NotificationCenterStatusFilter.todos => 'Todos',
          NotificationCenterStatusFilter.pendentes => 'Pendentes',
          NotificationCenterStatusFilter.notificados => 'Notificados',
        };
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _statusFilter = f),
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: selected
                    ? LinearGradient(colors: activePalette.gradient)
                    : null,
                color: selected
                    ? null
                    : (context.isDarkMode ? context.appSurface : Colors.white),
                border: Border.all(
                  color: selected
                      ? Colors.transparent
                      : activePalette.accent.withValues(alpha: 0.22),
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: activePalette.accent.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : context.appTextMuted,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEmptyTab(NotificationCenterTab tab) {
    final palette = _NotificationCenterTabPalette.of(tab);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              palette.icon,
              size: 52,
              color: palette.accent.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 14),
            Text(
              'Nenhum aviso de ${palette.shortLabel.toLowerCase()}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: context.appTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Itens futuros aparecem aqui por ordem de data.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: context.appTextMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.entry,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    required this.onDismiss,
  });

  final NotificationCenterEntry entry;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = _themeFor(entry.kind);
    final timeLabel = _timeLabel(entry);
    final statusLabel = entry.isPending ? 'Pendente' : 'Notificado';
    final statusColor =
        entry.isPending ? const Color(0xFFF59E0B) : const Color(0xFF16A34A);

    return Material(
      color: selected
          ? theme.color.withValues(alpha: 0.08)
          : (context.isDarkMode ? context.appSurface : Colors.white),
      elevation: 0,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  selected ? theme.color : theme.color.withValues(alpha: 0.28),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 2),
                  child: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected ? theme.color : const Color(0xFF94A3B8),
                    size: 22,
                  ),
                ),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(theme.icon, color: theme.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            entry.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: context.appTextPrimary,
                            ),
                          ),
                        ),
                        if (!selectionMode)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 44,
                              minHeight: 44,
                            ),
                            tooltip: 'Remover da central',
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: const Color(0xFF94A3B8),
                            ),
                            onPressed: onDismiss,
                          ),
                      ],
                    ),
                    if (entry.body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        entry.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: context.appTextMuted,
                        ),
                      ),
                    ],
                    if (entry.kind == NotificationCenterKind.compromisso &&
                        (entry.linkLocalizacao.isNotEmpty ||
                            entry.contatoWhatsApp.isNotEmpty))
                      CompromissoContactChips(
                        linkLocalizacao: entry.linkLocalizacao,
                        contatoWhatsApp: entry.contatoWhatsApp,
                        compact: true,
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Chip(label: theme.label, color: theme.color),
                        _Chip(label: statusLabel, color: statusColor),
                        if (timeLabel.isNotEmpty)
                          Text(
                            timeLabel,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static _CardTheme _themeFor(NotificationCenterKind kind) {
    return switch (kind) {
      NotificationCenterKind.audiencia => _CardTheme(
          label: 'Compromisso',
          icon: Icons.event_rounded,
          color: const Color(0xFF2563EB),
        ),
      NotificationCenterKind.compromisso => _CardTheme(
          label: 'Compromisso',
          icon: Icons.event_rounded,
          color: const Color(0xFF2563EB),
        ),
      NotificationCenterKind.escala => _CardTheme(
          label: 'Escala',
          icon: Icons.calendar_month_rounded,
          color: const Color(0xFF059669),
        ),
      NotificationCenterKind.financeiro => _CardTheme(
          label: 'Conta a pagar',
          icon: Icons.payments_outlined,
          color: const Color(0xFFDC2626),
        ),
      NotificationCenterKind.outros => _CardTheme(
          label: 'Aviso',
          icon: Icons.notifications_rounded,
          color: AppColors.primary,
        ),
    };
  }

  static String _timeLabel(NotificationCenterEntry entry) {
    final fmt = DateFormat('dd/MM · HH:mm', 'pt_BR');
    if (entry.eventAt != null) {
      return fmt.format(entry.eventAt!);
    }
    if (entry.notifiedAt != null) {
      return 'Enviado ${fmt.format(entry.notifiedAt!)}';
    }
    return '';
  }
}

class _CardTheme {
  const _CardTheme({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Animação de entrada slide+fade para os cartões da central.
class _AnimatedNotificationCard extends StatefulWidget {
  const _AnimatedNotificationCard({
    required this.child,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration delay;

  @override
  State<_AnimatedNotificationCard> createState() =>
      _AnimatedNotificationCardState();
}

class _AnimatedNotificationCardState extends State<_AnimatedNotificationCard> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      offset: _visible ? Offset.zero : const Offset(0, 0.08),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        opacity: _visible ? 1.0 : 0.0,
        child: widget.child,
      ),
    );
  }
}
