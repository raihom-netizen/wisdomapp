import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide showDatePicker;
import '../widgets/fast_text_field.dart';
import 'package:flutter/services.dart';
import '../models/user_profile.dart';
import '../models/landing_public_content.dart';
import '../services/mp_checkout_pricing_service.dart';
import '../services/mp_admin_config_service.dart';
import '../models/goias_ac4_rate_schedule.dart';
import '../models/scale_rates.dart';
import '../services/scale_rates_period_service.dart';
import '../services/scale_rates_service.dart';
import '../widgets/admin_scale_rates_periods_panel.dart';
import '../constants/app_brand.dart';
import '../constants/admin_partner_config.dart';
import '../constants/app_version.dart';
import '../constants/premium_pro_limits.dart';
import '../constants/currency_formats.dart';
import '../constants/app_strings.dart';
import '../theme/app_colors.dart';
import '../widgets/app_logo.dart';
import '../widgets/module_header_premium.dart';
import '../widgets/partnerships_admin_module.dart';
import '../widgets/admin_menu_lateral.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import '../services/logs_service.dart';
import '../services/admin_user_plan_apply_service.dart';
import '../services/billing_service.dart';
import '../utils/date_picker_a11y.dart';
import '../services/admin_audit_service.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/skeleton_loader.dart';
import 'gestao_equipe_adm.dart';
import 'logs_atividade_page.dart';
import 'acessos_dominio_tab.dart';
import 'admin_usuarios_inteligencia_tab.dart';
import 'admin_cursos_tab.dart';
import 'admin_promocoes_tab.dart';
import 'admin_migracao_email_tab.dart';
import 'admin_tips_page.dart';
import 'admin_notification_templates_tab.dart';
import 'admin_sugestoes_tab.dart';
import '../services/functions_service.dart';
import 'package:intl/intl.dart';
import '../utils/url_launcher_helper.dart' as url_helper;
import '../constants/app_business_rules.dart';
import '../utils/keyboard_form_scaffold.dart';
import '../widgets/shell_keyboard_bottom_pad.dart';
import '../widgets/light_filter_picker.dart';
import '../utils/admin_user_search.dart';
import '../utils/debounced_text_controller.dart';
import '../utils/user_export_csv_save.dart';
import '../constants/promo_site_urls.dart';
import '../services/version_check_service.dart';
import '../utils/maintenance_app_update_links.dart';
import '../utils/ios_store_payment.dart' show kOfficialPromoLandingUrl;
import '../widgets/app_pie_chart.dart';
import '../widgets/app_bar_chart.dart';
import '../widgets/admin_mp_revenue_line_chart.dart';
import '../widgets/admin_delegate_email_section.dart';
import '../services/admin_partnership_plan_catalog.dart';
import '../utils/admin_responsive.dart';
import '../services/admin_permissions_service.dart';
import '../services/admin_scheduled_export_prefs_service.dart';
import '../widgets/admin/admin_alert_center.dart';
import '../widgets/admin/admin_bulk_actions_bar.dart';
import '../widgets/admin/admin_global_search_delegate.dart';
import '../widgets/admin/admin_revenue_forecast_panel.dart';
import '../widgets/admin/admin_system_health_panel.dart';
import '../widgets/admin/admin_user_compare_sheet.dart';
import '../widgets/admin/admin_mercado_pago_tab.dart';
import '../widgets/admin/admin_partner_resumo_tab.dart';
import '../widgets/admin/admin_partner_receipts_tab.dart';
import '../widgets/admin/admin_page_shell.dart';
import '../utils/firestore_reliable_read.dart';
import '../utils/firestore_retry.dart';
import '../utils/firestore_web_guard.dart';

/// Quando [useUnifiedPanel] é true, exibe seletor Gestão Yahweh | CASER | Gestão Frotas e filtra usuários por [app].
class AdminScreen extends StatefulWidget {
  final String uid;
  final UserProfile profile;

  /// Painel unificado: seletor de sistemas e filtro por app (gestao_yahweh, caser, gestao_frotas).
  final bool useUnifiedPanel;
  const AdminScreen(
      {super.key,
      required this.uid,
      required this.profile,
      this.useUnifiedPanel = false});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  AdminMenuItem _selectedItem = AdminMenuItem.resumo;
  bool _menuCollapsed = false;
  final _landingDoc =
      FirebaseFirestore.instance.collection('landing_content').doc('main');
  final _mpCheckoutPricingDoc = FirebaseFirestore.instance
      .collection('app_config')
      .doc('mp_checkout_prices');
  bool _landingLoaded = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<AdminMercadoPagoTabState> _mpAdminTabKey =
      GlobalKey<AdminMercadoPagoTabState>();
  final GlobalKey<_RecebimentosPixSectionState> _mpPixSectionKey =
      GlobalKey<_RecebimentosPixSectionState>();

  bool _isAdminMobile(BuildContext context) =>
      AdminResponsive.useMobileLayout(context);

  EdgeInsets _adminListPadding(BuildContext context, {double top = 16}) =>
      AdminPageShell.listPadding(context, top: top);

  void _exitAdminToApp(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  /// BLINDAGEM: FocusNode persistente para SelectableRegion; não usar FocusNode() no build (ver blindagem-ux-menus-touch.mdc).
  final FocusNode _contentFocusNode = FocusNode();
  Future<_AdminStats>? _statsFuture;
  // Filtros da lista de usuários
  String _userFilterStatus = 'todos';
  String _userFilterPlan = 'todos';
  String _userFilterVencimento = 'todos';
  DateTime? _userFilterCadastroInicio;
  DateTime? _userFilterCadastroFim;
  final _userSearchCtrl = TextEditingController();
  Timer? _userSearchDebounce;
  // Painel unificado: sistema selecionado (gestao_yahweh | caser | gestao_frotas)
  String _selectedApp = 'gestao_yahweh';
  // Cache do stream da lista de usuários: evita recriar consulta Firestore
  // durante rebuilds (ex.: quando o teclado é aberto, muda MediaQuery).
  Stream<QuerySnapshot<Map<String, dynamic>>>? _usersListStream;
  bool _usersListStreamBound = false;
  bool _partnershipsBound = false;
  bool _adminHeavyWorkScheduled = false;
  bool _partnershipMetricsScheduled = false;
  bool _partnershipMetricsLoading = false;
  List<AdminPartnershipMetric>? _overlayPartnershipMetrics;
  bool _didEnsureGlobalScaleRates = false;
  // Resumo: período dos indicadores (7, 30 ou 90 dias)
  int _resumoPeriodDays = 30;
  // Alertas para o sino da AppBar (atualizado quando o Resumo carrega)
  int _alertCount = 0;
  // Usuários: ordenação (nome, vencimento, plano)
  String _userSortOrder = 'nome';
  Future<Map<String, dynamic>>? _relatorioReceitaFuture;
  DateTime? _lastResumoUpdate;
  _AdminStats? _cachedResumoStats;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _partnershipsPlansSub;
  List<AdminPartnershipPlanOption> _partnershipPlansCatalog = [];
  int _usuariosTabIndex = 0;
  String? _activeFilterPresetId;
  bool _userFilterComConvenio = false;
  final Set<String> _bulkSelectedUids = {};
  bool _bulkSelectMode = false;

  /// UIDs visíveis após filtros (atualizado pela lista em stream).
  List<String> _visibleFilteredUids = const [];
  String? _compareUidA;
  final _adminPermissions = const AdminPermissionsService();

  AdminCapability get _adminCapability => _adminPermissions.capabilityFor(
        role: widget.profile.role,
        email: widget.profile.email,
      );

  bool get _isContentGestor =>
      _adminPermissions.isContentGestor(_adminCapability);

  bool get _isPartner => _adminPermissions.isPartner(_adminCapability);

  /// Gestor de conteúdo ou sócio — menu e módulos restritos.
  bool get _isRestrictedPanel => _isContentGestor || _isPartner;

  /// Admin master / suporte / financeiro — painel completo.
  bool get _isFullAdmin => !_isRestrictedPanel;

  List<AdminMenuItem> get _allowedMenuItems =>
      _adminPermissions.allowedMenuItems(_adminCapability);

  AdminMenuItem get _adminHomeMenuItem =>
      _adminPermissions.defaultMenuItem(_adminCapability);

  bool get _canDeletePermanent =>
      _adminPermissions.canDeleteUserPermanent(_adminCapability);

  bool get _canRemoveUser => _adminPermissions.canRemoveUser(_adminCapability);

  void _onAdminMenuSelected(AdminMenuItem item) {
    if (item == AdminMenuItem.voltar) {
      _exitAdminToApp(context);
      return;
    }
    if (!_adminPermissions.canAccessMenuItem(_adminCapability, item)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sem permissão para este módulo do painel.'),
        ),
      );
      return;
    }
    if (item == AdminMenuItem.mercadopago &&
        !_adminPermissions.canAccessMercadoPago(_adminCapability)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sem permissão para Mercado Pago (nível financeiro).'),
        ),
      );
      return;
    }
    if (item == AdminMenuItem.usuarios360) {
      setState(() {
        _selectedItem = AdminMenuItem.usuarios;
        _usuariosTabIndex = 1;
      });
      _bindHeavyWorkForMenuItem(AdminMenuItem.usuarios);
      return;
    }
    setState(() {
      _selectedItem = item;
      if (item == AdminMenuItem.usuarios) _usuariosTabIndex = 0;
    });
    _bindHeavyWorkForMenuItem(item);
  }

  void _bindHeavyWorkForMenuItem(AdminMenuItem item) {
    switch (item) {
      case AdminMenuItem.resumo:
        _ensureStatsFuture();
        break;
      case AdminMenuItem.usuarios:
      case AdminMenuItem.usuarios360:
        _ensurePartnershipsCatalog();
        _ensureUsersListStream();
        _ensureStatsFuture();
        break;
      case AdminMenuItem.convenios:
        _ensurePartnershipsCatalog();
        break;
      case AdminMenuItem.escala:
        _ensureScaleRatesBootstrap();
        break;
      default:
        break;
    }
  }

  void _ensureStatsFuture() {
    if (_statsFuture != null) return;
    setState(() {
      _statsFuture = _loadStats(periodDays: _resumoPeriodDays);
    });
  }

  void _ensureUsersListStream() {
    if (_usersListStreamBound) return;
    _usersListStreamBound = true;
    setState(() {
      _usersListStream = _createUsersListStream();
    });
  }

  void _ensurePartnershipsCatalog() {
    if (_partnershipsBound) return;
    _partnershipsBound = true;
    _partnershipsPlansSub = FirebaseFirestore.instance
        .collection('partnerships')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _partnershipPlansCatalog = parsePartnershipPlansSnapshot(snap);
      });
    });
  }

  void _ensureScaleRatesBootstrap() {
    if (_didEnsureGlobalScaleRates) return;
    _didEnsureGlobalScaleRates = true;
    unawaited(ScaleRatesPeriodService().seedBootstrapIfEmpty());
  }

  void _resumeAdminHeavyWork() {
    if (!mounted) return;
    _bindHeavyWorkForMenuItem(_selectedItem);
  }

  void _scheduleAdminHeavyWork() {
    if (_adminHeavyWorkScheduled) return;
    _adminHeavyWorkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final delay = _adminPreferLightStatsIO
          ? (defaultTargetPlatform == TargetPlatform.android
              ? const Duration(milliseconds: 1400)
              : const Duration(milliseconds: 900))
          : const Duration(milliseconds: 48);
      Future<void>.delayed(delay, () {
        if (!mounted) return;
        _resumeAdminHeavyWork();
      });
    });
  }

  /// Mobile: menos I/O Firestore no 1º paint — evita ANR ao abrir o painel.
  bool get _adminPreferLightStatsIO =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  int get _usersListLimit => _adminPreferLightStatsIO ? 400 : 2000;

  int get _kAdminTxMaxDetailDocs => _adminPreferLightStatsIO ? 400 : 2500;

  int get _kAdminUsersFallbackLimit => _adminPreferLightStatsIO ? 800 : 5000;

  int get _kAdminUsersSizeSample => _adminPreferLightStatsIO ? 60 : 300;

  int get _kAdminTxSizeSample => _adminPreferLightStatsIO ? 80 : 400;

  int get _kAdminMpPaymentsLimit => _adminPreferLightStatsIO ? 250 : 800;

  int get _kAdminLicenseHorizonLimit => _adminPreferLightStatsIO ? 400 : 1500;

  void _schedulePartnershipMetricsOverlay() {
    if (!_adminPreferLightStatsIO) return;
    if (_partnershipMetricsScheduled) return;
    if (_overlayPartnershipMetrics != null) return;
    _partnershipMetricsScheduled = true;
    Future<void>.delayed(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      unawaited(_loadPartnershipMetricsOverlay());
    });
  }

  Future<void> _loadPartnershipMetricsOverlay() async {
    if (_partnershipMetricsLoading || _overlayPartnershipMetrics != null) {
      return;
    }
    _partnershipMetricsLoading = true;
    try {
      final metrics = await _fetchPartnershipMetrics();
      if (!mounted) return;
      setState(() => _overlayPartnershipMetrics = metrics);
    } catch (e) {
      debugPrint('Métricas convênios (adiado admin): $e');
    } finally {
      _partnershipMetricsLoading = false;
    }
  }

  Future<List<AdminPartnershipMetric>> _fetchPartnershipMetrics() async {
    final partnershipMetrics = <AdminPartnershipMetric>[];
    final pSnap = await firestoreQueryGetReliable(
      FirebaseFirestore.instance.collection('partnerships'),
    );
    final catalog = parsePartnershipPlansSnapshot(pSnap);
    if (catalog.isEmpty) return partnershipMetrics;
    final metrics = await Future.wait(
      catalog.map((c) async {
        final n = await countUsersPartnershipInPeriod(
          FirebaseFirestore.instance,
          c.partnershipDocId,
          0,
          partnershipPlanCode: c.planCode,
        );
        return AdminPartnershipMetric(
          partnershipDocId: c.partnershipDocId,
          planCode: c.planCode,
          partnershipName: c.partnershipName,
          userCount: n,
        );
      }),
    );
    partnershipMetrics.addAll(metrics);
    return partnershipMetrics;
  }

  static int _estimateDocSizeBytes(Map<String, dynamic> data) {
    var bytes = 48;
    for (final e in data.entries) {
      final v = e.value;
      if (v is String) {
        bytes += v.length;
      } else if (v is num) {
        bytes += 12;
      } else if (v is bool) {
        bytes += 1;
      } else if (v is Timestamp) {
        bytes += 12;
      } else if (v is Map) {
        bytes += 64;
      } else if (v is List) {
        bytes += v.length * 8;
      } else {
        bytes += 24;
      }
    }
    return bytes;
  }

  void _openAdminGlobalSearch() {
    showSearch<String?>(
      context: context,
      delegate: AdminGlobalSearchDelegate(
        onSelect: (uid, name, email) {
          setState(() {
            _selectedItem = AdminMenuItem.usuarios;
            _usuariosTabIndex = 0;
            _userSearchCtrl.text = email.isNotEmpty ? email : name;
          });
          openAdminUser360Preview(
            context,
            uid: uid,
            displayName: name,
            email: email,
            canEdit: _adminPermissions.canEditUserLicense(_adminCapability),
          );
        },
      ),
    );
  }

  void _navigateFromAlert(String alertId) {
    setState(() {
      _selectedItem = AdminMenuItem.usuarios;
      _usuariosTabIndex = 0;
      _activeFilterPresetId = alertId;
    });
    switch (alertId) {
      case 'licencas_vencidas':
        _applyFilterPreset('vencidos');
        break;
      case 'licencas_vencendo_7':
        _applyFilterPreset('vencendo_7');
        break;
      default:
        break;
    }
  }

  void _applyFilterPreset(String presetId) {
    setState(() {
      // Preset substitui filtros anteriores — evita combinações que escondem todos.
      _userSearchDebounce?.cancel();
      _userSearchCtrl.clear();
      _userFilterStatus = 'todos';
      _userFilterPlan = 'todos';
      _userFilterVencimento = 'todos';
      _userFilterCadastroInicio = null;
      _userFilterCadastroFim = null;
      _userFilterComConvenio = false;
      _activeFilterPresetId = presetId;
      switch (presetId) {
        case 'vencidos':
          _userFilterStatus = 'vencidos';
          break;
        case 'vencendo_7':
          _userFilterVencimento = 'vence_7';
          break;
        case 'premium':
          _userFilterPlan = 'premium';
          break;
        case 'ultimos_10':
          _userFilterStatus = 'ultimos_10';
          _userSortOrder = 'cadastro';
          break;
        case 'removidos':
          _userFilterStatus = 'removidos';
          break;
        case 'convenio':
          _userFilterComConvenio = true;
          break;
        default:
          break;
      }
    });
  }

  void _onUserManualFilterChanged(VoidCallback apply) {
    setState(() {
      _activeFilterPresetId = null;
      apply();
    });
  }

  Future<void> _handleBulkAction(String actionId) async {
    if (_bulkSelectedUids.isEmpty) return;
    final canEdit = _adminPermissions.canBulkActions(_adminCapability);
    if (!canEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem permissão para ações em lote.')),
      );
      return;
    }
    final uids = _bulkSelectedUids.toList();
    switch (actionId) {
      case 'prorrogar_30':
        var ok = 0;
        for (final uid in uids) {
          try {
            await BillingService().prorrogarPrazo(uid, 30);
            ok++;
          } catch (_) {}
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Prorrogado +30 dias para $ok/${uids.length}.')),
          );
        }
        break;
      case 'export_csv':
        await _exportUsersCsv(onlyUids: uids);
        break;
      case 'push':
        await _bulkSendPush(uids);
        break;
      case 'compare':
        if (uids.length == 2) {
          await showAdminUserCompareSheet(
            context,
            uidA: uids[0],
            uidB: uids[1],
          );
        }
        break;
      case 'remover':
        await _bulkRemoveUsers(uids);
        break;
      case 'excluir_total':
        await _bulkExcluirUsuariosTotal(uids);
        break;
    }
  }

  void _selectAllFilteredUsers() {
    if (_visibleFilteredUids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Nenhum usuário visível com os filtros atuais.')),
      );
      return;
    }
    setState(() {
      _bulkSelectMode = true;
      _bulkSelectedUids
        ..clear()
        ..addAll(_visibleFilteredUids.where((u) => u != widget.uid));
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${_bulkSelectedUids.length} usuário(s) selecionado(s) conforme filtros.',
        ),
      ),
    );
  }

  Future<void> _bulkRemoveUsers(List<String> uids) async {
    if (!_canRemoveUser) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem permissão para remover usuários.')),
      );
      return;
    }
    final targets =
        uids.where((u) => u.trim().isNotEmpty && u != widget.uid).toList();
    if (targets.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text('Remover ${targets.length} usuário(s)?'),
        content: const Text(
          'Os utilizadores perdem acesso ao app. Pode reativá-los depois (filtro Removidos).',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    var success = 0;
    for (final uid in targets) {
      try {
        await BillingService().removerUsuario(uid);
        await AdminAuditService().logAdminAction(
          action: removerUsuario,
          targetUserId: uid,
        );
        success++;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(_bulkSelectedUids.clear);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removidos: $success de ${targets.length}.')),
    );
  }

  Future<void> _bulkExcluirUsuariosTotal(List<String> uids) async {
    if (!_canDeletePermanent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Somente super admin pode excluir permanentemente.')),
      );
      return;
    }
    final targets =
        uids.where((u) => u.trim().isNotEmpty && u != widget.uid).toList();
    if (targets.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(
          targets.length == 1
              ? 'Excluir usuário permanentemente?'
              : 'Excluir ${targets.length} usuários permanentemente?',
        ),
        content: Text(
          targets.length == 1
              ? 'Deseja realmente remover este usuário de forma total? '
                  'Esta ação apaga login e dados permanentemente e não pode ser desfeita.'
              : 'Deseja realmente remover os ${targets.length} usuários selecionados de forma total? '
                  'Esta ação apaga login e dados de cada um permanentemente e não pode ser desfeita. '
                  'Contas admin/master são ignoradas pelo servidor.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sim, excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
          content: Text(
              'Iniciando exclusão total de ${targets.length} usuário(s)...')),
    );
    var success = 0;
    var fail = 0;
    for (final uid in targets) {
      try {
        final callable = FirebaseFunctions.instance.httpsCallable(
          'ctDeleteUserTotal',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 280)),
        );
        await callable.call<Map<String, dynamic>>({'uid': uid});
        await AdminAuditService().logAdminAction(
          action: excluirUsuario,
          targetUserId: uid,
          details: 'exclusão total em lote',
        );
        success++;
      } catch (_) {
        fail++;
      }
    }
    if (!mounted) return;
    setState(_bulkSelectedUids.clear);
    messenger.showSnackBar(
      SnackBar(
        content:
            Text('Exclusão total concluída. Sucesso: $success • Falhas: $fail'),
        backgroundColor: fail == 0 ? AppColors.success : Colors.orange.shade700,
      ),
    );
  }

  Future<void> _bulkSendPush(List<String> uids) async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text('Push em lote (${uids.length})'),
        content: KeyboardAwareDialogScrollBody(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FastTextField(
                controller: titleCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Título'),
              ),
              const SizedBox(height: 8),
              FastTextField(
                controller: bodyCtrl,
                kind: FastTextFieldKind.prose,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Mensagem'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      titleCtrl.dispose();
      bodyCtrl.dispose();
      return;
    }
    final title = titleCtrl.text.trim();
    final body = bodyCtrl.text.trim();
    titleCtrl.dispose();
    bodyCtrl.dispose();
    if (title.isEmpty || body.isEmpty) return;
    var sent = 0;
    for (final uid in uids.take(25)) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('notifications')
            .add({
          'title': title,
          'body': body,
          'fromAdmin': true,
          'bulk': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
        sent++;
      } catch (_) {}
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Notificações criadas: $sent.')),
      );
    }
  }

  Future<void> _openScheduledExportPrefs() async {
    final svc = AdminScheduledExportPrefsService();
    final existing = await svc.load();
    final emailCtrl = TextEditingController(
      text: (existing?['email'] ?? widget.profile.email ?? '').toString(),
    );
    var enabled = existing?['enabled'] == true;
    var frequency = (existing?['frequency'] ?? 'weekly').toString();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          scrollable: true,
          title: const Text('Exportação programada (CSV)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Guarda preferência no servidor. O envio automático por e-mail '
                'será ativado numa próxima atualização da Cloud Function.',
                style: TextStyle(fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ativar'),
                value: enabled,
                onChanged: (v) => setDlg(() => enabled = v),
              ),
              FastTextField(
                controller: emailCtrl,
                kind: FastTextFieldKind.email,
                decoration: const InputDecoration(labelText: 'E-mail destino'),
              ),
              const SizedBox(height: 8),
              LightFilterPicker<String>(
                value: frequency,
                label: 'Frequência',
                options: const [
                  LightFilterOption(value: 'daily', label: 'Diária'),
                  LightFilterOption(value: 'weekly', label: 'Semanal'),
                  LightFilterOption(value: 'monthly', label: 'Mensal'),
                ],
                onChanged: (v) => setDlg(() => frequency = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                await svc.save(
                  enabled: enabled,
                  email: emailCtrl.text,
                  frequency: frequency,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    emailCtrl.dispose();
  }

  @override
  void initState() {
    super.initState();
    _selectedItem = _adminHomeMenuItem;
    _scheduleAdminHeavyWork();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _createUsersListStream() {
    Query<Map<String, dynamic>> q =
        adminUsersWithEmailQuery(FirebaseFirestore.instance.collection('users'));
    if (widget.useUnifiedPanel) {
      q = q.where('app', isEqualTo: _selectedApp);
    }
    return q.limit(_usersListLimit).snapshots();
  }

  final _heroTitleCtrl = TextEditingController();
  final _heroSubtitleCtrl = TextEditingController();
  final _heroTealCtrl = TextEditingController();
  final _heroSlateCtrl = TextEditingController();
  final _heroBadgesCtrl = TextEditingController();
  final _heroNoteCtrl = TextEditingController();
  final _plansTitleCtrl = TextEditingController();
  final _landingPremiumDetailCtrl = TextEditingController();
  final _landingPremiumCardPeriodCtrl = TextEditingController();
  final _landingPremiumFeaturesCtrl = TextEditingController();
  final _planCtaCtrl = TextEditingController();
  final _footerCtrl = TextEditingController();
  final _supportTitleCtrl = TextEditingController();
  final _supportSubtitleCtrl = TextEditingController();
  final _apkDownloadUrlCtrl = TextEditingController();
  final _googleAgendaBtnCtrl = TextEditingController();
  final _googleAgendaUrlCtrl = TextEditingController();
  final _googleAgendaHintCtrl = TextEditingController();
  final _divThemePrimaryCtrl = TextEditingController();
  final _divThemeAccentCtrl = TextEditingController();
  bool _googleAgendaEnabled = true;

  /// Valores reais PIX/cartão (Mercado Pago) — `app_config/mp_checkout_prices`.
  final _mpPremiumMonthlyCtrl = TextEditingController();
  final _mpPremiumAnnualCtrl = TextEditingController();
  final _mpPremiumProMonthlyCtrl = TextEditingController();
  final _mpPremiumProAnnualCtrl = TextEditingController();
  final _mpExtraBankMonthlyCtrl = TextEditingController();
  final _mpExtraBankAnnualCtrl = TextEditingController();

  /// Campos da página `/divulgacao` (chave = id no Firestore).
  final Map<String, TextEditingController> _divulgacaoCtrls = {};
  bool _divulgacaoCtrlsReady = false;
  bool _divulgacaoDefaultsSeeded = false;

  void _ensureDivulgacaoCtrls() {
    if (_divulgacaoCtrlsReady) return;
    _divulgacaoCtrlsReady = true;
    for (final f in kDivulgacaoLandingFields) {
      _divulgacaoCtrls[f.key] = TextEditingController();
    }
  }

  Future<void> _seedDivulgacaoDefaultsIfMissing(
      Map<String, dynamic>? data) async {
    if (_divulgacaoDefaultsSeeded) return;
    _divulgacaoDefaultsSeeded = true;
    final raw = data ?? const <String, dynamic>{};
    final payload = <String, dynamic>{};
    for (final f in kDivulgacaoLandingFields) {
      final existing = raw[f.key];
      final asText = existing?.toString().trim() ?? '';
      if (existing == null || asText.isEmpty) {
        payload[f.key] = f.defaultValue;
      }
    }
    if (payload.isEmpty) return;
    payload['updatedAt'] = FieldValue.serverTimestamp();
    await _landingDoc.set(payload, SetOptions(merge: true));
  }

  @override
  void dispose() {
    _partnershipsPlansSub?.cancel();
    _userSearchDebounce?.cancel();
    _contentFocusNode.dispose();
    _userSearchCtrl.dispose();
    _heroTitleCtrl.dispose();
    _heroSubtitleCtrl.dispose();
    _heroTealCtrl.dispose();
    _heroSlateCtrl.dispose();
    _heroBadgesCtrl.dispose();
    _heroNoteCtrl.dispose();
    _plansTitleCtrl.dispose();
    _landingPremiumDetailCtrl.dispose();
    _landingPremiumCardPeriodCtrl.dispose();
    _landingPremiumFeaturesCtrl.dispose();
    _planCtaCtrl.dispose();
    _footerCtrl.dispose();
    _supportTitleCtrl.dispose();
    _supportSubtitleCtrl.dispose();
    _apkDownloadUrlCtrl.dispose();
    _googleAgendaBtnCtrl.dispose();
    _googleAgendaUrlCtrl.dispose();
    _googleAgendaHintCtrl.dispose();
    _divThemePrimaryCtrl.dispose();
    _divThemeAccentCtrl.dispose();
    _mpPremiumMonthlyCtrl.dispose();
    _mpPremiumAnnualCtrl.dispose();
    _mpPremiumProMonthlyCtrl.dispose();
    _mpPremiumProAnnualCtrl.dispose();
    _mpExtraBankMonthlyCtrl.dispose();
    _mpExtraBankAnnualCtrl.dispose();
    for (final c in _divulgacaoCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _parseList(String raw) {
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  void _loadLandingControllers(Map<String, dynamic> data) {
    _ensureDivulgacaoCtrls();
    _heroTitleCtrl.text =
        LandingPublicContent.pickLegacyEditor(data, 'heroTitle');
    _heroSubtitleCtrl.text =
        LandingPublicContent.pickLegacyEditor(data, 'heroSubtitle');
    _heroTealCtrl.text =
        LandingPublicContent.pickLegacyEditor(data, 'heroTealLine');
    _heroSlateCtrl.text =
        LandingPublicContent.pickLegacyEditor(data, 'heroSlateLine');
    _heroBadgesCtrl.text =
        LandingPublicContent.pickLegacyEditor(data, 'heroBadges');
    _heroNoteCtrl.text =
        LandingPublicContent.pickLegacyEditor(data, 'heroNote');
    _plansTitleCtrl.text =
        LandingPublicContent.pickLegacyEditor(data, 'plansTitle');
    _landingPremiumDetailCtrl.text =
        LandingPublicContent.pickLegacyEditor(data, 'landingPremiumDetail');
    _landingPremiumCardPeriodCtrl.text =
        LandingPublicContent.pickLegacyEditor(data, 'landingPremiumCardPeriod');
    _landingPremiumFeaturesCtrl.text =
        LandingPublicContent.pickLegacyEditor(data, 'landingPremiumFeatures');
    _planCtaCtrl.text =
        LandingPublicContent.pickLegacyEditor(data, 'planCtaText');
    _footerCtrl.text =
        LandingPublicContent.pickLegacyEditor(data, 'footerText');
    _supportTitleCtrl.text =
        LandingPublicContent.pickLegacyEditor(data, 'supportTitle');
    _supportSubtitleCtrl.text =
        LandingPublicContent.pickLegacyEditor(data, 'supportSubtitle');
    _googleAgendaBtnCtrl.text =
        LandingPublicContent.pickLegacyEditor(data, 'googleAgendaButtonText');
    _googleAgendaUrlCtrl.text =
        LandingPublicContent.pickLegacyEditor(data, 'googleAgendaConnectUrl');
    _googleAgendaHintCtrl.text =
        LandingPublicContent.pickLegacyEditor(data, 'googleAgendaHintText');
    _divThemePrimaryCtrl.text =
        LandingPublicContent.pickLegacyEditor(data, 'divThemePrimaryColor');
    _divThemeAccentCtrl.text =
        LandingPublicContent.pickLegacyEditor(data, 'divThemeAccentColor');
    _googleAgendaEnabled = data['googleAgendaEnabled'] != false;
    for (final f in kDivulgacaoLandingFields) {
      _divulgacaoCtrls[f.key]!.text =
          LandingPublicContent.pickDivEditor(data, f.key);
    }
  }

  void _setMoneyCtrl(TextEditingController c, double v) {
    c.text = v.toStringAsFixed(2).replaceAll('.', ',');
  }

  double? _parseMoneyCtrl(TextEditingController c) {
    final raw =
        c.text.trim().replaceAll(RegExp(r'\s+'), '').replaceAll(',', '.');
    final v = double.tryParse(raw);
    if (v == null || v <= 0) return null;
    return v;
  }

  Future<void> _hydrateMpCheckoutPriceFields() async {
    try {
      final doc = await _mpCheckoutPricingDoc.get();
      if (!mounted) return;
      final s = MpCheckoutPricingSnapshot.fromFirestore(doc.data());
      _setMoneyCtrl(_mpPremiumMonthlyCtrl, s.premiumMonthly);
      _setMoneyCtrl(_mpPremiumAnnualCtrl, s.premiumAnnual);
      _setMoneyCtrl(_mpPremiumProMonthlyCtrl, s.premiumProMonthly);
      _setMoneyCtrl(_mpPremiumProAnnualCtrl, s.premiumProAnnual);
      _setMoneyCtrl(_mpExtraBankMonthlyCtrl, s.extraBankConnectionMonthly);
      _setMoneyCtrl(_mpExtraBankAnnualCtrl, s.extraBankConnectionAnnual);
    } catch (_) {
      final d = MpCheckoutPricingSnapshot.defaults();
      _setMoneyCtrl(_mpPremiumMonthlyCtrl, d.premiumMonthly);
      _setMoneyCtrl(_mpPremiumAnnualCtrl, d.premiumAnnual);
      _setMoneyCtrl(_mpPremiumProMonthlyCtrl, d.premiumProMonthly);
      _setMoneyCtrl(_mpPremiumProAnnualCtrl, d.premiumProAnnual);
      _setMoneyCtrl(_mpExtraBankMonthlyCtrl, d.extraBankConnectionMonthly);
      _setMoneyCtrl(_mpExtraBankAnnualCtrl, d.extraBankConnectionAnnual);
    }
  }

  Future<void> _saveMpCheckoutPricing() async {
    final premM = _parseMoneyCtrl(_mpPremiumMonthlyCtrl);
    final premA = _parseMoneyCtrl(_mpPremiumAnnualCtrl);
    if (premM == null || premA == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Informe valores numéricos válidos (ex.: 14,99) em Premium mensal e anual.')),
        );
      }
      return;
    }
    final d = MpCheckoutPricingSnapshot.defaults();
    final exM = d.extraBankConnectionMonthly;
    final exA = d.extraBankConnectionAnnual;
    await _mpCheckoutPricingDoc.set(
      {
        'premium_monthly': premM,
        'premium_annual': premA,
        'premium_pro_monthly': premM,
        'premium_pro_annual': premA,
        'extra_bank_connection_monthly': exM,
        'extra_bank_connection_annual': exA,
        'basic_monthly': FieldValue.delete(),
        'basic_annual': FieldValue.delete(),
        'master_monthly': FieldValue.delete(),
        'master_annual': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByUid': widget.uid,
      },
      SetOptions(merge: true),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Preços do checkout salvos. Podem levar até ~1 minuto para as Cloud Functions usarem o cache novo.')),
      );
    }
  }

  Future<void> _syncPremiumPublicTextsFromCheckoutPricing() async {
    _ensureDivulgacaoCtrls();
    final premM = _parseMoneyCtrl(_mpPremiumMonthlyCtrl);
    final premA = _parseMoneyCtrl(_mpPremiumAnnualCtrl);
    if (premM == null || premA == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Premium mensal e anual precisam estar válidos.')),
        );
      }
      return;
    }
    final snap = MpCheckoutPricingSnapshot(
      premiumMonthly: premM,
      premiumAnnual: premA,
      premiumProMonthly: premM,
      premiumProAnnual: premA,
    );
    for (final e in snap.generatedPremiumLandingFields().entries) {
      final c = _divulgacaoCtrls[e.key];
      if (c != null) c.text = e.value;
    }
    final gen = snap.generatedPremiumLandingFields();
    _landingPremiumDetailCtrl.text =
        gen['landingPremiumDetail'] ?? _landingPremiumDetailCtrl.text;
    _landingPremiumCardPeriodCtrl.text =
        gen['landingPremiumCardPeriod'] ?? _landingPremiumCardPeriodCtrl.text;
    await _saveLanding();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Textos de preço Premium (landing /divulgação) atualizados e salvos em landing_content/main.',
          ),
        ),
      );
    }
  }

  Future<void> _saveLanding() async {
    _ensureDivulgacaoCtrls();
    final payload = <String, dynamic>{
      'heroTitle': _heroTitleCtrl.text.trim(),
      'heroSubtitle': _heroSubtitleCtrl.text.trim(),
      'heroTealLine': _heroTealCtrl.text.trim(),
      'heroSlateLine': _heroSlateCtrl.text.trim(),
      'heroBadges': _parseList(_heroBadgesCtrl.text),
      'heroNote': _heroNoteCtrl.text.trim(),
      'plansTitle': _plansTitleCtrl.text.trim(),
      'landingPremiumDetail': _landingPremiumDetailCtrl.text.trim(),
      'landingPremiumCardPeriod': _landingPremiumCardPeriodCtrl.text.trim(),
      'landingPremiumFeatures': _landingPremiumFeaturesCtrl.text.trim(),
      'premiumPrice': [
        _divulgacaoCtrls['divPremiumMensal']?.text.trim() ?? '',
        _divulgacaoCtrls['divPremiumAnual']?.text.trim() ?? '',
      ].where((s) => s.isNotEmpty).join(' • '),
      'masterPrice': [
        _divulgacaoCtrls['divPremiumMensal']?.text.trim() ?? '',
        _divulgacaoCtrls['divPremiumAnual']?.text.trim() ?? '',
      ].where((s) => s.isNotEmpty).join(' • '),
      'premiumPerks':
          _parseList(_divulgacaoCtrls['divPremiumBeneficios']?.text ?? ''),
      'masterPerks':
          _parseList(_divulgacaoCtrls['divPremiumBeneficios']?.text ?? ''),
      'planCtaText': _planCtaCtrl.text.trim(),
      'footerText': _footerCtrl.text.trim(),
      'supportTitle': _supportTitleCtrl.text.trim(),
      'supportSubtitle': _supportSubtitleCtrl.text.trim(),
      'googleAgendaButtonText': _googleAgendaBtnCtrl.text.trim().isEmpty
          ? 'Ativar integração com Google Agenda'
          : _googleAgendaBtnCtrl.text.trim(),
      'googleAgendaConnectUrl': _googleAgendaUrlCtrl.text.trim().isEmpty
          ? 'https://calendar.google.com/'
          : _googleAgendaUrlCtrl.text.trim(),
      'googleAgendaHintText': _googleAgendaHintCtrl.text.trim().isEmpty
          ? 'Conecte sua conta Google para abrir eventos da Agenda diretamente no Google Agenda.'
          : _googleAgendaHintCtrl.text.trim(),
      'googleAgendaEnabled': _googleAgendaEnabled,
      'divThemePrimaryColor': _divThemePrimaryCtrl.text.trim().isEmpty
          ? '#0B1B4B'
          : _divThemePrimaryCtrl.text.trim(),
      'divThemeAccentColor': _divThemeAccentCtrl.text.trim().isEmpty
          ? '#E8C547'
          : _divThemeAccentCtrl.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    for (final f in kDivulgacaoLandingFields) {
      payload[f.key] = _divulgacaoCtrls[f.key]!.text.trim();
    }
    await _landingDoc.set(payload, SetOptions(merge: true));
    final playUrl = _divulgacaoCtrls['divPlayStoreUrl']?.text.trim() ?? '';
    if (playUrl.isNotEmpty &&
        (playUrl.startsWith('http://') || playUrl.startsWith('https://'))) {
      await FirebaseFirestore.instance
          .collection('app_config')
          .doc('version')
          .set(
        {
          'apkDownloadUrl': playUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
  }

  String _formatAdminResumoError(Object error) {
    if (FirestoreWebGuard.isRecoverableFirestoreWebError(error)) {
      return 'Instabilidade temporária do Firestore na Web. '
          'Toque em «Tentar novamente» (ou atualize a página).';
    }
    if (FirestoreWebGuard.isInternalAssertionError(error)) {
      return 'Instabilidade temporária do Firestore na Web. '
          'Toque em «Tentar novamente» (ou atualize a página).';
    }
    final msg = error.toString().split('\n').first.trim();
    if (msg.length > 220) return '${msg.substring(0, 220)}…';
    return msg;
  }

  Future<void> _reloadResumoStats() async {
    if (kIsWeb) {
      await FirestoreWebGuard.recoverFirestoreWebSession().catchError((_) {});
    }
    if (!mounted) return;
    setState(() {
      _overlayPartnershipMetrics = null;
      _partnershipMetricsScheduled = false;
      _statsFuture = _loadStats(periodDays: _resumoPeriodDays);
    });
  }

  Future<_AdminStats> _loadStats({int periodDays = 30}) {
    Future<_AdminStats> core() => _loadStatsCore(periodDays: periodDays);
    if (kIsWeb) {
      return runFirestoreWithRetry(
        () => FirestoreWebGuard.runWithWebRecovery(core),
      );
    }
    return runFirestoreWithRetry(core);
  }

  Future<_AdminStats> _loadStatsCore({int periodDays = 30}) async {
    final now = DateTime.now();
    Query<Map<String, dynamic>> usersQuery =
        adminUsersWithEmailQuery(FirebaseFirestore.instance.collection('users'));
    if (widget.useUnifiedPanel) {
      usersQuery = usersQuery.where('app', isEqualTo: _selectedApp);
    }
    int admins = 0;
    int premiums = 0;
    int totalUsers = 0;

    /// Usuários com `partnershipId` não vazio (convênio vinculado).
    int usersWithPartnership = 0;
    final partnershipMetrics = <AdminPartnershipMetric>[];
    List<Map<String, dynamic>> usersSample = [];
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docsForLicenses = [];
    try {
      final uCounts = await Future.wait<AggregateQuerySnapshot>([
        usersQuery.count().get(),
        usersQuery.where('role', isEqualTo: 'admin').count().get(),
        usersQuery.where('role', isEqualTo: 'master').count().get(),
        usersQuery
            .where('plan', whereIn: [
              'premium',
              'premium_pro',
              'premium_assego',
              'premium_monthly',
              'premium_annual',
            ])
            .count()
            .get(),
      ]);
      totalUsers = uCounts[0].count ?? 0;
      admins = (uCounts[1].count ?? 0) + (uCounts[2].count ?? 0);
      premiums = uCounts[3].count ?? 0;
      try {
        final pw = await usersQuery
            .where('partnershipId', isNotEqualTo: '')
            .count()
            .get();
        usersWithPartnership = pw.count ?? 0;
      } catch (_) {}
      final sampleSnap = await firestoreQueryGetReliable(usersQuery.limit(6));
      usersSample = sampleSnap.docs.map((d) => d.data()).toList();
      docsForLicenses = [];
    } catch (_) {
      final usersSnap = await firestoreQueryGetReliable(
        usersQuery.limit(_kAdminUsersFallbackLimit),
      );
      usersSample = usersSnap.docs
          .where((d) => adminUserHasCompleteEmail(d.data()))
          .take(6)
          .map((d) => d.data())
          .toList();
      docsForLicenses = usersSnap.docs
          .where((d) => adminUserHasCompleteEmail(d.data()))
          .toList();
      totalUsers = 0;
      for (final doc in docsForLicenses) {
        totalUsers++;
        final data = doc.data();
        final role = (data['role'] ?? 'user').toString();
        final plan = (data['plan'] ?? 'free').toString().toLowerCase();
        if (role == 'admin' || role == 'master') admins += 1;
        if (plan == 'premium' ||
            plan == 'premium_assego' ||
            plan == 'premium_pro' ||
            plan == 'premium_monthly' ||
            plan == 'premium_annual') {
          premiums += 1;
        }
        if ((data['partnershipId'] ?? '').toString().trim().isNotEmpty) {
          usersWithPartnership++;
        }
      }
    }

    if (!_adminPreferLightStatsIO) {
      try {
        partnershipMetrics.addAll(await _fetchPartnershipMetrics());
      } catch (e) {
        debugPrint('Métricas convênios (resumo admin): $e');
      }
    }

    double revenue30d = 0;
    double pixBruto = 0, pixLiquido = 0, cardBruto = 0, cardLiquido = 0;
    int legacyMp = 0, premiumMp = 0;
    final lastPaymentsList = <Map<String, dynamic>>[];
    const taxaPix = 0.0099;
    const taxaCartao = 0.0499;
    final bucketSizeMp = periodDays <= 14
        ? 1
        : periodDays <= 31
            ? 2
            : periodDays <= 90
                ? 5
                : 7;
    final nMpBuckets =
        math.min(28, math.max(1, (periodDays / bucketSizeMp).ceil()));
    final mpBrutoBuckets = List<double>.filled(nMpBuckets, 0);
    final mpLiquidoBuckets = List<double>.filled(nMpBuckets, 0);
    final since30Mp = now.subtract(Duration(days: periodDays));
    final periodStart =
        DateTime(since30Mp.year, since30Mp.month, since30Mp.day);
    final mpChartLabels = List<String>.generate(nMpBuckets, (i) {
      final d = periodStart.add(Duration(days: i * bucketSizeMp));
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    });
    try {
      QuerySnapshot<Map<String, dynamic>> mpSnap;
      try {
        mpSnap = await firestoreQueryGetReliable(
          FirebaseFirestore.instance
              .collection('mp_payments')
              .where('status', isEqualTo: 'approved')
              .where('dateApprovedAt',
                  isGreaterThanOrEqualTo: Timestamp.fromDate(periodStart))
              .orderBy('dateApprovedAt', descending: true)
              .limit(_kAdminMpPaymentsLimit),
        );
      } catch (_) {
        mpSnap = await firestoreQueryGetReliable(
          FirebaseFirestore.instance
              .collection('mp_payments')
              .where('status', isEqualTo: 'approved')
              .limit(_adminPreferLightStatsIO ? 500 : 2000),
        );
      }
      final allForLast = <Map<String, dynamic>>[];
      for (final d in mpSnap.docs) {
        final data = d.data();
        if (data['isOutgoing'] == true) continue;
        final raw = data['raw'];
        if (raw is! Map) continue;
        final amt = raw['transaction_amount'];
        final valor = amt is num ? amt.toDouble() : 0.0;
        final method =
            (raw['payment_method_id'] ?? '').toString().toLowerCase();
        final isPix = method == 'pix';
        DateTime? dt;
        final topTs = data['dateApprovedAt'];
        if (topTs is Timestamp) {
          dt = topTs.toDate();
        } else {
          final dateApproved = raw['date_approved'];
          if (dateApproved is String) {
            dt = DateTime.tryParse(dateApproved);
          } else if (dateApproved is Timestamp) {
            dt = dateApproved.toDate();
          }
        }
        if (dt == null) continue;
        final dtDay = DateTime(dt.year, dt.month, dt.day);
        if (dtDay.isBefore(periodStart)) continue;
        revenue30d += valor;
        if (isPix) {
          pixBruto += valor;
          pixLiquido += valor * (1 - taxaPix);
        } else {
          cardBruto += valor;
          cardLiquido += valor * (1 - taxaCartao);
        }
        final plan =
            (data['plan'] ?? data['planCode'] ?? '').toString().toLowerCase();
        final pl = plan.toLowerCase();
        if (pl.contains('basic') || pl.contains('master')) {
          legacyMp++;
        } else {
          premiumMp++;
        }
        final payer = raw['payer'];
        String userDisplay = 'Usuário';
        if (payer is Map) {
          final email = (payer['email'] ?? '').toString().trim();
          final name =
              (payer['first_name'] ?? payer['name'] ?? '').toString().trim();
          userDisplay = email.isNotEmpty
              ? (name.isNotEmpty ? name : email)
              : (name.isNotEmpty ? name : 'Usuário');
        }
        final planLabel =
            (data['plan'] ?? data['planCode'] ?? 'premium').toString();
        final taxa = isPix ? taxaPix : taxaCartao;
        final liquido = valor * (1 - taxa);
        final dayFromStart = dtDay.difference(periodStart).inDays;
        if (dayFromStart >= 0 && dayFromStart < periodDays) {
          final bi = dayFromStart ~/ bucketSizeMp;
          if (bi >= 0 && bi < mpBrutoBuckets.length) {
            mpBrutoBuckets[bi] += valor;
            mpLiquidoBuckets[bi] += liquido;
          }
        }
        allForLast.add({
          'id': d.id,
          'userDisplay': userDisplay,
          'plan': planLabel,
          'method': isPix ? 'pix' : 'cartao',
          'valor': valor,
          'liquido': liquido,
          'dateApproved': dt,
        });
      }
      allForLast.sort((a, b) => (b['dateApproved'] as DateTime)
          .compareTo(a['dateApproved'] as DateTime));
      lastPaymentsList.addAll(allForLast.take(5));
    } catch (_) {}

    final since = now.subtract(Duration(days: periodDays));
    final sinceDayTx = DateTime(since.year, since.month, since.day);
    final bucketSizeTx = periodDays <= 14
        ? 1
        : periodDays <= 31
            ? 2
            : periodDays <= 90
                ? 5
                : 7;
    final nTxBuckets =
        math.min(24, math.max(1, (periodDays / bucketSizeTx).ceil()));
    int txCount30d = 0;
    double totalValue = 0;
    String? txResumoAviso;
    DateTime? latestTransactionAt;
    DateTime? latestUserCreatedAt;
    DateTime? latestPaymentApprovedAt;
    double usersEstimatedMb = 0;
    double txEstimatedMb = 0;
    final series = List<double>.filled(nTxBuckets, 0);

    try {
      final uSamp = await Future.wait<QuerySnapshot<Map<String, dynamic>>>([
        firestoreQueryGetReliable(usersQuery.limit(_kAdminUsersSizeSample)),
        firestoreQueryGetReliable(
          usersQuery.orderBy('createdAt', descending: true).limit(1),
        ),
      ]);
      final usersSampleForSize = uSamp[0];
      final latestUser = uSamp[1];
      if (usersSampleForSize.docs.isNotEmpty && totalUsers > 0) {
        var sum = 0;
        for (final d in usersSampleForSize.docs) {
          sum += _estimateDocSizeBytes(d.data());
        }
        final avg = sum / usersSampleForSize.docs.length;
        final totalEstimatedBytes = avg * totalUsers;
        usersEstimatedMb = totalEstimatedBytes / (1024 * 1024);
      }
      if (latestUser.docs.isNotEmpty) {
        final data = latestUser.docs.first.data();
        final ts = data['createdAt'];
        if (ts is Timestamp) latestUserCreatedAt = ts.toDate();
      }
    } catch (_) {}

    try {
      final baseTx = FirebaseFirestore.instance
          .collectionGroup('transactions')
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(sinceDayTx));
      final cSnap = await baseTx.count().get();
      txCount30d = cSnap.count ?? 0;
      if (txCount30d != 0) {
        final latestTxSnap = await firestoreQueryGetReliable(
          baseTx.orderBy('date', descending: true).limit(1),
        );
        final txDetailSnap = await firestoreQueryGetReliable(
          baseTx
              .orderBy('date', descending: true)
              .limit(_kAdminTxMaxDetailDocs),
        );
        if (latestTxSnap.docs.isNotEmpty) {
          final ts0 = latestTxSnap.docs.first.data()['date'];
          if (ts0 is Timestamp) latestTransactionAt = ts0.toDate();
        }
        for (var i = 0; i < txDetailSnap.docs.length; i++) {
          final doc = txDetailSnap.docs[i];
          final data = doc.data();
          final amount = (data['amount'] ?? 0).toDouble();
          totalValue += amount;
          final ts = data['date'];
          if (ts is Timestamp) {
            final date = ts.toDate();
            final dayIdx = date.difference(sinceDayTx).inDays;
            if (dayIdx >= 0 && dayIdx < periodDays) {
              final bi = dayIdx ~/ bucketSizeTx;
              if (bi >= 0 && bi < series.length) {
                series[bi] += amount;
              }
            }
          }
          if (i % 120 == 119) {
            await Future<void>.delayed(Duration.zero);
          }
        }
        if (txCount30d > _kAdminTxMaxDetailDocs) {
          txResumoAviso =
              'Volume, gráfico e estimativa de espaço: até $_kAdminTxMaxDetailDocs lanç. mais recentes. '
              'Lanç. no período: $txCount30d (contagem exata).';
        }
        if (txDetailSnap.docs.isNotEmpty) {
          final sample = txDetailSnap.docs
              .take(_kAdminTxSizeSample)
              .toList();
          var sampleBytes = 0;
          for (final d in sample) {
            sampleBytes += _estimateDocSizeBytes(d.data());
          }
          final avgTx = sampleBytes / sample.length;
          txEstimatedMb = (avgTx * txCount30d) / (1024 * 1024);
        }
      }
    } catch (_) {
      txCount30d = 0;
      totalValue = 0;
    }

    if (lastPaymentsList.isNotEmpty) {
      final dt = lastPaymentsList.first['dateApproved'];
      if (dt is DateTime) latestPaymentApprovedAt = dt;
    }

    final labels = List<String>.generate(nTxBuckets, (i) {
      final d = sinceDayTx.add(Duration(days: i * bucketSizeTx));
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    });

    int licensesExpiring7d = 0;
    int licensesExpired = 0;
    final startOfToday = DateTime(now.year, now.month, now.day);
    const licHorizonDays = 90;
    const nLicBuckets = 10;
    final licBucketSizeDays = (licHorizonDays / nLicBuckets).ceil();
    var licenseExpiryHorizonCounts = List<int>.filled(nLicBuckets, 0);
    final licenseExpiryHorizonLabels = List<String>.generate(nLicBuckets, (i) {
      final d = startOfToday.add(Duration(days: i * licBucketSizeDays));
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    });
    final end7thDay =
        DateTime(startOfToday.year, startOfToday.month, startOfToday.day)
            .add(const Duration(days: 7));
    final end7Eod =
        DateTime(end7thDay.year, end7thDay.month, end7thDay.day, 23, 59, 59);
    final horizonLastDay =
        startOfToday.add(const Duration(days: licHorizonDays - 1));
    final horizonEndEod = DateTime(horizonLastDay.year, horizonLastDay.month,
        horizonLastDay.day, 23, 59, 59);
    void bucketLicenseExpiry(DateTime exp) {
      final day = DateTime(exp.year, exp.month, exp.day);
      if (day.isBefore(startOfToday)) return;
      final daysFromStart = day.difference(startOfToday).inDays;
      if (daysFromStart < 0 || daysFromStart >= licHorizonDays) return;
      final bi = daysFromStart ~/ licBucketSizeDays;
      if (bi >= 0 && bi < nLicBuckets) {
        licenseExpiryHorizonCounts[bi]++;
      }
    }

    try {
      Query<Map<String, dynamic>> licQ =
          adminUsersWithEmailQuery(FirebaseFirestore.instance.collection('users'));
      if (widget.useUnifiedPanel) {
        licQ = licQ.where('app', isEqualTo: _selectedApp);
      }
      final licAggs = await Future.wait<AggregateQuerySnapshot>([
        licQ
            .where('licenseExpiresAt',
                isLessThan: Timestamp.fromDate(startOfToday))
            .count()
            .get(),
        licQ
            .where('licenseExpiresAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
            .where('licenseExpiresAt',
                isLessThanOrEqualTo: Timestamp.fromDate(end7Eod))
            .count()
            .get(),
      ]);
      licensesExpired = licAggs[0].count ?? 0;
      licensesExpiring7d = licAggs[1].count ?? 0;
      licenseExpiryHorizonCounts = List<int>.filled(nLicBuckets, 0);
      try {
        final horizonSnap = await firestoreQueryGetReliable(
          licQ
              .where('licenseExpiresAt',
                  isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
              .where('licenseExpiresAt',
                  isLessThanOrEqualTo: Timestamp.fromDate(horizonEndEod))
              .limit(_kAdminLicenseHorizonLimit),
        );
        for (final doc in horizonSnap.docs) {
          final expRaw = doc.data()['licenseExpiresAt'];
          if (expRaw is! Timestamp) continue;
          bucketLicenseExpiry(expRaw.toDate());
        }
      } catch (_) {
        licenseExpiryHorizonCounts = List<int>.filled(nLicBuckets, 0);
        for (final doc in docsForLicenses) {
          final d = doc.data();
          final exp = d['licenseExpiresAt'] is Timestamp
              ? (d['licenseExpiresAt'] as Timestamp).toDate()
              : null;
          if (exp == null) continue;
          bucketLicenseExpiry(exp);
        }
      }
    } catch (_) {
      for (final doc in docsForLicenses) {
        final d = doc.data();
        final exp = d['licenseExpiresAt'] is Timestamp
            ? (d['licenseExpiresAt'] as Timestamp).toDate()
            : null;
        if (exp == null) continue;
        final days =
            exp.difference(DateTime(now.year, now.month, now.day)).inDays;
        if (days < 0) {
          licensesExpired++;
        } else if (days <= 7) {
          licensesExpiring7d++;
        }
        bucketLicenseExpiry(exp);
      }
    }

    return _AdminStats(
      totalUsers: totalUsers,
      totalAdmins: admins,
      partnershipMetrics: partnershipMetrics,
      totalUsersWithPartnership: usersWithPartnership,
      totalPremiums: premiums,
      txCount30d: txCount30d,
      txValue30d: totalValue,
      revenue30d: revenue30d,
      pixBruto: pixBruto,
      pixLiquido: pixLiquido,
      cardBruto: cardBruto,
      cardLiquido: cardLiquido,
      legacyMp: legacyMp,
      premiumMp: premiumMp,
      chartValues: series,
      chartLabels: labels,
      mpRevenueBrutoByBucket: List<double>.from(mpBrutoBuckets),
      mpRevenueLiquidoByBucket: List<double>.from(mpLiquidoBuckets),
      mpRevenueBucketLabels: mpChartLabels,
      usersSample: usersSample,
      lastPayments: lastPaymentsList,
      licensesExpiring7d: licensesExpiring7d,
      licensesExpired: licensesExpired,
      licenseExpiryHorizonCounts: licenseExpiryHorizonCounts,
      licenseExpiryHorizonLabels: licenseExpiryHorizonLabels,
      usersEstimatedMb: usersEstimatedMb,
      txEstimatedMb: txEstimatedMb,
      latestTransactionAt: latestTransactionAt,
      latestUserCreatedAt: latestUserCreatedAt,
      latestPaymentApprovedAt: latestPaymentApprovedAt,
      txResumoAviso: txResumoAviso,
    );
  }

  Future<void> _openDownloadEditor(
      {DocumentSnapshot<Map<String, dynamic>>? doc}) async {
    final titleCtrl =
        TextEditingController(text: doc?.data()?['title']?.toString() ?? '');
    final subtitleCtrl =
        TextEditingController(text: doc?.data()?['subtitle']?.toString() ?? '');
    final urlCtrl =
        TextEditingController(text: doc?.data()?['url']?.toString() ?? '');
    final iconCtrl = TextEditingController(
        text: doc?.data()?['icon']?.toString() ?? 'android');
    final orderCtrl =
        TextEditingController(text: doc?.data()?['order']?.toString() ?? '0');

    await showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        scrollable: true,
        title: Text(doc == null ? 'Novo Download' : 'Editar Download'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FastTextField(
                  controller: titleCtrl,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (v) => FocusScope.of(dlgCtx).nextFocus(),
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(labelText: 'Título')),
              FastTextField(
                  controller: subtitleCtrl,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (v) => FocusScope.of(dlgCtx).nextFocus(),
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(labelText: 'Descrição')),
              FastTextField(
                  controller: urlCtrl,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (v) => FocusScope.of(dlgCtx).nextFocus(),
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(labelText: 'URL')),
              FastTextField(
                  controller: iconCtrl,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (v) => FocusScope.of(dlgCtx).nextFocus(),
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                      labelText: 'Ícone (android/ios/web)')),
              FastTextField(
                  controller: orderCtrl,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(labelText: 'Ordem')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              final data = {
                'title': titleCtrl.text.trim(),
                'subtitle': subtitleCtrl.text.trim(),
                'url': urlCtrl.text.trim(),
                'icon': iconCtrl.text.trim(),
                'order': int.tryParse(orderCtrl.text.trim()) ?? 0,
                'updatedAt': FieldValue.serverTimestamp(),
              };
              final ref =
                  FirebaseFirestore.instance.collection('public_downloads');
              if (doc == null) {
                await ref.add(data);
              } else {
                await doc.reference.set(data, SetOptions(merge: true));
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    titleCtrl.dispose();
    subtitleCtrl.dispose();
    urlCtrl.dispose();
    iconCtrl.dispose();
    orderCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF2D5BFF);
    const brandTeal = Color(0xFF12B5A5);
    final isMobile = _isAdminMobile(context);

    // Blindagem: tecla Voltar (Android) e botão voltar sempre param na tela inicial (Resumo); sair do painel só pelo menu "Voltar" ou ícone Home.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectedItem != _adminHomeMenuItem) {
          setState(() => _selectedItem = _adminHomeMenuItem);
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        resizeToAvoidBottomInset: scaffoldKeyboardResizeToAvoidBottomInset(),
        backgroundColor: AdminPageShell.background,
        appBar: AppBar(
          title: Text(
            _selectedItem == _adminHomeMenuItem && _isFullAdmin
                ? 'Painel Admin'
                : _isPartner
                    ? 'Painel ${AppBrand.idealizerName} · ${_breadcrumbLabel(_selectedItem)}'
                    : 'Painel Admin · ${_breadcrumbLabel(_selectedItem)}',
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3),
          ),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF1A237E),
                  AppColors.primary,
                  AppColors.accent
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 4,
          leading: IconButton(
            icon: Icon(isMobile
                ? Icons.menu_rounded
                : (_menuCollapsed ? Icons.menu : Icons.menu_open)),
            onPressed: () {
              if (isMobile) {
                _scaffoldKey.currentState?.openDrawer();
              } else {
                setState(() => _menuCollapsed = !_menuCollapsed);
              }
            },
          ),
          actions: [
            if (!_isContentGestor)
              IconButton(
                icon: const Icon(Icons.search_rounded),
                onPressed: _openAdminGlobalSearch,
                tooltip: 'Busca global',
              ),
            if (_isFullAdmin && _selectedItem != AdminMenuItem.resumo)
              IconButton(
                icon: const Icon(Icons.dashboard_rounded),
                onPressed: () =>
                    setState(() => _selectedItem = AdminMenuItem.resumo),
                tooltip: 'Ir ao Resumo',
              ),
            if (_isPartner && _selectedItem != AdminMenuItem.resumo)
              IconButton(
                icon: const Icon(Icons.dashboard_rounded),
                onPressed: () =>
                    setState(() => _selectedItem = _adminHomeMenuItem),
                tooltip: 'Ir ao Resumo',
              ),
            if (isMobile)
              IconButton(
                icon: const Icon(Icons.home_rounded),
                onPressed: () => _exitAdminToApp(context),
                tooltip: 'Voltar ao aplicativo',
              ),
            if ((_isFullAdmin || _isPartner) && _alertCount > 0)
              IconButton(
                icon: Badge(
                  label: Text('$_alertCount'),
                  child: const Icon(Icons.notifications_active_rounded),
                ),
                onPressed: () => _navigateFromAlert('licencas_vencidas'),
                tooltip: '$_alertCount licenças vencendo ou vencidas',
              ),
          ],
        ),
        drawer: isMobile
            ? AdminMenuLateral(
                selectedItem: _selectedItem,
                onItemSelected: (item) {
                  if (item == AdminMenuItem.voltar) {
                    _exitAdminToApp(context);
                    return;
                  }
                  if (mounted) _onAdminMenuSelected(item);
                },
                isCollapsed: false,
                asDrawer: true,
                onCloseDrawer: () => _scaffoldKey.currentState?.closeDrawer(),
                allowedItems:
                    _isRestrictedPanel ? _allowedMenuItems : null,
                accountEmail: widget.profile.email,
                accountSubtitle: _isContentGestor
                    ? '${widget.profile.email ?? ''} · gestor · dicas · cursos · relatórios'
                    : _isPartner
                        ? '${widget.profile.email ?? ''} · sócio · usuários · recebimentos'
                        : null,
                titleOverrides: _isPartner
                    ? {AdminMenuItem.mercadopago: 'Recebimentos'}
                    : null,
              )
            : null,
        body: SafeArea(
          top: false,
          left: false,
          right: false,
          child: isMobile
              ? _buildContent(brandBlue, brandTeal)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // BLINDAGEM: menu SEMPRE fora de SelectableRegion — senão o toque não abre o módulo (ver .cursor/rules/blindagem-ux-menus-touch.mdc).
                    AdminMenuLateral(
                      selectedItem: _selectedItem,
                      onItemSelected: (item) {
                        if (item == AdminMenuItem.voltar) {
                          _exitAdminToApp(context);
                          return;
                        }
                        if (mounted) _onAdminMenuSelected(item);
                      },
                      isCollapsed: _menuCollapsed,
                      allowedItems:
                          _isRestrictedPanel ? _allowedMenuItems : null,
                      accountEmail: widget.profile.email,
                      accountSubtitle: _isContentGestor
                          ? '${widget.profile.email ?? ''} · gestor · dicas · cursos · divulgação'
                          : _isPartner
                              ? '${widget.profile.email ?? ''} · sócio · usuários · recebimentos'
                              : null,
                      titleOverrides: _isPartner
                          ? {AdminMenuItem.mercadopago: 'Recebimentos'}
                          : null,
                    ),
                    Expanded(
                      child: _selectedItem == AdminMenuItem.convenios
                          ? _buildContent(brandBlue, brandTeal)
                          : SelectableRegion(
                              focusNode: _contentFocusNode,
                              selectionControls: materialTextSelectionControls,
                              child: _buildContent(brandBlue, brandTeal),
                            ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  String _breadcrumbLabel(AdminMenuItem item) {
    switch (item) {
      case AdminMenuItem.resumo:
        return 'Resumo';
      case AdminMenuItem.usuarios:
        return 'Usuários';
      case AdminMenuItem.usuarios360:
        return 'WISDOMAPP 360°';
      case AdminMenuItem.equipe:
        return 'Equipe';
      case AdminMenuItem.logs:
        return 'Logs';
      case AdminMenuItem.relatorios:
        return 'Relatórios';
      case AdminMenuItem.sugestoes:
        return 'Sugestões';
      case AdminMenuItem.dicasFinanceiras:
        return 'Dicas financeiras';
      case AdminMenuItem.downloads:
        return 'Downloads';
      case AdminMenuItem.landing:
        return 'Landing';
      case AdminMenuItem.acessosDominio:
        return 'Acessos domínio';
      case AdminMenuItem.escala:
        return 'Escala';
      case AdminMenuItem.drive:
        return 'Backups';
      case AdminMenuItem.mercadopago:
        return _isPartner ? 'Recebimentos' : 'Mercado Pago';
      case AdminMenuItem.cursos:
        return 'Cursos em vídeo';
      case AdminMenuItem.pluggy:
        return 'Pluggy (Open Finance)';
      case AdminMenuItem.openFinanceExtras:
        return 'Conexões extras Open Finance';
      case AdminMenuItem.premiumProMonitor:
        return 'Monitor legado (API bancos)';
      case AdminMenuItem.promocoes:
        return 'Promoções';
      case AdminMenuItem.convenios:
        return 'Convênios';
      case AdminMenuItem.lojas:
        return 'Publicar nas Lojas';
      case AdminMenuItem.migracaoEmail:
        return 'Migração de e-mail';
      case AdminMenuItem.email:
        return 'E-mail';
      case AdminMenuItem.manutencao:
        return 'Manutenção';
      case AdminMenuItem.voltar:
        return '';
    }
  }

  Widget _buildDiscontinuedOpenFinanceMessage(Color brandBlue) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Integração automática a bancos está descontinuada nesta versão. Os planos ativos são Premium e Premium ASSEGO (convênios).',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: brandBlue,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  static const Map<String, String> _sistemasUnificados = {
    'gestao_yahweh': 'Gestão Yahweh Igrejas',
    'caser': 'CASER',
    'gestao_frotas': 'Gestão Frotas',
  };

  Widget _buildSeletorSistema() {
    final mobile = _isAdminMobile(context);
    final pad = AdminResponsive.horizontalPadding(context);
    final dropdown = DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selectedApp,
        isExpanded: true,
        dropdownColor: const Color(0xFF1D1E33),
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
        items: _sistemasUnificados.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
        onChanged: (v) {
          if (v != null) {
            setState(() {
              _selectedApp = v;
              _usersListStreamBound = false;
              _usersListStream = null;
              _statsFuture = null;
            });
            _ensureUsersListStream();
            _ensureStatsFuture();
          }
        },
      ),
    );
    return Container(
      margin: EdgeInsets.fromLTRB(pad, 8, pad, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [const Color(0xFF122B6B), AppColors.primary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4))
        ],
      ),
      child: mobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.swap_horiz_rounded,
                        color: Colors.white.withOpacity(0.9), size: 22),
                    const SizedBox(width: 10),
                    Text('Sistema:',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withOpacity(0.95))),
                  ],
                ),
                const SizedBox(height: 10),
                dropdown,
              ],
            )
          : Row(
              children: [
                Icon(Icons.swap_horiz_rounded,
                    color: Colors.white.withOpacity(0.9), size: 22),
                const SizedBox(width: 12),
                Text('Sistema:',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withOpacity(0.95))),
                const SizedBox(width: 12),
                Expanded(child: dropdown),
              ],
            ),
    );
  }

  Widget _buildContent(Color brandBlue, Color brandTeal) {
    final label = _breadcrumbLabel(_selectedItem);
    if (label.isEmpty) return const SizedBox.shrink();
    final horizontalPad = AdminResponsive.horizontalPadding(context);
    final isMobile = _isAdminMobile(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.useUnifiedPanel) _buildSeletorSistema(),
        if (isMobile)
          Padding(
            padding: EdgeInsets.fromLTRB(horizontalPad, 8, horizontalPad, 0),
            child: OutlinedButton.icon(
              onPressed: () => _exitAdminToApp(context),
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
              label: const Text('Voltar ao aplicativo'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary.withOpacity(0.6)),
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(horizontalPad, 12, horizontalPad, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.admin_panel_settings_rounded,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 10),
                Text('Admin',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800)),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: AdminPageShell.wrap(
            context: context,
            child: _buildContentBody(brandBlue, brandTeal),
          ),
        ),
      ],
    );
  }

  Widget _buildContentBody(Color brandBlue, Color brandTeal) {
    switch (_selectedItem) {
      case AdminMenuItem.resumo:
        return _buildResumoTab(brandBlue, brandTeal);
      case AdminMenuItem.usuarios:
        return _buildUsuariosTab(brandBlue, brandTeal);
      case AdminMenuItem.usuarios360:
        return _buildUsuariosTab(brandBlue, brandTeal, forceSubTab: 1);
      case AdminMenuItem.equipe:
        return GestaoEquipeAdm(
          canManageTeam: _adminPermissions.canManageTeam(_adminCapability),
          embeddedInAdmin: true,
        );
      case AdminMenuItem.logs:
        return LogsAtividadePage(
          isMaster: widget.profile.role == 'master',
          embeddedInAdmin: true,
        );
      case AdminMenuItem.relatorios:
        return _buildRelatoriosTab(brandBlue, brandTeal);
      case AdminMenuItem.sugestoes:
        return _buildSugestoesTab(brandBlue, brandTeal);
      case AdminMenuItem.dicasFinanceiras:
        return const AdminTipsPage();
      case AdminMenuItem.downloads:
        return _buildDownloadsTab();
      case AdminMenuItem.landing:
        return _buildLandingTab();
      case AdminMenuItem.acessosDominio:
        return AcessosDominioTab();
      case AdminMenuItem.escala:
        return _buildEscalaTab(brandBlue, brandTeal);
      case AdminMenuItem.drive:
        return _buildDriveBackupTab(brandBlue, brandTeal);
      case AdminMenuItem.mercadopago:
        return _buildMercadoPagoTab(brandBlue, brandTeal);
      case AdminMenuItem.cursos:
        return const AdminCursosTab();
      case AdminMenuItem.pluggy:
        return _buildDiscontinuedOpenFinanceMessage(brandBlue);
      case AdminMenuItem.openFinanceExtras:
        return _buildDiscontinuedOpenFinanceMessage(brandBlue);
      case AdminMenuItem.premiumProMonitor:
        return _buildDiscontinuedOpenFinanceMessage(brandBlue);
      case AdminMenuItem.promocoes:
        return const AdminPromocoesTab();
      case AdminMenuItem.convenios:
        return _buildConveniosTab(brandBlue, brandTeal);
      case AdminMenuItem.lojas:
        return _buildLojasTab(brandBlue, brandTeal);
      case AdminMenuItem.migracaoEmail:
        return const AdminMigracaoEmailTab();
      case AdminMenuItem.email:
        return _buildEmailConfigTab(brandBlue, brandTeal);
      case AdminMenuItem.manutencao:
        return _buildManutencaoTab(brandBlue, brandTeal);
      case AdminMenuItem.voltar:
        return const SizedBox.shrink();
    }
  }

  void _clearUserFilters() {
    _userSearchDebounce?.cancel();
    _userSearchCtrl.clear();
    setState(() {
      _userFilterStatus = 'todos';
      _userFilterPlan = 'todos';
      _userFilterVencimento = 'todos';
      _userFilterCadastroInicio = null;
      _userFilterCadastroFim = null;
      _userSortOrder = 'nome';
      _activeFilterPresetId = null;
      _userFilterComConvenio = false;
    });
  }

  static const int _ultimosCadastrosLimit = 10;

  DateTime? _userDocCreatedAt(Map<String, dynamic> d) {
    final raw = d['createdAt'];
    if (raw is Timestamp) return raw.toDate();
    return null;
  }

  String _dateLabel(DateTime? dt, {required String fallback}) {
    if (dt == null) return fallback;
    return DateFormat('dd/MM/yyyy').format(dt);
  }

  Future<void> _pickUserCadastroDate({required bool isStart}) async {
    final initial =
        (isStart ? _userFilterCadastroInicio : _userFilterCadastroFim) ??
            DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    _onUserManualFilterChanged(() {
      if (isStart) {
        _userFilterCadastroInicio = picked;
      } else {
        _userFilterCadastroFim = picked;
      }
    });
  }

  bool _docMatchesCadastroPeriodo(Map<String, dynamic> d,
      {required DateTime? inicio, required DateTime? fim}) {
    final createdAt = d['createdAt'] is Timestamp
        ? (d['createdAt'] as Timestamp).toDate()
        : null;
    if (inicio == null && fim == null) return true;
    // Utilizadores legados sem createdAt: não esconder quando há filtro de data.
    if (createdAt == null) return true;

    final cadDay = DateTime(createdAt.year, createdAt.month, createdAt.day);
    DateTime? s =
        inicio != null ? DateTime(inicio.year, inicio.month, inicio.day) : null;
    DateTime? e = fim != null ? DateTime(fim.year, fim.month, fim.day) : null;
    if (s != null && e != null && e.isBefore(s)) {
      final tmp = s;
      s = e;
      e = tmp;
    }

    if (s != null && cadDay.isBefore(s)) return false;
    if (e != null && cadDay.isAfter(e)) return false;
    return true;
  }

  Widget _buildUsuariosTab(Color brandBlue, Color brandTeal,
      {int? forceSubTab}) {
    if (forceSubTab != null && _usuariosTabIndex != forceSubTab) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _usuariosTabIndex = forceSubTab);
      });
    }
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final horizontalPad = MediaQuery.sizeOf(context).width < 380 ? 12.0 : 16.0;
    final canEdit = _adminPermissions.canEditUserLicense(_adminCapability);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(horizontalPad, 8, horizontalPad, 0),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      label: Text('Lista'),
                      icon: Icon(Icons.list_rounded, size: 18),
                    ),
                    ButtonSegment(
                      value: 1,
                      label: Text('360°'),
                      icon: Icon(Icons.insights_rounded, size: 18),
                    ),
                  ],
                  selected: {_usuariosTabIndex},
                  onSelectionChanged: (s) =>
                      setState(() => _usuariosTabIndex = s.first),
                ),
              ),
              IconButton(
                tooltip: _bulkSelectMode
                    ? 'Desativar seleção em lote'
                    : 'Seleção em lote',
                onPressed: () => setState(() {
                  _bulkSelectMode = !_bulkSelectMode;
                  if (!_bulkSelectMode) _bulkSelectedUids.clear();
                }),
                icon: Icon(
                  _bulkSelectMode
                      ? Icons.check_box_rounded
                      : Icons.check_box_outlined,
                ),
              ),
              if (_bulkSelectMode)
                TextButton(
                  onPressed: _selectAllFilteredUsers,
                  child: Text(
                    _visibleFilteredUids.isEmpty
                        ? 'Selecionar todos'
                        : 'Selecionar todos (${_visibleFilteredUids.length})',
                  ),
                ),
            ],
          ),
        ),
        if (_bulkSelectedUids.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(horizontalPad, 8, horizontalPad, 0),
            child: AdminBulkActionsBar(
              selectedCount: _bulkSelectedUids.length,
              enabled: canEdit,
              canRemove: _canRemoveUser,
              canDeletePermanent: _canDeletePermanent,
              onClear: () => setState(_bulkSelectedUids.clear),
              onAction: (id) {
                if (id == 'compare' || _bulkSelectedUids.length == 2) {
                  if (_bulkSelectedUids.length == 2) {
                    _handleBulkAction('compare');
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Selecione exatamente 2 para comparar.'),
                      ),
                    );
                  }
                  return;
                }
                _handleBulkAction(id);
              },
            ),
          ),
        Expanded(
          child: _usuariosTabIndex == 1
              ? AdminUsuariosInteligenciaTab(
                  useUnifiedPanel: widget.useUnifiedPanel,
                  unifiedApp: _selectedApp,
                  adminCanEdit: canEdit,
                )
              : _buildUsuariosListTab(
                  brandBlue: brandBlue,
                  brandTeal: brandTeal,
                  bottomPad: bottomPad,
                  horizontalPad: horizontalPad,
                  canEdit: canEdit,
                ),
        ),
      ],
    );
  }

  Widget _buildUsuariosListTab({
    required Color brandBlue,
    required Color brandTeal,
    required double bottomPad,
    required double horizontalPad,
    required bool canEdit,
  }) {
    if (!_usersListStreamBound) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureUsersListStream();
      });
    }
    return RefreshIndicator(
      onRefresh: () async => setState(() {}),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
                horizontalPad, 16, horizontalPad, 8 + bottomPad),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ModuleHeaderPremium(
                    title: 'Usuários',
                    icon: Icons.people_rounded,
                    subtitle:
                        'Controle recebimentos (PIX/cartão), planos e vencimento da licença. Altere plano, prorrogue prazo, defina Free ou remova usuário. Use os filtros para buscar por ativos, plano ou vencimento.',
                  ),
                  const SizedBox(height: 16),
                  AdminUserFilterPresetsBar(
                    activePresetId: _activeFilterPresetId,
                    onPresetSelected: _applyFilterPreset,
                  ),
                  const SizedBox(height: 12),
                  if (_statsFuture != null)
                    FutureBuilder<_AdminStats>(
                      future: _statsFuture,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting &&
                            !snap.hasData) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child:
                                  const LinearProgressIndicator(minHeight: 4),
                            ),
                          );
                        }
                        if (!snap.hasData) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _AdminUserMonitoringPanel(
                            stats: snap.data!,
                            periodoDias: _resumoPeriodDays,
                            brandBlue: brandBlue,
                            brandTeal: brandTeal,
                          ),
                        );
                      },
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: const LinearProgressIndicator(minHeight: 4),
                      ),
                    ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final narrowFilters = constraints.maxWidth < 400;
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.18)),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.10),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.filter_list_rounded,
                                      size: 20, color: AppColors.primary),
                                  const SizedBox(width: 8),
                                  Text('Filtros',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.grey.shade800)),
                                  const Spacer(),
                                  TextButton.icon(
                                    icon: const Icon(Icons.clear_all_rounded,
                                        size: 18),
                                    label: const Text('Limpar filtros'),
                                    onPressed: _clearUserFilters,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              FastTextField(
                                controller: _userSearchCtrl,
                                kind: FastTextFieldKind.search,
                                textInputAction: TextInputAction.search,
                                onTapOutside: (_) => FocusManager
                                    .instance.primaryFocus
                                    ?.unfocus(),
                                decoration: InputDecoration(
                                  hintText:
                                      'Buscar por nome, e-mail, UID ou CPF...',
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                onSubmitted: (_) {
                                  _userSearchDebounce?.cancel();
                                  if (mounted) setState(() {});
                                  FocusManager.instance.primaryFocus?.unfocus();
                                },
                                onChanged: (_) {
                                  _userSearchDebounce?.cancel();
                                  _userSearchDebounce = Timer(
                                    Duration(
                                        milliseconds:
                                            AppBusinessRules.searchDebounceMs),
                                    () {
                                      if (mounted) setState(() {});
                                    },
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 12,
                                runSpacing: 10,
                                children: [
                                  _filterDropdown<String>(
                                    value: _userFilterStatus,
                                    label: 'Status',
                                    minWidth: narrowFilters
                                        ? constraints.maxWidth - 24
                                        : 180,
                                    options: const [
                                      LightFilterOption(
                                          value: 'todos', label: 'Todos'),
                                      LightFilterOption(
                                          value: 'ativos',
                                          label: 'Ativos (licença válida)'),
                                      LightFilterOption(
                                          value: 'vencidos', label: 'Vencidos'),
                                      LightFilterOption(
                                          value: 'removidos',
                                          label: 'Removidos'),
                                      LightFilterOption(
                                          value: 'ultimos_10',
                                          label: 'Últimos 10 cadastros'),
                                    ],
                                    onChanged: (v) =>
                                        _onUserManualFilterChanged(() {
                                      _userFilterStatus = v ?? 'todos';
                                      if (_userFilterStatus == 'ultimos_10') {
                                        _userSortOrder = 'cadastro';
                                      } else if (_userFilterStatus != 'todos') {
                                        // Chip «Convênio» + status manual esvaziava a lista.
                                        _userFilterComConvenio = false;
                                      }
                                    }),
                                  ),
                                  _filterDropdown<String>(
                                    value: _userFilterPlan,
                                    label: 'Plano',
                                    minWidth: narrowFilters
                                        ? constraints.maxWidth - 24
                                        : 180,
                                    options: adminUserFilterPlanLightOptions(
                                        _partnershipPlansCatalog),
                                    onChanged: (v) =>
                                        _onUserManualFilterChanged(() {
                                      _userFilterPlan = v ?? 'todos';
                                      if (_userFilterPlan != 'todos') {
                                        _userFilterComConvenio = false;
                                      }
                                    }),
                                  ),
                                  _filterDropdown<String>(
                                    value: _userFilterVencimento,
                                    label: 'Vencimento',
                                    minWidth: narrowFilters
                                        ? constraints.maxWidth - 24
                                        : 180,
                                    options: const [
                                      LightFilterOption(
                                          value: 'todos', label: 'Todos'),
                                      LightFilterOption(
                                          value: 'ativa',
                                          label: 'Licença ativa'),
                                      LightFilterOption(
                                          value: 'vence_7',
                                          label: 'Vence em 7 dias'),
                                      LightFilterOption(
                                          value: 'vence_15',
                                          label: 'Vence em 15 dias'),
                                      LightFilterOption(
                                          value: 'vence_30',
                                          label: 'Vence em 30 dias'),
                                      LightFilterOption(
                                          value: 'vencida',
                                          label: 'Já vencida'),
                                    ],
                                    onChanged: (v) =>
                                        _onUserManualFilterChanged(() =>
                                            _userFilterVencimento =
                                                v ?? 'todos'),
                                  ),
                                  _filterDropdown<String>(
                                    value: _userSortOrder,
                                    label: 'Ordenar por',
                                    minWidth: narrowFilters
                                        ? constraints.maxWidth - 24
                                        : 160,
                                    options: const [
                                      LightFilterOption(
                                          value: 'nome', label: 'Nome'),
                                      LightFilterOption(
                                          value: 'vencimento',
                                          label: 'Vencimento'),
                                      LightFilterOption(
                                          value: 'plano', label: 'Plano'),
                                      LightFilterOption(
                                          value: 'cadastro',
                                          label: 'Data de cadastro'),
                                    ],
                                    onChanged: (v) {
                                      if (_userFilterStatus == 'ultimos_10')
                                        return;
                                      _onUserManualFilterChanged(
                                          () => _userSortOrder = v ?? 'nome');
                                    },
                                  ),
                                  SizedBox(
                                    width: narrowFilters
                                        ? constraints.maxWidth - 24
                                        : 220,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('Data de cadastro',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600)),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: () =>
                                                    _pickUserCadastroDate(
                                                        isStart: true),
                                                icon: const Icon(
                                                    Icons
                                                        .calendar_month_rounded,
                                                    size: 16),
                                                label: Text(
                                                    _dateLabel(
                                                        _userFilterCadastroInicio,
                                                        fallback: 'De'),
                                                    style: const TextStyle(
                                                        fontSize: 12),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    maxLines: 1),
                                                style: OutlinedButton.styleFrom(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      vertical: 8,
                                                      horizontal: 8),
                                                  shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10)),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: () =>
                                                    _pickUserCadastroDate(
                                                        isStart: false),
                                                icon: const Icon(
                                                    Icons
                                                        .calendar_month_rounded,
                                                    size: 16),
                                                label: Text(
                                                    _dateLabel(
                                                        _userFilterCadastroFim,
                                                        fallback: 'Até'),
                                                    style: const TextStyle(
                                                        fontSize: 12),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    maxLines: 1),
                                                style: OutlinedButton.styleFrom(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      vertical: 8,
                                                      horizontal: 8),
                                                  shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10)),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (_userFilterCadastroInicio != null ||
                                            _userFilterCadastroFim != null)
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: TextButton(
                                              onPressed: () =>
                                                  _onUserManualFilterChanged(
                                                      () {
                                                _userFilterCadastroInicio =
                                                    null;
                                                _userFilterCadastroFim = null;
                                              }),
                                              child: const Text(
                                                  'Limpar período',
                                                  style:
                                                      TextStyle(fontSize: 11)),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (_userFilterStatus == 'ultimos_10') ...[
                                const SizedBox(height: 10),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.person_add_alt_1_rounded,
                                        size: 20,
                                        color: AppColors.primary,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Exibindo sempre os $_ultimosCadastrosLimit cadastros '
                                          'mais recentes (respeita busca e demais filtros).',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey.shade800,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              _buildExportCsvButton(),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _usersListStream,
            builder: (context, snap) {
              if (_usersListStream == null) {
                return _usersListStateSliver(
                  child: const SkeletonListLoader(itemCount: 5, itemHeight: 72),
                );
              }
              if (snap.hasError) {
                return _usersListStateSliver(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline_rounded,
                            size: 40, color: Colors.red.shade700),
                        const SizedBox(height: 10),
                        Text(
                          'Erro ao carregar usuários: ${snap.error}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade800),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => setState(() {
                            _usersListStreamBound = false;
                            _usersListStream = null;
                            _ensureUsersListStream();
                          }),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return _usersListStateSliver(
                  child: const SkeletonListLoader(itemCount: 5, itemHeight: 72),
                );
              }
              if (!snap.hasData) {
                return _usersListStateSliver(
                  child: const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                );
              }
              final docs = snap.data!.docs;
              final filtered = _filterUserDocs(docs);
              _visibleFilteredUids = filtered.map((d) => d.id).toList();
              final atLimit = docs.length >= _usersListLimit;
              if (filtered.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 4))
                        ],
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_outline_rounded,
                                size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              docs.isEmpty
                                  ? 'Nenhum usuário.'
                                  : 'Nenhum usuário corresponde aos filtros.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 14, color: Colors.grey.shade600),
                            ),
                            if (!docs.isEmpty) ...[
                              const SizedBox(height: 16),
                              TextButton.icon(
                                icon: const Icon(Icons.clear_all_rounded,
                                    size: 18),
                                label: const Text('Limpar filtros'),
                                onPressed: _clearUserFilters,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }
              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Exibindo ${filtered.length} usuário(s)',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700),
                            ),
                            if (atLimit)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'Mostrando até $_usersListLimit usuários. Use os filtros ou Exportar CSV para ver todos.',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600),
                                ),
                              ),
                          ],
                        ),
                      );
                    }
                    final doc = filtered[index - 1];
                    return RepaintBoundary(
                      child: Padding(
                        padding: EdgeInsets.only(
                            bottom: index - 1 == filtered.length - 1 ? 0 : 10),
                        child: _buildUserCard(
                          doc,
                          brandBlue,
                          brandTeal,
                          canEdit: canEdit,
                        ),
                      ),
                    );
                  },
                  childCount: 1 + filtered.length,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: false,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _filterDropdown<T>({
    required T value,
    required String label,
    double minWidth = 180,
    required List<LightFilterOption<T>> options,
    required ValueChanged<T?> onChanged,
  }) {
    return RepaintBoundary(
      child: LightFilterPicker<T>(
        value: value,
        label: label,
        minWidth: minWidth,
        options: options,
        onChanged: (v) => onChanged(v),
      ),
    );
  }

  Widget _buildExportCsvButton() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        TextButton.icon(
          icon: const Icon(Icons.download_rounded, size: 20),
          label: const Text('Exportar usuários (CSV)'),
          onPressed: () => _exportUsersCsv(),
        ),
        TextButton.icon(
          icon: const Icon(Icons.schedule_send_rounded, size: 20),
          label: const Text('Exportação programada'),
          onPressed: _openScheduledExportPrefs,
        ),
        TextButton.icon(
          icon: const Icon(Icons.upload_file_rounded, size: 20),
          label: const Text('Importar ASSEGO (CSV)'),
          onPressed: () => _importAssegoCsv(),
        ),
        TextButton.icon(
          icon: const Icon(Icons.autorenew_rounded, size: 20),
          label: const Text('Prorrogar ASSEGO +1 ano'),
          onPressed: () => _renewAssegoLicenses(),
        ),
      ],
    );
  }

  List<String> _extractEmailsFromCsv(String raw) {
    final lines = const LineSplitter().convert(raw);
    final emails = <String>{};
    final rx = RegExp(
      r'[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}',
      caseSensitive: false,
    );
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final matches = rx.allMatches(trimmed);
      for (final m in matches) {
        final email = (m.group(0) ?? '').trim().toLowerCase();
        if (email.isNotEmpty) emails.add(email);
      }
    }
    return emails.toList()..sort();
  }

  Future<void> _importAssegoCsv() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'txt'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Arquivo vazio ou inválido.')),
        );
        return;
      }
      final content = utf8.decode(bytes, allowMalformed: true);
      final emails = _extractEmailsFromCsv(content);
      if (emails.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Nenhum e-mail válido encontrado no CSV.')),
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Importando ${emails.length} e-mail(s) ASSEGO...')),
      );
      final res = await FunctionsService().upsertAssegoMembers(emails: emails);
      if (!mounted) return;
      final imported = (res['imported'] ?? 0).toString();
      final updatedUsers = (res['updatedUsers'] ?? 0).toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'ASSEGO: $imported e-mail(s) importado(s), $updatedUsers usuário(s) atualizado(s) com licença anual.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
      setState(() => _userFilterPlan = 'premium_assego');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Erro ao importar CSV ASSEGO: $e'),
            backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _renewAssegoLicenses() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Prorrogar licenças ASSEGO'),
        content: const Text(
          'Deseja prorrogar automaticamente +1 ano para todos os usuários premium_assego?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Prorrogar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final res = await FunctionsService().renewAssegoLicenses();
      if (!mounted) return;
      final renewed = (res['renewed'] ?? 0).toString();
      final total = (res['total'] ?? 0).toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'ASSEGO: $renewed/$total licença(s) prorrogada(s) em +1 ano.'),
          backgroundColor: AppColors.success,
        ),
      );
      setState(() => _userFilterPlan = 'premium_assego');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Erro ao prorrogar ASSEGO: $e'),
            backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _exportUsersCsv({List<String>? onlyUids}) async {
    try {
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
      if (onlyUids != null && onlyUids.isNotEmpty) {
        final rows = <String>['nome;email;plano;vencimento_licenca'];
        for (final uid in onlyUids.take(100)) {
          final snap = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();
          if (!snap.exists) continue;
          final d = snap.data() ?? {};
          final name = (d['name'] ?? '').toString().replaceAll(';', ',');
          final email = (d['email'] ?? '').toString().replaceAll(';', ',');
          final plan = (d['plan'] ?? 'free').toString().replaceAll(';', ',');
          final exp = d['licenseExpiresAt'] is Timestamp
              ? DateFormat('dd/MM/yyyy')
                  .format((d['licenseExpiresAt'] as Timestamp).toDate())
              : '';
          rows.add('$name;$email;$plan;$exp');
        }
        final csv = rows.join('\n');
        final filename =
            'usuarios_lote_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';
        final ok = await saveUserExportCsv(filename, csv);
        if (!mounted) return;
        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Exportação cancelada.')),
          );
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${rows.length - 1} utilizador(es) exportado(s).'),
          ),
        );
        return;
      } else {
        Query<Map<String, dynamic>> q =
            FirebaseFirestore.instance.collection('users');
        if (widget.useUnifiedPanel) q = q.where('app', isEqualTo: _selectedApp);
        const csvLimit = 5000;
        final snap = await q.limit(csvLimit).get();
        docs = snap.docs;
        if (snap.docs.length >= csvLimit && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Exportados até 5.000 usuários. Use os filtros (app/plan) para refinar.')),
          );
        }
      }
      final filtered = _filterUserDocs(docs);
      final rows = <String>[
        'nome;email;plano;vencimento_licenca',
      ];
      for (final doc in filtered) {
        final d = doc.data();
        final name = (d['name'] ?? '').toString().replaceAll(';', ',');
        final email = (d['email'] ?? '').toString().replaceAll(';', ',');
        final plan = (d['plan'] ?? 'free').toString().replaceAll(';', ',');
        final exp = d['licenseExpiresAt'] is Timestamp
            ? DateFormat('dd/MM/yyyy')
                .format((d['licenseExpiresAt'] as Timestamp).toDate())
            : '';
        rows.add('$name;$email;$plan;$exp');
      }
      final csv = rows.join('\n');
      final filename =
          'usuarios_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';
      final ok = await saveUserExportCsv(filename, csv);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exportação cancelada.')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${filtered.length} usuário(s) no CSV. Salve na pasta desejada (Downloads / computador).',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao exportar: $e')));
      }
    }
  }

  bool _userDocMatchesPlanFilter(String planRaw) {
    if (_userFilterPlan == 'todos') return true;
    final plan = planRaw.trim().toLowerCase();
    if (_userFilterPlan == 'free') {
      return plan.isEmpty || plan == 'free';
    }
    if (_userFilterPlan == 'premium') {
      return plan == 'premium' ||
          plan == 'premium_monthly' ||
          plan == 'premium_annual' ||
          UserProfile.planIndicatesPremiumPro(plan);
    }
    return adminUserPlanDropdownValue(planRaw) == _userFilterPlan;
  }

  Widget _usersListStateSliver({required Widget child}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        child: child,
      ),
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterUserDocs(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final now = DateTime.now();
    final query = _userSearchCtrl.text.trim();
    var list = docs.where((doc) {
      final d = doc.data();
      if (!adminUserHasCompleteEmail(d)) return false;
      if (query.isNotEmpty && !adminUserMatchesSearch(d, doc.id, query)) {
        return false;
      }
      final plan = (d['plan'] ?? 'free').toString().toLowerCase();
      final licenseExpiresAt = d['licenseExpiresAt'] is Timestamp
          ? (d['licenseExpiresAt'] as Timestamp).toDate()
          : null;
      final removedByAdminAt = d['removedByAdminAt'];
      final isRemoved = removedByAdminAt != null;
      final isExpired = UserProfile.isLicenseExpiredByDate(licenseExpiresAt);
      final hasActiveLicense = licenseExpiresAt != null &&
          !UserProfile.isLicenseExpiredByDate(licenseExpiresAt);
      final expDay = licenseExpiresAt != null
          ? DateTime(licenseExpiresAt.year, licenseExpiresAt.month,
              licenseExpiresAt.day)
          : null;
      final todayDate = DateTime(now.year, now.month, now.day);
      final daysLeft =
          expDay != null ? expDay.difference(todayDate).inDays : null;

      if (_userFilterStatus != 'ultimos_10') {
        if (_userFilterStatus == 'ativos' && (!hasActiveLicense || isRemoved)) {
          return false;
        }
        if (_userFilterStatus == 'vencidos' && (!isExpired || isRemoved)) {
          return false;
        }
        if (_userFilterStatus == 'removidos' && !isRemoved) return false;
      }

      if (!_userDocMatchesPlanFilter(plan)) {
        return false;
      }

      if (_userFilterComConvenio &&
          (d['partnershipId'] ?? '').toString().trim().isEmpty) {
        return false;
      }

      if (_userFilterVencimento != 'todos') {
        if (_userFilterVencimento == 'ativa' && !hasActiveLicense) return false;
        if (_userFilterVencimento == 'vence_7' &&
            (daysLeft == null || daysLeft > 7 || daysLeft < 0)) return false;
        if (_userFilterVencimento == 'vence_15' &&
            (daysLeft == null || daysLeft > 15 || daysLeft < 0)) return false;
        if (_userFilterVencimento == 'vence_30' &&
            (daysLeft == null || daysLeft > 30 || daysLeft < 0)) return false;
        if (_userFilterVencimento == 'vencida' && !isExpired) return false;
      }
      if (_userFilterCadastroInicio != null || _userFilterCadastroFim != null) {
        if (!_docMatchesCadastroPeriodo(d,
            inicio: _userFilterCadastroInicio,
            fim: _userFilterCadastroFim)) return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      final da = a.data();
      final db = b.data();
      switch (_userSortOrder) {
        case 'cadastro':
          final ca = _userDocCreatedAt(da);
          final cb = _userDocCreatedAt(db);
          if (ca == null && cb == null) {
            return (da['name'] ?? da['email'] ?? '')
                .toString()
                .compareTo((db['name'] ?? db['email'] ?? '').toString());
          }
          if (ca == null) return 1;
          if (cb == null) return -1;
          return cb.compareTo(ca);
        case 'vencimento':
          final expA = da['licenseExpiresAt'] is Timestamp
              ? (da['licenseExpiresAt'] as Timestamp).toDate()
              : null;
          final expB = db['licenseExpiresAt'] is Timestamp
              ? (db['licenseExpiresAt'] as Timestamp).toDate()
              : null;
          if (expA == null && expB == null)
            return (da['name'] ?? da['email'] ?? '')
                .toString()
                .compareTo((db['name'] ?? db['email'] ?? '').toString());
          if (expA == null) return 1;
          if (expB == null) return -1;
          return expA.compareTo(expB);
        case 'plano':
          final pa = (da['plan'] ?? 'free').toString();
          final pb = (db['plan'] ?? 'free').toString();
          final cmp = pa.compareTo(pb);
          if (cmp != 0) return cmp;
          return (da['name'] ?? da['email'] ?? '')
              .toString()
              .compareTo((db['name'] ?? db['email'] ?? '').toString());
        case 'nome':
        default:
          final na = (da['name'] ?? da['email'] ?? '').toString().toLowerCase();
          final nb = (db['name'] ?? db['email'] ?? '').toString().toLowerCase();
          return na.compareTo(nb);
      }
    });

    if (_userFilterStatus == 'ultimos_10') {
      list.sort((a, b) {
        final ca = _userDocCreatedAt(a.data());
        final cb = _userDocCreatedAt(b.data());
        if (ca == null && cb == null) return 0;
        if (ca == null) return 1;
        if (cb == null) return -1;
        return cb.compareTo(ca);
      });
      if (list.length > _ultimosCadastrosLimit) {
        list = list.sublist(0, _ultimosCadastrosLimit);
      }
    }
    return list;
  }

  /// Dropdown Admin: limite de conexões Open Finance inclusas por utilizador (`premiumProIncludedBankConnections`).
  Widget _openFinanceIncludedSlotsDropdown({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required String uid,
    required String name,
    required String email,
    required String plan,
    required int? proSlotsAdmin,
    required bool compact,
  }) {
    // Open Finance / PRO descontinuado no app.
    return const SizedBox.shrink();
  }

  /// Atualiza `plan` e, para convênios `premium_*`, preenche `partnershipId` / `partnershipName`.
  Future<void> _adminApplyUserPlanChange({
    required DocumentReference<Map<String, dynamic>> ref,
    required String uid,
    required String name,
    required String email,
    required String currentPlan,
    required String currentPartnershipId,
    required String currentPartnershipName,
    required String newPlan,
  }) async {
    await AdminUserPlanApplyService.apply(
      ref: ref,
      uid: uid,
      name: name,
      email: email,
      currentPlan: currentPlan,
      currentPartnershipId: currentPartnershipId,
      currentPartnershipName: currentPartnershipName,
      newPlan: newPlan,
      conveniosCatalog: _partnershipPlansCatalog,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Plano alterado para ${UserProfile.planDisplayLabelForFirestorePlan(newPlan.trim().toLowerCase())}.',
          ),
        ),
      );
    }
  }

  List<Widget> _userCardStatusIcons({
    required bool isExpiredCard,
    required bool hasActiveLicense,
    required String plan,
    required String partnershipId,
    required String? platformRaw,
  }) {
    final icons = <Widget>[];
    if (isExpiredCard) {
      icons.add(_statusIconChip(
          Icons.event_busy_rounded, Colors.red.shade700, 'Vencida'));
    } else if (hasActiveLicense) {
      icons.add(_statusIconChip(
          Icons.verified_rounded, Colors.green.shade700, 'Ativa'));
    }
    if (plan.contains('premium')) {
      icons.add(_statusIconChip(
          Icons.star_rounded, Colors.amber.shade800, 'Premium'));
    }
    if (partnershipId.isNotEmpty) {
      icons.add(_statusIconChip(
          Icons.handshake_rounded, Colors.indigo.shade700, 'Convênio'));
    }
    final p = (platformRaw ?? '').toLowerCase();
    if (p.contains('android')) {
      icons.add(_statusIconChip(
          Icons.android_rounded, Colors.green.shade600, 'Android'));
    } else if (p.contains('ios') || p.contains('iphone')) {
      icons.add(_statusIconChip(
          Icons.phone_iphone_rounded, Colors.grey.shade800, 'iOS'));
    } else if (p.contains('web')) {
      icons.add(
          _statusIconChip(Icons.language_rounded, AppColors.primary, 'Web'));
    }
    return icons;
  }

  Widget _statusIconChip(IconData icon, Color color, String tip) {
    return Tooltip(
      message: tip,
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }

  /// Iniciais (1–2 letras) para o avatar moderno do usuário.
  String _adminUserInitials(String name, String email) {
    final base = name.trim().isNotEmpty ? name.trim() : email.trim();
    if (base.isEmpty) return '?';
    final parts =
        base.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return base.substring(0, 1).toUpperCase();
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  /// Avatar moderno: gradiente na cor do status + iniciais (substitui o ícone cinza).
  Widget _buildAdminUserAvatar(String name, String email, Color statusColor) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            statusColor.withValues(alpha: 0.92),
            statusColor.withValues(alpha: 0.62),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.28),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        _adminUserInitials(name, email),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 16,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildUserCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    Color brandBlue,
    Color brandTeal, {
    bool canEdit = true,
  }) {
    final d = doc.data();
    final uid = doc.id;
    final name = adminUserDisplayName(d);
    final email = (d['email'] ?? '').toString();
    final plan = (d['plan'] ?? 'free').toString().toLowerCase();
    final proSlotsAdmin = PremiumProLimits.parseAdminIncludedSlotsOverride(
        d['premiumProIncludedBankConnections']);
    final role = (d['role'] ?? 'user').toString().toLowerCase();
    final licenseExpiresAt = d['licenseExpiresAt'] is Timestamp
        ? (d['licenseExpiresAt'] as Timestamp).toDate()
        : null;
    final removedByAdminAt = d['removedByAdminAt'];
    final isRemoved = removedByAdminAt != null;
    final now = DateTime.now();
    final isExpiredCard = UserProfile.isLicenseExpiredByDate(licenseExpiresAt);
    final hasActiveLicense = licenseExpiresAt != null &&
        !UserProfile.isLicenseExpiredByDate(licenseExpiresAt);
    final expDay = licenseExpiresAt != null
        ? DateTime(
            licenseExpiresAt.year, licenseExpiresAt.month, licenseExpiresAt.day)
        : null;
    final todayDate = DateTime(now.year, now.month, now.day);
    final daysLeft =
        expDay != null ? expDay.difference(todayDate).inDays : null;

    String validadeStr;
    String statusLabel;
    Color statusColor;
    if (isRemoved) {
      validadeStr = 'Removido pelo admin';
      statusLabel = 'Removido';
      statusColor = Colors.grey;
    } else if (licenseExpiresAt == null) {
      validadeStr = plan == 'free' ? 'Sem licença' : '—';
      statusLabel = plan == 'free' ? 'Free' : '—';
      statusColor = Colors.grey;
    } else if (isExpiredCard) {
      validadeStr =
          'Vencimento: ${DateFormat('dd/MM/yyyy').format(licenseExpiresAt)}';
      statusLabel = 'Vencida';
      statusColor = AppColors.error;
    } else {
      validadeStr =
          'Vencimento: ${DateFormat('dd/MM/yyyy').format(licenseExpiresAt)}';
      if (daysLeft != null && daysLeft <= 7) {
        statusLabel = 'Vence em ${daysLeft}d';
        statusColor = Colors.orange;
      } else {
        statusLabel = 'Ativa';
        statusColor = AppColors.success;
      }
    }

    final partnershipId = (d['partnershipId'] ?? '').toString().trim();
    final partnershipName = (d['partnershipName'] ?? '').toString().trim();
    final tel = d['clientTelemetry'];
    String? platformRaw;
    if (tel is Map) {
      platformRaw = (tel['platform'] ?? tel['os'] ?? '').toString();
    }
    final statusIcons = _userCardStatusIcons(
      isExpiredCard: isExpiredCard,
      hasActiveLicense: hasActiveLicense,
      plan: plan,
      partnershipId: partnershipId,
      platformRaw: platformRaw,
    );
    final canDelete = _canDeletePermanent;
    final canRemove = _canRemoveUser;
    final rawDelegate =
        (d['authorizedDelegateEmail'] ?? '').toString().trim().toLowerCase();
    final authorizedDelegateEmail = rawDelegate.isEmpty ? null : rawDelegate;
    final planLabel = UserProfile.planDisplayLabelForFirestorePlan(plan);
    final narrow = _isAdminMobile(context);
    final isSelf = uid == widget.uid;

    Future<void> alterarPerfil(String newRole) async {
      if (newRole == role) return;
      final beforeMap = <String, dynamic>{'role': role};
      final afterMap = <String, dynamic>{'role': newRole};
      await doc.reference
          .update({'role': newRole, 'updatedAt': FieldValue.serverTimestamp()});
      await AdminAuditService().logAdminAction(
          action: 'alterar_perfil',
          targetUserId: uid,
          targetUserEmail: email.isNotEmpty ? email : null,
          before: beforeMap,
          after: afterMap);
      await LogsService().saveLog(
          modulo: 'Admin',
          acao: 'Alterou perfil de usuário',
          detalhes: '${name.isEmpty ? uid : name} → $newRole');
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Perfil alterado para $newRole. ${newRole == 'admin' || newRole == 'master' ? 'Usuário terá acesso ao painel admin.' : 'Usuário não terá acesso ao painel admin.'}')));
    }

    Future<void> editVencimento() async {
      final picked = await showDatePicker(
        context: context,
        initialDate:
            licenseExpiresAt ?? DateTime.now().add(const Duration(days: 30)),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (picked == null || !context.mounted) return;
      final endOfDay =
          DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      final graceEnd = endOfDay.add(const Duration(days: 3));
      final before = licenseExpiresAt != null
          ? <String, dynamic>{
              'licenseExpiresAt': licenseExpiresAt.toIso8601String()
            }
          : <String, dynamic>{};
      final after = <String, dynamic>{
        'licenseExpiresAt': endOfDay.toIso8601String()
      };
      await doc.reference.update({
        'licenseExpiresAt': Timestamp.fromDate(endOfDay),
        'licenseValidUntilIncludingGrace': Timestamp.fromDate(graceEnd),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await AdminAuditService().logAdminAction(
        action: alterarVencimento,
        targetUserId: uid,
        targetUserEmail: email.isNotEmpty ? email : null,
        before: before,
        after: after,
        details:
            '${name.isEmpty ? uid : name} → ${DateFormat('dd/MM/yyyy').format(picked)}',
      );
      await LogsService().saveLog(
          modulo: 'Admin',
          acao: 'Alterou data de vencimento da licença',
          detalhes:
              '${name.isEmpty ? uid : name} → ${DateFormat('dd/MM/yyyy').format(picked)}');
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Vencimento alterado para ${DateFormat('dd/MM/yyyy').format(picked)}.')));
    }

    Future<void> auditDelegateEmail(
        String action, String? delegateEmail) async {
      await AdminAuditService().logAdminAction(
        action: action,
        targetUserId: uid,
        targetUserEmail: email.isNotEmpty ? email : null,
        details:
            '${name.isEmpty ? uid : name} · sub-login ${delegateEmail ?? "(removido)"}',
      );
    }

    void open360() => openAdminUser360Preview(
          context,
          uid: uid,
          displayName: name,
          email: email,
          canEdit: canEdit,
        );

    Widget build360Button({bool iconOnly = false}) {
      if (iconOnly) {
        return Tooltip(
          message: 'WISDOMAPP 360° — uso, plano, convênio e pagamentos',
          child: IconButton.filled(
            onPressed: open360,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.deepBlue,
              foregroundColor: Colors.white,
              minimumSize: const Size(44, 44),
            ),
            icon: const Icon(Icons.visibility_rounded, size: 22),
          ),
        );
      }
      return Tooltip(
        message: 'Visão 360° — uso, plano, convênio e pagamentos',
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.deepBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: open360,
          icon: const Icon(Icons.visibility_rounded, size: 20),
          label: const Text(
            '360°',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isRemoved ? Colors.grey.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(18),
        // Faixa de status à esquerda + borda sutil = visual mais moderno e legível.
        border: Border(
          left:
              BorderSide(color: statusColor.withValues(alpha: 0.85), width: 5),
          top: BorderSide(
              color: isRemoved ? Colors.grey.shade300 : Colors.grey.shade200),
          right: BorderSide(
              color: isRemoved ? Colors.grey.shade300 : Colors.grey.shade200),
          bottom: BorderSide(
              color: isRemoved ? Colors.grey.shade300 : Colors.grey.shade200),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding:
            EdgeInsets.symmetric(horizontal: 14, vertical: narrow ? 14 : 10),
        child: narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (_bulkSelectMode)
                        AdminBulkSelectCheckbox(
                          selected: _bulkSelectedUids.contains(uid),
                          enabled: true,
                          onChanged: (v) => setState(() {
                            if (v) {
                              _bulkSelectedUids.add(uid);
                            } else {
                              _bulkSelectedUids.remove(uid);
                            }
                          }),
                        ),
                      _buildAdminUserAvatar(name, email, statusColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                    child: Text(name.isEmpty ? 'Usuário' : name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700),
                                        overflow: TextOverflow.ellipsis)),
                                ...statusIcons,
                                if (role == 'admin' || role == 'master')
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6)),
                                    child: Text(
                                        role == 'admin' ? 'Admin' : 'Master',
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary)),
                                  ),
                              ],
                            ),
                            Text(email,
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600),
                                overflow: TextOverflow.ellipsis),
                            AdminDelegateEmailSection(
                              principalUid: uid,
                              principalEmail: email,
                              authorizedEmail: authorizedDelegateEmail,
                              onAudit: auditDelegateEmail,
                            ),
                            if (partnershipId.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Chip(
                                    avatar: Icon(Icons.handshake_rounded,
                                        size: 16,
                                        color: Colors.indigo.shade800),
                                    label: Text(
                                      partnershipName.isNotEmpty
                                          ? 'Convênio: $partnershipName ($partnershipId)'
                                          : 'Convênio: $partnershipId',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    backgroundColor: Colors.indigo.shade50,
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ),
                            Row(
                              children: [
                                Expanded(
                                    child: Text('$planLabel • $validadeStr',
                                        style: TextStyle(
                                            fontSize: 11, color: brandTeal))),
                                if (!isRemoved)
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.primary,
                                      side: BorderSide(
                                          color: AppColors.primary
                                              .withValues(alpha: 0.6)),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      minimumSize: const Size(0, 28),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                    ),
                                    onPressed: editVencimento,
                                    icon: const Icon(
                                        Icons.edit_calendar_rounded,
                                        size: 16),
                                    label: const Text('Editar venc.',
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8)),
                              child: Text(statusLabel,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: statusColor)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      build360Button(),
                      if (!isRemoved && plan != 'free')
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.date_range, size: 18),
                          label: const Text('+15 dias'),
                          onPressed: () async {
                            final beforeMap = licenseExpiresAt != null
                                ? <String, dynamic>{
                                    'licenseExpiresAt':
                                        licenseExpiresAt.toIso8601String()
                                  }
                                : <String, dynamic>{};
                            await BillingService().prorrogarPrazo(uid, 15);
                            await AdminAuditService().logAdminAction(
                                action: prorrogarPrazo,
                                targetUserId: uid,
                                targetUserEmail:
                                    email.isNotEmpty ? email : null,
                                before: beforeMap,
                                details: '+15 dias');
                            await LogsService().saveLog(
                                modulo: 'Admin',
                                acao: 'Prorrogou prazo 15 dias',
                                detalhes: name.isEmpty ? uid : name);
                            if (context.mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Prazo prorrogado em 15 dias.')));
                          },
                        ),
                      if (!isRemoved) ...[
                        DropdownButton<String>(
                          value: role == 'admin'
                              ? 'admin'
                              : (role == 'master' ? 'master' : 'user'),
                          isExpanded: false,
                          hint: const Text('Perfil',
                              style: TextStyle(fontSize: 11)),
                          items: const [
                            DropdownMenuItem(
                                value: 'user', child: Text('Usuário')),
                            DropdownMenuItem(
                                value: 'admin', child: Text('Admin')),
                            DropdownMenuItem(
                                value: 'master', child: Text('Master')),
                          ],
                          onChanged: (String? newRole) async {
                            if (newRole == null) return;
                            await alterarPerfil(newRole);
                          },
                        ),
                        DropdownButton<String>(
                          value: adminUserPlanDropdownValue(plan),
                          isExpanded: false,
                          items: adminUserPlanDropdownItems(
                            currentPlan: plan,
                            convenios: _partnershipPlansCatalog,
                          ),
                          onChanged: (String? newPlan) async {
                            if (newPlan == null) return;
                            await _adminApplyUserPlanChange(
                              ref: doc.reference,
                              uid: uid,
                              name: name,
                              email: email,
                              currentPlan: plan,
                              currentPartnershipId: partnershipId,
                              currentPartnershipName: partnershipName,
                              newPlan: newPlan,
                            );
                          },
                        ),
                        _openFinanceIncludedSlotsDropdown(
                          doc: doc,
                          uid: uid,
                          name: name,
                          email: email,
                          plan: plan,
                          proSlotsAdmin: proSlotsAdmin,
                          compact: true,
                        ),
                      ],
                      if (isRemoved)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.person_add_rounded, size: 18),
                          label: const Text('Reativar'),
                          onPressed: () async {
                            await BillingService().reativarUsuario(uid);
                            await AdminAuditService().logAdminAction(
                                action: reativarUsuario,
                                targetUserId: uid,
                                targetUserEmail:
                                    email.isNotEmpty ? email : null);
                            await LogsService().saveLog(
                                modulo: 'Admin',
                                acao: 'Reativou usuário',
                                detalhes: name.isEmpty ? uid : name);
                            if (context.mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Usuário reativado. Altere o plano para dar acesso.')));
                          },
                        ),
                      if (!isRemoved && canRemove)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.error,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          icon:
                              const Icon(Icons.person_remove_rounded, size: 18),
                          label: const Text('Remover'),
                          onPressed: () =>
                              _confirmRemoverUsuario(context, uid, name, email),
                        ),
                      if (!isSelf && canDelete)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.error,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.delete_forever_rounded,
                              size: 18),
                          label: const Text('Excluir total'),
                          onPressed: () => _confirmExcluirUsuarioTotal(
                              context, uid, name, email),
                        ),
                    ],
                  ),
                ],
              )
            : Row(
                children: [
                  _buildAdminUserAvatar(name, email, statusColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(name.isEmpty ? 'Usuário' : name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            if (role == 'admin' || role == 'master') ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6)),
                                child: Text(
                                    role == 'admin' ? 'Admin' : 'Master',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary)),
                              ),
                            ],
                          ],
                        ),
                        Text(email,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600)),
                        AdminDelegateEmailSection(
                          principalUid: uid,
                          principalEmail: email,
                          authorizedEmail: authorizedDelegateEmail,
                          onAudit: auditDelegateEmail,
                        ),
                        if (partnershipId.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 2),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Chip(
                                avatar: Icon(Icons.handshake_rounded,
                                    size: 16, color: Colors.indigo.shade800),
                                label: Text(
                                  partnershipName.isNotEmpty
                                      ? 'Convênio: $partnershipName ($partnershipId)'
                                      : 'Convênio: $partnershipId',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                backgroundColor: Colors.indigo.shade50,
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            Text('$planLabel • $validadeStr',
                                style:
                                    TextStyle(fontSize: 11, color: brandTeal)),
                            if (!isRemoved) ...[
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  side: BorderSide(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.6)),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  minimumSize: const Size(0, 28),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: editVencimento,
                                icon: const Icon(Icons.edit_calendar_rounded,
                                    size: 16),
                                label: const Text('Editar venc.',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(statusLabel,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor)),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: build360Button(iconOnly: true),
                  ),
                  if (!isRemoved && plan != 'free')
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.date_range, size: 18),
                        label: const Text('+15 dias'),
                        onPressed: () async {
                          final beforeMap = licenseExpiresAt != null
                              ? <String, dynamic>{
                                  'licenseExpiresAt':
                                      licenseExpiresAt.toIso8601String()
                                }
                              : <String, dynamic>{};
                          await BillingService().prorrogarPrazo(uid, 15);
                          await AdminAuditService().logAdminAction(
                              action: prorrogarPrazo,
                              targetUserId: uid,
                              targetUserEmail: email.isNotEmpty ? email : null,
                              before: beforeMap,
                              details: '+15 dias');
                          await LogsService().saveLog(
                              modulo: 'Admin',
                              acao: 'Prorrogou prazo 15 dias',
                              detalhes: name.isEmpty ? uid : name);
                          if (context.mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Prazo prorrogado em 15 dias.')));
                        },
                      ),
                    ),
                  if (!isRemoved) ...[
                    DropdownButton<String>(
                      value: role == 'admin'
                          ? 'admin'
                          : (role == 'master' ? 'master' : 'user'),
                      hint:
                          const Text('Perfil', style: TextStyle(fontSize: 11)),
                      items: const [
                        DropdownMenuItem(value: 'user', child: Text('Usuário')),
                        DropdownMenuItem(value: 'admin', child: Text('Admin')),
                        DropdownMenuItem(
                            value: 'master', child: Text('Master')),
                      ],
                      onChanged: (String? newRole) async {
                        if (newRole == null) return;
                        await alterarPerfil(newRole);
                      },
                    ),
                    DropdownButton<String>(
                      value: adminUserPlanDropdownValue(plan),
                      items: adminUserPlanDropdownItems(
                        currentPlan: plan,
                        convenios: _partnershipPlansCatalog,
                      ),
                      onChanged: (String? newPlan) async {
                        if (newPlan == null) return;
                        await _adminApplyUserPlanChange(
                          ref: doc.reference,
                          uid: uid,
                          name: name,
                          email: email,
                          currentPlan: plan,
                          currentPartnershipId: partnershipId,
                          currentPartnershipName: partnershipName,
                          newPlan: newPlan,
                        );
                      },
                    ),
                    _openFinanceIncludedSlotsDropdown(
                      doc: doc,
                      uid: uid,
                      name: name,
                      email: email,
                      plan: plan,
                      proSlotsAdmin: proSlotsAdmin,
                      compact: false,
                    ),
                  ],
                  if (isRemoved)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.person_add_rounded, size: 18),
                      label: const Text('Reativar'),
                      onPressed: () async {
                        await BillingService().reativarUsuario(uid);
                        await AdminAuditService().logAdminAction(
                            action: reativarUsuario,
                            targetUserId: uid,
                            targetUserEmail: email.isNotEmpty ? email : null);
                        await LogsService().saveLog(
                            modulo: 'Admin',
                            acao: 'Reativou usuário',
                            detalhes: name.isEmpty ? uid : name);
                        if (context.mounted)
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text(
                                  'Usuário reativado. Altere o plano para dar acesso.')));
                      },
                    ),
                  if (!isRemoved)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.person_remove_rounded, size: 18),
                      label: const Text('Remover'),
                      onPressed: () =>
                          _confirmRemoverUsuario(context, uid, name, email),
                    ),
                  if (!isSelf)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.delete_forever_rounded, size: 18),
                      label: const Text('Excluir total'),
                      onPressed: () => _confirmExcluirUsuarioTotal(
                          context, uid, name, email),
                    ),
                ],
              ),
      ),
    );
  }

  /// Texto para log/auditoria (nome + e-mail quando existirem).
  String _adminUserLogLabel(String name, String email, String uid) {
    final n = name.trim();
    final e = email.trim();
    if (n.isNotEmpty && e.isNotEmpty) return '$n • $e';
    if (n.isNotEmpty) return n;
    if (e.isNotEmpty) return e;
    return uid;
  }

  /// Corpo do diálogo: pergunta + dados do usuário (nome, e-mail, ID).
  Widget _adminConfirmUserBody({
    required String intro,
    required String name,
    required String email,
    required String uid,
  }) {
    final n = name.trim();
    final e = email.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(intro,
            style: TextStyle(
                fontSize: 14, color: Colors.grey.shade800, height: 1.35)),
        const SizedBox(height: 16),
        Text('Usuário',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade700)),
        const SizedBox(height: 8),
        if (n.isNotEmpty)
          Text('Nome: $n',
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        if (n.isEmpty)
          Text('Nome: (não informado)',
              style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade600)),
        const SizedBox(height: 6),
        if (e.isNotEmpty)
          SelectableText('E-mail: $e',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade800)),
        if (e.isEmpty)
          Text('E-mail: (não informado)',
              style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade600)),
        const SizedBox(height: 8),
        SelectableText(
          'ID: $uid',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Future<void> _confirmRemoverUsuario(
      BuildContext context, String uid, String name, String email) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Remover usuário?'),
        content: SingleChildScrollView(
          child: _adminConfirmUserBody(
            intro:
                'Tem certeza de que deseja remover este usuário? Ele perderá acesso ao app. Você pode reativar depois (filtro Removidos).',
            name: name,
            email: email,
            uid: uid,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final logLabel = _adminUserLogLabel(name, email, uid);
    await BillingService().removerUsuario(uid);
    await AdminAuditService().logAdminAction(
      action: removerUsuario,
      targetUserId: uid,
      targetUserEmail: email.trim().isNotEmpty ? email.trim() : null,
      details: logLabel,
    );
    await LogsService()
        .saveLog(modulo: 'Admin', acao: 'Removeu usuário', detalhes: logLabel);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Usuário removido. Ele pode ser reativado na lista (filtro Removidos).')),
      );
    }
  }

  Future<void> _confirmExcluirUsuarioTotal(
      BuildContext context, String targetUid, String name, String email) async {
    if (!_canDeletePermanent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Somente super admin pode excluir permanentemente.'),
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Excluir usuário permanentemente?'),
        content: SingleChildScrollView(
          child: _adminConfirmUserBody(
            intro: 'Deseja realmente remover este usuário de forma total? '
                'Esta ação apaga permanentemente o login e todos os dados '
                '(Firestore, Storage e Auth). Não pode ser desfeita.',
            name: name,
            email: email,
            uid: targetUid,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sim, excluir'),
          ),
        ],
      ),
    );

    if (ok != true || !context.mounted) return;
    final logLabel = _adminUserLogLabel(name, email, targetUid);
    try {
      // A exclusao total roda no servidor (Admin SDK: Firestore recursivo, Storage, Auth).
      // Timeout longo: muitos lançamentos/anexos podem demorar vários minutos.
      final callable = FirebaseFunctions.instance.httpsCallable(
        'ctDeleteUserTotal',
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 280),
        ),
      );
      await callable.call<Map<String, dynamic>>({'uid': targetUid});

      await AdminAuditService().logAdminAction(
        action: excluirUsuario,
        targetUserId: targetUid,
        targetUserEmail: email.trim().isNotEmpty ? email.trim() : null,
        details: '$logLabel (exclusão total)',
      );
      await LogsService().saveLog(
          modulo: 'Admin', acao: 'Excluiu usuário TOTAL', detalhes: logLabel);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Usuário excluído permanentemente.')));
      }
    } on FirebaseFunctionsException catch (e) {
      if (!context.mounted) return;
      final detail = e.message?.trim().isNotEmpty == true
          ? e.message!
          : (e.details?.toString() ?? e.code);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao excluir: $detail'),
          backgroundColor: AppColors.error,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Falha ao excluir total: ${e.toString().split('\n').first}'),
            backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _deleteUsersPermanentBulk(
    BuildContext context,
    List<Map<String, dynamic>> users,
  ) async {
    if (users.isEmpty) return;
    if (!_canDeletePermanent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Somente super admin pode excluir permanentemente.'),
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(
          users.length == 1
              ? 'Excluir usuário permanentemente?'
              : 'Excluir ${users.length} usuários permanentemente?',
        ),
        content: Text(
          users.length == 1
              ? 'Deseja realmente remover este usuário inativo de forma total? '
                  'Esta ação não pode ser desfeita.'
              : 'Deseja realmente remover os ${users.length} usuários selecionados de forma total? '
                  'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sim, excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
          content: Text('Iniciando exclusão de ${users.length} usuário(s)...')),
    );
    var success = 0;
    var fail = 0;
    for (final u in users) {
      final uid = (u['uid'] ?? '').toString().trim();
      if (uid.isEmpty) continue;
      try {
        final callable = FirebaseFunctions.instance.httpsCallable(
          'ctDeleteUserTotal',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 280)),
        );
        await callable.call<Map<String, dynamic>>({'uid': uid});
        success++;
      } catch (_) {
        fail++;
      }
    }
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('Exclusão concluída. Sucesso: $success • Falhas: $fail'),
        backgroundColor: fail == 0 ? AppColors.success : Colors.orange.shade700,
      ),
    );
    setState(() => _statsFuture = _loadStats(periodDays: _resumoPeriodDays));
  }

  bool _pushingVersion = false;
  bool _clearingForceUpdate = false;

  Future<void> _pushAppVersionToServer({required bool forceUpdate}) async {
    setState(() {
      if (forceUpdate) {
        _pushingVersion = true;
      } else {
        _clearingForceUpdate = true;
      }
    });
    try {
      final apkUrl = _apkDownloadUrlCtrl.text.trim();
      Future<Map<String, dynamic>> call() => FunctionsService().adminPushAppVersion(
            version: AppVersion.current,
            buildNumber: AppVersion.buildNumber,
            versionCode: AppVersion.versionCode,
            releaseTag: AppVersion.releaseTag,
            forceUpdate: forceUpdate,
            apkDownloadUrl: apkUrl.isNotEmpty ? apkUrl : null,
            testFlightUrl: VersionCheckService.defaultTestFlightPublicUrl,
          );

      final result = kIsWeb
          ? await FirestoreWebGuard.runWithWebRecovery(call)
          : await call();

      if (!mounted) return;
      if (result['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              forceUpdate
                  ? 'Release ${AppVersion.releaseTag} gravado. Usuários em build antigo verão aviso com link para atualizar.'
                  : 'Aviso de nova versão desativado (forceUpdate: false).',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        throw StateError((result['error'] ?? 'Falha ao gravar versão.').toString());
      }
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
      if (mounted) {
        setState(() {
          _pushingVersion = false;
          _clearingForceUpdate = false;
        });
      }
    }
  }

  /// Card no Resumo: gravar versão no Firestore e avisar usuários (faixa com link Play / TestFlight).
  Widget _buildForceUpdateCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.1),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 500;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.system_update_rounded,
                        color: AppColors.primary, size: 32),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Versão no servidor',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Gravar release ${AppVersion.releaseTag} (${AppVersion.internalLabel}) e avisar usuários em build antigo (faixa com link — Play Store no Android, TestFlight no iPhone). '
                            'O deploy publica o site mas não dispara aviso — só este botão. '
                            'Usuários já na versão atual não veem nada. Para cancelar avisos, use "Desativar aviso".',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FastTextField(
                  controller: _apkDownloadUrlCtrl,
                  textInputAction: TextInputAction.done,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: InputDecoration(
                    labelText: 'URL Google Play (opcional)',
                    hintText:
                        'https://play.google.com/store/apps/details?id=com.wisdomapp.app',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                ),
                const SizedBox(height: 8),
                Text(
                  'Android abre a Play Store ao atualizar. Não use link direto de APK.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                if (narrow) const SizedBox(height: 12),
                SizedBox(
                  width: narrow ? double.infinity : null,
                  child: FilledButton.icon(
                    onPressed: (_pushingVersion || _clearingForceUpdate)
                        ? null
                        : () => _pushAppVersionToServer(forceUpdate: true),
                    icon: _pushingVersion
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.cloud_upload_rounded, size: 20),
                    label: Text(_pushingVersion
                        ? 'Gravando...'
                        : 'Subir versão e avisar usuários'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: narrow ? double.infinity : null,
                  child: OutlinedButton.icon(
                    onPressed: (_pushingVersion || _clearingForceUpdate)
                        ? null
                        : () => _pushAppVersionToServer(forceUpdate: false),
                    icon: _clearingForceUpdate
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.notifications_off_outlined, size: 18),
                    label: Text(_clearingForceUpdate
                        ? 'Desativando...'
                        : 'Desativar aviso de versão'),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      scrollable: true,
                      title: Text('Release ${AppVersion.releaseTag}'),
                      content: const SingleChildScrollView(
                        child: Text(
                          'Melhorias contínuas: painel admin premium, filtros de período, alertas de licenças, relatórios e acessibilidade no iPhone e iPad.',
                          style: TextStyle(height: 1.4),
                        ),
                      ),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Fechar')),
                      ],
                    ),
                  ),
                  icon: const Icon(Icons.new_releases_rounded, size: 18),
                  label: const Text('Ver novidades'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildResumoPeriodFilter(Color brandBlue) {
    final isNarrow = MediaQuery.sizeOf(context).width < 400;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.date_range_rounded, size: 20, color: brandBlue),
          const SizedBox(width: 10),
          Text('Período:',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade800)),
          const SizedBox(width: 10),
          if (isNarrow)
            Expanded(
              child: LightFilterPicker<int>(
                value: _resumoPeriodDays,
                label: 'Período',
                options: const [
                  LightFilterOption(value: 7, label: 'Últimos 7 dias'),
                  LightFilterOption(value: 30, label: 'Últimos 30 dias'),
                  LightFilterOption(value: 90, label: 'Últimos 90 dias'),
                ],
                onChanged: (v) {
                  setState(() {
                    _resumoPeriodDays = v;
                    _overlayPartnershipMetrics = null;
                    _partnershipMetricsScheduled = false;
                    _statsFuture = _loadStats(periodDays: v);
                  });
                },
              ),
            )
          else
            Wrap(
              spacing: 8,
              children: [7, 30, 90].map((d) {
                final selected = _resumoPeriodDays == d;
                return ChoiceChip(
                  label: Text(d == 7
                      ? '7 dias'
                      : d == 30
                          ? '30 dias'
                          : '90 dias'),
                  selected: selected,
                  onSelected: (v) {
                    if (v)
                      setState(() {
                        _resumoPeriodDays = d;
                        _overlayPartnershipMetrics = null;
                        _partnershipMetricsScheduled = false;
                        _statsFuture = _loadStats(periodDays: d);
                      });
                  },
                  selectedColor: brandBlue.withValues(alpha: 0.2),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildResumoTab(Color brandBlue, Color brandTeal) {
    if (_isPartner) {
      return AdminPartnerResumoTab(
        brandBlue: brandBlue,
        brandTeal: brandTeal,
        onNavigate: (item) => _onAdminMenuSelected(item),
        onAlertNavigate: _navigateFromAlert,
        onStatsLoaded: (expired, exp7) {
          final total = expired + exp7;
          if (mounted && total != _alertCount) {
            setState(() => _alertCount = total);
          }
        },
      );
    }
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final horizontalPad = MediaQuery.sizeOf(context).width < 380 ? 12.0 : 16.0;
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _overlayPartnershipMetrics = null;
          _partnershipMetricsScheduled = false;
          _statsFuture = _loadStats(periodDays: _resumoPeriodDays);
        });
        final f = _statsFuture;
        if (f != null) await f;
        if (mounted) setState(() => _lastResumoUpdate = DateTime.now());
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(
            horizontalPad, 16, horizontalPad, 16 + bottomPad),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _AdminResumoHeader(brandBlue: brandBlue, brandTeal: brandTeal),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Versão: v${AppVersion.current} · ${AppVersion.internalLabel}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
              if (_lastResumoUpdate != null) ...[
                const SizedBox(width: 16),
                Text(
                    'Atualizado às ${DateFormat('HH:mm').format(_lastResumoUpdate!)}',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ],
          ),
          const SizedBox(height: 12),
          _buildResumoPeriodFilter(brandBlue),
          const SizedBox(height: 20),
          _buildForceUpdateCard(),
          const SizedBox(height: 20),
          _AdminResumoQuickActions(
            onRefresh: () async {
              setState(() {
                _overlayPartnershipMetrics = null;
                _partnershipMetricsScheduled = false;
                _statsFuture = _loadStats(periodDays: _resumoPeriodDays);
              });
              final f = _statsFuture;
              if (f != null) await f;
              if (mounted) setState(() => _lastResumoUpdate = DateTime.now());
            },
            onUsuarios: () =>
                setState(() => _selectedItem = AdminMenuItem.usuarios),
            onMercadoPago: () =>
                setState(() => _selectedItem = AdminMenuItem.mercadopago),
            lastUpdate: _lastResumoUpdate,
          ),
          const SizedBox(height: 24),
          if (_statsFuture == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SkeletonListLoader(itemCount: 6, itemHeight: 80),
            )
          else
            FutureBuilder<_AdminStats>(
              future: _statsFuture!,
              builder: (context, snap) {
                if (snap.hasData && mounted) {
                  final s = snap.data!;
                  _cachedResumoStats = s;
                  _schedulePartnershipMetricsOverlay();
                  final total = s.licensesExpiring7d + s.licensesExpired;
                  if (total != _alertCount) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _alertCount = total);
                    });
                  }
                  if (_lastResumoUpdate == null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted)
                        setState(() => _lastResumoUpdate = DateTime.now());
                    });
                  }
                }
                if (snap.hasError) {
                  return Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.orange.shade300),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.orange.withValues(alpha: 0.1),
                            blurRadius: 14,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline_rounded,
                            size: 48, color: Colors.orange.shade700),
                        const SizedBox(height: 12),
                        Text('Erro ao carregar: ${_formatAdminResumoError(snap.error!)}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.grey.shade700, fontSize: 13)),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _reloadResumoStats,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  );
                }
                if (snap.connectionState == ConnectionState.waiting ||
                    !snap.hasData) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: SkeletonListLoader(itemCount: 6, itemHeight: 80),
                  );
                }
                final stats = snap.data!;
                final partnershipMetrics = stats.partnershipMetrics.isNotEmpty
                    ? stats.partnershipMetrics
                    : (_overlayPartnershipMetrics ?? const []);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (stats.licensesExpiring7d > 0 ||
                        stats.licensesExpired > 0) ...[
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final narrow = constraints.maxWidth < 360;
                          final textColumn = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (stats.licensesExpired > 0)
                                Text(
                                    '${stats.licensesExpired} licença(s) vencida(s).',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        color: Colors.orange.shade900)),
                              if (stats.licensesExpiring7d > 0)
                                Text(
                                    '${stats.licensesExpiring7d} licença(s) vencendo em até 7 dias.',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: Colors.orange.shade800)),
                              const SizedBox(height: 6),
                              Text(
                                  'Acesse Usuários para prorrogar ou editar vencimento.',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange.shade700)),
                            ],
                          );
                          return Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.orange.shade300),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.orange.withValues(alpha: 0.12),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade100,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(Icons.warning_amber_rounded,
                                          color: Colors.orange.shade700,
                                          size: 28),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(child: textColumn),
                                    if (!narrow)
                                      FilledButton.tonalIcon(
                                        onPressed: () => setState(() =>
                                            _selectedItem =
                                                AdminMenuItem.usuarios),
                                        icon: const Icon(Icons.people_rounded,
                                            size: 18),
                                        label: const Text('Usuários'),
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              Colors.orange.shade100,
                                          foregroundColor:
                                              Colors.orange.shade900,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 10),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10)),
                                        ),
                                      ),
                                  ],
                                ),
                                if (narrow) ...[
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.tonalIcon(
                                      onPressed: () => setState(() =>
                                          _selectedItem =
                                              AdminMenuItem.usuarios),
                                      icon: const Icon(Icons.people_rounded,
                                          size: 18),
                                      label: const Text('Ir para Usuários'),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.orange.shade100,
                                        foregroundColor: Colors.orange.shade900,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 10),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    AdminAlertCenterPanel(
                      items: [
                        AdminAlertItem(
                          id: 'licencas_vencidas',
                          title: 'Licenças vencidas',
                          subtitle: 'Utilizadores com licença expirada',
                          icon: Icons.event_busy_rounded,
                          color: Colors.red.shade700,
                          count: stats.licensesExpired,
                        ),
                        AdminAlertItem(
                          id: 'licencas_vencendo_7',
                          title: 'Vencem em 7 dias',
                          subtitle: 'Renovar antes do bloqueio',
                          icon: Icons.schedule_rounded,
                          color: Colors.orange.shade800,
                          count: stats.licensesExpiring7d,
                        ),
                      ],
                      onNavigate: _navigateFromAlert,
                    ),
                    const SizedBox(height: 20),
                    AdminSystemHealthPanel(
                      totalUsers: stats.totalUsers,
                      txResumoAviso: stats.txResumoAviso,
                      latestTransactionAt: stats.latestTransactionAt,
                      latestUserCreatedAt: stats.latestUserCreatedAt,
                      usersEstimatedMb: stats.usersEstimatedMb,
                      txEstimatedMb: stats.txEstimatedMb,
                    ),
                    const SizedBox(height: 16),
                    AdminRevenueForecastPanel(
                      revenueRealizedMp: stats.revenue30d,
                      totalPremiums: stats.totalPremiums,
                      totalUsers: stats.totalUsers,
                      pixLiquido: stats.pixLiquido,
                      cardLiquido: stats.cardLiquido,
                    ),
                    const SizedBox(height: 20),
                    _AdminSectionTitle(
                        icon: Icons.people_rounded,
                        title: 'Indicadores da base'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _MetricCard(
                            label: 'Usuários',
                            value: '${stats.totalUsers}',
                            color: brandBlue,
                            icon: Icons.person_rounded),
                        _MetricCard(
                            label: 'Premium',
                            value: '${stats.totalPremiums}',
                            color: brandTeal,
                            icon: Icons.star_rounded),
                        ...partnershipMetrics.map(
                          (m) => _MetricCard(
                            label: 'Convênio ${m.partnershipName}',
                            value: '${m.userCount}',
                            subValue: 'Toque para ver e editar usuários',
                            color: brandBlue,
                            icon: Icons.handshake_rounded,
                            onTap: () => openPartnershipUsersPreview(
                              context,
                              partnershipId: m.partnershipDocId,
                              partnershipPlanCode: m.planCode,
                              partnershipName: m.partnershipName,
                            ),
                          ),
                        ),
                        _MetricCard(
                            label: 'Com convênio (vínculo)',
                            value: '${stats.totalUsersWithPartnership}',
                            subValue: 'Campo partnershipId preenchido',
                            color: const Color(0xFF6366F1),
                            icon: Icons.account_tree_rounded,
                            onTap: () => openPartnershipUsersPreview(
                                  context,
                                  scope: PartnershipUsersPreviewScope
                                      .allWithPartnershipLink,
                                  partnershipId: '__all__',
                                  partnershipPlanCode: '__all__',
                                  partnershipName: 'Todos',
                                )),
                        _MetricCard(
                            label: 'Admins',
                            value: '${stats.totalAdmins}',
                            color: brandTeal,
                            icon: Icons.admin_panel_settings_rounded),
                        _MetricCard(
                            label: 'Licenças vencidas',
                            value: '${stats.licensesExpired}',
                            subValue: 'Campo licenseExpiresAt antes de hoje',
                            color: const Color(0xFFEA580C),
                            icon: Icons.event_busy_rounded),
                        _MetricCard(
                            label: 'Licenças (≤7 dias)',
                            value: '${stats.licensesExpiring7d}',
                            subValue: 'Vencem na próxima semana',
                            color: const Color(0xFFF59E0B),
                            icon: Icons.schedule_rounded),
                        _MetricCard(
                            label: 'Transações (${_resumoPeriodDays}d)',
                            value: '${stats.txCount30d}',
                            color: brandBlue,
                            icon: Icons.receipt_long_rounded),
                        _MetricCard(
                            label: 'Volume (${_resumoPeriodDays}d)',
                            value: CurrencyFormats.formatBRL(stats.txValue30d),
                            subValue: stats.txResumoAviso,
                            color: brandTeal,
                            icon: Icons.trending_up_rounded),
                      ],
                    ),
                    if (stats.txResumoAviso != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        stats.txResumoAviso!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                          height: 1.3,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _AdminUserMonitoringPanel(
                      stats: stats,
                      periodoDias: _resumoPeriodDays,
                      brandBlue: brandBlue,
                      brandTeal: brandTeal,
                    ),
                    const SizedBox(height: 24),
                    _AdminInactiveUsersPanel(
                      useUnifiedPanel: widget.useUnifiedPanel,
                      selectedApp: _selectedApp,
                      onDeleteUsersPermanent: (users) =>
                          _deleteUsersPermanentBulk(context, users),
                    ),
                    const SizedBox(height: 24),
                    _AdminSectionTitle(
                        icon: Icons.payment_rounded,
                        title: 'Financeiro (Mercado Pago)'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _MetricCard(
                            label: 'PIX (Líquido MP)',
                            value: CurrencyFormats.formatBRL(stats.pixLiquido),
                            subValue:
                                'Bruto: ${CurrencyFormats.formatBRL(stats.pixBruto)}',
                            color: const Color(0xFF34D399),
                            icon: Icons.qr_code_2_rounded),
                        _MetricCard(
                            label: 'Cartão (Líquido MP)',
                            value: CurrencyFormats.formatBRL(stats.cardLiquido),
                            subValue:
                                'Bruto: ${CurrencyFormats.formatBRL(stats.cardBruto)}',
                            color: const Color(0xFFA78BFA),
                            icon: Icons.credit_card_rounded),
                        _MetricCard(
                            label: 'Lucro Total Real',
                            value: CurrencyFormats.formatBRL(
                                stats.pixLiquido + stats.cardLiquido),
                            subValue: 'Descontando todas as taxas',
                            color: brandBlue,
                            highlight: true,
                            icon: Icons.savings_rounded),
                        _MetricCard(
                          label: 'Conversão Premium',
                          value: '${stats.premiumMp}',
                          subValue:
                              '${stats.legacyMp + stats.premiumMp == 0 ? 0 : ((stats.premiumMp / (stats.legacyMp + stats.premiumMp)) * 100).round()}% da base',
                          color: const Color(0xFFFBBF24),
                          icon: Icons.percent_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _AdminSectionTitle(
                        icon: Icons.calendar_month_rounded,
                        title: 'Recebimentos (Mercado Pago — PIX/cartão)'),
                    const SizedBox(height: 12),
                    _RecebimentosResumoWidget(
                      brandBlue: brandBlue,
                      brandTeal: brandTeal,
                      resumoPeriodDays: _resumoPeriodDays,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'O período personalizado abaixo abre nos últimos $_resumoPeriodDays dias (mesmo filtro do resumo).',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    RepaintBoundary(
                      child: AdminMpRevenueLineChart(
                        title:
                            'Mercado Pago — bruto vs líquido ($_resumoPeriodDays dias)',
                        brutoBuckets: stats.mpRevenueBrutoByBucket,
                        liquidoBuckets: stats.mpRevenueLiquidoByBucket,
                        labels: stats.mpRevenueBucketLabels,
                        height: 240,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Horizonte de vencimento: contagem atual por faixa (próximos 90 dias; não é série histórica).',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    AppBarChart(
                      title: 'Licenças — vencimentos nos próximos 90 dias',
                      values: stats.licenseExpiryHorizonCounts
                          .map((e) => e.toDouble())
                          .toList(),
                      labels: stats.licenseExpiryHorizonLabels,
                      barColor: brandTeal,
                      height: 200,
                    ),
                    const SizedBox(height: 24),
                    _AdminSectionTitle(
                        icon: Icons.receipt_long_rounded,
                        title: 'Últimas transações'),
                    const SizedBox(height: 12),
                    _UltimasTransacoesTable(
                      payments: stats.lastPayments,
                      onVerTudo: () => setState(
                          () => _selectedItem = AdminMenuItem.mercadopago),
                      onRefresh: () => setState(() => _statsFuture =
                          _loadStats(periodDays: _resumoPeriodDays)),
                    ),
                    const SizedBox(height: 24),
                    _AdminSectionTitle(
                        icon: Icons.people_outline_rounded,
                        title: 'Últimos usuários'),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Cadastros recentes',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade600),
                                ),
                                TextButton.icon(
                                  onPressed: () => setState(() =>
                                      _selectedItem = AdminMenuItem.usuarios),
                                  icon: const Icon(Icons.arrow_forward_rounded,
                                      size: 18),
                                  label: const Text('Ver todos'),
                                  style: TextButton.styleFrom(
                                      foregroundColor: AppColors.primary),
                                ),
                              ],
                            ),
                          ),
                          ...stats.usersSample.map((u) {
                            final name = (u['name'] ?? '').toString();
                            final email = (u['email'] ?? '').toString();
                            final plan = (u['plan'] ?? '').toString();
                            return Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: AppColors.primary
                                        .withValues(alpha: 0.15),
                                    child: Text(
                                      (name.isNotEmpty ? name[0] : '?')
                                          .toUpperCase(),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.primary),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name.isEmpty ? 'Usuário' : name,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14),
                                        ),
                                        if (email.isNotEmpty)
                                          Text(email,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade600)),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: brandTeal.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color:
                                              brandTeal.withValues(alpha: 0.3)),
                                    ),
                                    child: Text(
                                      plan.isEmpty ? '—' : plan.toUpperCase(),
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: brandTeal),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildRelatoriosTab(Color brandBlue, Color brandTeal) {
    final pad = _adminListPadding(context);
    _relatorioReceitaFuture ??= _loadRelatorioReceita();
    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _relatorioReceitaFuture = _loadRelatorioReceita());
        await _relatorioReceitaFuture;
      },
      child: FutureBuilder<Map<String, dynamic>>(
        future: _relatorioReceitaFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return ListView(
              padding: pad,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              children: [
                const ModuleHeaderPremium(
                  title: 'Relatórios',
                  icon: Icons.bar_chart_rounded,
                  subtitle: 'Receita por período (Mercado Pago) e exportação.',
                ),
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
              ],
            );
          }
          final data = snap.data ?? {};
          final total30 = (data['total30'] ?? 0.0).toDouble();
          final total90 = (data['total90'] ?? 0.0).toDouble();
          final pix30 = (data['pix30'] ?? 0.0).toDouble();
          final card30 = (data['card30'] ?? 0.0).toDouble();
          final rows = (data['rows'] as List<Map<String, dynamic>>?) ?? [];
          return ListView(
            padding: pad,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            children: [
              const ModuleHeaderPremium(
                title: 'Relatórios',
                icon: Icons.bar_chart_rounded,
                subtitle: 'Receita por período (Mercado Pago) e exportação.',
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricCard(
                      label: 'Receita 30 dias',
                      value: CurrencyFormats.formatBRL(total30),
                      color: brandBlue,
                      icon: Icons.trending_up_rounded),
                  _MetricCard(
                      label: 'Receita 90 dias',
                      value: CurrencyFormats.formatBRL(total90),
                      color: brandTeal,
                      icon: Icons.calendar_month_rounded),
                  _MetricCard(
                      label: 'PIX (30d)',
                      value: CurrencyFormats.formatBRL(pix30),
                      color: const Color(0xFF34D399),
                      icon: Icons.qr_code_2_rounded),
                  _MetricCard(
                      label: 'Cartão (30d)',
                      value: CurrencyFormats.formatBRL(card30),
                      color: const Color(0xFFA78BFA),
                      icon: Icons.credit_card_rounded),
                ],
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                icon: const Icon(Icons.download_rounded),
                label: const Text('Exportar recebimentos (CSV)'),
                onPressed: () => _exportRelatorioReceitaCsv(rows),
              ),
              if (snap.hasError) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.orange.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text('${snap.error}',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.orange.shade900))),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<Map<String, dynamic>> _loadRelatorioReceita() async {
    final now = DateTime.now();
    final since30 = now.subtract(const Duration(days: 30));
    final since90 = now.subtract(const Duration(days: 90));
    double total30 = 0, total90 = 0, pix30 = 0, card30 = 0;
    final rows = <Map<String, dynamic>>[];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('mp_payments')
          .where('status', isEqualTo: 'approved')
          .get();
      for (final d in snap.docs) {
        final data = d.data();
        if (data['isOutgoing'] == true) continue;
        final raw = data['raw'];
        if (raw is! Map) continue;
        final amt = raw['transaction_amount'];
        final valor = amt is num ? amt.toDouble() : 0.0;
        final method =
            (raw['payment_method_id'] ?? '').toString().toLowerCase();
        final isPix = method == 'pix';
        final dateApproved = raw['date_approved'];
        DateTime? dt;
        if (dateApproved is String)
          dt = DateTime.tryParse(dateApproved);
        else if (dateApproved is Timestamp) dt = dateApproved.toDate();
        if (dt == null) continue;
        if (dt.isAfter(since30)) {
          total30 += valor;
          if (isPix)
            pix30 += valor;
          else
            card30 += valor;
        }
        if (dt.isAfter(since90)) total90 += valor;
        rows.add({
          'date': dt.toIso8601String(),
          'value': valor,
          'method': isPix ? 'PIX' : 'Cartão',
          'id': d.id,
        });
      }
      rows.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    } catch (_) {}
    return {
      'total30': total30,
      'total90': total90,
      'pix30': pix30,
      'card30': card30,
      'rows': rows
    };
  }

  Future<void> _exportRelatorioReceitaCsv(
      List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nenhum dado para exportar.')));
      return;
    }
    final sb = StringBuffer('data;valor;método;id\n');
    for (final r in rows.take(1000)) {
      final date = (r['date'] ?? '').toString();
      final value = (r['value'] ?? 0).toString();
      final method = (r['method'] ?? '').toString();
      final id = (r['id'] ?? '').toString();
      sb.writeln('$date;$value;$method;$id');
    }
    try {
      await Share.share(sb.toString(),
          subject:
              'Relatório recebimentos ${DateFormat('yyyy-MM-dd').format(DateTime.now())}');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Exportação compartilhada.')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Widget _buildSugestoesTab(Color brandBlue, Color brandTeal) {
    return AdminSugestoesTab(brandBlue: brandBlue, brandTeal: brandTeal);
  }

  Widget _buildDownloadsTab() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: _adminListPadding(context),
      children: [
        const ModuleHeaderPremium(
            title: 'Downloads públicos',
            icon: Icons.download_rounded,
            subtitle: 'Gerencie links e versões.'),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => _openDownloadEditor(),
            icon: const Icon(Icons.add),
            label: const Text('Novo download'),
          ),
        ),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('public_downloads')
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator()));
            }
            final docs = snap.data!.docs
              ..sort((a, b) {
                final oa = (a.data()['order'] ?? 0) is int
                    ? (a.data()['order'] as int)
                    : int.tryParse((a.data()['order'] ?? '0').toString()) ?? 0;
                final ob = (b.data()['order'] ?? 0) is int
                    ? (b.data()['order'] as int)
                    : int.tryParse((b.data()['order'] ?? '0').toString()) ?? 0;
                return oa.compareTo(ob);
              });
            if (docs.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ],
                ),
                child: ListTile(
                  leading: Icon(Icons.download),
                  title: Text('Sem downloads publicados'),
                  subtitle: Text('Cadastre um link para começar.'),
                ),
              );
            }
            return Column(
              children: docs.map((doc) {
                final data = doc.data();
                final title = (data['title'] ?? 'Download').toString();
                final subtitle = (data['subtitle'] ?? '').toString();
                final icon = (data['icon'] ?? '').toString();
                IconData iconData = Icons.download;
                if (icon == 'android') iconData = Icons.android;
                if (icon == 'ios') iconData = Icons.apple;
                if (icon == 'web') iconData = Icons.language;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 2))
                    ],
                  ),
                  child: ListTile(
                    leading: Icon(iconData, color: AppColors.primary),
                    title: Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle:
                        Text(subtitle.isEmpty ? 'Link disponível' : subtitle),
                    trailing: Wrap(
                      spacing: 6,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_rounded),
                          onPressed: () => _openDownloadEditor(doc: doc),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () async {
                            await doc.reference.delete();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildLandingTab() {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPad),
      children: [
        const ModuleHeaderPremium(
            title: 'Landing page',
            icon: Icons.web_rounded,
            subtitle: 'Edite textos e destaques da divulgação.'),
        const SizedBox(height: 12),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _landingDoc.snapshots(),
          builder: (context, snap) {
            _ensureDivulgacaoCtrls();
            if (snap.hasData && !_landingLoaded) {
              _landingLoaded = true;
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                final loaded = snap.data!.data() ?? <String, dynamic>{};
                _loadLandingControllers(loaded);
                await _seedDivulgacaoDefaultsIfMissing(loaded);
                await _hydrateMpCheckoutPriceFields();
                if (mounted) setState(() {});
              });
            }
            if (snap.hasError) {
              return Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.orange.shade300),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.orange.withValues(alpha: 0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 48, color: Colors.orange.shade700),
                    const SizedBox(height: 12),
                    Text('Erro ao carregar: ${snap.error}',
                        textAlign: TextAlign.center),
                  ],
                ),
              );
            }

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 14,
                      offset: const Offset(0, 4))
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Preços checkout (Mercado Pago)',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(
                      'Documento app_config/mp_checkout_prices — usado nas Cloud Functions (valor cobrado) e nas telas do app que mostram preço. Leitura pública. Assinaturas nativas da App Store (se houver) continuam no App Store Connect.',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          height: 1.35),
                    ),
                    const SizedBox(height: 12),
                    _LandingField(
                        controller: _mpPremiumMonthlyCtrl,
                        label: 'Premium mensal (R\$)'),
                    _LandingField(
                        controller: _mpPremiumAnnualCtrl,
                        label: 'Premium anual (R\$)'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              await _saveMpCheckoutPricing();
                              if (context.mounted) setState(() {});
                            },
                            icon: const Icon(Icons.payments_rounded),
                            label: const Text('Salvar preços checkout'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await _syncPremiumPublicTextsFromCheckoutPricing();
                              if (context.mounted) setState(() {});
                            },
                            icon: const Icon(Icons.auto_fix_high_rounded),
                            label: const Text('Sincronizar preços nos textos'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '“Sincronizar preços nos textos” atualiza linhas de valor Premium em landing/divulgação (e parágrafos da home) a partir dos valores acima e grava landing_content/main. Valores legados no Firestore são alinhados ao Premium ao salvar.',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 28),
                    Text('Página inicial (/)',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(
                      'Hero principal. Campos vazios no servidor usam o texto padrão do site.',
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 16),
                    _LandingField(
                        controller: _heroTitleCtrl, label: 'Título principal'),
                    _LandingField(
                        controller: _heroSubtitleCtrl,
                        label: 'Subtítulo (cinza escuro)'),
                    _LandingField(
                        controller: _heroTealCtrl,
                        label: 'Linha em destaque (verde-água)'),
                    _LandingField(
                        controller: _heroSlateCtrl,
                        label: 'Linha final (ardósia)'),
                    _LandingField(
                        controller: _heroBadgesCtrl,
                        label:
                            'Badges (vírgula): Financeiro, Agenda, Cursos, Dicas bíblicas'),
                    _LandingField(
                        controller: _heroNoteCtrl,
                        label: 'Nota abaixo dos botões'),
                    const SizedBox(height: 8),
                    Text(
                      'Planos — textos na divulgação (Premium; blocos legados ocultos no site)',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Nome, benefícios e faixas dos planos; valores mensais/anuais são alinhados ao checkout pelos botões acima ou por “Sincronizar”. premiumPrice/masterPrice espelham o Premium ao salvar.',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 12),
                    ...kDivulgacaoPlanPricingFields.map(
                      (f) => _LandingField(
                        controller: _divulgacaoCtrls[f.key]!,
                        label: f.label,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Página inicial (/) — faixa do plano Premium',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    _LandingField(
                        controller: _plansTitleCtrl,
                        label: 'Título da faixa (ex.: Plano Premium)'),
                    _LandingField(
                      controller: _landingPremiumDetailCtrl,
                      label:
                          'Parágrafo explicativo (abaixo do preço em destaque)',
                    ),
                    _LandingField(
                      controller: _landingPremiumCardPeriodCtrl,
                      label:
                          'Texto do período no cartão (linha menor sob o valor)',
                    ),
                    _LandingField(
                      controller: _landingPremiumFeaturesCtrl,
                      label: 'Benefícios no cartão Premium da home (vírgula)',
                    ),
                    _LandingField(
                        controller: _planCtaCtrl,
                        label: 'Texto do botão (ex.: Assinar agora)'),
                    _LandingField(
                        controller: _supportTitleCtrl,
                        label: 'Título do suporte'),
                    _LandingField(
                        controller: _supportSubtitleCtrl,
                        label: 'Subtítulo do suporte'),
                    const SizedBox(height: 12),
                    Text(
                      'Google Agenda + cores da divulgação',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Configura o botão de integração no módulo Agenda e as cores-base da divulgação (padrão azul/dourado).',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Integração Google Agenda habilitada'),
                      subtitle: const Text(
                          'Mostra/oculta botão no topo do módulo Agenda.'),
                      value: _googleAgendaEnabled,
                      onChanged: (v) =>
                          setState(() => _googleAgendaEnabled = v),
                    ),
                    const SizedBox(height: 10),
                    _LandingField(
                        controller: _googleAgendaBtnCtrl,
                        label: 'Texto do botão Google Agenda'),
                    _LandingField(
                        controller: _googleAgendaUrlCtrl,
                        label: 'URL da integração Google Agenda'),
                    _LandingField(
                        controller: _googleAgendaHintCtrl,
                        label: 'Texto de ajuda da integração'),
                    _LandingField(
                        controller: _divThemePrimaryCtrl,
                        label:
                            'Cor principal da divulgação (hex, ex.: #0B1B4B)'),
                    _LandingField(
                        controller: _divThemeAccentCtrl,
                        label:
                            'Cor destaque da divulgação (hex, ex.: #E8C547)'),
                    _LandingField(
                        controller: _footerCtrl, label: 'Texto do rodapé'),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF6366F1).withValues(alpha: 0.08),
                            const Color(0xFFD4AF37).withValues(alpha: 0.06),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.hub_rounded, color: Colors.indigo.shade700),
                              const SizedBox(width: 8),
                              Text(
                                'Canais oficiais (site / landing)',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'YouTube, Instagram e WhatsApp na barra superior do site e apps (landing). Salve com o botão abaixo.',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.35),
                          ),
                          const SizedBox(height: 14),
                          ...kLandingOfficialChannelsFields.map(
                            (f) => _LandingField(
                              controller: _divulgacaoCtrls[f.key]!,
                              label: f.label,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF34A853).withValues(alpha: 0.08),
                            const Color(0xFF0A1F56).withValues(alpha: 0.06),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: const Color(0xFF34A853).withValues(alpha: 0.35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.shop_rounded,
                                  color: Colors.green.shade700),
                              const SizedBox(width: 8),
                              Text(
                                'Baixar o app (Google Play)',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Link do botão «Google Play» na barra «Baixar o app» do site. '
                            'Também sincroniza com app_config/version (avisos de atualização).',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                                height: 1.35),
                          ),
                          const SizedBox(height: 14),
                          ...kLandingAppDownloadFields.map(
                            (f) => _LandingField(
                              controller: _divulgacaoCtrls[f.key]!,
                              label: f.label,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFBE185D).withValues(alpha: 0.08),
                            const Color(0xFFD4AF37).withValues(alpha: 0.06),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: const Color(0xFFBE185D).withValues(alpha: 0.35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.person_rounded,
                                  color: Colors.pink.shade700),
                              const SizedBox(width: 8),
                              Text(
                                'Livro e mentor (Tarley)',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Seção «Um Degrau Abaixo» e botões do mentor na página /divulgacao. '
                            'Instagram padrão: @wisdomappgo.',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                                height: 1.35),
                          ),
                          const SizedBox(height: 14),
                          ...kLandingMentorTarleyFields.map(
                            (f) => _LandingField(
                              controller: _divulgacaoCtrls[f.key]!,
                              label: f.label,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Página pública /divulgacao',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(
                      'Demais textos da rota /divulgacao (planos já estão na seção acima).',
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 16),
                    ...kDivulgacaoLandingFieldsSemPlanos.map(
                      (f) => _LandingField(
                        controller: _divulgacaoCtrls[f.key]!,
                        label: f.label,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () async {
                        await _saveLanding();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Landing atualizada com sucesso.')),
                          );
                        }
                      },
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('Salvar mudanças na divulgação'),
                      style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildEscalaTab(Color brandBlue, Color brandTeal) {
    return _adminScaleRatesTab(brandBlue, brandTeal);
  }

  Widget _buildDriveBackupTab(Color brandBlue, Color brandTeal) {
    return _DriveBackupTabContent(brandBlue: brandBlue, brandTeal: brandTeal);
  }

  Widget _buildMercadoPagoTab(Color brandBlue, Color brandTeal) {
    if (_isPartner) {
      return const AdminPartnerReceiptsTab();
    }
    if (_isContentGestor) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AdminPageShell.listPadding(context, top: 8),
        children: [
          const ModuleHeaderPremium(
            title: 'Recebimentos',
            icon: Icons.receipt_long_rounded,
            subtitle: 'Gráficos e transações Mercado Pago — somente leitura.',
          ),
          const SizedBox(height: 16),
          _RecebimentosPixSection(key: _mpPixSectionKey),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          if (_mpAdminTabKey.currentState != null)
            _mpAdminTabKey.currentState!.reload(),
          if (_mpPixSectionKey.currentState != null)
            _mpPixSectionKey.currentState!.reloadPayments(),
        ]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          AdminMercadoPagoTab(
            key: _mpAdminTabKey,
            brandBlue: brandBlue,
            brandTeal: brandTeal,
          ),
          const SizedBox(height: 24),
          _ZonaEmergenciaMpCard(),
          const SizedBox(height: 20),
          _RecebimentosPixSection(key: _mpPixSectionKey),
        ],
      ),
    );
  }

  Widget _buildLojasTab(Color brandBlue, Color brandTeal) {
    return _LojasTabContent(brandBlue: brandBlue, brandTeal: brandTeal);
  }

  Widget _buildConveniosTab(Color brandBlue, Color brandTeal) {
    return PartnershipsAdminModule(brandBlue: brandBlue, brandTeal: brandTeal);
  }

  Widget _buildManutencaoTab(Color brandBlue, Color brandTeal) {
    return _ManutencaoTabContent(brandBlue: brandBlue, brandTeal: brandTeal);
  }

  Widget _buildEmailConfigTab(Color brandBlue, Color brandTeal) {
    return _EmailConfigTabContent(brandBlue: brandBlue, brandTeal: brandTeal);
  }

  Widget _adminScaleRatesTab(Color brandBlue, Color brandTeal) {
    _ensureScaleRatesBootstrap();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        AdminScaleRatesPeriodsPanel(
          brandBlue: brandBlue,
          brandTeal: brandTeal,
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [brandBlue, brandTeal],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Row(
            children: [
              Icon(Icons.table_chart_rounded, color: Colors.white, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tabela vigente (espelho)',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Valores do período ativo agora. Para reajuste futuro use "Agendar reajuste".',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        StreamBuilder<ScaleRates>(
          stream: ScaleRatesService().watchGlobalRates(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Card(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator())));
            }
            final rates = snap.data!;
            return _AdminScaleRatesEditor(
              rates: rates,
              brandBlue: brandBlue,
              brandTeal: brandTeal,
            );
          },
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Versão do app',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                    '${AppVersion.internalLabel} — Atualização pelo deploy (syncAppVersion grava version, buildNumber, versionCode).',
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AdminScaleRatesEditor extends StatefulWidget {
  final ScaleRates rates;
  final Color brandBlue;
  final Color brandTeal;

  const _AdminScaleRatesEditor({
    required this.rates,
    required this.brandBlue,
    required this.brandTeal,
  });

  @override
  State<_AdminScaleRatesEditor> createState() => _AdminScaleRatesEditorState();
}

class _AdminScaleRatesEditorState extends State<_AdminScaleRatesEditor> {
  static const List<String> _weekdayLabels = [
    'Dom',
    'Seg',
    'Ter',
    'Qua',
    'Qui',
    'Sex',
    'Sáb'
  ];
  late List<TextEditingController> _diurnoCtrls;
  late List<TextEditingController> _noturnoCtrls;
  late TextEditingController _nightStartCtrl;
  late TextEditingController _nightEndCtrl;

  @override
  void initState() {
    super.initState();
    _diurnoCtrls = List.generate(
        7,
        (i) => TextEditingController(
            text: widget.rates.valueDiurno[i].toStringAsFixed(2)));
    _noturnoCtrls = List.generate(
        7,
        (i) => TextEditingController(
            text: widget.rates.valueNoturno[i].toStringAsFixed(2)));
    _nightStartCtrl = TextEditingController(text: widget.rates.nightStart);
    _nightEndCtrl = TextEditingController(text: widget.rates.nightEnd);
  }

  @override
  void dispose() {
    for (final c in _diurnoCtrls) c.dispose();
    for (final c in _noturnoCtrls) c.dispose();
    _nightStartCtrl.dispose();
    _nightEndCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final diurno = _diurnoCtrls
        .map((c) => double.tryParse(c.text.replaceAll(',', '.')) ?? 0.0)
        .toList();
    final noturno = _noturnoCtrls
        .map((c) => double.tryParse(c.text.replaceAll(',', '.')) ?? 0.0)
        .toList();
    if (diurno.length != 7 || noturno.length != 7) return;
    final nightStart = _nightStartCtrl.text.trim().isEmpty
        ? '22:00'
        : _nightStartCtrl.text.trim();
    final nightEnd =
        _nightEndCtrl.text.trim().isEmpty ? '05:00' : _nightEndCtrl.text.trim();
    final rates = ScaleRates(
      nightStart: nightStart,
      nightEnd: nightEnd,
      valueDiurno: diurno,
      valueNoturno: noturno,
    );
    await ScaleRatesService().setGlobalRates(rates);
    // Atualiza também o período vigente no histórico.
    final periodSvc = ScaleRatesPeriodService();
    await periodSvc.ensureLoaded();
    final active = periodSvc.activePeriodNow();
    if (active != null) {
      await periodSvc.addOrUpdatePeriod(active.copyWith(rates: rates));
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valores da escala salvos.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Período noturno (24h)',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(
            children: [
              SizedBox(
                width: 100,
                child: FastTextField(
                  controller: _nightStartCtrl,
                  keyboardType: TextInputType.datetime,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                    labelText: 'Início (ex: 22:00)',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 100,
                child: FastTextField(
                  controller: _nightEndCtrl,
                  keyboardType: TextInputType.datetime,
                  textInputAction: TextInputAction.done,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                    labelText: 'Fim (ex: 05:00)',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Valor hora por dia da semana (R\$)',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(
                    label: Text('Dia',
                        style: TextStyle(fontWeight: FontWeight.w700))),
                DataColumn(
                    label: Text('Diurno (R\$/h)',
                        style: TextStyle(fontWeight: FontWeight.w700))),
                DataColumn(
                    label: Text('Noturno (R\$/h)',
                        style: TextStyle(fontWeight: FontWeight.w700))),
              ],
              rows: List.generate(7, (i) {
                return DataRow(
                  cells: [
                    DataCell(Text(_weekdayLabels[i])),
                    DataCell(SizedBox(
                      width: 72,
                      child: FastTextField(
                        controller: _diurnoCtrls[i],
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        ),
                      ),
                    )),
                    DataCell(SizedBox(
                      width: 72,
                      child: FastTextField(
                        controller: _noturnoCtrls[i],
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        ),
                      ),
                    )),
                  ],
                );
              }),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_rounded),
                label: const Text('Salvar valores da escala'),
                style:
                    FilledButton.styleFrom(backgroundColor: widget.brandTeal),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await ScaleRatesService()
                      .setGlobalRates(ScaleRates.defaultRates);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Padrão Goiás (AC4) restaurado no servidor.')),
                    );
                  }
                },
                icon: const Icon(Icons.restore),
                label: const Text('Restaurar padrão Goiás (AC4)'),
                style:
                    FilledButton.styleFrom(backgroundColor: widget.brandBlue),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await _save();
                },
                icon: const Icon(Icons.cloud_upload_rounded),
                label: const Text('Garantir padrão no servidor'),
                style:
                    FilledButton.styleFrom(backgroundColor: widget.brandBlue),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LandingField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  const _LandingField({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    const fieldMaxLines = 3;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: FastTextField(
        controller: controller,
        textInputAction: TextInputAction.newline,
        onSubmitted: null,
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
        ),
        minLines: 1,
        maxLines: fieldMaxLines,
      ),
    );
  }
}

/// Cabeçalho premium do painel Resumo: gradiente, título e subtítulo.
class _AdminResumoHeader extends StatelessWidget {
  final Color brandBlue;
  final Color brandTeal;

  const _AdminResumoHeader({required this.brandBlue, required this.brandTeal});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [brandBlue, brandTeal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: brandBlue.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.dashboard_rounded,
                color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Painel executivo',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      letterSpacing: 0.5),
                ),
                const SizedBox(height: 4),
                Text(
                  'Base, licenças, armazenamento estimado e receitas Mercado Pago.',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    'App em produção: ${AppVersion.internalLabel}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
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

/// Ações rápidas: Atualizar, Usuários, Mercado Pago.
class _AdminResumoQuickActions extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final VoidCallback onUsuarios;
  final VoidCallback onMercadoPago;
  final DateTime? lastUpdate;

  const _AdminResumoQuickActions({
    required this.onRefresh,
    required this.onUsuarios,
    required this.onMercadoPago,
    this.lastUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 500;
    final btnStyle = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    final outlineStyle = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 14),
      foregroundColor: AppColors.primary,
      side: const BorderSide(color: AppColors.primary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    final buttons = [
      OutlinedButton.icon(
        onPressed: () => onRefresh(),
        icon: const Icon(Icons.refresh_rounded, size: 20),
        label: const Text('Atualizar dados'),
        style: outlineStyle,
      ),
      FilledButton.tonalIcon(
        onPressed: onUsuarios,
        icon: const Icon(Icons.people_rounded, size: 20),
        label: const Text('Usuários'),
        style: btnStyle,
      ),
      FilledButton.tonalIcon(
        onPressed: onMercadoPago,
        icon: const Icon(Icons.payment_rounded, size: 20),
        label: const Text('Mercado Pago'),
        style: btnStyle,
      ),
    ];
    if (isNarrow) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          double targetWidth;
          if (w < 340) {
            targetWidth = w;
          } else {
            targetWidth = (w - 10) / 2;
          }
          targetWidth = targetWidth.clamp(140.0, 320.0).toDouble();
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: buttons
                .map((b) => SizedBox(width: targetWidth, child: b))
                .toList(),
          );
        },
      );
    }
    return Row(
      children: [
        Expanded(child: buttons[0]),
        const SizedBox(width: 12),
        Expanded(child: buttons[1]),
        const SizedBox(width: 12),
        Expanded(child: buttons[2]),
      ],
    );
  }
}

/// Título de seção do Resumo (ícone + texto).
class _AdminSectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _AdminSectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A237E)),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String? subValue;
  final bool highlight;
  final IconData? icon;
  final VoidCallback? onTap;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.color,
    this.subValue,
    this.highlight = false,
    this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = AdminResponsive.useMobileLayout(context);
    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: highlight
            ? color.withValues(alpha: 0.12)
            : color.withValues(alpha: 0.06),
        border: Border.all(
            color: color.withValues(alpha: highlight ? 0.5 : 0.2),
            width: highlight ? 2 : 1),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 8),
          ],
          Text(label,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 0.3)),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: highlight ? 22 : 19,
              fontWeight: FontWeight.w800,
              color: highlight ? color : Colors.grey.shade800,
              letterSpacing: -0.5,
            ),
          ),
          if (subValue != null && subValue!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(subValue!,
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade600, height: 1.2)),
          ],
          if (onTap != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.touch_app_rounded, size: 14, color: color),
                const SizedBox(width: 4),
                Text(
                  'Abrir',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: isMobile ? 140 : 172,
        maxWidth: isMobile ? (screenWidth * 0.92) : 220,
      ),
      child: onTap == null
          ? card
          : Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(18),
                child: card,
              ),
            ),
    );
  }
}

/// Credenciais de produção Mercado Pago (Controle Total) — gravadas no banco e editáveis pelo admin.
const String _mpDefaultPublicKey =
    'APP_USR-c2f7c815-7bc1-4c48-940f-7ce963e4b481';
const String _mpDefaultAccessToken =
    'APP_USR-209346412583133-021110-d9359130d5fc0919bc8c4c860ff643b6-270646278';
const String _mpDefaultClientId = '209346412583133';
const String _mpDefaultClientSecret = 'LbxuyOhjHwUXJGLNhE9S0dk2eNNYNgHr';

class _MercadoPagoTabContent extends StatefulWidget {
  final Color brandBlue;
  final Color brandTeal;

  const _MercadoPagoTabContent(
      {required this.brandBlue, required this.brandTeal});

  @override
  State<_MercadoPagoTabContent> createState() => _MercadoPagoTabContentState();
}

class _MercadoPagoTabContentState extends State<_MercadoPagoTabContent> {
  final _publicKeyCtrl = TextEditingController();
  final _accessTokenCtrl = TextEditingController();
  final _clientIdCtrl = TextEditingController();
  final _clientSecretCtrl = TextEditingController();
  final _webhookUrlCtrl = TextEditingController();
  final _webhookSecretCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _syncingAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _publicKeyCtrl.dispose();
    _accessTokenCtrl.dispose();
    _clientIdCtrl.dispose();
    _clientSecretCtrl.dispose();
    _webhookUrlCtrl.dispose();
    _webhookSecretCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('settings')
          .doc('mercadopago')
          .get();
      final d = snap.data();
      final hasStored = d != null &&
          (d['access_token'] ?? d['accessToken'] ?? '')
              .toString()
              .trim()
              .isNotEmpty;
      if (mounted) {
        _publicKeyCtrl.text = (hasStored
                ? (d!['public_key'] ?? d['publicKey'])
                : _mpDefaultPublicKey)
            .toString()
            .trim();
        _accessTokenCtrl.text = (hasStored
                ? (d['access_token'] ?? d['accessToken'])
                : _mpDefaultAccessToken)
            .toString()
            .trim();
        _clientIdCtrl.text =
            (hasStored ? (d['client_id'] ?? d['clientId']) : _mpDefaultClientId)
                .toString()
                .trim();
        _clientSecretCtrl.text = (hasStored
                ? (d['client_secret'] ?? d['clientSecret'])
                : _mpDefaultClientSecret)
            .toString()
            .trim();
        _webhookUrlCtrl.text =
            (d?['webhook_url'] ?? d?['webhookUrl'] ?? '').toString().trim();
        _webhookSecretCtrl.text =
            (d?['webhook_secret'] ?? d?['webhookSecret'] ?? '')
                .toString()
                .trim();
      }
      if (!hasStored && mounted) {
        await _writeToFirestore(
          _mpDefaultPublicKey,
          _mpDefaultAccessToken,
          _mpDefaultClientId,
          _mpDefaultClientSecret,
          '',
          '',
        );
      }
    } catch (_) {
      if (mounted) {
        _publicKeyCtrl.text = _mpDefaultPublicKey;
        _accessTokenCtrl.text = _mpDefaultAccessToken;
        _clientIdCtrl.text = _mpDefaultClientId;
        _clientSecretCtrl.text = _mpDefaultClientSecret;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _writeToFirestore(
    String publicKey,
    String accessToken,
    String clientId,
    String clientSecret,
    String webhookUrl,
    String webhookSecret,
  ) async {
    await FirebaseFirestore.instance
        .collection('settings')
        .doc('mercadopago')
        .set({
      'public_key': publicKey,
      'access_token': accessToken,
      'client_id': clientId,
      'client_secret': clientSecret,
      'webhook_url': webhookUrl,
      'webhook_secret': webhookSecret,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _restoreDefaults() {
    _publicKeyCtrl.text = _mpDefaultPublicKey;
    _accessTokenCtrl.text = _mpDefaultAccessToken;
    _clientIdCtrl.text = _mpDefaultClientId;
    _clientSecretCtrl.text = _mpDefaultClientSecret;
    setState(() {});
  }

  Future<void> _syncAllPayments() async {
    setState(() => _syncingAll = true);
    try {
      final res = await FunctionsService().syncAllMpPayments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(res['message'] ?? 'Sincronização concluída.'),
              backgroundColor: Colors.green),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.message ?? 'Erro ao sincronizar.'),
              backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _syncingAll = false);
    }
  }

  Future<void> _save() async {
    final accessToken = _accessTokenCtrl.text.trim();
    if (accessToken.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Access Token é obrigatório.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await _writeToFirestore(
        _publicKeyCtrl.text.trim(),
        accessToken,
        _clientIdCtrl.text.trim(),
        _clientSecretCtrl.text.trim(),
        _webhookUrlCtrl.text.trim(),
        _webhookSecretCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Credenciais Mercado Pago salvas. Checkout e webhook usarão esses valores.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const ModuleHeaderPremium(
            title: 'Mercado Pago',
            icon: Icons.payment_rounded,
            subtitle:
                'Credenciais de produção gravadas no banco. Altere aqui quando quiser.',
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded,
                            color: AppColors.success, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Em produção: use o Access Token da sua conta Mercado Pago. Os pagamentos (PIX e cartão) são creditados na conta vinculada a esse token.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Credenciais de produção',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  FastTextField(
                    controller: _publicKeyCtrl,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: const InputDecoration(
                      labelText: 'Public Key',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.vpn_key_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FastTextField(
                    controller: _accessTokenCtrl,
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: const InputDecoration(
                      labelText: 'Access Token',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FastTextField(
                    controller: _clientIdCtrl,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: const InputDecoration(
                      labelText: 'Client ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FastTextField(
                    controller: _clientSecretCtrl,
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: const InputDecoration(
                      labelText: 'Client Secret',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FastTextField(
                    controller: _webhookUrlCtrl,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: const InputDecoration(
                      labelText: 'Webhook URL (opcional)',
                      hintText: 'Ex: https://.../mpWebhook',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FastTextField(
                    controller: _webhookSecretCtrl,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: const InputDecoration(
                      labelText: 'Webhook Secret (opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.save_rounded),
                        label:
                            Text(_saving ? 'Salvando...' : 'Salvar no banco'),
                        style: FilledButton.styleFrom(
                            backgroundColor: widget.brandTeal),
                      ),
                      OutlinedButton.icon(
                        onPressed: _restoreDefaults,
                        icon: const Icon(Icons.restore_rounded),
                        label: const Text('Restaurar credenciais de produção'),
                      ),
                      FilledButton.icon(
                        onPressed:
                            (_saving || _syncingAll) ? null : _syncAllPayments,
                        icon: _syncingAll
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.sync_rounded),
                        label: Text(_syncingAll
                            ? 'Sincronizando...'
                            : 'Sincronizar pagamentos (24h)'),
                        style: FilledButton.styleFrom(
                            backgroundColor: widget.brandBlue),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _ZonaEmergenciaMpCard(),
          const SizedBox(height: 20),
          const _RecebimentosPixSection(),
        ],
      ),
    );
  }
}

/// Chave Mestra: sincronização forçada quando o webhook falha ou a internet oscila.
class _ZonaEmergenciaMpCard extends StatefulWidget {
  @override
  State<_ZonaEmergenciaMpCard> createState() => _ZonaEmergenciaMpCardState();
}

class _ZonaEmergenciaMpCardState extends State<_ZonaEmergenciaMpCard> {
  final _paymentIdCtrl = TextEditingController();
  bool _syncing = false;
  String? _syncError;
  String? _syncSuccess;

  @override
  void dispose() {
    _paymentIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _forcarLiberacao() async {
    final id = _paymentIdCtrl.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (id.isEmpty) {
      setState(() {
        _syncError = 'Digite o ID do pagamento.';
        _syncSuccess = null;
      });
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Confirmar liberação manual'),
        content: const Text(
          'Isso irá consultar o Mercado Pago e liberar o acesso manualmente. Confirmar?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFA117)),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _syncing = true;
      _syncError = null;
      _syncSuccess = null;
    });
    try {
      final res = await FunctionsService().syncMpPayment(paymentId: id);
      if (mounted) {
        setState(() {
          _syncing = false;
          _syncSuccess = (res['message'] ?? 'Licença liberada.') as String?;
          _syncError = null;
          if (res['ok'] == true || res['activated'] == true)
            _paymentIdCtrl.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncing = false;
          _syncError = e
              .toString()
              .replaceFirst(RegExp(r'^Exception:?\s*'), '')
              .split('\n')
              .first;
          _syncSuccess = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFA117), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: const Color(0xFF663C00), size: 28),
              const SizedBox(width: 10),
              Text(
                'Zona de Emergência',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF663C00),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Use apenas se o PIX foi pago e o sistema não liberou automaticamente.',
            style: TextStyle(
                fontSize: 13, color: const Color(0xFF663C00), height: 1.3),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FastTextField(
                  controller: _paymentIdCtrl,
                  textInputAction: TextInputAction.done,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: InputDecoration(
                    hintText: 'ID do Pagamento (Ex: 123456789)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade400),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  keyboardType: TextInputType.number,
                  enabled: !_syncing,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _syncing ? null : _forcarLiberacao,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFA117),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: _syncing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('FORÇAR LIBERAÇÃO',
                        style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          if (_syncError != null) ...[
            const SizedBox(height: 10),
            Text(_syncError!,
                style: TextStyle(fontSize: 13, color: Colors.red.shade700)),
          ],
          if (_syncSuccess != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: AppColors.success, size: 20),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(_syncSuccess!,
                        style: TextStyle(
                            fontSize: 13,
                            color: AppColors.success,
                            fontWeight: FontWeight.w600))),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Totais de recebimentos Mercado Pago (PIX/cartão) por período: diário, semanal, mensal, anual e personalizado.
class _RecebimentosResumoWidget extends StatefulWidget {
  final Color brandBlue;
  final Color brandTeal;

  /// Alinhado ao chip de período do resumo admin (7 / 30 / 90).
  final int resumoPeriodDays;

  const _RecebimentosResumoWidget({
    required this.brandBlue,
    required this.brandTeal,
    required this.resumoPeriodDays,
  });

  @override
  State<_RecebimentosResumoWidget> createState() =>
      _RecebimentosResumoWidgetState();
}

class _RecebimentosResumoWidgetState extends State<_RecebimentosResumoWidget> {
  List<Map<String, dynamic>> _payments = [];
  bool _loading = true;
  late DateTime _periodStart;
  late DateTime _periodEnd;

  void _syncPeriodFromResumo() {
    final now = DateTime.now();
    final since = now.subtract(Duration(days: widget.resumoPeriodDays));
    _periodStart = DateTime(since.year, since.month, since.day);
    _periodEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  @override
  void initState() {
    super.initState();
    _syncPeriodFromResumo();
    _load();
  }

  @override
  void didUpdateWidget(covariant _RecebimentosResumoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resumoPeriodDays != widget.resumoPeriodDays) {
      _syncPeriodFromResumo();
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final queryStart =
        DateTime(_periodStart.year, _periodStart.month, _periodStart.day);
    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await FirebaseFirestore.instance
            .collection('mp_payments')
            .where('status', isEqualTo: 'approved')
            .where('dateApprovedAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(queryStart))
            .orderBy('dateApprovedAt', descending: true)
            .limit(800)
            .get();
      } catch (_) {
        snap = await FirebaseFirestore.instance
            .collection('mp_payments')
            .where('status', isEqualTo: 'approved')
            .limit(1200)
            .get();
      }
      final list = snap.docs
          .map((d) => d.data())
          .where((d) =>
              (d['status'] ?? '').toString() == 'approved' &&
              d['isOutgoing'] != true)
          .toList();
      if (mounted)
        setState(() {
          _payments = list;
          _loading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _payments = [];
          _loading = false;
        });
    }
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    final s = v.toString();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  static double _amount(Map<String, dynamic> d) {
    final raw = d['raw'];
    if (raw is! Map) return 0;
    final a = raw['transaction_amount'];
    if (a is num) return a.toDouble();
    return double.tryParse(a?.toString() ?? '0') ?? 0;
  }

  double _totalInRange(DateTime start, DateTime end) {
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day, 23, 59, 59);
    double sum = 0;
    for (final d in _payments) {
      final dt = _parseDate(
          d['raw'] is Map ? (d['raw'] as Map)['date_approved'] : null);
      if (dt == null) continue;
      final day = DateTime(dt.year, dt.month, dt.day);
      if (!day.isBefore(startDay) && !day.isAfter(endDay)) sum += _amount(d);
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartDay =
        DateTime(weekStart.year, weekStart.month, weekStart.day);
    final monthStart = DateTime(now.year, now.month, 1);
    final yearStart = DateTime(now.year, 1, 1);

    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final resumoSince = now.subtract(Duration(days: widget.resumoPeriodDays));
    final resumoStart =
        DateTime(resumoSince.year, resumoSince.month, resumoSince.day);
    final resumoEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final resumoFiltro = _totalInRange(resumoStart, resumoEnd);
    final daily = _totalInRange(todayStart, now);
    final weekly = _totalInRange(weekStartDay, now);
    final monthly = _totalInRange(monthStart, now);
    final annual = _totalInRange(yearStart, now);
    final custom = _totalInRange(
      DateTime(_periodStart.year, _periodStart.month, _periodStart.day),
      DateTime(_periodEnd.year, _periodEnd.month, _periodEnd.day, 23, 59, 59),
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _RecebCard(
                  'Resumo (${widget.resumoPeriodDays}d)',
                  resumoFiltro,
                  widget.brandBlue,
                ),
                _RecebCard('Hoje', daily, widget.brandTeal),
                _RecebCard('Esta semana', weekly, widget.brandBlue),
                _RecebCard('Este mês', monthly, widget.brandTeal),
                _RecebCard('Este ano', annual, widget.brandBlue),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.date_range_rounded,
                    size: 18, color: Colors.grey.shade700),
                const SizedBox(width: 8),
                const Text('Período personalizado',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today_rounded, size: 18),
                    label: Text(DateFormat('dd/MM/yyyy').format(_periodStart)),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _periodStart,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) setState(() => _periodStart = d);
                    },
                  ),
                ),
                const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('até')),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today_rounded, size: 18),
                    label: Text(DateFormat('dd/MM/yyyy').format(_periodEnd)),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _periodEnd,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) setState(() => _periodEnd = d);
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _load,
                  tooltip: 'Recarregar pagamentos',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: widget.brandBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.payment_rounded,
                      color: AppColors.primary, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Total no período: ${CurrencyFormats.formatBRL(custom)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16),
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

Widget _RecebCard(String label, double value, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 4),
        Text(
          CurrencyFormats.formatBRL(value),
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w800, color: color),
        ),
      ],
    ),
  );
}

/// Seção de recebimentos PIX no admin: lista pagamentos da coleção mp_payments.
class _RecebimentosPixSection extends StatefulWidget {
  const _RecebimentosPixSection({super.key});

  @override
  State<_RecebimentosPixSection> createState() =>
      _RecebimentosPixSectionState();
}

class _RecebimentosPixSectionState extends State<_RecebimentosPixSection> {
  final _paymentIdCtrl = TextEditingController();
  final _emailSyncCtrl = TextEditingController();
  final _searchFilterCtrl = TextEditingController();
  Timer? _pixSearchDebounce;
  bool _syncing = false;
  bool _syncingEmail = false;
  String? _syncError;
  String? _syncSuccess;
  DateTime _filterStart = DateTime.now().subtract(const Duration(days: 30));
  DateTime _filterEnd = DateTime.now();

  /// Filtro de busca: e-mail ou nome do usuário.
  String _searchQuery = '';

  /// Status: 'all' | 'approved' | 'cancelled'
  String _filterStatus = 'all';

  /// true = ordenar por usuário (e-mail/nome) e depois por data; false = só por data (mais recente primeiro).
  bool _orderByUser = false;

  /// Filtro recebedor interno: all | raihom | partner
  String _recipientFilter = 'all';

  Map<String, String> _uidDisplayCache = {};
  String _uidDisplayCacheKey = '';
  Future<Map<String, String>>? _uidDisplayFuture;

  bool _loadingPayments = true;
  String? _loadPaymentsError;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _allPaymentDocs = [];

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  /// Recarrega a lista (pull-to-refresh ou após sync manual).
  Future<void> reloadPayments() => _loadPayments();

  Future<void> _loadPayments() async {
    if (!mounted) return;
    setState(() {
      _loadingPayments = true;
      _loadPaymentsError = null;
    });
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.recoverFirestoreWebSession().catchError((_) {});
      }
      final snap = await firestoreQueryGetReliable(
        FirebaseFirestore.instance.collection('mp_payments').limit(500),
      );
      if (!mounted) return;
      setState(() {
        _allPaymentDocs = snap.docs;
        _loadingPayments = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _allPaymentDocs = [];
        _loadingPayments = false;
        _loadPaymentsError = FirestoreWebGuard.isInternalAssertionError(e)
            ? 'Instabilidade do Firestore na Web. Toque em Atualizar ou recarregue a página (F5).'
            : 'Não foi possível carregar os pagamentos.';
      });
    }
  }

  void _ensureUserDisplayFuture(List<String> uids) {
    final key = uids.join('|');
    if (key == _uidDisplayCacheKey && _uidDisplayFuture != null) return;
    _uidDisplayCacheKey = key;
    if (uids.isEmpty) {
      _uidDisplayCache = {};
      _uidDisplayFuture = Future.value(_uidDisplayCache);
      return;
    }
    _uidDisplayFuture = _loadUserDisplayMap(uids).then((m) {
      _uidDisplayCache = m;
      return m;
    });
  }

  static String? _splitRecipientLabel(Map<String, dynamic> data) {
    final ownerGross = data['splitOwnerShareGross'];
    final partnerGross = data['splitPartnerShareGross'];
    if (ownerGross == null && partnerGross == null) return null;
    final owner = (data['splitOwnerLabel'] ?? AppBrand.developerName).toString();
    final partner = (data['splitPartnerLabel'] ?? AppBrand.idealizerName).toString();
    return '$owner / $partner';
  }

  static bool _matchesRecipientFilter(Map<String, dynamic> data, String filter) {
    if (filter == 'all') return true;
    final ownerLabel = (data['splitOwnerLabel'] ?? '').toString().toLowerCase();
    if (filter == 'raihom') {
      return ownerLabel.contains('raihom') || data['splitOwnerShareGross'] != null;
    }
    if (filter == 'partner') {
      return ownerLabel.contains('johnathan') ||
          ownerLabel.contains('jhonathan') ||
          data['splitPartnerShareGross'] != null;
    }
    return true;
  }

  static DateTime? _parseApprovedDate(Map<String, dynamic> d) {
    final raw = d['raw'];
    if (raw is! Map) return null;
    final v =
        raw['date_approved'] ?? raw['date_created'] ?? raw['date_last_updated'];
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  static String? _parseUserDisplay(Map<String, dynamic> d) {
    final raw = d['raw'];
    if (raw is! Map) return null;
    final payer = raw['payer'];
    if (payer is! Map) return null;
    final email = (payer['email'] ?? '').toString().trim();
    final name = (payer['first_name'] ?? payer['name'] ?? '').toString().trim();
    if (email.isNotEmpty) return name.isNotEmpty ? '$name ($email)' : email;
    return null;
  }

  @override
  void dispose() {
    _pixSearchDebounce?.cancel();
    _paymentIdCtrl.dispose();
    _emailSyncCtrl.dispose();
    _searchFilterCtrl.dispose();
    super.dispose();
  }

  /// Carrega mapa uid -> "nome (email)" ou email a partir da coleção users (fallback quando MP não envia payer).
  Future<Map<String, String>> _loadUserDisplayMap(List<String> uids) async {
    final unique = uids.where((s) => s.isNotEmpty).toSet().toList();
    if (unique.isEmpty) return {};
    final result = <String, String>{};
    const batchSize = 30;
    for (var i = 0; i < unique.length; i += batchSize) {
      final batch = unique.skip(i).take(batchSize).toList();
      final refs = batch
          .map((uid) => FirebaseFirestore.instance.collection('users').doc(uid))
          .toList();
      final snaps = await Future.wait(refs.map((r) => r.get()));
      for (var j = 0; j < batch.length; j++) {
        final d = snaps[j].data();
        if (d == null) continue;
        final name = (d['name'] ?? '').toString().trim();
        final email = (d['email'] ?? '').toString().trim();
        if (email.isNotEmpty) {
          result[batch[j]] = name.isNotEmpty ? '$name ($email)' : email;
        } else if (name.isNotEmpty) {
          result[batch[j]] = name;
        }
      }
    }
    return result;
  }

  Future<void> _syncByEmail() async {
    final email = _emailSyncCtrl.text.trim();
    if (email.isEmpty) {
      setState(() {
        _syncError = 'Digite o e-mail do usuário.';
        _syncSuccess = null;
      });
      return;
    }
    setState(() {
      _syncingEmail = true;
      _syncError = null;
      _syncSuccess = null;
    });
    try {
      final res = await FunctionsService().syncMpPaymentByEmail(email: email);
      if (mounted) {
        setState(() {
          _syncingEmail = false;
          _syncSuccess = (res['message'] ?? 'Sincronizado.') as String?;
          _syncError = null;
          if ((res['activated'] ?? res['ok']) == true) _emailSyncCtrl.clear();
        });
        await _loadPayments();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncingEmail = false;
          _syncError = e
              .toString()
              .replaceFirst(RegExp(r'^Exception:?\s*'), '')
              .split('\n')
              .first;
          _syncSuccess = null;
        });
      }
    }
  }

  Future<void> _syncPayment() async {
    final id = _paymentIdCtrl.text.trim();
    if (id.isEmpty) {
      setState(() {
        _syncError = 'Digite o ID do pagamento.';
        _syncSuccess = null;
      });
      return;
    }
    if (!RegExp(r'^\d+$').hasMatch(id)) {
      setState(() {
        _syncError = 'O ID deve ser numérico (ex.: 147204656312).';
        _syncSuccess = null;
      });
      return;
    }
    setState(() {
      _syncing = true;
      _syncError = null;
      _syncSuccess = null;
    });
    try {
      final res = await FunctionsService().syncMpPayment(paymentId: id);
      if (mounted) {
        setState(() {
          _syncing = false;
          _syncSuccess =
              (res['message'] ?? 'Pagamento sincronizado.') as String?;
          _syncError = null;
          _paymentIdCtrl.clear();
        });
        await _loadPayments();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncing = false;
          _syncError = e
              .toString()
              .replaceFirst(RegExp(r'^Exception:?\s*'), '')
              .split('\n')
              .first;
          _syncSuccess = null;
        });
      }
    }
  }

  static Widget _buildApprovedDate(dynamic approved) {
    DateTime dt;
    if (approved is Timestamp) {
      dt = approved.toDate();
    } else if (approved is DateTime) {
      dt = approved;
    } else {
      dt = DateTime.tryParse(approved.toString()) ?? DateTime.now();
    }
    return Text('Aprovado: ${DateFormat('dd/MM/yyyy HH:mm').format(dt)}',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600));
  }

  static Widget _buildDateAndTime(Map<String, dynamic> data) {
    final raw = data['raw'];
    if (raw is! Map) return const SizedBox.shrink();
    final v =
        raw['date_approved'] ?? raw['date_created'] ?? raw['date_last_updated'];
    if (v == null) return const SizedBox.shrink();
    DateTime dt;
    if (v is Timestamp)
      dt = v.toDate();
    else if (v is DateTime)
      dt = v;
    else
      dt = DateTime.tryParse(v.toString()) ?? DateTime.now();
    return Text(
        '${DateFormat('dd/MM/yyyy').format(dt)} às ${DateFormat('HH:mm').format(dt)}',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade700));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.receipt_long_rounded,
                    color: AppColors.accent, size: 24),
              ),
              const SizedBox(width: 12),
              const Text(
                'Recebimentos PIX / Cartão',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Fluxo: webhook do Mercado Pago ativa a licença ao aprovar o pagamento. '
            'Se não ativar, use «Sync pagamentos (24h)» acima ou sincronize pelo ID/e-mail abaixo. '
            'Webhook: ${MpAdminConfigService.defaultWebhookUrl}',
            style: TextStyle(
                fontSize: 12, color: Colors.grey.shade700, height: 1.4),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.sync_rounded,
                        size: 20, color: AppColors.primary),
                    const SizedBox(width: 8),
                    const Text('Sincronizar pagamento manualmente',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Se um pagamento chegou no Mercado Pago mas não apareceu aqui, informe o ID numérico do pagamento (encontre no app MP ou painel do vendedor).',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, c) {
                    final narrow = c.maxWidth < 520;
                    final idField = FastTextField(
                      controller: _paymentIdCtrl,
                      textInputAction: TextInputAction.done,
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      decoration: const InputDecoration(
                        hintText: 'ID do pagamento (ex: 147204656312)',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                      keyboardType: TextInputType.number,
                      enabled: !_syncing,
                    );
                    final syncBtn = FilledButton.icon(
                      onPressed: _syncing ? null : _syncPayment,
                      icon: _syncing
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.sync_rounded, size: 20),
                      label:
                          Text(_syncing ? 'Sincronizando...' : 'Sincronizar'),
                    );
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [idField, const SizedBox(height: 10), syncBtn],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: idField),
                        const SizedBox(width: 12),
                        syncBtn,
                      ],
                    );
                  },
                ),
                if (_syncError != null) ...[
                  const SizedBox(height: 8),
                  Text(_syncError!,
                      style:
                          TextStyle(fontSize: 12, color: Colors.red.shade700)),
                ],
                if (_syncSuccess != null) ...[
                  const SizedBox(height: 8),
                  Text(_syncSuccess!,
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.success,
                          fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.email_rounded,
                        size: 20, color: AppColors.accent),
                    const SizedBox(width: 8),
                    const Text('Sincronizar por e-mail do usuário',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Quando o usuário pagou via PIX mas a licença não ativou: informe o e-mail (ex.: caseanapolisgo@gmail.com) para buscar e processar o PIX pendente dele.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, c) {
                    final narrow = c.maxWidth < 520;
                    final emailField = FastTextField(
                      controller: _emailSyncCtrl,
                      textInputAction: TextInputAction.done,
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      decoration: const InputDecoration(
                        hintText: 'E-mail do usuário (ex: usuario@email.com)',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      enabled: !_syncingEmail,
                    );
                    final syncBtn = FilledButton.icon(
                      onPressed: _syncingEmail ? null : _syncByEmail,
                      icon: _syncingEmail
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.sync_rounded, size: 20),
                      label: Text(_syncingEmail
                          ? 'Sincronizando...'
                          : 'Sincronizar por e-mail'),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent),
                    );
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [emailField, const SizedBox(height: 10), syncBtn],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: emailField),
                        const SizedBox(width: 12),
                        syncBtn,
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Filtro por período:',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700)),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
                onPressed: () async {
                  final d = await showDatePicker(
                      context: context,
                      initialDate: _filterStart,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now());
                  if (d != null) setState(() => _filterStart = d);
                },
                child: Text(DateFormat('dd/MM/yyyy').format(_filterStart)),
              ),
              Text('até', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
                onPressed: () async {
                  final d = await showDatePicker(
                      context: context,
                      initialDate: _filterEnd,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now());
                  if (d != null) setState(() => _filterEnd = d);
                },
                child: Text(DateFormat('dd/MM/yyyy').format(_filterEnd)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FastTextField(
                  controller: _searchFilterCtrl,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.search,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                    hintText: 'Buscar por e-mail ou nome',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  onChanged: (_) {
                    _pixSearchDebounce?.cancel();
                    _pixSearchDebounce = Timer(
                      Duration(milliseconds: AppBusinessRules.searchDebounceMs),
                      () {
                        if (mounted) {
                          setState(() =>
                              _searchQuery = _searchFilterCtrl.text.trim());
                        }
                      },
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _filterStatus,
                isDense: true,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Status: Todos')),
                  DropdownMenuItem(value: 'approved', child: Text('Aprovado')),
                  DropdownMenuItem(
                      value: 'cancelled', child: Text('Cancelado')),
                ],
                onChanged: (v) => setState(() => _filterStatus = v ?? 'all'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Recebedor:',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700)),
              ChoiceChip(
                label: const Text('Todos'),
                selected: _recipientFilter == 'all',
                onSelected: (_) => setState(() => _recipientFilter = 'all'),
              ),
              ChoiceChip(
                label: Text(AppBrand.developerName.split(' ').first),
                selected: _recipientFilter == 'raihom',
                onSelected: (_) => setState(() => _recipientFilter = 'raihom'),
              ),
              ChoiceChip(
                label: Text(AppBrand.idealizerName.split(' ').first),
                selected: _recipientFilter == 'partner',
                onSelected: (_) => setState(() => _recipientFilter = 'partner'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('Ordenar:',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700)),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Mais recente'),
                selected: !_orderByUser,
                onSelected: (_) => setState(() => _orderByUser = false),
                selectedColor: AppColors.primary.withValues(alpha: 0.3),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('Por usuário'),
                selected: _orderByUser,
                onSelected: (_) => setState(() => _orderByUser = true),
                selectedColor: AppColors.primary.withValues(alpha: 0.3),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Atualizar lista',
                onPressed: _loadingPayments ? null : _loadPayments,
                icon: _loadingPayments
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                    : Icon(Icons.refresh_rounded, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildPaymentsList(),
        ],
      ),
    );
  }

  Widget _buildPaymentsList() {
    if (_loadingPayments) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_loadPaymentsError != null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 40, color: Colors.orange.shade800),
            const SizedBox(height: 10),
            Text(
              _loadPaymentsError!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loadPayments,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }

    final allDocs = _allPaymentDocs;
    if (allDocs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.inbox_rounded, size: 40, color: Colors.grey.shade400),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'Nenhum pagamento registrado ainda. Quando houver vendas via '
                'Mercado Pago, elas aparecerão aqui.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.35),
              ),
            ),
          ],
        ),
      );
    }

    final startDay =
        DateTime(_filterStart.year, _filterStart.month, _filterStart.day);
    final endDay = DateTime(
        _filterEnd.year, _filterEnd.month, _filterEnd.day, 23, 59, 59);
    var docs = allDocs.where((d) {
      final data = d.data();
      if (data['isOutgoing'] == true) return false;
      final dt = _parseApprovedDate(data);
      if (dt == null) return true;
      final day = DateTime(dt.year, dt.month, dt.day);
      if (day.isBefore(startDay) || day.isAfter(endDay)) return false;
      if (_filterStatus == 'approved' && (data['status'] ?? '') != 'approved') {
        return false;
      }
      if (_filterStatus == 'cancelled' &&
          (data['status'] ?? '') != 'cancelled') {
        return false;
      }
      return true;
    }).toList();
    final uniqueUids = docs
        .map((d) => (d.data()['uid'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    _ensureUserDisplayFuture(uniqueUids);
    return FutureBuilder<Map<String, String>>(
      future: _uidDisplayFuture,
      builder: (context, userSnap) {
        if (userSnap.connectionState == ConnectionState.waiting &&
            uniqueUids.isNotEmpty &&
            userSnap.data == null &&
            _uidDisplayCache.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }
        final uidToDisplay = userSnap.data ?? _uidDisplayCache;
        var filteredDocs = docs;
        if (_recipientFilter != 'all') {
          filteredDocs = filteredDocs
              .where((d) => _matchesRecipientFilter(d.data(), _recipientFilter))
              .toList();
        }
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          filteredDocs = docs.where((d) {
            final data = d.data();
            final uid = (data['uid'] ?? '').toString();
            final fromPayer = _parseUserDisplay(data) ?? '';
            final fromUser = uidToDisplay[uid] ?? '';
            final combined = '$fromPayer $fromUser $uid'.toLowerCase();
            return combined.contains(q);
          }).toList();
        }
        filteredDocs = filteredDocs.toList()
          ..sort((a, b) {
            final ta = a.data()['updatedAt'] is Timestamp
                ? (a.data()['updatedAt'] as Timestamp).millisecondsSinceEpoch
                : 0;
            final tb = b.data()['updatedAt'] is Timestamp
                ? (b.data()['updatedAt'] as Timestamp).millisecondsSinceEpoch
                : 0;
            if (_orderByUser) {
              final uidA = (a.data()['uid'] ?? '').toString();
              final uidB = (b.data()['uid'] ?? '').toString();
              final displayA =
                  _parseUserDisplay(a.data()) ?? uidToDisplay[uidA] ?? uidA;
              final displayB =
                  _parseUserDisplay(b.data()) ?? uidToDisplay[uidB] ?? uidB;
              final cmp =
                  displayA.toLowerCase().compareTo(displayB.toLowerCase());
              if (cmp != 0) return cmp;
            }
            return tb.compareTo(ta);
          });
        if (filteredDocs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.inbox_rounded, size: 40, color: Colors.grey.shade400),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    _searchQuery.isNotEmpty || _filterStatus != 'all'
                        ? 'Nenhum pagamento com os filtros aplicados.'
                        : 'Nenhum pagamento no período. Ajuste o filtro ou aguarde novos pagamentos.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),
                ),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final sb = StringBuffer();
                  sb.writeln('Data;Horário;Usuário;UID;Plano;Valor;Status');
                  for (final d in filteredDocs) {
                    final data = d.data();
                    final uid = (data['uid'] ?? '').toString();
                    final plan = (data['plan'] ?? '').toString();
                    final status = (data['status'] ?? '').toString();
                    final userDisplay =
                        _parseUserDisplay(data) ?? uidToDisplay[uid] ?? '';
                    final raw = data['raw'] as Map?;
                    final amt = raw?['transaction_amount'] ?? 0;
                    final val =
                        amt is num ? amt : double.tryParse(amt.toString()) ?? 0;
                    final dt = _parseApprovedDate(data);
                    final dtStr =
                        dt != null ? DateFormat('dd/MM/yyyy').format(dt) : '';
                    final horaStr =
                        dt != null ? DateFormat('HH:mm').format(dt) : '';
                    sb.writeln(
                        '$dtStr;$horaStr;$userDisplay;$uid;$plan;${val.toStringAsFixed(2)};$status');
                  }
                  await Clipboard.setData(ClipboardData(text: sb.toString()));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'CSV copiado (${AppStrings.itemCountLabel(filteredDocs.length)}). Cole em um arquivo .csv para salvar.',
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Exportar CSV'),
              ),
            ),
            ...filteredDocs.map((d) {
              final data = d.data();
              final uid = (data['uid'] ?? '').toString();
              final plan = (data['plan'] ?? '').toString();
              final planCode = (data['planCode'] ?? '').toString();
              final status = (data['status'] ?? '').toString();
              final raw = data['raw'] as Map<String, dynamic>?;
              final amount = raw?['transaction_amount'] ?? 0;
              final isApproved = status == 'approved';
              final userDisplay = _parseUserDisplay(data) ??
                  uidToDisplay[uid] ??
                  (uid.isNotEmpty
                      ? 'UID ${uid.substring(0, uid.length.clamp(0, 12))}${uid.length > 12 ? '…' : ''}'
                      : '—');
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isApproved
                      ? AppColors.success.withValues(alpha: 0.08)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isApproved
                        ? AppColors.success.withValues(alpha: 0.3)
                        : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isApproved
                          ? Icons.check_circle_rounded
                          : Icons.schedule_rounded,
                      color: isApproved ? AppColors.success : Colors.orange,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Usuário: $userDisplay',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (uid.isNotEmpty)
                            Text(
                              'UID: ${uid.substring(0, uid.length.clamp(0, 14))}${uid.length > 14 ? '…' : ''}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          Text(
                            'Plano: $plan • ${planCode.isNotEmpty ? planCode : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          if (data['splitEnabled'] == true ||
                              data['splitOwnerShareGross'] != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Split: ${AppBrand.developerName} '
                              '${CurrencyFormats.formatBRL((data['splitOwnerShareGross'] as num?)?.toDouble() ?? 0)} · '
                              '${AppBrand.idealizerName} '
                              '${CurrencyFormats.formatBRL((data['splitPartnerShareGross'] as num?)?.toDouble() ?? 0)}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                          _buildDateAndTime(data),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          CurrencyFormats.formatBRL(amount is num
                              ? amount
                              : double.tryParse(amount.toString()) ?? 0),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: isApproved
                                ? AppColors.success
                                : Colors.grey.shade700,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isApproved
                                ? AppColors.success.withValues(alpha: 0.2)
                                : Colors.orange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isApproved
                                  ? AppColors.success
                                  : Colors.orange.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _MaintenanceRecipient {
  final String uid;
  final String label;
  const _MaintenanceRecipient({required this.uid, required this.label});
}

/// Linha mutável no diálogo de escolha múltipla (usuários cadastrados).
class _RegistryPickRow {
  final String uid;
  final String email;
  final String name;
  bool selected = false;
  _RegistryPickRow({
    required this.uid,
    required this.email,
    required this.name,
  });
  String get label =>
      name.isNotEmpty ? '$name ($email)' : (email.isNotEmpty ? email : uid);
}

/// Lista paginada de `users/` com checkboxes — adiciona vários destinatários de manutenção de uma vez.
class _MaintenanceRegistryPickerDialog extends StatefulWidget {
  const _MaintenanceRegistryPickerDialog();

  @override
  State<_MaintenanceRegistryPickerDialog> createState() =>
      _MaintenanceRegistryPickerDialogState();
}

class _MaintenanceRegistryPickerDialogState
    extends State<_MaintenanceRegistryPickerDialog> {
  static const int _pageSize = 80;
  static const int _maxRows = 800;

  final List<_RegistryPickRow> _rows = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _loadingInitial = true;
  bool _loadingMore = false;
  bool _exhausted = false;
  String? _loadError;
  final _filterCtrl = TextEditingController();
  VoidCallback? _detachFilterListener;

  @override
  void initState() {
    super.initState();
    // Debounce: evita `setState` por keystroke (causa do "teclado lento" em
    // listas longas no Admin do Android — IME e rebuild competiam por frame).
    _detachFilterListener = attachDebouncedRebuild(_filterCtrl, () {
      if (mounted) setState(() {});
    });
    _loadPage();
  }

  @override
  void dispose() {
    _detachFilterListener?.call();
    _filterCtrl.dispose();
    super.dispose();
  }

  String get _filterLc => _filterCtrl.text.trim().toLowerCase();

  List<_RegistryPickRow> get _visible {
    if (_filterLc.isEmpty) return _rows;
    return _rows.where((r) {
      return r.label.toLowerCase().contains(_filterLc) ||
          r.uid.toLowerCase().contains(_filterLc);
    }).toList();
  }

  Future<void> _loadPage() async {
    if (_loadingMore || _exhausted || _rows.length >= _maxRows) return;
    setState(() {
      _loadError = null;
      if (_rows.isEmpty) {
        _loadingInitial = true;
      } else {
        _loadingMore = true;
      }
    });
    try {
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collection('users')
          .orderBy(FieldPath.documentId)
          .limit(_pageSize);
      if (_lastDoc != null) q = q.startAfterDocument(_lastDoc!);
      final snap = await q.get();
      if (!mounted) return;
      for (final d in snap.docs) {
        final m = d.data();
        final em = (m['email'] ?? '').toString().trim();
        final name = (m['name'] ?? '').toString().trim();
        _rows.add(_RegistryPickRow(uid: d.id, email: em, name: name));
      }
      if (snap.docs.isEmpty) {
        _exhausted = true;
      } else {
        _lastDoc = snap.docs.last;
        if (snap.docs.length < _pageSize) _exhausted = true;
      }
      if (_rows.length >= _maxRows) _exhausted = true;
    } catch (e) {
      if (mounted) {
        _loadError = e.toString().split('\n').first;
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingInitial = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _setAllVisible(bool checked) {
    setState(() {
      for (final r in _visible) {
        r.selected = checked;
      }
    });
  }

  int get _selectedCount => _rows.where((r) => r.selected).length;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
              decoration: BoxDecoration(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(22)),
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
                  Icon(Icons.groups_rounded,
                      color: Colors.white.withValues(alpha: 0.95)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Quem recebe o aviso',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: FastTextField(
                controller: _filterCtrl,
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
                  labelText: 'Filtrar lista carregada',
                  hintText: 'Nome, e-mail ou trecho do UID',
                  border: OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: Icon(Icons.filter_list_rounded, size: 22),
                ),
              ),
            ),
            if (_loadError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_loadError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed:
                        _visible.isEmpty ? null : () => _setAllVisible(true),
                    child: const Text('Marcar visíveis'),
                  ),
                  TextButton(
                    onPressed:
                        _visible.isEmpty ? null : () => _setAllVisible(false),
                    child: const Text('Desmarcar visíveis'),
                  ),
                  const Spacer(),
                  Text(
                    '${_rows.length} carregado(s) · $_selectedCount selecionado(s)',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            if (_rows.length >= _maxRows)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Limite de $_maxRows contas nesta tela. Use o filtro ou e-mail/UID no painel para achar outros.',
                  style: TextStyle(fontSize: 11, color: Colors.orange.shade900),
                ),
              ),
            Expanded(
              child: _loadingInitial && _rows.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                      ? Center(
                          child: Text(
                            _loadError != null
                                ? 'Não foi possível carregar.'
                                : 'Nenhum usuário encontrado.',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          itemCount: _visible.length + (_exhausted ? 0 : 1),
                          itemBuilder: (context, i) {
                            if (!_exhausted && i == _visible.length) {
                              return Padding(
                                padding: const EdgeInsets.all(12),
                                child: Center(
                                  child: _loadingMore
                                      ? const CircularProgressIndicator()
                                      : TextButton.icon(
                                          onPressed: _loadPage,
                                          icon: const Icon(
                                              Icons.expand_more_rounded),
                                          label: const Text(
                                              'Carregar mais cadastros'),
                                        ),
                                ),
                              );
                            }
                            final r = _visible[i];
                            return CheckboxListTile(
                              value: r.selected,
                              onChanged: (v) =>
                                  setState(() => r.selected = v ?? false),
                              title: Text(
                                r.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                r.uid,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade600),
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
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final out = _rows
                          .where((r) => r.selected)
                          .map((r) => _MaintenanceRecipient(
                                uid: r.uid,
                                label: r.label,
                              ))
                          .toList();
                      if (out.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Marque pelo menos um usuário na lista.'),
                          ),
                        );
                        return;
                      }
                      Navigator.pop(context, out);
                    },
                    child: Text(
                        'Adicionar${_selectedCount > 0 ? ' ($_selectedCount)' : ''}'),
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

/// Tab para enviar mensagem de manutenção (data e hora) — chega para todos na tela principal.
class _ManutencaoTabContent extends StatefulWidget {
  final Color brandBlue;
  final Color brandTeal;

  const _ManutencaoTabContent(
      {required this.brandBlue, required this.brandTeal});

  @override
  State<_ManutencaoTabContent> createState() => _ManutencaoTabContentState();
}

class _ManutencaoTabContentState extends State<_ManutencaoTabContent> {
  final _messageCtrl = TextEditingController();
  final _promoUrlAndroidCtrl = TextEditingController();
  final _promoUrlIosCtrl = TextEditingController();
  final _promoLabelCtrl = TextEditingController();
  final _addEmailCtrl = TextEditingController();
  final _addUidCtrl = TextEditingController();
  DateTime _data = DateTime.now();
  TimeOfDay _hora = TimeOfDay.now();
  bool _saving = false;
  bool _loaded = false;

  /// false = todos; true = só [maintenanceTargetUids].
  bool _restrictRecipients = false;
  final List<_MaintenanceRecipient> _recipients = [];
  bool _lookingUpUser = false;
  bool _useOfficialPromoSite = false;

  /// Botões Play Store (Android) e TestFlight (iOS) na mensagem de melhorias.
  bool _includeAppUpdateButtons = true;

  /// Documento `promotions/{id}` — link no app e no e-mail com `?promo=` (preço da promoção no checkout).
  String? _selectedPromoId;
  bool _sendingMaintenanceEmail = false;

  @override
  void initState() {
    super.initState();
    _loadConfigOnce();
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _promoUrlAndroidCtrl.dispose();
    _promoUrlIosCtrl.dispose();
    _promoLabelCtrl.dispose();
    _addEmailCtrl.dispose();
    _addUidCtrl.dispose();
    super.dispose();
  }

  /// Carrega os dados uma única vez (sem listener) para evitar lentidão e travamentos.
  Future<void> _loadConfigOnce() async {
    try {
      final snap = await FirebaseFirestore.instance.doc('system/config').get();
      final d = snap.data();
      if (d == null || !mounted) return;
      final msg = (d['maintenanceMessage'] ?? '').toString();
      if (msg.isNotEmpty) _messageCtrl.text = msg;
      final dateStr = (d['maintenanceDate'] ?? '').toString();
      if (dateStr.isNotEmpty) {
        final parts = dateStr.split('-');
        if (parts.length == 3) {
          final y = int.tryParse(parts[0]) ?? DateTime.now().year;
          final m = int.tryParse(parts[1]) ?? DateTime.now().month;
          final dd = int.tryParse(parts[2]) ?? DateTime.now().day;
          _data = DateTime(y, m, dd);
        }
      }
      final timeStr = (d['maintenanceTime'] ?? '').toString();
      if (timeStr.isNotEmpty) {
        final tParts = timeStr.split(':');
        if (tParts.length >= 2) {
          _hora = TimeOfDay(
              hour: int.tryParse(tParts[0]) ?? 12,
              minute: int.tryParse(tParts[1]) ?? 0);
        }
      }
      final promoUrlAndroid =
          (d['maintenancePromoUrlAndroid'] ?? '').toString();
      final promoUrlIos = (d['maintenancePromoUrlIos'] ?? '').toString();
      final promoUrlLegacy = (d['maintenancePromoUrl'] ?? '').toString();
      if (promoUrlAndroid.isNotEmpty)
        _promoUrlAndroidCtrl.text = promoUrlAndroid;
      if (promoUrlIos.isNotEmpty) _promoUrlIosCtrl.text = promoUrlIos;
      if (_promoUrlAndroidCtrl.text.trim().isEmpty &&
          promoUrlLegacy.isNotEmpty) {
        _promoUrlAndroidCtrl.text = promoUrlLegacy;
      }
      final promoLbl = (d['maintenancePromoLabel'] ?? '').toString();
      if (promoLbl.isNotEmpty) _promoLabelCtrl.text = promoLbl;
      _useOfficialPromoSite = d['maintenancePromoUseOfficialSite'] == true;
      _includeAppUpdateButtons =
          d['maintenanceIncludeAppUpdateButtons'] != false;
      if (_includeAppUpdateButtons && !_useOfficialPromoSite) {
        if (_promoUrlAndroidCtrl.text.trim().isEmpty) {
          _promoUrlAndroidCtrl.text = VersionCheckService.playStoreAppUrl;
        }
        if (_promoUrlIosCtrl.text.trim().isEmpty) {
          _promoUrlIosCtrl.text = VersionCheckService.effectiveTestFlightUrl;
        }
      }
      final pid = (d['maintenancePromoFirestoreId'] ?? '').toString().trim();
      _selectedPromoId = pid.isEmpty ? null : pid;
      final rawUids = d['maintenanceTargetUids'];
      if (rawUids is List) {
        final uids = rawUids
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (uids.isNotEmpty) {
          _restrictRecipients = true;
          _recipients.clear();
          for (final uid in uids) {
            try {
              final u =
                  await FirebaseFirestore.instance.doc('users/$uid').get();
              final ud = u.data();
              final name = (ud?['name'] ?? '').toString().trim();
              final em = (ud?['email'] ?? '').toString().trim();
              final label =
                  name.isNotEmpty ? '$name ($em)' : (em.isNotEmpty ? em : uid);
              _recipients.add(_MaintenanceRecipient(uid: uid, label: label));
            } catch (_) {
              _recipients.add(_MaintenanceRecipient(uid: uid, label: uid));
            }
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _openRegistryPicker() async {
    final list = await showDialog<List<_MaintenanceRecipient>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _MaintenanceRegistryPickerDialog(),
    );
    if (!mounted || list == null || list.isEmpty) return;
    setState(() {
      _restrictRecipients = true;
      for (final r in list) {
        if (!_recipients.any((x) => x.uid == r.uid)) {
          _recipients.add(r);
        }
      }
    });
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
    setState(() => _lookingUpUser = true);
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
      final doc = q.docs.first;
      _mergeRecipientFromDoc(doc);
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
      if (mounted) setState(() => _lookingUpUser = false);
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
    setState(() => _lookingUpUser = true);
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
      if (mounted) setState(() => _lookingUpUser = false);
    }
  }

  void _mergeRecipientFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final uid = doc.id;
    if (_recipients.any((r) => r.uid == uid)) {
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
      _restrictRecipients = true;
      _recipients.add(_MaintenanceRecipient(uid: uid, label: label));
    });
  }

  void _removeRecipient(String uid) {
    setState(() {
      _recipients.removeWhere((r) => r.uid == uid);
      if (_recipients.isEmpty) {
        _restrictRecipients = false;
      }
    });
  }

  void _showPreview() {
    final msg = _messageCtrl.text.trim().isEmpty
        ? 'Manutenção programada. Pode haver instabilidade no sistema.'
        : _messageCtrl.text.trim();
    final dateStr =
        '${_data.day.toString().padLeft(2, '0')}/${_data.month.toString().padLeft(2, '0')}/${_data.year}';
    final timeStr =
        '${_hora.hour.toString().padLeft(2, '0')}:${_hora.minute.toString().padLeft(2, '0')}';
    final pUrlAndroid = _promoUrlAndroidCtrl.text.trim();
    final pUrlIos = _promoUrlIosCtrl.text.trim();
    final pLbl = _promoLabelCtrl.text.trim();
    final resolvedUrlAndroid = resolveMaintenancePromoLaunchUrl(
      useOfficialPromoSite: _useOfficialPromoSite,
      customUrl: pUrlAndroid,
      promoFirestoreId: _selectedPromoId ?? '',
    );
    final resolvedUrlIos = resolveMaintenancePromoLaunchUrl(
      useOfficialPromoSite: _useOfficialPromoSite,
      customUrl: pUrlIos,
      promoFirestoreId: _selectedPromoId ?? '',
    );
    final showPromoAndroid = resolvedUrlAndroid.isNotEmpty;
    final showPromoIos = resolvedUrlIos.isNotEmpty;
    final showPromo = showPromoAndroid || showPromoIos;
    final destinatarios = !_restrictRecipients
        ? 'Destinatários: todos os usuários.'
        : (_recipients.isEmpty
            ? 'Destinatários: modo selecionados (lista cadastrada ou e-mail/UID).'
            : 'Destinatários: ${_recipients.length} usuário(s).');
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
                decoration: BoxDecoration(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
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
                    Icon(Icons.visibility_rounded,
                        color: Colors.white.withValues(alpha: 0.95)),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Preview da mensagem',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: Colors.orange.shade200.withValues(alpha: 0.85)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(msg,
                          style: const TextStyle(fontSize: 15, height: 1.4)),
                      const SizedBox(height: 8),
                      Text('Data: $dateStr às $timeStr',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade700)),
                      const SizedBox(height: 8),
                      Text(destinatarios,
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade800)),
                      if (showPromo) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Links promoção / pagamento:',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade800),
                        ),
                        if (showPromoAndroid) ...[
                          const SizedBox(height: 4),
                          Text('Android:',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w700)),
                          SelectableText(
                            resolvedUrlAndroid,
                            style: TextStyle(
                                fontSize: 12, color: Colors.blue.shade800),
                          ),
                        ],
                        if (showPromoIos) ...[
                          const SizedBox(height: 4),
                          Text('iPhone:',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w700)),
                          SelectableText(
                            resolvedUrlIos,
                            style: TextStyle(
                                fontSize: 12, color: Colors.blue.shade800),
                          ),
                        ],
                        if ((_selectedPromoId ?? '').trim().isNotEmpty)
                          Text(
                            'Promoção Firestore: ${_selectedPromoId!.trim()} (checkout com preço promocional)',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w600),
                          ),
                        if (pLbl.isNotEmpty)
                          Text('Botão: $pLbl',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade700)),
                        if (showPromo)
                          Text(
                            'E-mail: não sai ao salvar. Use «Enviar e-mails (link do site)» depois de gravar o aviso.',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.teal.shade800,
                                fontWeight: FontWeight.w600),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Fechar'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _maintenanceEmailLaunchLink() {
    final promoUrlAndroid = _promoUrlAndroidCtrl.text.trim();
    final promoUrlIos = _promoUrlIosCtrl.text.trim();
    return resolveMaintenancePromoLaunchUrl(
      useOfficialPromoSite: _useOfficialPromoSite,
      customUrl: promoUrlAndroid.isNotEmpty ? promoUrlAndroid : promoUrlIos,
      promoFirestoreId: _selectedPromoId ?? '',
      source: 'email_promocao',
    );
  }

  Future<void> _sendMaintenanceEmailsNow() async {
    if (_restrictRecipients && _recipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Modo "Somente selecionados": escolha na lista cadastrada ou adicione por e-mail/UID.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    final emailLink = _maintenanceEmailLaunchLink();
    if (emailLink.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Para enviar e-mail, marque «site oficial», informe uma URL https válida ou selecione uma promoção no Firestore.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    final msg = _messageCtrl.text.trim().isEmpty
        ? 'Manutenção programada. Pode haver instabilidade no sistema.'
        : _messageCtrl.text.trim();
    setState(() => _sendingMaintenanceEmail = true);
    try {
      final er = await FunctionsService().sendMaintenancePromoEmails(
        linkUrl: emailLink,
        messageText: msg,
        targetUids: _restrictRecipients && _recipients.isNotEmpty
            ? _recipients.map((e) => e.uid).toList()
            : null,
      );
      if (!mounted) return;
      final sent = er['sent'] ?? 0;
      final failed = er['failed'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'E-mail: $sent enviado(s)${failed > 0 ? ', $failed falha(s)' : ''}.',
          ),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('E-mail: ${e.toString().split('\n').first}'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingMaintenanceEmail = false);
    }
  }

  Future<void> _saveMensagem() async {
    if (_restrictRecipients && _recipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Modo "Somente selecionados": escolha na lista cadastrada ou adicione por e-mail/UID.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final msg = _messageCtrl.text.trim().isEmpty
          ? 'Manutenção programada. Pode haver instabilidade no sistema.'
          : _messageCtrl.text.trim();
      final promoUrlAndroid = _promoUrlAndroidCtrl.text.trim();
      final promoUrlIos = _promoUrlIosCtrl.text.trim();
      final promoLabel = _promoLabelCtrl.text.trim();
      bool isValidHttpUrl(String u) =>
          u.startsWith('http://') || u.startsWith('https://');
      final useAppStoreButtons =
          _includeAppUpdateButtons && !_useOfficialPromoSite;
      final storeAndroid = VersionCheckService.playStoreAppUrl;
      final storeIos = VersionCheckService.effectiveTestFlightUrl;
      final validPromoAndroid = useAppStoreButtons ||
          (!_useOfficialPromoSite &&
              promoUrlAndroid.isNotEmpty &&
              isValidHttpUrl(promoUrlAndroid));
      final validPromoIos = useAppStoreButtons ||
          (!_useOfficialPromoSite &&
              promoUrlIos.isNotEmpty &&
              isValidHttpUrl(promoUrlIos));
      final savedAndroid = useAppStoreButtons ? storeAndroid : promoUrlAndroid;
      final savedIos = useAppStoreButtons ? storeIos : promoUrlIos;
      await FirebaseFirestore.instance.doc('system/config').set({
        'manutencao': false,
        'maintenanceMessage': msg,
        'maintenanceDate':
            '${_data.year}-${_data.month.toString().padLeft(2, '0')}-${_data.day.toString().padLeft(2, '0')}',
        'maintenanceTime':
            '${_hora.hour.toString().padLeft(2, '0')}:${_hora.minute.toString().padLeft(2, '0')}',
        'maintenanceIncludeAppUpdateButtons': _includeAppUpdateButtons,
        'maintenancePromoUseOfficialSite': _useOfficialPromoSite,
        'maintenancePromoUrlAndroid': validPromoAndroid ? savedAndroid : '',
        'maintenancePromoUrlIos': validPromoIos ? savedIos : '',
        // Compatibilidade com app antigo/leitura legada.
        'maintenancePromoUrl':
            validPromoAndroid ? savedAndroid : (validPromoIos ? savedIos : ''),
        'maintenancePromoLabel':
            (_useOfficialPromoSite || validPromoAndroid || validPromoIos)
                ? promoLabel
                : '',
        'maintenancePromoFirestoreId': (_selectedPromoId ?? '').trim(),
        'maintenanceTargetUids': _restrictRecipients && _recipients.isNotEmpty
            ? _recipients.map((e) => e.uid).toList()
            : [],
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await AdminAuditService().logAdminAction(
        action: enviarManutencao,
        targetUserId: 'system',
        details: msg,
      );
      if (mounted) {
        setState(() => _saving = false);
        final base = _restrictRecipients && _recipients.isNotEmpty
            ? 'Mensagem na tela Início para ${_recipients.length} usuário(s).'
            : 'Mensagem na tela Início para todos os usuários.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(base),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  /// Remove a mensagem de manutenção (limpa aviso na tela principal).
  Future<void> _removerMensagem() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Remover mensagem de manutenção?'),
        content: const Text(
            'O aviso deixará de aparecer na tela principal (todos ou selecionados, conforme estava ativo).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Remover')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.doc('system/config').set({
        'manutencao': false,
        'maintenanceMessage': '',
        'maintenanceDate': '',
        'maintenanceTime': '',
        'maintenancePromoUrlAndroid': '',
        'maintenancePromoUrlIos': '',
        'maintenancePromoUrl': '',
        'maintenancePromoLabel': '',
        'maintenancePromoUseOfficialSite': false,
        'maintenanceIncludeAppUpdateButtons': true,
        'maintenancePromoFirestoreId': '',
        'maintenanceTargetUids': [],
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _messageCtrl.clear();
      _promoUrlAndroidCtrl.clear();
      _promoUrlIosCtrl.clear();
      _promoLabelCtrl.clear();
      _useOfficialPromoSite = false;
      _includeAppUpdateButtons = true;
      _selectedPromoId = null;
      _restrictRecipients = false;
      _recipients.clear();
      _data = DateTime.now();
      _hora = TimeOfDay.now();
      await AdminAuditService().logAdminAction(
        action: removerManutencao,
        targetUserId: 'system',
        details: 'Mensagem removida',
      );
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Mensagem de manutenção removida. O aviso não será mais exibido.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final isNarrow = MediaQuery.sizeOf(context).width < 380;
    final horizontalPad = isNarrow ? 12.0 : 16.0;
    if (!_loaded) {
      return ColoredBox(
        color: const Color(0xFFF0F4F9),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
              horizontalPad, 16, horizontalPad, 16 + bottomPad),
          children: [
            const ModuleHeaderPremium(
              title: 'Manutenção',
              icon: Icons.construction_rounded,
              subtitle:
                  'Aviso na tela Início (data/hora e link opcional). E-mail em massa só pelo botão dedicado, após salvar.',
            ),
            const SizedBox(height: 32),
            const Center(child: CircularProgressIndicator()),
          ],
        ),
      );
    }
    return ColoredBox(
      color: const Color(0xFFF0F4F9),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            horizontalPad, 16, horizontalPad, 16 + bottomPad),
        children: [
          const ModuleHeaderPremium(
            title: 'Manutenção',
            icon: Icons.construction_rounded,
            subtitle:
                'Salvar grava o aviso na tela Início. E-mails com link do site são enviados só quando você tocar em «Enviar e-mails».',
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                colors: [
                  AppColors.deepBlue.withValues(alpha: 0.3),
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
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Mensagem para os usuários',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade800)),
                    const SizedBox(height: 8),
                    FastTextField(
                      controller: _messageCtrl,
                      maxLines: 3,
                      textInputAction: TextInputAction.newline,
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      decoration: const InputDecoration(
                        hintText:
                            'Ex.: Temos melhorias na nova versão — toque no botão para atualizar.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _includeAppUpdateButtons = true;
                              _useOfficialPromoSite = false;
                              _messageCtrl.text =
                                  kMaintenanceImprovementsMessageDefault;
                              applyDefaultMaintenanceAppUpdateUrls(
                                setAndroid: (u) =>
                                    _promoUrlAndroidCtrl.text = u,
                                setIos: (u) => _promoUrlIosCtrl.text = u,
                              );
                            });
                          },
                          icon:
                              const Icon(Icons.system_update_rounded, size: 18),
                          label:
                              const Text('Modelo: melhorias + atualizar app'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      value: _includeAppUpdateButtons,
                      onChanged: _useOfficialPromoSite
                          ? null
                          : (v) {
                              setState(() {
                                _includeAppUpdateButtons = v;
                                if (v) {
                                  applyDefaultMaintenanceAppUpdateUrls(
                                    setAndroid: (u) =>
                                        _promoUrlAndroidCtrl.text = u,
                                    setIos: (u) => _promoUrlIosCtrl.text = u,
                                  );
                                }
                              });
                            },
                      title: const Text('Botões de atualização do app'),
                      subtitle: Text(
                        'Android: Google Play · iPhone: TestFlight. Cada usuário vê só o botão da sua plataforma.',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade700),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 8),
                    Text('Links no site (promoção / planos / pagamento)',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade800)),
                    const SizedBox(height: 6),
                    Text(
                      'Opcional. Você pode enviar dois links na mesma mensagem: um para Android e outro para iPhone. Ou marque “site oficial” para usar wisdomapp-b9e98.web.app em ambos.',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      value: _useOfficialPromoSite,
                      onChanged: (v) => setState(() {
                        _useOfficialPromoSite = v;
                        if (v) _includeAppUpdateButtons = false;
                      }),
                      title: const Text('Usar site oficial para promoção'),
                      subtitle: Text(
                        'Abre $kOfficialPromoLandingUrl — a oferta e o checkout ficam no site (login Google, cadastro, PIX/cartão).',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade700),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 4),
                    FastTextField(
                      controller: _promoUrlAndroidCtrl,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      readOnly:
                          _useOfficialPromoSite || _includeAppUpdateButtons,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      decoration: InputDecoration(
                        labelText: _includeAppUpdateButtons
                            ? 'Google Play (automático)'
                            : 'Link Android (opcional)',
                        hintText: _includeAppUpdateButtons
                            ? VersionCheckService.playStoreAppUrl
                            : 'https://... (desmarque “site oficial” para editar)',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.android_rounded),
                        filled:
                            _useOfficialPromoSite || _includeAppUpdateButtons,
                        fillColor:
                            (_useOfficialPromoSite || _includeAppUpdateButtons)
                                ? Colors.grey.shade100
                                : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FastTextField(
                      controller: _promoUrlIosCtrl,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      readOnly:
                          _useOfficialPromoSite || _includeAppUpdateButtons,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      decoration: InputDecoration(
                        labelText: _includeAppUpdateButtons
                            ? 'TestFlight (automático)'
                            : 'Link iPhone (opcional)',
                        hintText: _includeAppUpdateButtons
                            ? VersionCheckService.effectiveTestFlightUrl
                            : 'https://... (desmarque “site oficial” para editar)',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.apple_rounded),
                        filled:
                            _useOfficialPromoSite || _includeAppUpdateButtons,
                        fillColor:
                            (_useOfficialPromoSite || _includeAppUpdateButtons)
                                ? Colors.grey.shade100
                                : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FastTextField(
                      controller: _promoLabelCtrl,
                      textInputAction: TextInputAction.done,
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      decoration: const InputDecoration(
                        labelText: 'Texto do botão (opcional)',
                        hintText: 'Ex.: Ver oferta no site',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Promoção cadastrada (Firestore)',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Selecione uma promoção para o link incluir ?promo=ID em wisdomapp-b9e98.web.app — o checkout usa o preço e a duração da promoção (PIX/cartão no site).',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('promotions')
                          .snapshots(),
                      builder: (context, snap) {
                        final docs = snap.data?.docs ?? [];
                        docs.sort((a, b) {
                          final ta = (a.data()['title'] ?? a.id).toString();
                          final tb = (b.data()['title'] ?? b.id).toString();
                          return ta.toLowerCase().compareTo(tb.toLowerCase());
                        });
                        return LightFilterPicker<String?>(
                          value: _selectedPromoId,
                          label: 'Promoção (opcional)',
                          sheetTitle: 'Promoção (opcional)',
                          decoration: const InputDecoration(
                            labelText: 'Promoção (opcional)',
                            border: OutlineInputBorder(),
                            hintText:
                                'Nenhuma — só URL própria ou site genérico',
                          ),
                          options: [
                            const LightFilterOption<String?>(
                              value: null,
                              label: 'Nenhuma',
                            ),
                            ...docs.map((d) {
                              final m = d.data();
                              final t = (m['title'] ?? d.id).toString();
                              final active = m['active'] != false;
                              return LightFilterOption<String?>(
                                value: d.id,
                                label: active ? t : '$t (inativa)',
                              );
                            }),
                          ],
                          onChanged: (v) =>
                              setState(() => _selectedPromoId = v),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.teal.shade100),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.mark_email_unread_outlined,
                              color: Colors.teal.shade800, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'E-mail com link do site não é enviado ao salvar. Depois de gravar o aviso, use «Enviar e-mails (link do site)» abaixo (Gmail em Admin > E-mail).',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Quem vê o aviso',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade800)),
                    const SizedBox(height: 8),
                    RadioListTile<bool>(
                      value: false,
                      groupValue: _restrictRecipients,
                      title: const Text('Todos os usuários'),
                      subtitle: const Text(
                          'Manutenção e promo na tela Início para toda a base.'),
                      onChanged: (_) => setState(() {
                        _restrictRecipients = false;
                        _recipients.clear();
                      }),
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile<bool>(
                      value: true,
                      groupValue: _restrictRecipients,
                      title: const Text('Somente selecionados'),
                      subtitle: const Text(
                          'Abra a lista cadastrada e marque quem recebe o aviso; ou adicione por e-mail/UID.'),
                      onChanged: (_) =>
                          setState(() => _restrictRecipients = true),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (_restrictRecipients) ...[
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: _lookingUpUser ? null : _openRegistryPicker,
                        icon: const Icon(Icons.groups_rounded),
                        label: const Text('Escolher na lista cadastrada'),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Carrega usuários do Firestore em lotes; marque um ou vários. Combine com e-mail/UID abaixo, se precisar.',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 12),
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
                              onTapOutside: (_) =>
                                  FocusManager.instance.primaryFocus?.unfocus(),
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
                                _lookingUpUser ? null : _addRecipientByEmail,
                            child: _lookingUpUser
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
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
                              onTapOutside: (_) =>
                                  FocusManager.instance.primaryFocus?.unfocus(),
                              decoration: const InputDecoration(
                                labelText: 'UID (opcional)',
                                hintText: 'Cole o ID do documento em users/',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed:
                                _lookingUpUser ? null : _addRecipientByUid,
                            child: const Text('Add UID'),
                          ),
                        ],
                      ),
                      if (_recipients.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Selecionados (${_recipients.length}):',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _recipients
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
                            'Nenhum na lista — use “Escolher na lista cadastrada”, e-mail ou UID.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.orange.shade800),
                          ),
                        ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_today_rounded,
                                size: 18),
                            label: Text(
                                '${_data.day.toString().padLeft(2, '0')}/${_data.month.toString().padLeft(2, '0')}/${_data.year}'),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _data,
                                  firstDate: DateTime(2024),
                                  lastDate: DateTime(2030));
                              if (picked != null)
                                setState(() => _data = picked);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon:
                                const Icon(Icons.access_time_rounded, size: 18),
                            label: Text(
                                '${_hora.hour.toString().padLeft(2, '0')}:${_hora.minute.toString().padLeft(2, '0')}'),
                            onPressed: () async {
                              final picked = await showTimePicker(
                                  context: context, initialTime: _hora);
                              if (picked != null)
                                setState(() => _hora = picked);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _showPreview(),
                      icon: const Icon(Icons.visibility_rounded, size: 18),
                      label: const Text('Visualizar antes de salvar'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: widget.brandBlue),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: (_saving || _sendingMaintenanceEmail)
                              ? null
                              : _saveMensagem,
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
                                  color: AppColors.deepBlueDark
                                      .withValues(alpha: 0.28),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (_saving)
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  else ...[
                                    const Icon(Icons.save_rounded,
                                        color: Colors.white, size: 22),
                                    const SizedBox(width: 10),
                                    const Text(
                                      'Salvar na tela Início',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: (_saving || _sendingMaintenanceEmail)
                            ? null
                            : _sendMaintenanceEmailsNow,
                        icon: _sendingMaintenanceEmail
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.mark_email_unread_outlined,
                                size: 22),
                        label: Text(_sendingMaintenanceEmail
                            ? 'Enviando e-mails…'
                            : 'Enviar e-mails (link do site)'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          foregroundColor: AppColors.deepBlueDark,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: (_saving || _sendingMaintenanceEmail)
                          ? null
                          : _removerMensagem,
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      label: const Text('Remover mensagem'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tab para configurar envio de e-mail (lembretes de plantão, licença). Firestore settings/email.
class _EmailConfigTabContent extends StatefulWidget {
  final Color brandBlue;
  final Color brandTeal;

  const _EmailConfigTabContent(
      {required this.brandBlue, required this.brandTeal});

  @override
  State<_EmailConfigTabContent> createState() => _EmailConfigTabContentState();
}

class _EmailConfigTabContentState extends State<_EmailConfigTabContent> {
  final _userCtrl = TextEditingController();
  final _appPasswordCtrl = TextEditingController();
  bool _saving = false;
  bool _sendingTest = false;
  bool _sendingTestGmail = false;
  bool _sendingRetroactive = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _appPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('settings')
          .doc('email')
          .get();
      final d = snap.data();
      if (d != null && mounted) {
        final user = (d['user'] ?? d['email'] ?? '').toString().trim();
        if (user.isNotEmpty) _userCtrl.text = user;
        // Senha de app não é reexibida por segurança; campo fica vazio
      }
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _save() async {
    final user = _userCtrl.text.trim();
    // Senha de app Gmail: 16 caracteres; remover todos os espaços (evita erro 535 "Username and Password not accepted")
    final pass = _appPasswordCtrl.text.replaceAll(RegExp(r'\s'), '').trim();
    if (user.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Informe o e-mail (Gmail) que enviará as mensagens.'),
            backgroundColor: AppColors.error),
      );
      return;
    }
    if (pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Informe a senha de app do Gmail (16 caracteres, gerada em Conta Google > Senhas de app).'),
            backgroundColor: AppColors.error),
      );
      return;
    }
    if (pass.length != 16) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'A senha de app do Gmail tem 16 caracteres (sem espaços). Você digitou ${pass.length}. Gere uma nova em Conta Google → Segurança → Senhas de app.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('settings').doc('email').set({
        'user': user,
        'appPassword': pass,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        setState(() => _saving = false);
        _appPasswordCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Configuração de e-mail salva. Lembretes e avisos de licença serão enviados por e-mail.'),
              backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  /// Envia e-mail de teste usando a mesma lógica do reset de senha: Firebase Auth envia,
  /// sem precisar configurar Gmail. O Firebase pode aceitar o pedido mas o e-mail ir para spam ou atrasar.
  Future<void> _sendTestEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email?.trim();
    if (email == null || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Sua conta não tem e-mail. Use uma conta com e-mail para testar.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    setState(() => _sendingTest = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        setState(() => _sendingTest = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pedido enviado ao Firebase para $email. Pode levar 1–2 min. Confira: Caixa de entrada, Spam e Promoções. '
              'Se não chegar: Firebase Console > Authentication > Templates (modelo de redefinição de senha).',
            ),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _sendingTest = false);
        String msg = e.message ?? 'Erro ao enviar e-mail.';
        if (e.code == 'user-not-found')
          msg = 'Nenhuma conta com este e-mail no Firebase Auth.';
        if (e.code == 'invalid-email') msg = 'E-mail inválido.';
        if (e.code == 'too-many-requests')
          msg = 'Muitas tentativas. Espere alguns minutos.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.error),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sendingTest = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  /// Teste usando o Gmail configurado acima (mesmo canal dos lembretes de plantão).
  Future<void> _sendTestEmailViaGmail() async {
    setState(() => _sendingTestGmail = true);
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('ctSendTestEmail')
          .call<Map<String, dynamic>>({});
      final data = res.data ?? {};
      if (mounted) {
        setState(() => _sendingTestGmail = false);
        if (data['ok'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'E-mail de teste enviado pelo Gmail! Confira a caixa de entrada e o spam.'),
                backgroundColor: AppColors.success),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Falha: ${data['error'] ?? 'erro desconhecido'}'),
                backgroundColor: AppColors.error),
          );
        }
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() => _sendingTestGmail = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.message ?? 'Erro ao enviar teste'),
              backgroundColor: AppColors.error),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sendingTestGmail = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _runLembretesRetroativos() async {
    setState(() => _sendingRetroactive = true);
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('ctEnviarLembretesRetroativos')
          .call<Map<String, dynamic>>({});
      final data = res.data ?? {};
      if (mounted) {
        setState(() => _sendingRetroactive = false);
        final pushSent = data['pushSent'] as int? ?? 0;
        final emailSent = data['emailSent'] as int? ?? 0;
        final errs = data['errors'] as List<dynamic>?;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Concluído. Push: $pushSent, E-mail: $emailSent${errs != null && errs.isNotEmpty ? '. Erros: ${errs.length}' : ''}.'),
            backgroundColor: (errs != null && errs.isNotEmpty)
                ? Colors.orange
                : AppColors.success,
          ),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() => _sendingRetroactive = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(e.message ?? 'Erro ao enviar lembretes retroativos'),
              backgroundColor: AppColors.error),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sendingRetroactive = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    if (!_loaded) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPad),
        children: [
          const ModuleHeaderPremium(
            title: 'E-mail',
            icon: Icons.email_rounded,
            subtitle:
                'Configure o Gmail para lembretes financeiros, agenda, cursos e avisos de licença por e-mail.',
          ),
          const SizedBox(height: 32),
          const Center(child: CircularProgressIndicator()),
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPad),
      children: [
        const ModuleHeaderPremium(
          title: 'E-mail',
          icon: Icons.email_rounded,
          subtitle:
              'Configure o Gmail para lembretes financeiros, agenda, cursos e avisos de licença. Use senha de app (não a senha normal da conta).',
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 20, color: Colors.blue.shade800),
                  const SizedBox(width: 8),
                  Text('Como funciona (milhares de usuários)',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.blue.shade900)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '• Você configura aqui apenas UMA conta Gmail (a que envia). Essa conta envia para todos os usuários.\n\n'
                '• O sistema é 100% automático: a cada 5 minutos o servidor verifica, para cada usuário, se há conta a vencer, compromisso na agenda ou curso novo. Se houver, envia:\n'
                '  – Notificação na tela (push no celular/app)\n'
                '  – E-mail para o endereço cadastrado do usuário\n\n'
                '• Ninguém precisa clicar em "enviar". Com 5 mil usuários, cada um recebe na hora certa: lembretes na tela e por e-mail.',
                style: TextStyle(
                    fontSize: 13, height: 1.4, color: Colors.blue.shade900),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AdminNotificationTemplatesSection(brandBlue: widget.brandBlue),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.mail_rounded,
                      size: 20, color: Colors.green.shade800),
                  const SizedBox(width: 8),
                  Text('O que os clientes recebem (Gmail acima)',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.green.shade900)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '• Lembrete financeiro — contas a pagar ou receber próximas do vencimento.\n'
                '• Lembrete de agenda — compromissos com título, data e hora.\n'
                '• Novos cursos — quando publicar vídeo no módulo Cursos.\n'
                '• Licença vencendo — e-mail "Licença vence em 3 (ou 7) dias" para renovação.\n\n'
                'Todos enviados pelo Gmail que você configurou. O botão "Enviar e-mail de teste (sem usar Gmail)" só envia um e-mail de redefinição de senha para testar se a entrega funciona; não é o conteúdo que os clientes recebem. Para testar o envio real, use "Enviar teste via Gmail" ou "Enviar lembretes retroativos".',
                style: TextStyle(
                    fontSize: 13, height: 1.4, color: Colors.green.shade900),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.grey.shade200)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('E-mail (Gmail) — conta que envia para todos',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade800)),
                const SizedBox(height: 6),
                FastTextField(
                  controller: _userCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                    hintText: 'ex.: seu@gmail.com',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Senha de app do Gmail',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade800)),
                const SizedBox(height: 6),
                FastTextField(
                  controller: _appPasswordCtrl,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                    hintText:
                        '16 caracteres, sem espaços (pode colar com espaços que serão removidos)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Gmail → Conta Google → Segurança → Verificação em 2 etapas (ative) → Senhas de app → Gerar nova. Cole a senha de 16 caracteres; espaços são removidos ao salvar.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_rounded, size: 20),
                    label: const Text('Salvar configuração'),
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: (_saving || _sendingTest) ? null : _sendTestEmail,
                  icon: _sendingTest
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.mark_email_read_rounded, size: 20),
                  label: Text(_sendingTest
                      ? 'Enviando...'
                      : 'Enviar e-mail de teste (sem usar Gmail)'),
                ),
                const SizedBox(height: 6),
                Text(
                  'Apenas teste de entrega: o e-mail chega como "redefinição de senha" de propósito. Os clientes recebem lembretes financeiros, de agenda e avisos de licença (enviados pelo Gmail acima).',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: (_saving ||
                          _sendingTest ||
                          _sendingTestGmail ||
                          _sendingRetroactive)
                      ? null
                      : _sendTestEmailViaGmail,
                  icon: _sendingTestGmail
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.mark_email_unread_rounded, size: 20),
                  label: Text(_sendingTestGmail
                      ? 'Enviando...'
                      : 'Enviar teste via Gmail (configuração acima)'),
                ),
                const SizedBox(height: 4),
                Text(
                  'Usa o mesmo envio dos lembretes automáticos. Preencha Gmail + senha de app e salve antes.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: (_saving || _sendingRetroactive)
                      ? null
                      : _runLembretesRetroativos,
                  icon: _sendingRetroactive
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.schedule_send_rounded, size: 20),
                  label: Text(_sendingRetroactive
                      ? 'Enviando...'
                      : 'Enviar lembretes retroativos (a partir de hoje)'),
                ),
                const SizedBox(height: 6),
                Text(
                  'Envia e-mail e push de lembretes financeiros e de agenda a partir de hoje para usuários que ainda não foram notificados.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Tab para publicar o app nas lojas (Play Store e App Store)
class _LojasTabContent extends StatefulWidget {
  final Color brandBlue;
  final Color brandTeal;

  const _LojasTabContent({required this.brandBlue, required this.brandTeal});

  @override
  State<_LojasTabContent> createState() => _LojasTabContentState();
}

class _LojasTabContentState extends State<_LojasTabContent> {
  bool _uploading = false;
  bool _submitting = false;
  String? _aabStoragePath;
  String? _lastError;
  bool _uploadingApk = false;
  String? _apkTestDownloadUrl;

  static const String _testApkStoragePath = 'admin/test/app-release.apk';

  /// Pasta do Google Drive onde o APK fica disponível para download (CONTROLETOTAL > APK_ANDROID).
  static const String _apkGoogleDriveFolderUrl =
      'https://drive.google.com/drive/u/0/folders/1_05BjX8boKktub1AnKmSjfc9n3e-pjcf';

  @override
  void initState() {
    super.initState();
    _loadTestApkUrl();
  }

  Future<void> _loadTestApkUrl() async {
    try {
      final ref = FirebaseStorage.instance.ref().child(_testApkStoragePath);
      final url = await ref.getDownloadURL();
      if (mounted) setState(() => _apkTestDownloadUrl = url);
    } catch (_) {
      if (mounted) setState(() => _apkTestDownloadUrl = null);
    }
  }

  Future<void> _pickAndUploadApkForTest() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['apk'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Não foi possível ler o arquivo. Tente novamente.')),
      );
      return;
    }
    setState(() {
      _uploadingApk = true;
      _lastError = null;
    });
    try {
      final ref = FirebaseStorage.instance.ref().child(_testApkStoragePath);
      await ref.putData(
          bytes,
          SettableMetadata(
              contentType: 'application/vnd.android.package-archive'));
      final url = await ref.getDownloadURL();
      if (mounted) {
        setState(() {
          _apkTestDownloadUrl = url;
          _uploadingApk = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'APK enviado. Use "Baixar APK para teste" para instalar no celular.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploadingApk = false;
          _lastError = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao enviar APK: $e')),
        );
      }
    }
  }

  Future<void> _downloadTestApk() async {
    if (_apkTestDownloadUrl == null) return;
    try {
      await url_helper.openUrlPreferChrome(_apkTestDownloadUrl!);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao abrir link: $e')));
    }
  }

  Future<void> _pickAndUploadAab() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['aab'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Não foi possível ler o arquivo. Tente novamente.')),
      );
      return;
    }
    setState(() {
      _uploading = true;
      _lastError = null;
    });
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('releases')
          .child('app-release.aab');
      await ref.putData(
          bytes, SettableMetadata(contentType: 'application/octet-stream'));
      if (mounted) {
        setState(() {
          _aabStoragePath = 'releases/app-release.aab';
          _uploading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'AAB enviado com sucesso. Clique em "Enviar para Play Store".')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploading = false;
          _lastError = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao enviar AAB: $e')),
        );
      }
    }
  }

  Future<void> _submitToPlayStore() async {
    if (_aabStoragePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Envie um AAB primeiro.')),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _lastError = null;
    });
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('ctSubmitToPlayStore')
          .call({
        'storagePath': _aabStoragePath,
      });
      final data = res.data as Map<String, dynamic>?;
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  data?['message'] ?? 'Publicação solicitada com sucesso.')),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _lastError = e.message ?? e.code;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: ${e.message ?? e.code}')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _lastError = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  Future<void> _openUrl(String url) async {
    try {
      await url_helper.openUrlPreferChrome(url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao abrir link: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const ModuleHeaderPremium(
          title: 'Publicar nas Lojas',
          icon: Icons.store_rounded,
          subtitle:
              'Envie o AAB para a Play Store e acesse o App Store Connect para iOS.',
        ),
        const SizedBox(height: 16),
        // Google Play Store
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.android, color: AppColors.success, size: 28),
                    const SizedBox(width: 10),
                    const Text('Google Play Store',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '1. Gere o AAB: flutter build appbundle\n'
                  '2. Envie o arquivo abaixo\n'
                  '3. Clique em "Enviar para Play Store"',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade700, height: 1.5),
                ),
                const SizedBox(height: 16),
                if (_aabStoragePath != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle,
                            color: AppColors.success, size: 20),
                        const SizedBox(width: 8),
                        Text('AAB pronto: $_aabStoragePath',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _uploading ? null : _pickAndUploadAab,
                      icon: _uploading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.upload_file_rounded, size: 20),
                      label: Text(_uploading
                          ? 'Enviando...'
                          : 'Selecionar e enviar AAB'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _submitting || _aabStoragePath == null
                          ? null
                          : _submitToPlayStore,
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.publish_rounded, size: 20),
                      label: Text(_submitting
                          ? 'Enviando...'
                          : 'Enviar para Play Store'),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.deepBlue),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _openUrl('https://play.google.com/console'),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Abrir Play Console'),
                ),
                const SizedBox(height: 20),
                // Testar no celular antes de publicar (só admin)
                Divider(height: 1, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text(
                  'Testar no celular antes de publicar',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Colors.grey.shade800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Envie um APK (flutter build apk) e baixe aqui para instalar no celular como na Play Store.',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600, height: 1.4),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed:
                          _uploadingApk ? null : _pickAndUploadApkForTest,
                      icon: _uploadingApk
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.upload_file_rounded, size: 20),
                      label: Text(_uploadingApk
                          ? 'Enviando...'
                          : 'Selecionar e enviar APK para teste'),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed:
                          _apkTestDownloadUrl == null ? null : _downloadTestApk,
                      icon: const Icon(Icons.download_rounded, size: 20),
                      label: const Text('Baixar APK para teste'),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.success),
                    ),
                  ],
                ),
                if (_apkTestDownloadUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle,
                            color: AppColors.success, size: 18),
                        const SizedBox(width: 6),
                        Text('APK disponível para download.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade700)),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                Divider(height: 1, color: Colors.grey.shade300),
                const SizedBox(height: 10),
                Text(
                  'Ou baixe o APK na pasta do Google Drive',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Colors.grey.shade800),
                ),
                const SizedBox(height: 6),
                Text(
                  'O arquivo pode ser enviado para a pasta APK_ANDROID no Drive e baixado por este link.',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600, height: 1.3),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () => _openUrl(_apkGoogleDriveFolderUrl),
                  icon: const Icon(Icons.folder_open_rounded, size: 20),
                  label: const Text('Abrir pasta APK no Google Drive'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
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
                          Icon(Icons.info_outline_rounded,
                              size: 18, color: Colors.amber.shade800),
                          const SizedBox(width: 8),
                          Text('Configuração',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.amber.shade900)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Para envio automático, adicione em Firestore: settings/play_store, campo service_account_json (JSON da service account do Play Console). Ou defina a variável PLAY_STORE_SERVICE_ACCOUNT_JSON nas Functions.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.amber.shade900),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Apple App Store
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.apple, color: Colors.grey.shade800, size: 28),
                    const SizedBox(width: 10),
                    const Text('Apple App Store',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'O build iOS requer Mac com Xcode. Use Codemagic, GitHub Actions (macOS) ou Xcode local.\n'
                  'Após gerar o IPA, envie pelo Transporter ou App Store Connect.',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade700, height: 1.5),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () =>
                      _openUrl('https://appstoreconnect.apple.com'),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Abrir App Store Connect'),
                ),
              ],
            ),
          ),
        ),
        if (_lastError != null) ...[
          const SizedBox(height: 12),
          Card(
            color: AppColors.error.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_lastError!,
                  style: TextStyle(color: AppColors.error, fontSize: 13)),
            ),
          ),
        ],
      ],
    );
  }
}

class _DriveBackupTabContent extends StatefulWidget {
  final Color brandBlue;
  final Color brandTeal;

  const _DriveBackupTabContent(
      {required this.brandBlue, required this.brandTeal});

  @override
  State<_DriveBackupTabContent> createState() => _DriveBackupTabContentState();
}

class _DriveBackupTabContentState extends State<_DriveBackupTabContent> {
  bool _loading = true;
  bool _creating = false;
  bool _restoring = false;
  List<Map<String, dynamic>> _backups = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await FunctionsService().listFirebaseBackups();
      final list =
          (res['backups'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
              [];
      if (mounted)
        setState(() {
          _backups = list;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _backups = [];
          _loading = false;
        });
    }
  }

  Future<void> _createBackup() async {
    setState(() => _creating = true);
    try {
      final res = await FunctionsService().createFirebaseBackup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(res['message'] ?? 'Backup criado com sucesso.'),
              backgroundColor: Colors.green),
        );
        _load();
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.message ?? 'Erro ao criar backup.'),
              backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString().replaceAll('Exception:', '').trim()),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _downloadBackup(String path) async {
    try {
      final res =
          await FunctionsService().getFirebaseBackupDownloadUrl(path: path);
      final url = (res['url'] ?? '').toString();
      if (url.isEmpty) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('URL não retornada.')));
        return;
      }
      try {
        await url_helper.openUrlPreferChrome(url);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Abrindo download...')));
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Erro ao abrir link: $e')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Erro ao obter link: ${e.toString().split('\n').first}'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _restoreBackup(String path, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Restaurar backup?'),
        content: Text(
            'Isso irá sobrescrever dados existentes no Firestore com os dados do backup "$name". Deseja continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _restoring = true);
    try {
      await FunctionsService().restoreFirebaseBackup(path: path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Backup restaurado com sucesso.'),
            backgroundColor: Colors.green));
        _load();
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.message ?? 'Erro ao restaurar.'),
              backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString().replaceAll('Exception:', '').trim()),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const ModuleHeaderPremium(
          title: 'Backup no Firebase',
          icon: Icons.cloud_rounded,
          subtitle:
              'Backups são salvos no Firebase Storage. Crie, baixe ou restaure um backup.',
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: (_creating || _restoring) ? null : _createBackup,
                  icon: _creating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.add_circle_outline_rounded),
                  label: Text(
                      _creating ? 'Criando backup...' : 'Criar backup agora'),
                  style: FilledButton.styleFrom(
                      backgroundColor: widget.brandTeal,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('Backups disponíveis',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        if (_loading)
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator()))
        else if (_backups.isEmpty)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_off_rounded,
                        size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text('Nenhum backup encontrado.',
                        style: TextStyle(color: Colors.grey.shade600)),
                    const SizedBox(height: 8),
                    Text(
                        'Clique em "Criar backup agora" para gerar o primeiro.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _backups.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final b = _backups[i];
              final name = (b['name'] ?? '').toString();
              final path = (b['path'] ?? name).toString();
              final size = (b['size'] ?? 0) as num;
              final sizeStr = size >= 1024
                  ? '${(size / 1024).toStringAsFixed(1)} KB'
                  : '$size B';
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 2))
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: widget.brandBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.insert_drive_file_rounded,
                          color: widget.brandBlue, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          Text(sizeStr,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.download_rounded),
                      onPressed: () => _downloadBackup(path),
                      tooltip: 'Baixar',
                    ),
                    IconButton(
                      icon: const Icon(Icons.restore_rounded),
                      onPressed:
                          _restoring ? null : () => _restoreBackup(path, name),
                      tooltip: 'Restaurar',
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

class _AdminStats {
  final int totalUsers;
  final int totalAdmins;

  /// Um card por convênio ativo em `partnerships` (ASSEGO, UNIMIL, etc.).
  final List<AdminPartnershipMetric> partnershipMetrics;

  /// Campo `users.partnershipId` preenchido (vínculo explícito com convênio).
  final int totalUsersWithPartnership;
  final int totalPremiums;
  final int txCount30d;
  final double txValue30d;
  final double revenue30d;
  final double pixBruto;
  final double pixLiquido;
  final double cardBruto;
  final double cardLiquido;
  final int legacyMp;
  final int premiumMp;
  final List<double> chartValues;
  final List<String> chartLabels;

  /// Mercado Pago: bruto aprovado por faixa de dias (alinhado ao período do resumo).
  final List<double> mpRevenueBrutoByBucket;
  final List<double> mpRevenueLiquidoByBucket;
  final List<String> mpRevenueBucketLabels;
  final List<Map<String, dynamic>> usersSample;
  final List<Map<String, dynamic>> lastPayments;
  final int licensesExpiring7d;
  final int licensesExpired;

  /// Vencimentos futuros agregados (snapshot atual; próximos 90 dias em faixas).
  final List<int> licenseExpiryHorizonCounts;
  final List<String> licenseExpiryHorizonLabels;
  final double usersEstimatedMb;
  final double txEstimatedMb;
  final DateTime? latestTransactionAt;
  final DateTime? latestUserCreatedAt;
  final DateTime? latestPaymentApprovedAt;

  /// Quando há muitos lançamentos: volume/gráfico vêm de amostra (ver [_kAdminTxMaxDetailDocs]).
  final String? txResumoAviso;

  _AdminStats({
    required this.totalUsers,
    required this.totalAdmins,
    this.partnershipMetrics = const [],
    this.totalUsersWithPartnership = 0,
    required this.totalPremiums,
    required this.txCount30d,
    required this.txValue30d,
    this.revenue30d = 0,
    this.pixBruto = 0,
    this.pixLiquido = 0,
    this.cardBruto = 0,
    this.cardLiquido = 0,
    this.legacyMp = 0,
    this.premiumMp = 0,
    required this.chartValues,
    required this.chartLabels,
    this.mpRevenueBrutoByBucket = const [],
    this.mpRevenueLiquidoByBucket = const [],
    this.mpRevenueBucketLabels = const [],
    required this.usersSample,
    this.lastPayments = const [],
    this.licensesExpiring7d = 0,
    this.licensesExpired = 0,
    this.licenseExpiryHorizonCounts = const [],
    this.licenseExpiryHorizonLabels = const [],
    this.usersEstimatedMb = 0,
    this.txEstimatedMb = 0,
    this.latestTransactionAt,
    this.latestUserCreatedAt,
    this.latestPaymentApprovedAt,
    this.txResumoAviso,
  });
}

class _InactiveUsersSnapshot {
  final List<Map<String, dynamic>> bucket30;
  final List<Map<String, dynamic>> bucket60;
  final List<Map<String, dynamic>> bucket90;

  const _InactiveUsersSnapshot({
    required this.bucket30,
    required this.bucket60,
    required this.bucket90,
  });
}

class _AdminInactiveUsersPanel extends StatefulWidget {
  final bool useUnifiedPanel;
  final String selectedApp;
  final Future<void> Function(List<Map<String, dynamic>> users)
      onDeleteUsersPermanent;

  const _AdminInactiveUsersPanel({
    required this.useUnifiedPanel,
    required this.selectedApp,
    required this.onDeleteUsersPermanent,
  });

  @override
  State<_AdminInactiveUsersPanel> createState() =>
      _AdminInactiveUsersPanelState();
}

class _AdminInactiveUsersPanelState extends State<_AdminInactiveUsersPanel> {
  late Future<_InactiveUsersSnapshot> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadInactiveUsers();
  }

  @override
  void didUpdateWidget(covariant _AdminInactiveUsersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedApp != widget.selectedApp ||
        oldWidget.useUnifiedPanel != widget.useUnifiedPanel) {
      _future = _loadInactiveUsers();
    }
  }

  Future<_InactiveUsersSnapshot> _loadInactiveUsers() async {
    final callable = FirebaseFunctions.instance.httpsCallable(
      'ctAdminListInactiveUsers',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 280)),
    );
    String? cursor;
    final bucket30ByUid = <String, Map<String, dynamic>>{};
    final bucket60ByUid = <String, Map<String, dynamic>>{};
    final bucket90ByUid = <String, Map<String, dynamic>>{};

    while (true) {
      final payload = <String, dynamic>{
        'pageSize': 250,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        if (widget.useUnifiedPanel) 'app': widget.selectedApp,
      };
      final res = await callable.call<Map<String, dynamic>>(payload);
      final data = (res.data);
      final list30 = ((data['inactive30'] as List?) ?? const <dynamic>[]);
      final list60 = ((data['inactive60'] as List?) ?? const <dynamic>[]);
      final list90 = ((data['inactive90'] as List?) ?? const <dynamic>[]);

      for (final raw in list30) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final uid = (map['uid'] ?? '').toString();
        if (uid.isNotEmpty) bucket30ByUid[uid] = map;
      }
      for (final raw in list60) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final uid = (map['uid'] ?? '').toString();
        if (uid.isNotEmpty) bucket60ByUid[uid] = map;
      }
      for (final raw in list90) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final uid = (map['uid'] ?? '').toString();
        if (uid.isNotEmpty) bucket90ByUid[uid] = map;
      }

      final next = (data['nextCursor'] ?? '').toString().trim();
      if (next.isEmpty) break;
      cursor = next;
    }

    List<Map<String, dynamic>> sortUsers(
        Map<String, Map<String, dynamic>> source) {
      final list = source.values.toList();
      list.sort((a, b) => (a['name'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['name'] ?? '').toString().toLowerCase()));
      return list;
    }

    return _InactiveUsersSnapshot(
      bucket30: sortUsers(bucket30ByUid),
      bucket60: sortUsers(bucket60ByUid),
      bucket90: sortUsers(bucket90ByUid),
    );
  }

  Future<void> _openInactiveList(
    BuildContext context,
    String title,
    List<Map<String, dynamic>> users,
  ) async {
    final selected = <String>{};
    // Debounced: evita rebuild da lista a cada tecla (Android Gboard lento).
    final searchCtrl = DebouncedTextController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return ValueListenableBuilder<String>(
              valueListenable: searchCtrl.debouncedText,
              builder: (ctx, debouncedQ, _) {
                final q = debouncedQ.trim().toLowerCase();
                final filtered = q.isEmpty
                    ? users
                    : users.where((u) {
                        final name = (u['name'] ?? '').toString().toLowerCase();
                        final email =
                            (u['email'] ?? '').toString().toLowerCase();
                        return name.contains(q) || email.contains(q);
                      }).toList();
                return SafeArea(
                  child: SizedBox(
                    height: MediaQuery.sizeOf(ctx).height * 0.86,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          FastTextField(
                            controller: searchCtrl,
                            // Sem `onChanged: setState` — o
                            // `ValueListenableBuilder` acima reage ao debounce.
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
                              isDense: true,
                              prefixIcon: Icon(Icons.search_rounded),
                              border: OutlineInputBorder(),
                              hintText: 'Buscar por nome ou e-mail',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => setSheetState(() {
                                  selected
                                    ..clear()
                                    ..addAll(filtered.map(
                                        (e) => (e['uid'] ?? '').toString()));
                                }),
                                icon: const Icon(Icons.select_all_rounded),
                                label: const Text('Selecionar filtrados'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => setSheetState(selected.clear),
                                icon: const Icon(Icons.deselect_rounded),
                                label: const Text('Limpar seleção'),
                              ),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.error),
                                onPressed: selected.isEmpty
                                    ? null
                                    : () async {
                                        final payload = filtered
                                            .where((u) => selected.contains(
                                                (u['uid'] ?? '').toString()))
                                            .toList();
                                        await widget
                                            .onDeleteUsersPermanent(payload);
                                        if (ctx.mounted) Navigator.pop(ctx);
                                        if (mounted) {
                                          setState(() =>
                                              _future = _loadInactiveUsers());
                                        }
                                      },
                                icon: const Icon(Icons.delete_forever_rounded),
                                label: Text(
                                    'Excluir selecionados (${selected.length})'),
                              ),
                              FilledButton.tonalIcon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.orange.shade100,
                                  foregroundColor: Colors.orange.shade900,
                                ),
                                onPressed: filtered.isEmpty
                                    ? null
                                    : () async {
                                        await widget
                                            .onDeleteUsersPermanent(filtered);
                                        if (ctx.mounted) Navigator.pop(ctx);
                                        if (mounted) {
                                          setState(() =>
                                              _future = _loadInactiveUsers());
                                        }
                                      },
                                icon: const Icon(Icons.delete_sweep_rounded),
                                label:
                                    Text('Excluir todos (${filtered.length})'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: filtered.isEmpty
                                ? const Center(
                                    child: Text('Nenhum usuário nesta lista.'))
                                : ListView.builder(
                                    itemCount: filtered.length,
                                    itemBuilder: (context, i) {
                                      final u = filtered[i];
                                      final uid = (u['uid'] ?? '').toString();
                                      final name = (u['name'] ?? '').toString();
                                      final email =
                                          (u['email'] ?? '').toString();
                                      final plan = (u['plan'] ?? '').toString();
                                      final isSel = selected.contains(uid);
                                      return CheckboxListTile(
                                        value: isSel,
                                        onChanged: (_) => setSheetState(() {
                                          if (isSel) {
                                            selected.remove(uid);
                                          } else {
                                            selected.add(uid);
                                          }
                                        }),
                                        title: Text(
                                            name.isEmpty ? 'Sem nome' : name),
                                        subtitle: Text(
                                          '${email.isEmpty ? 'Sem e-mail' : email} • Plano: ${plan.isEmpty ? '—' : plan}',
                                        ),
                                        controlAffinity:
                                            ListTileControlAffinity.leading,
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
    searchCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_InactiveUsersSnapshot>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(minHeight: 3),
            ),
          );
        }
        if (snap.hasError || snap.data == null) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Falha ao calcular inatividade: ${snap.error}'),
            ),
          );
        }
        final data = snap.data!;
        final buckets = [
          ('Sem movimentação 30 dias (1 mês)', data.bucket30),
          ('Sem movimentação 60 dias (2 meses)', data.bucket60),
          ('Sem movimentação 90 dias (3 meses)', data.bucket90),
        ];
        final maxCount = buckets
            .map((b) => b.$2.length)
            .fold<int>(1, (prev, curr) => curr > prev ? curr : prev);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Inatividade de usuários (clique no gráfico para abrir lista)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Base com até 5.000 usuários e movimentações de transações dos últimos 90 dias.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: buckets.map((entry) {
                  final title = entry.$1;
                  final users = entry.$2;
                  final h = (users.length / maxCount) * 120;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _openInactiveList(context, title, users),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: Column(
                            children: [
                              Text(
                                '${users.length}',
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                height: h < 8 ? 8 : h,
                                width: 22,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2563EB),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AdminUserMonitoringPanel extends StatelessWidget {
  final _AdminStats stats;
  final int periodoDias;
  final Color brandBlue;
  final Color brandTeal;

  const _AdminUserMonitoringPanel({
    required this.stats,
    required this.periodoDias,
    required this.brandBlue,
    required this.brandTeal,
  });

  String _fmtDateTime(DateTime? dt) {
    if (dt == null) return '--';
    return DateFormat('dd/MM/yyyy HH:mm').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final freeUsers = (stats.totalUsers - stats.totalPremiums) < 0
        ? 0
        : (stats.totalUsers - stats.totalPremiums);
    final totalEstimatedMb = stats.usersEstimatedMb + stats.txEstimatedMb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AdminSectionTitle(
          icon: Icons.insights_rounded,
          title: 'Operações, armazenamento e lançamentos',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              label: 'Espaço base usuários (estimado)',
              value: '${stats.usersEstimatedMb.toStringAsFixed(2)} MB',
              subValue: 'Estimativa por amostragem de documentos users',
              color: brandBlue,
              icon: Icons.storage_rounded,
            ),
            _MetricCard(
              label: 'Espaço lançamentos ${periodoDias}d',
              value: '${stats.txEstimatedMb.toStringAsFixed(2)} MB',
              subValue: stats.txResumoAviso == null
                  ? 'Amostragem de transactions do período'
                  : 'Projeção pelo total; corpo usado é amostra (ver nota no resumo)',
              color: brandTeal,
              icon: Icons.receipt_long_rounded,
            ),
            _MetricCard(
              label: 'Espaço total estimado',
              value: '${totalEstimatedMb.toStringAsFixed(2)} MB',
              subValue: 'users + lançamentos do período',
              color: const Color(0xFF7C3AED),
              icon: Icons.dns_rounded,
              highlight: true,
            ),
            _MetricCard(
              label: 'Último lançamento',
              value: _fmtDateTime(stats.latestTransactionAt),
              subValue: 'Último registro em transactions',
              color: const Color(0xFFF59E0B),
              icon: Icons.event_note_rounded,
            ),
            _MetricCard(
              label: 'Último cadastro de usuário',
              value: _fmtDateTime(stats.latestUserCreatedAt),
              subValue: 'Campo createdAt em users',
              color: const Color(0xFF0EA5E9),
              icon: Icons.person_add_alt_1_rounded,
            ),
            _MetricCard(
              label: 'Último pagamento aprovado',
              value: _fmtDateTime(stats.latestPaymentApprovedAt),
              subValue: 'Mercado Pago aprovado',
              color: const Color(0xFF22C55E),
              icon: Icons.paid_rounded,
            ),
            _MetricCard(
              label: 'Lançamentos (${periodoDias}d)',
              value: '${stats.txCount30d}',
              subValue: 'collectionGroup transactions no período',
              color: const Color(0xFF6366F1),
              icon: Icons.format_list_numbered_rounded,
            ),
            _MetricCard(
              label: 'Volume lançamentos (${periodoDias}d)',
              value: CurrencyFormats.formatBRL(stats.txValue30d),
              subValue: stats.txResumoAviso ?? 'Soma dos valores no período',
              color: const Color(0xFF0D9488),
              icon: Icons.account_balance_wallet_rounded,
            ),
            _MetricCard(
              label: 'Bruto MP (PIX+cartão)',
              value:
                  CurrencyFormats.formatBRL(stats.pixBruto + stats.cardBruto),
              subValue: 'Antes das taxas',
              color: const Color(0xFF94A3B8),
              icon: Icons.receipt_long_rounded,
            ),
            _MetricCard(
              label: 'Líquido MP (PIX+cartão)',
              value: CurrencyFormats.formatBRL(
                  stats.pixLiquido + stats.cardLiquido),
              subValue: 'Após taxas — lucro operacional MP',
              color: const Color(0xFF16A34A),
              highlight: true,
              icon: Icons.savings_rounded,
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppBarChart(
          title: 'Volume de lançamentos ($periodoDias dias)',
          values: stats.chartValues,
          labels: stats.chartLabels,
          barColor: brandTeal,
          height: 200,
        ),
        const SizedBox(height: 12),
        AppPieChart(
          title: 'Mercado Pago: líquido vs taxas (estimado)',
          segments: [
            (
              label: 'Líquido',
              value: (stats.pixLiquido + stats.cardLiquido)
                  .clamp(0.0, double.infinity),
              color: const Color(0xFF22C55E),
            ),
            (
              label: 'Taxas (bruto − líquido)',
              value: ((stats.pixBruto + stats.cardBruto) -
                      (stats.pixLiquido + stats.cardLiquido))
                  .clamp(0.0, double.infinity),
              color: Colors.orange.shade400,
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppPieChart(
          title: 'Distribuição da base (planos e convênio)',
          segments: [
            (
              label: 'Premium',
              value: stats.totalPremiums.toDouble(),
              color: brandTeal
            ),
            (
              label: 'Free',
              value: freeUsers.toDouble(),
              color: Colors.blueGrey.shade400
            ),
            (
              label: 'Admins',
              value: stats.totalAdmins.toDouble(),
              color: brandBlue
            ),
            (
              label: 'Convênio (partnershipId)',
              value: stats.totalUsersWithPartnership.toDouble(),
              color: const Color(0xFF818CF8),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AppPieChart(
          title: 'Conversão por plano (pagamentos MP no período)',
          segments: [
            (
              label: 'Premium',
              value: stats.premiumMp.toDouble(),
              color: brandTeal,
            ),
            (
              label: 'Legado (checkout antigo)',
              value: stats.legacyMp.toDouble(),
              color: brandBlue,
            ),
          ],
        ),
      ],
    );
  }
}

/// Tabela de últimas transações (vendas) do Mercado Pago.
class _UltimasTransacoesTable extends StatelessWidget {
  final List<Map<String, dynamic>> payments;
  final VoidCallback? onVerTudo;
  final VoidCallback? onRefresh;

  const _UltimasTransacoesTable(
      {required this.payments, this.onVerTudo, this.onRefresh});

  Future<void> _identificarPagamento(
      BuildContext context, String paymentId) async {
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('ctFetchMpPaymentById');
      final result = await callable.call({'paymentId': paymentId});
      final data = result.data as Map<String, dynamic>?;
      if (context.mounted) {
        final ok = data?['ok'] == true;
        final email = (data?['email'] ?? '').toString();
        final name = (data?['name'] ?? '').toString();
        final uid = (data?['uid'] ?? '').toString();
        if (ok && (email.isNotEmpty || name.isNotEmpty || uid.isNotEmpty)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Identificado: ${name.isNotEmpty ? name : email.isNotEmpty ? email : 'UID $uid'}'),
              backgroundColor: AppColors.success,
            ),
          );
          onRefresh?.call();
        } else if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Pagamento atualizado no MP; e-mail/pagador não encontrado no retorno. Recarregue a página.')),
          );
          onRefresh?.call();
        }
      }
    } on FirebaseFunctionsException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro: ${e.message ?? e.code}'),
              backgroundColor: Colors.red.shade700),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.receipt_long_rounded,
                        size: 20, color: Colors.grey.shade700),
                    const SizedBox(width: 8),
                    const Text('Últimas Transações',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                  ],
                ),
                TextButton.icon(
                  onPressed: onVerTudo,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Ver tudo'),
                  style:
                      TextButton.styleFrom(foregroundColor: AppColors.primary),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStatePropertyAll(Colors.grey.shade100),
              headingTextStyle: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
                letterSpacing: 0.5,
              ),
              columns: const [
                DataColumn(label: Text('Usuário')),
                DataColumn(label: Text('Plano')),
                DataColumn(label: Text('Método')),
                DataColumn(label: Text('Valor Bruto'), numeric: true),
                DataColumn(label: Text('Líquido (MP)'), numeric: true),
                DataColumn(label: Text('Data/Hora')),
                DataColumn(label: Text('Ação')),
              ],
              rows: payments.isEmpty
                  ? [
                      DataRow(cells: [
                        DataCell(Text('Nenhuma transação recente',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey.shade600))),
                        const DataCell(SizedBox.shrink()),
                        const DataCell(SizedBox.shrink()),
                        const DataCell(SizedBox.shrink()),
                        const DataCell(SizedBox.shrink()),
                        const DataCell(SizedBox.shrink()),
                        const DataCell(SizedBox.shrink()),
                      ]),
                    ]
                  : payments.map((p) {
                      final userDisplay =
                          (p['userDisplay'] ?? 'Usuário').toString();
                      final plan = (p['plan'] ?? '').toString();
                      final method = (p['method'] ?? 'pix').toString();
                      final valor = (p['valor'] ?? 0.0) as double;
                      final liquido = (p['liquido'] ?? 0.0) as double;
                      final dt = p['dateApproved'] as DateTime?;
                      final dtStr = dt != null
                          ? DateFormat('dd/MM/yyyy HH:mm').format(dt)
                          : '—';
                      final isPremium =
                          plan.toLowerCase().contains('premium') ||
                              plan.toLowerCase().contains('premium_pro');
                      final paymentId = (p['id'] ?? '').toString();
                      final semDados =
                          userDisplay.isEmpty || userDisplay == 'Usuário';
                      return DataRow(
                        cells: [
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor:
                                      AppColors.primary.withValues(alpha: 0.2),
                                  child: Text(
                                    userDisplay.isNotEmpty
                                        ? userDisplay[0].toUpperCase()
                                        : 'U',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                    userDisplay.isEmpty
                                        ? 'Usuário'
                                        : userDisplay,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isPremium
                                    ? Colors.amber.withValues(alpha: 0.15)
                                    : Colors.blue.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: isPremium
                                        ? Colors.amber.withValues(alpha: 0.3)
                                        : Colors.blue.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                  plan.isNotEmpty ? plan.toUpperCase() : '—',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: isPremium
                                          ? Colors.amber.shade800
                                          : Colors.blue.shade800)),
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                    method == 'pix'
                                        ? Icons.account_balance_wallet_rounded
                                        : Icons.credit_card_rounded,
                                    size: 16,
                                    color: Colors.grey.shade600),
                                const SizedBox(width: 6),
                                Text(method.toUpperCase(),
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700)),
                              ],
                            ),
                          ),
                          DataCell(Text(CurrencyFormats.formatBRL(valor),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600))),
                          DataCell(Text(CurrencyFormats.formatBRL(liquido),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.success))),
                          DataCell(Text(dtStr,
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade600))),
                          DataCell(
                            semDados && paymentId.isNotEmpty
                                ? TextButton.icon(
                                    icon: const Icon(
                                        Icons.person_search_rounded,
                                        size: 16),
                                    label: const Text('Identificar'),
                                    onPressed: () => _identificarPagamento(
                                        context, paymentId),
                                    style: TextButton.styleFrom(
                                        foregroundColor: AppColors.primary),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      );
                    }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
