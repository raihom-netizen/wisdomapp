import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import 'package:intl/intl.dart';

import '../utils/admin_user_search.dart';
import '../services/user_client_telemetry_service.dart';
import '../theme/app_colors.dart';
import '../widgets/shell_keyboard_bottom_pad.dart';
import '../widgets/home_start_module_picker.dart';
import '../widgets/module_header_premium.dart';
import '../widgets/admin/admin_page_shell.dart';
import '../widgets/admin_delegate_email_section.dart';
import '../widgets/admin/admin_user_360_extras.dart';

/// Painel admin: visão 360° por utilizador (uso, versão do cliente, convênio, MP, mensagem push).
class AdminUsuariosInteligenciaTab extends StatefulWidget {
  final bool useUnifiedPanel;
  final String unifiedApp;
  final bool adminCanEdit;

  const AdminUsuariosInteligenciaTab({
    super.key,
    required this.useUnifiedPanel,
    required this.unifiedApp,
    this.adminCanEdit = true,
  });

  @override
  State<AdminUsuariosInteligenciaTab> createState() =>
      _AdminUsuariosInteligenciaTabState();
}

class _AdminUsuariosInteligenciaTabState
    extends State<AdminUsuariosInteligenciaTab> {
  final _searchCtrl = TextEditingController();
  String? _selectedUid;
  String _filter = '';
  Timer? _filterDebounce;
  // Stream cacheado: evita recriar a subscrição (e resetar a lista para o spinner)
  // a cada tecla digitada na busca — era isso que fazia a busca "não funcionar".
  Stream<QuerySnapshot<Map<String, dynamic>>>? _usersStreamCached;
  String? _usersStreamApp;

  void _onSearchChanged(String v) {
    _filterDebounce?.cancel();
    _filterDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      setState(() => _filter = v);
    });
  }

  void _applySearchNow() {
    _filterDebounce?.cancel();
    setState(() => _filter = _searchCtrl.text);
  }

  @override
  void didUpdateWidget(covariant AdminUsuariosInteligenciaTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.useUnifiedPanel &&
        oldWidget.unifiedApp != widget.unifiedApp) {
      setState(() => _selectedUid = null);
    }
  }

  @override
  void dispose() {
    _filterDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _usersStream() {
    final appKey = widget.useUnifiedPanel ? widget.unifiedApp : '';
    // Recria só quando o app selecionado muda; caso contrário reusa o mesmo
    // stream para a busca filtrar localmente sem perder os dados já carregados.
    if (_usersStreamCached == null || _usersStreamApp != appKey) {
      Query<Map<String, dynamic>> q =
          FirebaseFirestore.instance.collection('users');
      if (widget.useUnifiedPanel) {
        q = q.where('app', isEqualTo: widget.unifiedApp);
      }
      _usersStreamCached = q.limit(2000).snapshots();
      _usersStreamApp = appKey;
    }
    return _usersStreamCached!;
  }

  String _userLabel(Map<String, dynamic> d, String id) {
    final name = adminUserDisplayName(d);
    final email = (d['email'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    if (email.isNotEmpty) return email;
    return id;
  }

  String _userSubtitle(Map<String, dynamic> d) {
    final email = (d['email'] ?? '').toString().trim();
    final plan = (d['plan'] ?? d['licensePlan'] ?? '').toString().trim();
    final pid = (d['partnershipId'] ?? '').toString().trim();
    final pname = (d['partnershipName'] ?? '').toString().trim();
    final bits = <String>[];
    if (email.isNotEmpty) bits.add(email);
    final delegate = (d['authorizedDelegateEmail'] ?? '').toString().trim();
    if (delegate.isNotEmpty) bits.add('Autorizado: $delegate');
    if (plan.isNotEmpty) bits.add(plan);
    if (pid.isNotEmpty) {
      bits.add(pname.isNotEmpty ? 'Convênio: $pname' : 'Convênio: $pid');
    }
    return bits.join(' · ');
  }

  /// Valor bruto de `users.data.clientTelemetry.platform` (web, android, ios, …).
  String? _telemetryPlatformRaw(Map<String, dynamic> d) {
    final t = d['clientTelemetry'];
    if (t is! Map) return null;
    final p = t['platform'];
    final s = (p ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  String _telemetryPlatformTooltip(Map<String, dynamic> d) {
    final raw = _telemetryPlatformRaw(d);
    if (raw == null) {
      return 'Última plataforma: ainda não registada (utilizador não abriu o app recentemente).';
    }
    return 'Última plataforma: ${UserClientTelemetryService.platformDisplayPt(raw)}';
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final q = _filter.trim();
    if (q.isEmpty) return docs;
    return docs
        .where((doc) => adminUserMatchesSearch(doc.data(), doc.id, q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final narrow = w < 900;
    final phoneDetail = narrow && _selectedUid != null;
    final pad = AdminPageShell.listPadding(
      context,
      top: phoneDetail ? 4 : 8,
    );

    return Padding(
      padding: pad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!phoneDetail) ...[
            ModuleHeaderPremium(
              title: 'Usuários 360°',
              icon: Icons.hub_rounded,
              dense: narrow,
              subtitleFontSize: narrow ? 11.5 : null,
              subtitle:
                  'Uso estimado, plataforma (Web / Android / iPhone), versão, tela inicial, convênio, Mercado Pago e push individual.',
            ),
            SizedBox(height: narrow ? 10 : 16),
            FastTextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              enableSuggestions: false,
              autocorrect: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              scrollPadding: EdgeInsets.only(
                bottom: 80 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              onSubmitted: (_) {
                _applySearchNow();
                FocusManager.instance.primaryFocus?.unfocus();
              },
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              decoration: InputDecoration(
                hintText: 'Buscar por nome, e-mail ou UID…',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white,
                isDense: narrow,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: narrow ? 12 : 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              onChanged: _onSearchChanged,
            ),
            SizedBox(height: narrow ? 8 : 12),
          ],
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _usersStream(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Text('Erro: ${snap.error}',
                        style: TextStyle(color: Colors.red.shade700)),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final filtered = _filterDocs(snap.data!.docs);
                if (narrow) {
                  if (_selectedUid == null) {
                    return _buildUserList(filtered, narrow: true);
                  }
                  return _Usuario360Detail(
                    canEdit: widget.adminCanEdit,
                    uid: _selectedUid!,
                    onBack: () => setState(() => _selectedUid = null),
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: (w * 0.34).clamp(280.0, 420.0),
                      child: _buildUserList(filtered, narrow: false),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _selectedUid == null
                          ? _emptyDetail()
                          : _Usuario360Detail(
                              uid: _selectedUid!,
                              onBack: null,
                              canEdit: widget.adminCanEdit,
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyDetail() {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app_rounded,
              size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'Selecione um utilizador à esquerda',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Verá gráficos de volume, último lançamento, versão do app, convênio e totais de pagamento.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _buildUserList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required bool narrow,
  }) {
    if (docs.isEmpty) {
      return Center(
        child: Text(
          'Nenhum utilizador neste filtro.',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: docs.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
        itemBuilder: (context, i) {
          final doc = docs[i];
          final d = doc.data();
          final sel = _selectedUid == doc.id;
          final platformRaw = _telemetryPlatformRaw(d);
          return Material(
            color: sel ? AppColors.primary.withValues(alpha: 0.08) : Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _selectedUid = doc.id),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: narrow ? 14 : 12,
                ),
                child: Row(
                  children: [
                    if ((d['partnershipId'] ?? '').toString().trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Tooltip(
                          message: 'Utilizador com convênio vinculado',
                          child: Icon(
                            Icons.handshake_rounded,
                            size: 22,
                            color: Colors.indigo.shade600,
                          ),
                        ),
                      ),
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.deepBlue.withValues(alpha: 0.12),
                      child: Text(
                        _userLabel(d, doc.id).isNotEmpty
                            ? _userLabel(d, doc.id)[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.deepBlue,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _userLabel(d, doc.id),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Colors.grey.shade900,
                            ),
                          ),
                          if (_userSubtitle(d).isNotEmpty)
                            Text(
                              _userSubtitle(d),
                              maxLines: narrow ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              platformRaw == null
                                  ? 'App: sem telemetria ainda'
                                  : 'App: ${UserClientTelemetryService.platformDisplayPt(platformRaw)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: platformRaw == null
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                                color: platformRaw == null
                                    ? Colors.grey.shade500
                                    : Colors.grey.shade700,
                                fontStyle: platformRaw == null
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Tooltip(
                      message: _telemetryPlatformTooltip(d),
                      child: Icon(
                        UserClientTelemetryService.platformIcon(platformRaw),
                        size: 22,
                        color: platformRaw == null
                            ? Colors.grey.shade400
                            : AppColors.primary,
                      ),
                    ),
                    if (narrow)
                      Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Usuario360Detail extends StatefulWidget {
  final String uid;
  final VoidCallback? onBack;
  final bool canEdit;

  const _Usuario360Detail({
    required this.uid,
    this.onBack,
    this.canEdit = true,
  });

  @override
  State<_Usuario360Detail> createState() => _Usuario360DetailState();
}

class _Usuario360DetailState extends State<_Usuario360Detail> {
  bool _sendingPush = false;
  late Future<_UsageBundle> _usageFuture;

  @override
  void initState() {
    super.initState();
    _usageFuture = _loadUsage(widget.uid);
  }

  @override
  void didUpdateWidget(covariant _Usuario360Detail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _usageFuture = _loadUsage(widget.uid);
    }
  }

  void _refreshUsage() {
    setState(() => _usageFuture = _loadUsage(widget.uid));
  }

  Future<void> _openMessageSheet() async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final urlCtrl = TextEditingController();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final inset = AppKeyboardInsets.of(ctx);
        final maxH = MediaQuery.sizeOf(ctx).height * 0.88;
        return Padding(
          padding: EdgeInsets.only(bottom: inset),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxH),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                Row(
                  children: [
                    const Icon(Icons.notifications_active_rounded,
                        color: AppColors.primary),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Mensagem + push',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Text(
                  'Cria um documento em notifications — a Cloud Function envia FCM se houver deviceTokens.',
                  style: TextStyle(fontSize: 12, height: 1.35, color: Colors.black54),
                ),
                const SizedBox(height: 14),
                FastTextField(
                  controller: titleCtrl,
                  textInputAction: TextInputAction.next,
                  enableSuggestions: false,
                  autocorrect: false,
                  scrollPadding: EdgeInsets.only(bottom: 120 + inset),
                  onSubmitted: (_) => FocusScope.of(ctx).nextFocus(),
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                    labelText: 'Título',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                FastTextField(
                  controller: bodyCtrl,
                  maxLines: 4,
                  minLines: 2,
                  textInputAction: TextInputAction.newline,
                  enableSuggestions: false,
                  autocorrect: false,
                  scrollPadding: EdgeInsets.only(bottom: 120 + inset),
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                    labelText: 'Mensagem',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                FastTextField(
                  controller: urlCtrl,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  enableSuggestions: false,
                  autocorrect: false,
                  scrollPadding: EdgeInsets.only(bottom: 120 + inset),
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                    labelText: 'URL (opcional, ex. /financeiro)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Enviar'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (ok != true || !mounted) {
      titleCtrl.dispose();
      bodyCtrl.dispose();
      urlCtrl.dispose();
      return;
    }

    final title = titleCtrl.text.trim();
    final body = bodyCtrl.text.trim();
    final url = urlCtrl.text.trim();
    titleCtrl.dispose();
    bodyCtrl.dispose();
    urlCtrl.dispose();

    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha título e mensagem.')),
      );
      return;
    }

    setState(() => _sendingPush = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .collection('notifications')
          .add({
        'title': title,
        'body': body,
        if (url.isNotEmpty) 'url': url,
        'fromAdmin': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        _refreshUsage();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notificação criada. Push será enviado se o utilizador tiver tokens.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingPush = false);
    }
  }

  Future<_UsageBundle> _loadUsage(String uid) async {
    final db = FirebaseFirestore.instance;
    final uref = db.collection('users').doc(uid);

    Future<int> count(String col) async {
      final c = await uref.collection(col).count().get();
      return c.count ?? 0;
    }

    final lastTxSnap = await uref
        .collection('transactions')
        .orderBy('date', descending: true)
        .limit(1)
        .get();

    DateTime? lastTxDate;
    if (lastTxSnap.docs.isNotEmpty) {
      final t = lastTxSnap.docs.first.data()['date'];
      if (t is Timestamp) lastTxDate = t.toDate();
    }

    final tx = await count('transactions');
    final scales = await count('scales');
    final reminders = await count('reminders');
    final goals = await count('goals');
    final ocorrencias = await count('ocorrencias');

    final mpSnap = await db.collection('mp_payments').where('uid', isEqualTo: uid).get();
    double mpTotal = 0;
    int mpApproved = 0;
    for (final d in mpSnap.docs) {
      final data = d.data();
      if ((data['status'] ?? '').toString() != 'approved') continue;
      if (data['isOutgoing'] == true) continue;
      mpApproved++;
      final raw = data['raw'];
      if (raw is Map) {
        final amt = raw['transaction_amount'];
        if (amt is num) mpTotal += amt.toDouble();
      }
    }

    Map<String, dynamic>? partnership;
    final userSnap = await uref.get();
    final userData = userSnap.data() ?? {};
    final pid = (userData['partnershipId'] ?? '').toString().trim();
    if (pid.isNotEmpty) {
      final pSnap = await db.collection('partnerships').doc(pid).get();
      if (pSnap.exists) partnership = pSnap.data();
    }

    return _UsageBundle(
      transactions: tx,
      scales: scales,
      reminders: reminders,
      goals: goals,
      ocorrencias: ocorrencias,
      lastTransactionAt: lastTxDate,
      mpTotalApproved: mpTotal,
      mpApprovedCount: mpApproved,
      partnership: partnership,
      partnershipId: pid,
    );
  }

  double _estimateStorageKb(_UsageBundle b) {
    return b.transactions * 2.8 +
        b.scales * 2.2 +
        b.reminders * 1.2 +
        b.goals * 1.0 +
        b.ocorrencias * 2.0 +
        48;
  }

  @override
  Widget build(BuildContext context) {
    final onBack = widget.onBack;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onBack != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onBack,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Lista de utilizadores'),
                ),
              ),
            ),
          Expanded(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(widget.uid)
                  .snapshots(),
              builder: (context, userSnap) {
                if (!userSnap.hasData || !userSnap.data!.exists) {
                  return const Center(child: Text('Utilizador não encontrado.'));
                }
                final u = userSnap.data!.data() ?? {};
                final tel = u['clientTelemetry'];
                Map<String, dynamic>? telMap;
                if (tel is Map) telMap = Map<String, dynamic>.from(tel);

                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: homePlanningRef(widget.uid).snapshots(),
                  builder: (context, planSnap) {
                    int? startIdx;
                    if (planSnap.hasData && planSnap.data!.exists) {
                      final p = planSnap.data!.data() ?? {};
                      final v = p[kHomeDefaultStartModuleField];
                      if (v is int) startIdx = v;
                      else if (v is num) startIdx = v.toInt();
                    }
                    final startLabel = startIdx != null
                        ? (kHomeDefaultStartModuleLabels[startIdx] ??
                            'Índice $startIdx')
                        : 'Padrão (Início)';

                    return FutureBuilder<_UsageBundle>(
                      future: _usageFuture,
                      builder: (context, usageSnap) {
                        final usage = usageSnap.data;
                        final df = DateFormat('dd/MM/yyyy HH:mm');

                        return LayoutBuilder(
                          builder: (context, constraints) {
                            final compactHeader = constraints.maxWidth < 520;
                            return ListView(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: EdgeInsets.fromLTRB(
                                compactHeader ? 12 : 18,
                                8,
                                compactHeader ? 12 : 18,
                                24 + MediaQuery.paddingOf(context).bottom,
                              ),
                              children: [
                                _buildDetailHeader(
                                  u: u,
                                  compact: compactHeader,
                                ),
                            _metricRow(
                              'Plano',
                              (u['plan'] ?? u['licensePlan'] ?? '—').toString(),
                              Icons.verified_rounded,
                            ),
                            if ((u['app'] ?? '').toString().trim().isNotEmpty)
                              _metricRow(
                                'Sistema (app)',
                                (u['app'] ?? '').toString(),
                                Icons.apps_rounded,
                              ),
                            _metricRow(
                              'Tela inicial',
                              startLabel,
                              Icons.home_work_rounded,
                            ),
                            _metricRow(
                              'Último lançamento (financeiro)',
                              usage?.lastTransactionAt != null
                                  ? df.format(usage!.lastTransactionAt!)
                                  : (usageSnap.connectionState ==
                                          ConnectionState.waiting
                                      ? '…'
                                      : 'Sem lançamentos'),
                              Icons.event_available_rounded,
                            ),
                            _metricRow(
                              'Onde usa o app',
                              telMap == null
                                  ? 'Ainda sem ping (Web / Android / iPhone)'
                                  : UserClientTelemetryService.platformDisplayPt(
                                      telMap['platform'],
                                    ),
                              UserClientTelemetryService.platformIcon(
                                telMap == null ? null : telMap['platform'],
                              ),
                            ),
                            _metricRow(
                              'Versão no cliente (telemetria)',
                              telMap == null
                                  ? 'Ainda sem ping'
                                  : '${telMap['appVersion'] ?? '?'} · build ${telMap['buildNumber'] ?? '?'}',
                              Icons.system_update_rounded,
                            ),
                            _metricRow(
                              'Último ping',
                              _formatTs(telMap?['lastPingAt'], df),
                              Icons.schedule_rounded,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Gráfico: volume de dados (proxy por contagens de documentos).',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (usage != null) ...[
                              LayoutBuilder(
                                builder: (context, chartBox) {
                                  if (chartBox.maxWidth < 360) {
                                    return _VolumeMetricsCompact(usage);
                                  }
                                  return SizedBox(
                                    height: chartBox.maxWidth < 480 ? 220 : 200,
                                    child: _VolumeBarChart(
                                      usage,
                                      compact: chartBox.maxWidth < 520,
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              _financeCard(usage, u, compact: compactHeader),
                              const SizedBox(height: 12),
                              _storageCard(usage),
                            ] else if (usageSnap.hasError)
                              Text('Erro ao carregar métricas: ${usageSnap.error}')
                            else
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(child: CircularProgressIndicator()),
                              ),
                            const SizedBox(height: 20),
                            AdminUser360ExtrasPanel(
                              uid: widget.uid,
                              userEmail: (u['email'] ?? '').toString(),
                              canEdit: widget.canEdit,
                            ),
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailHeader({
    required Map<String, dynamic> u,
    required bool compact,
  }) {
    final name = (u['name'] ?? widget.uid).toString();
    final email = (u['email'] ?? '').toString();
    final delegateEmail = ((u['authorizedDelegateEmail'] ?? '') as String)
        .trim()
        .toLowerCase();
    final delegateSection = AdminDelegateEmailSection(
      principalUid: widget.uid,
      principalEmail: email,
      authorizedEmail: delegateEmail.isEmpty ? null : delegateEmail,
    );
    final nameBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: TextStyle(
            fontSize: compact ? 18 : 20,
            fontWeight: FontWeight.w800,
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        if (email.isNotEmpty)
          Text(
            email,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: compact ? 12 : 13,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        delegateSection,
        const SizedBox(height: 6),
        Text(
          'UID: ${widget.uid}',
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey.shade500,
            fontFamily: 'monospace',
            height: 1.35,
          ),
          softWrap: true,
        ),
      ],
    );
    final refreshBtn = IconButton(
      tooltip: 'Atualizar métricas',
      onPressed: _refreshUsage,
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      icon: const Icon(Icons.refresh_rounded),
    );
    final msgBtn = FilledButton.tonalIcon(
      onPressed: _sendingPush ? null : _openMessageSheet,
      style: FilledButton.styleFrom(
        minimumSize: Size(compact ? double.infinity : 0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      icon: _sendingPush
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.campaign_rounded),
      label: const Text('Mensagem + push'),
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: nameBlock),
              refreshBtn,
            ],
          ),
          const SizedBox(height: 10),
          msgBtn,
          const SizedBox(height: 16),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: nameBlock),
            refreshBtn,
            const SizedBox(width: 4),
            msgBtn,
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  String _formatTs(dynamic t, DateFormat df) {
    if (t is Timestamp) return df.format(t.toDate());
    return '—';
  }

  Widget _metricRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade600,
                    letterSpacing: 0.2,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                  softWrap: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _financeCard(_UsageBundle b, Map<String, dynamic> u, {bool compact = false}) {
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final cost = (b.partnership?['costPerUser'] as num?)?.toDouble();
    final rev = (b.partnership?['revenuePerUser'] as num?)?.toDouble();
    final margin = (cost != null && rev != null) ? rev - cost : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0F172A),
            AppColors.deepBlue.withValues(alpha: 0.95),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Receita Mercado Pago (aprovados)',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            currency.format(b.mpTotalApproved),
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 20 : 22,
              fontWeight: FontWeight.w800,
            ),
            softWrap: true,
          ),
          Text(
            '${b.mpApprovedCount} pagamento(s) aprovado(s) · sem saídas admin',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 14),
          if (b.partnershipId.isNotEmpty) ...[
            const Divider(color: Colors.white24),
            Text(
              'Convênio: ${b.partnershipId}',
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              cost != null
                  ? 'Custo ref. / usuário: ${currency.format(cost)}'
                  : 'Custo ref. / usuário: —',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Text(
              rev != null
                  ? 'Receita ref. / usuário: ${currency.format(rev)}'
                  : 'Receita ref. / usuário: —',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            if (margin != null)
              Text(
                'Margem ref. (contrato): ${currency.format(margin)}',
                style: const TextStyle(
                  color: Color(0xFF6EE7B7),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(height: 6),
            const Text(
              'Valores de convênio são referência do cadastro — não substituem o somatório MP acima.',
              style: TextStyle(color: Colors.white38, fontSize: 10, height: 1.3),
            ),
          ] else
            const Text(
              'Sem partnershipId neste utilizador.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _storageCard(_UsageBundle b) {
    final kb = _estimateStorageKb(b);
    final mb = kb / 1024;
    final label = mb >= 1
        ? '~${mb.toStringAsFixed(2)} MB (estimativa Firestore)'
        : '~${kb.toStringAsFixed(0)} KB (estimativa Firestore)';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.storage_rounded, color: Colors.grey.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Espaço estimado no banco',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Colors.grey.shade800,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageBundle {
  final int transactions;
  final int scales;
  final int reminders;
  final int goals;
  final int ocorrencias;
  final DateTime? lastTransactionAt;
  final double mpTotalApproved;
  final int mpApprovedCount;
  final Map<String, dynamic>? partnership;
  final String partnershipId;

  _UsageBundle({
    required this.transactions,
    required this.scales,
    required this.reminders,
    required this.goals,
    required this.ocorrencias,
    required this.lastTransactionAt,
    required this.mpTotalApproved,
    required this.mpApprovedCount,
    required this.partnership,
    required this.partnershipId,
  });
}

class _VolumeBarChart extends StatelessWidget {
  final _UsageBundle b;
  final bool compact;

  const _VolumeBarChart(this.b, {this.compact = false});

  @override
  Widget build(BuildContext context) {
    final maxV = [
      b.transactions,
      b.scales,
      b.reminders,
      b.goals,
      b.ocorrencias,
    ].reduce((a, c) => a > c ? a : c).toDouble().clamp(1, 999999);

    final data = [
      (compact ? 'Trans.' : 'Transações', b.transactions.toDouble(), const Color(0xFF2563EB)),
      ('Escalas', b.scales.toDouble(), const Color(0xFF0D9488)),
      (compact ? 'Lembr.' : 'Lembretes', b.reminders.toDouble(), const Color(0xFFEA580C)),
      ('Metas', b.goals.toDouble(), const Color(0xFF7C3AED)),
      ('Ocorr.', b.ocorrencias.toDouble(), const Color(0xFF64748B)),
    ];

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxV * 1.15,
        barTouchData: BarTouchData(enabled: true),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: compact ? 32 : 36,
              getTitlesWidget: (v, m) => Text(
                v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.toInt().toString(),
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: compact ? 36 : 28,
              getTitlesWidget: (v, m) {
                final i = v.round().clamp(0, data.length - 1);
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    data[i].$1,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: compact ? 9 : 10, color: Colors.grey.shade700),
                  ),
                );
              },
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxV > 10 ? (maxV / 4).ceilToDouble() : 1,
          getDrawingHorizontalLine: (v) => FlLine(
            color: Colors.grey.shade200,
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (int i = 0; i < data.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: data[i].$2,
                  width: compact ? 14 : 18,
                  borderRadius: BorderRadius.circular(6),
                  gradient: LinearGradient(
                    colors: [data[i].$3, data[i].$3.withValues(alpha: 0.75)],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Lista compacta de volume — legível em telemóveis estreitos (evita gráfico cortado).
class _VolumeMetricsCompact extends StatelessWidget {
  final _UsageBundle b;

  const _VolumeMetricsCompact(this.b);

  @override
  Widget build(BuildContext context) {
    final maxV = [
      b.transactions,
      b.scales,
      b.reminders,
      b.goals,
      b.ocorrencias,
    ].reduce((a, c) => a > c ? a : c).toDouble().clamp(1, 999999);

    final rows = [
      ('Transações', b.transactions, const Color(0xFF2563EB)),
      ('Escalas', b.scales, const Color(0xFF0D9488)),
      ('Lembretes', b.reminders, const Color(0xFFEA580C)),
      ('Metas', b.goals, const Color(0xFF7C3AED)),
      ('Ocorrências', b.ocorrencias, const Color(0xFF64748B)),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(
                      row.$1,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: row.$2 / maxV,
                        minHeight: 10,
                        backgroundColor: Colors.grey.shade200,
                        color: row.$3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${row.$2}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: row.$3,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Pré-visualização 360° a partir da lista **Usuários** do admin (olho).
Future<void> openAdminUser360Preview(
  BuildContext context, {
  required String uid,
  String displayName = '',
  String email = '',
  bool canEdit = true,
}) {
  final name = displayName.trim();
  final mail = email.trim();
  final title = name.isNotEmpty ? name : (mail.isNotEmpty ? mail : uid);

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Fechar visão 360°',
    barrierColor: Colors.black.withValues(alpha: 0.52),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, _, __) {
      final pad = MediaQuery.paddingOf(ctx);
      final size = MediaQuery.sizeOf(ctx);
      final insetH = size.width < 600 ? 8.0 : 20.0;
      final insetV = size.height < 700 ? 8.0 : 16.0;
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            insetH,
            insetV + pad.top * 0.15,
            insetH,
            insetV + pad.bottom,
          ),
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                constraints: BoxConstraints(maxHeight: size.height * 0.94),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F7FA),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.deepBlue.withValues(alpha: 0.22),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AdminUser360PreviewHeader(
                      title: title,
                      subtitle: mail.isNotEmpty ? mail : uid,
                      onClose: () => Navigator.of(ctx).pop(),
                    ),
                    Expanded(
                      child: _Usuario360Detail(
                        uid: uid,
                        onBack: null,
                        canEdit: canEdit,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim, _, child) {
      final curve = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curve,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curve),
          child: child,
        ),
      );
    },
  );
}

class _AdminUser360PreviewHeader extends StatelessWidget {
  const _AdminUser360PreviewHeader({
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E3A8A), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: const Icon(
              Icons.hub_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Visão 360°',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Fechar',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
