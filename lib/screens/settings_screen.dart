import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_profile.dart';
import '../utils/premium_upgrade.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/firestore_user_doc_id.dart';
import '../constants/app_verse.dart';
import '../theme/app_colors.dart';
import '../services/user_backup_service.dart';
import '../services/backup_save.dart';
import 'system_info_screen.dart';
import 'restore_data_screen.dart';
import 'local_notification_settings_screen.dart';
import '../services/biometric_auth_service.dart';
import '../services/produtividade_config_service.dart';
import '../constants/app_business_rules.dart';
import '../services/weekly_summary_in_app_coordinator.dart';
import '../models/weekly_summary_ui_data.dart';
import '../widgets/weekly_summary_premium_body.dart';
import '../utils/app_update_launcher.dart';
import '../constants/app_version.dart';
import '../widgets/home_start_module_picker.dart';
import '../widgets/google_calendar_integration_toggle.dart';
import '../services/account_switch_flow.dart';
import '../utils/keyboard_form_scaffold.dart';
import '../utils/home_shell_layout.dart';
import '../services/delegate_access_service.dart';
import '../services/ios_payments_gate.dart';
import '../services/user_settings_docs_cache.dart';

class _BiometricSwitchTile extends StatefulWidget {
  const _BiometricSwitchTile();

  @override
  State<_BiometricSwitchTile> createState() => _BiometricSwitchTileState();
}

class _BiometricSwitchTileState extends State<_BiometricSwitchTile> {
  bool _enabled = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    BiometricPreferences.isEnabled().then((v) {
      if (mounted) setState(() => _enabled = v);
    });
  }

  Future<void> _onToggle(bool wantEnable) async {
    if (_busy) return;
    if (wantEnable) {
      setState(() => _busy = true);
      final ok = await authenticateWithBiometric();
      if (!mounted) return;
      setState(() => _busy = false);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível confirmar digital ou rosto. Tente de novo.'),
          ),
        );
        return;
      }
    }
    await BiometricPreferences.setEnabled(wantEnable);
    await BiometricPreferences.setAsked();
    BiometricStartupCache.invalidate();
    if (mounted) {
      setState(() => _enabled = wantEnable);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wantEnable
                ? 'Digital/facial ativado. Ao voltar do app, pede confirmação.'
                : 'Digital/facial desativado. Entrada direta com sessão salva.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SwitchListTile(
        secondary:
            Icon(Icons.fingerprint_rounded, color: AppColors.primary, size: 26),
        title: const Text('Acesso por digital ou facial',
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          _enabled
              ? 'Ativado. Sessão mantida no aparelho; após ${AppBusinessRules.inactivityTimeoutMinutes} min em segundo plano, pede digital de novo.'
              : 'Desativado — abre direto com a sessão guardada (como Controle Total). Funciona offline.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        value: _enabled,
        onChanged: _busy ? null : _onToggle,
      ),
    );
  }
}

class _PontuacaoParaFolgaCard extends StatefulWidget {
  final String uid;
  final bool canEdit;

  const _PontuacaoParaFolgaCard({required this.uid, this.canEdit = true});

  @override
  State<_PontuacaoParaFolgaCard> createState() =>
      _PontuacaoParaFolgaCardState();
}

class _PontuacaoParaFolgaCardState extends State<_PontuacaoParaFolgaCard> {
  late TextEditingController _ctrl;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '30');
    ProdutividadeConfigService().getPontuacaoParaFolga(widget.uid).then((v) {
      if (mounted) {
        _ctrl.text = v.toString();
        setState(() => _loaded = true);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.emoji_events_rounded,
                    color: AppColors.accent, size: 26),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Pontuação para folga',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Número de referência da sua unidade (ex.: 30). Ao atingir essa pontuação em aberto, você pode marcar sua folga.',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textMuted, height: 1.3),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 100,
                  child: FastTextField(
                    controller: _ctrl,
                    readOnly: !widget.canEdit,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Pontos',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _loaded && widget.canEdit
                      ? () async {
                          final n = int.tryParse(_ctrl.text.trim());
                          if (n == null || n < 1 || n > 999) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Informe um número entre 1 e 999.')),
                            );
                            return;
                          }
                          await ProdutividadeConfigService()
                              .setPontuacaoParaFolga(widget.uid, n);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Pontuação para folga atualizada.')),
                            );
                          }
                        }
                      : null,
                  child: const Text('Salvar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Aviso fixo: sub-login revogado; licença própria + link para planos.
class _DelegateRevokedNoticeCard extends StatelessWidget {
  const _DelegateRevokedNoticeCard();

  @override
  Widget build(BuildContext context) {
    final titular = (DelegateAccessService.revokedPrincipalEmail ?? '').trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    color: Colors.amber.shade300, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    DelegateAccessService.revokedNoticeMessage,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (titular.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Licença principal: $titular',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'A partir de agora você usa sua licença própria. Para renovar ou adquirir um plano:',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => IosPaymentsGate.pushEscolhaPlano(context),
                icon: const Icon(Icons.shopping_bag_rounded, size: 20),
                label: const Text(
                  'Clique aqui — ver planos e renovar',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.amber.shade200,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Titular: cadastra um e-mail autorizado (sub-login) para compartilhar os dados da licença.
class _DelegateSharingCard extends StatefulWidget {
  final String principalUid;
  final String principalEmail;
  final String? initialAuthorizedEmail;

  const _DelegateSharingCard({
    required this.principalUid,
    required this.principalEmail,
    this.initialAuthorizedEmail,
  });

  @override
  State<_DelegateSharingCard> createState() => _DelegateSharingCardState();
}

class _DelegateSharingCardState extends State<_DelegateSharingCard> {
  String? _authorizedEmail;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _authorizedEmail = widget.initialAuthorizedEmail?.trim().toLowerCase();
  }

  @override
  void didUpdateWidget(covariant _DelegateSharingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialAuthorizedEmail != widget.initialAuthorizedEmail) {
      _authorizedEmail =
          widget.initialAuthorizedEmail?.trim().toLowerCase();
    }
  }

  Future<void> _openEmailDialog({String? initial}) async {
    final ctrl = TextEditingController(text: initial ?? '');
    final err = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        String? localErr;
        return StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: Text(initial == null
                ? 'Adicionar e-mail autorizado'
                : 'Editar e-mail autorizado'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Não cria licença nova. O autorizado entra com Google ou Apple usando o e-mail cadastrado.',
                  style: TextStyle(fontSize: 12.5, height: 1.35),
                ),
                const SizedBox(height: 14),
                FastTextField(
                  controller: ctrl,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'E-mail autorizado',
                    hintText: 'pessoa@exemplo.com',
                    errorText: localErr,
                    border: const OutlineInputBorder(),
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
                    setLocal(() => localErr = 'Informe um e-mail válido.');
                    return;
                  }
                  Navigator.pop(ctx, e);
                },
                child: const Text('Salvar'),
              ),
            ],
          ),
        );
      },
    );
    ctrl.dispose();
    if (err == null || !mounted) return;

    setState(() => _busy = true);
    final saveErr = await DelegateAccessService.saveAuthorizedEmail(
      principalUid: widget.principalUid,
      principalEmail: widget.principalEmail,
      newEmail: err,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (saveErr == null) {
        _authorizedEmail = err.trim().toLowerCase();
      }
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saveErr ?? 'E-mail autorizado salvo.'),
        backgroundColor: saveErr != null ? Colors.red.shade700 : null,
      ),
    );
  }

  Future<void> _confirmRemove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover e-mail autorizado?'),
        content: Text(
          '$_authorizedEmail deixará de acessar os dados desta licença.',
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
      if (!mounted) return;
      setState(() {
        _authorizedEmail = null;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-mail autorizado removido.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível remover: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasEmail =
        _authorizedEmail != null && _authorizedEmail!.trim().isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.primary.withOpacity(0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.group_add_rounded,
                    color: AppColors.primary, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Compartilhamento de dados',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.orange.shade800, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'O e-mail autorizado terá permissão total: lançar, editar e '
                      'excluir financeiro, agenda, cursos e documentos da licença principal. '
                      'Não cria outro usuário no sistema — fica vinculado a quem cadastrou.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (hasEmail) ...[
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFB74D)),
                ),
                child: Text(
                  'Autonomia ativa: $_authorizedEmail pode alterar e remover '
                  'lançamentos e compromissos como se fosse o titular. Você pode editar '
                  'ou remover este e-mail aqui a qualquer momento.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade900,
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.primary.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.mail_outline_rounded,
                        color: AppColors.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'E-mail de compartilhamento',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _authorizedEmail!,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _openEmailDialog(initial: _authorizedEmail),
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Editar e-mail'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _confirmRemove,
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 18, color: Colors.red.shade700),
                    label: Text('Remover',
                        style: TextStyle(color: Colors.red.shade700)),
                  ),
                ],
              ),
            ] else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _openEmailDialog(),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Adicionar e-mail'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  final String uid;
  final String? userEmail;
  final String? userName;

  /// Perfil do usuário (quando dentro do shell). Usado para bloquear alterações quando licença vencida.
  final UserProfile? profile;

  /// Quando true, exibe AppBar com título e botão voltar (ex.: aberta por push).
  /// Quando false, usada como módulo dentro do shell (sem AppBar).
  final bool showAppBar;
  final void Function(int index)? onNavigateTo;

  /// Quando dentro do [HomeShell]: scroll volta ao topo ao mudar de módulo.
  final ScrollController? shellScrollController;

  const SettingsScreen({
    super.key,
    required this.uid,
    this.userEmail,
    this.userName,
    this.profile,
    this.showAppBar = true,
    this.onNavigateTo,
    this.shellScrollController,
  });

  bool get _blocked => profile != null && !profile!.hasActiveLicense;

  void _onConfigTap(BuildContext context, VoidCallback action) {
    if (_blocked) {
      mostrarAvisoSeLicencaInativa(context, profile!);
      return;
    }
    action();
  }

  /// Encerra a sessão e abre o login para escolher outro e-mail/conta.
  Future<void> _confirmarTrocarUsuario(BuildContext context) async {
    await AccountSwitchFlow.confirmAndOpenLogin(context);
  }

  String get _docUid => firestoreUserDocIdForAppShell(uid);

  DocumentReference<Map<String, dynamic>> get _planningRef =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_docUid)
          .collection('settings')
          .doc('planning');

  DocumentReference<Map<String, dynamic>> get _backupRef =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_docUid)
          .collection('settings')
          .doc('backup');

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 720;
    final embeddedInShell = shellScrollController != null;
    return Scaffold(
      resizeToAvoidBottomInset: scaffoldKeyboardResizeToAvoidBottomInset(
        embeddedInHomeShell: embeddedInShell,
      ),
      appBar: showAppBar
          ? AppBar(
              title: const Text('Configurações do Sistema'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            )
          : null,
      // Topo: o shell já respeita status bar (barra gradiente + SafeArea). Evita
      // segundo recuo que deixava Configurações “desalinhada” no painel.
      body: SafeArea(
        top: false,
        bottom: homeShellSafeAreaBottom(embeddedInHomeShell: embeddedInShell),
        child: ListView(
          controller: shellScrollController,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16,
            showAppBar ? (isNarrow ? 6 : 4) : 0,
            16,
            homeShellScrollBottomPadding(
              context,
              embeddedInHomeShell: embeddedInShell,
              tail: 12,
            ),
          ),
          children: [
            // Card de identidade do usuário: nome, e-mail usado e vencimento da
            // licença. Fica sempre no topo (com ou sem AppBar) — a pedido do
            // usuário, ele precisa saber qual e-mail está usando para entrar.
            _userIdentityCard(context),
            ListenableBuilder(
              listenable: DelegateAccessService.sessionRevision,
              builder: (context, _) {
                if (!DelegateAccessService.showRevokedBannerInSettings) {
                  return const SizedBox.shrink();
                }
                return const _DelegateRevokedNoticeCard();
              },
            ),
            if (DelegateAccessService.canManageDelegateSharing())
              _DelegateSharingCard(
                principalUid: FirebaseAuth.instance.currentUser?.uid ?? uid,
                principalEmail: userEmail ?? profile?.email ?? '',
                initialAuthorizedEmail: profile?.authorizedDelegateEmail,
              ),
            const SizedBox(height: 14),
            if (!showAppBar) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded,
                        color: AppColors.primary, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Backup, notificações e preferências.',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            _sectionTitle('APARÊNCIA'),
            _PlanningSettingsSection(
              uid: _docUid,
              blocked: _blocked,
              planningRef: _planningRef,
            ),
            const SizedBox(height: 24),
            _sectionTitle('NOTIFICAÇÕES'),
            _tile(
              context,
              icon: Icons.notifications_active_rounded,
              iconColor: Colors.orange,
              title: 'Notificações',
              subtitle:
                  'Financeiro, novos cursos — ativar ou não; 1 dia ou 1 hora antes',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const LocalNotificationSettingsScreen()),
              ),
            ),
            _tileBiometria(context),
            const SizedBox(height: 24),
            _sectionTitle('AGENDA'),
            GoogleCalendarIntegrationToggle(
              userDocId: _docUid,
              showChangeAccountAction: true,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4, right: 4, bottom: 8),
              child: Text(
                'Use o interruptor acima para sincronizar com o Gmail da sua conta. '
                'Compromissos novos vão para o Google Calendar automaticamente.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 24),
            _sectionTitle('BACKUP E DADOS'),
            _DeferredSettingsSection(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildBackupDestinoCard(context),
                  _tile(
                    context,
                    icon: Icons.save_rounded,
                    iconColor: Colors.blue,
                    title: 'Backup (Exportar Dados)',
                    subtitle:
                        'Salve localmente; recomendamos enviar para Google Drive ou nuvem',
                    onTap: () => _onConfigTap(context, () => _doBackup(context)),
                  ),
                  _BackupAutoSettingsTile(
                    uid: _docUid,
                    blocked: _blocked,
                    backupRef: _backupRef,
                    onOpenSheet: (ctx, enabled, frequency, dailyHour, weeklyDays) {
                      if (_blocked && profile != null) {
                        mostrarAvisoSeLicencaInativa(ctx, profile!);
                        return;
                      }
                      _openBackupAutoSheet(
                        ctx,
                        enabled,
                        frequency,
                        dailyHour,
                        weeklyDays,
                      );
                    },
                  ),
                  _tile(
                    context,
                    icon: Icons.restore_rounded,
                    iconColor: Colors.lightBlue,
                    title: 'Restaurar Dados',
                    subtitle:
                        'Busque o arquivo de backup no dispositivo ou nuvem e restaure',
                    onTap: () => _onConfigTap(
                        context,
                        () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => RestoreDataScreen(uid: _docUid)),
                            )),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _DeferredSettingsSection(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionTitle('SUPORTE E INFORMAÇÕES'),
                  if (!kIsWeb && showAndroidStoreUi)
                    _tile(
                      context,
                      icon: Icons.shop_rounded,
                      iconColor: Colors.green,
                      title: 'Atualizar aplicativo',
                      subtitle:
                          'Abre a Google Play para instalar a versão mais recente',
                      onTap: () => launchControleTotalAppUpdate(context),
                    ),
                  if (!kIsWeb && showIosStoreUi)
                    _tile(
                      context,
                      icon: Icons.apple_rounded,
                      iconColor: Colors.blueGrey,
                      title: 'Atualizar aplicativo',
                      subtitle:
                          'Abre o TestFlight para instalar a versão mais recente',
                      onTap: () => launchControleTotalAppUpdate(context),
                    ),
                  if (!kIsWeb && (showAndroidStoreUi || showIosStoreUi))
                    const SizedBox(height: 12),
                  _PlanningFinanceTipsTile(
                    uid: _docUid,
                    blocked: _blocked,
                    planningRef: _planningRef,
                  ),
                  _tile(
                    context,
                    icon: Icons.info_outline_rounded,
                    iconColor: AppColors.textMuted,
                    title: 'Informações do Sistema',
                    subtitle:
                        'Resumo, créditos (Johnathan Tarley · Raihom Barbosa) e sugestões/críticas',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SystemInfoScreen(
                          uid: _docUid,
                          userEmail: userEmail,
                          userName: userName,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Versão ${AppVersion.current} · ${AppVersion.internalLabel}',
                  style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupDestinoCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_upload_rounded,
                    color: Colors.blue.shade700, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Destino do backup',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'O backup é salvo no seu aparelho (pasta Downloads ou compartilhamento). '
              'Recomendamos enviar para Google Drive ou outra nuvem — é mais seguro e não ocupa espaço no celular.',
              style: TextStyle(
                  fontSize: 13, height: 1.5, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardPontuacaoParaFolga(BuildContext context) {
    return _PontuacaoParaFolgaCard(uid: _docUid, canEdit: !_blocked);
  }

  Widget _sectionTitle(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// Card moderno no topo de Configurações: nome, e-mail usado pelo usuário e
  /// vencimento da licença. O e-mail é o que está logado neste aparelho —
  /// fundamental para o usuário conferir qual conta está em uso (e qual usar
  /// para entrar de novo).
  Widget _userIdentityCard(BuildContext context) {
    final name = (userName ?? profile?.name ?? '').trim();
    final email = (userEmail ?? profile?.email ?? '').trim();
    final sessionEmail =
        FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
    final displayName = name.isEmpty ? 'Usuário' : name;
    final initial = displayName.characters.first.toUpperCase();
    final exp = profile?.licenseExpiresAt;
    final access = profile?.licenseAccessState ?? 'ATIVO';
    final planLabel =
        profile == null ? 'Plano —' : profile!.planDisplayLabelForUi;

    String? expText;
    if (exp != null) {
      final dd = exp.day.toString().padLeft(2, '0');
      final mm = exp.month.toString().padLeft(2, '0');
      expText = 'Válido até $dd/$mm/${exp.year}';
    }

    final (
      Color statusBg,
      Color statusFg,
      IconData statusIcon,
      String statusLabel
    ) = switch (access) {
      'BLOQUEADO' => (
          const Color(0xFFFFE9E9),
          const Color(0xFFC62828),
          Icons.lock_outline_rounded,
          'Bloqueado'
        ),
      'CARENCIA' => (
          const Color(0xFFFFF3E0),
          const Color(0xFFE65100),
          Icons.warning_amber_rounded,
          'Em carência'
        ),
      _ => (
          const Color(0xFFE8F5E9),
          const Color(0xFF2E7D32),
          Icons.verified_rounded,
          'Ativa'
        ),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A237E), Color(0xFF2D5BFF), Color(0xFF0D9488)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A237E).withOpacity(0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withOpacity(0.35), width: 1),
                ),
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DelegateAccessService.isActingAsDelegate
                          ? 'Sub-login · licença de ${(DelegateAccessService.principalEmail ?? '').trim().isNotEmpty ? DelegateAccessService.principalEmail!.trim() : 'titular'}'
                          : 'Conta em uso neste aparelho',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.white.withOpacity(0.80),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // E-mail: linha destacada com ícone, em "card branco translúcido".
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.22)),
            ),
            child: Row(
              children: [
                const Icon(Icons.alternate_email_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    DelegateAccessService.isActingAsDelegate
                        ? (sessionEmail.isNotEmpty
                            ? 'Sessão: $sessionEmail'
                            : 'E-mail da sessão')
                        : (email.isEmpty ? 'E-mail não disponível' : email),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (email.isNotEmpty)
                  Tooltip(
                    message: 'Copiar e-mail',
                    child: InkWell(
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: email));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('E-mail copiado.'),
                              duration: Duration(seconds: 2)),
                        );
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.copy_rounded,
                            color: Colors.white.withOpacity(0.85), size: 18),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Plano + vencimento + status, junto ao bloco do e-mail (fonte grande: Wrap).
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.28)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.workspace_premium_rounded,
                        color: Colors.white, size: 15),
                    const SizedBox(width: 6),
                    Text(
                      planLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              if (expText != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.22)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.event_available_rounded,
                          color: Colors.white, size: 15),
                      const SizedBox(width: 6),
                      Text(
                        expText,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: statusFg, size: 15),
                    const SizedBox(width: 6),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: statusFg,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _confirmarTrocarUsuario(context),
              icon: const Icon(Icons.switch_account_rounded,
                  color: Colors.white, size: 22),
              label: const Text(
                '«Entrar com outra conta»',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.28,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white, width: 1.25),
                backgroundColor: Colors.white.withOpacity(0.14),
                minimumSize: const Size(double.infinity, 48),
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Encerra a sessão, apaga credenciais locais e abre login para outra conta.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withOpacity(0.88),
                height: 1.35,
                letterSpacing: 0.15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tileBiometria(BuildContext context) {
    if (kIsWeb) {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          leading: Icon(Icons.lock_open_rounded, color: AppColors.primary, size: 26),
          title: const Text(
            'Sessão neste navegador',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            'Permanece logada até «Entrar com outra conta». Com internet off, '
            'continua a usar dados guardados no aparelho.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ),
      );
    }
    return const _BiometricSwitchTile();
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Icon(icon, color: iconColor, size: 26),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle != null
            ? Text(subtitle,
                style: TextStyle(fontSize: 12, color: AppColors.textMuted))
            : null,
        trailing:
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        onTap: onTap,
      ),
    );
  }

  void _openBackupAutoSheet(BuildContext context, bool enabled,
      String frequency, int dailyHour, List<int> weeklyDays) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _BackupAutoSheet(
        uid: _docUid,
        backupRef: _backupRef,
        initialEnabled: enabled,
        initialFrequency: frequency,
        initialDailyHour: dailyHour,
        initialWeeklyDays: List<int>.from(weeklyDays),
      ),
    );
  }

  Future<void> _doBackup(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Preparando seu backup...'),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      final json = await UserBackupService().exportUserDataAsJson(_docUid);
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final filename = 'controle-total-backup-$date.json';
      if (!context.mounted) return;
      Navigator.of(context).pop();
      await saveBackupFile(filename, json);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Backup exportado. Envie para o seu Google Drive ou outra nuvem para não ocupar espaço no celular.'),
          backgroundColor: AppColors.success,
        ),
      );
      _showSaveToCloudReminder(context);
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao exportar: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _showSaveToCloudReminder(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Salvar na nuvem'),
        content: const Text(
          'Recomendamos enviar o arquivo de backup para o seu Google Drive ou outro serviço na nuvem. '
          'Assim você não ocupa espaço no celular e mantém uma cópia segura. O backup não fica armazenado no nosso servidor.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendi')),
        ],
      ),
    );
  }

  void _openResumoSemanal(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(_docUid)
        .collection('settings')
        .doc('weekly_summary');
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) {
        final mq = MediaQuery.sizeOf(ctx);
        final w = (mq.width - 40).clamp(280.0, 440.0);
        final h = (mq.height * 0.52).clamp(320.0, 520.0);
        return Center(
          child: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: w,
              height: h,
              child: _WeeklySummarySettingsDialog(ref: ref),
            ),
          ),
        );
      },
    );
  }

  static Future<void> _showAboutDialog(BuildContext context) async {
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sobre o App'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('WISDOMAPP',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Versão ${info.version} (${info.buildNumber})',
                style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
            const SizedBox(height: 16),
            Text(
                'Sabedoria financeira com princípios bíblicos: Financeiro, Agenda e Cursos em um só app.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            Text(
              AppVerse.full,
              style: TextStyle(
                  fontSize: 10,
                  color: AppColors.textMuted.withOpacity(0.8),
                  fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  static Future<void> _openSuggestionsEmail(BuildContext context) async {
    String version = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = 'Versão: ${info.version}+${info.buildNumber}\n\n';
    } catch (_) {}
    final uri = Uri(
      scheme: 'mailto',
      path: 'raihom@gmail.com',
      queryParameters: <String, String>{
        'subject': 'WISDOMAPP – Sugestão ou problema',
        'body': '${version}Descreva sua sugestão ou o problema encontrado:\n\n',
      },
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Não foi possível abrir o e-mail.')));
      }
    }
  }
}

/// Diálogo central (Android, iOS, Web) — resumo semanal super premium nas definições.
class _WeeklySummarySettingsDialog extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> ref;

  const _WeeklySummarySettingsDialog({required this.ref});

  @override
  State<_WeeklySummarySettingsDialog> createState() =>
      _WeeklySummarySettingsDialogState();
}

class _WeeklySummarySettingsDialogState
    extends State<_WeeklySummarySettingsDialog> {
  bool _enabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.ref.get().then((snap) {
      if (!mounted) return;
      setState(() {
        _enabled = snap.data()?['enabled'] == true;
        _loading = false;
      });
    });
  }

  Future<void> _toggle(bool v) async {
    await widget.ref.set(
        {'enabled': v, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true));
    if (mounted) {
      setState(() => _enabled = v);
      if (!v) {
        WeeklySummaryInAppCoordinator.clearBecauseDisabled();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                v ? 'Resumo semanal ativado.' : 'Resumo semanal desativado.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBlueDark.withValues(alpha: 0.2),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 5,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF0F172A),
                    AppColors.deepBlue,
                    AppColors.accent
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.14)),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.summarize_rounded,
                        color: AppColors.primary, size: 26),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Resumo semanal',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                            height: 1.25,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Super premium · WISDOMAPP',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('OK',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 15)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Uma vez por semana mostramos um cartão com o resumo financeiro: contas a pagar, '
                      'valores pagos e a receber e saldo do período. '
                      'Funciona em Android, iPhone e Web.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.12)),
                        ),
                        child: SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          value: _enabled,
                          onChanged: _toggle,
                          title: const Text(
                            'Mostrar resumo semanal',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                          subtitle: const Text(
                            'Padrão do app: desligado. Ative só se quiser ver o cartão semanal.',
                            style: TextStyle(
                                fontSize: 12.5, color: AppColors.textMuted),
                          ),
                          activeThumbColor: Colors.white,
                          activeTrackColor: AppColors.primary,
                        ),
                      ),
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: AppColors.accent.withValues(alpha: 0.28)),
                        boxShadow: [
                          BoxShadow(
                            color:
                                AppColors.deepBlueDark.withValues(alpha: 0.06),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.visibility_rounded,
                                  color: AppColors.deepBlue, size: 22),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Pré-visualização (exemplo)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Ilustração fictícia com o mesmo layout do cartão semanal. O rótulo de semana segue a data atual; os valores são só para ver o desenho.',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.1)),
                            ),
                            child: WeeklySummaryPremiumBody(
                              data: WeeklySummaryUiData.previewSample(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dias da semana para backup semanal (1 = segunda, 7 = domingo).
const Map<int, String> _backupWeekdayLabels = {
  1: 'Seg',
  2: 'Ter',
  3: 'Qua',
  4: 'Qui',
  5: 'Sex',
  6: 'Sáb',
  7: 'Dom',
};

class _BackupAutoSheet extends StatefulWidget {
  final String uid;
  final DocumentReference<Map<String, dynamic>> backupRef;
  final bool initialEnabled;
  final String initialFrequency;
  final int initialDailyHour;
  final List<int> initialWeeklyDays;

  const _BackupAutoSheet({
    required this.uid,
    required this.backupRef,
    required this.initialEnabled,
    required this.initialFrequency,
    required this.initialDailyHour,
    required this.initialWeeklyDays,
  });

  @override
  State<_BackupAutoSheet> createState() => _BackupAutoSheetState();
}

class _BackupAutoSheetState extends State<_BackupAutoSheet> {
  late bool _enabled;
  late String _frequency;
  late int _dailyHour;
  late List<int> _weeklyDays;

  @override
  void initState() {
    super.initState();
    _enabled = widget.initialEnabled;
    _frequency = widget.initialFrequency;
    _dailyHour = widget.initialDailyHour.clamp(0, 23);
    _weeklyDays = widget.initialWeeklyDays.isEmpty
        ? [1]
        : List<int>.from(widget.initialWeeklyDays)
      ..sort();
  }

  void _toggleWeekDay(int day) {
    setState(() {
      if (_weeklyDays.contains(day)) {
        _weeklyDays.remove(day);
        if (_weeklyDays.isEmpty) _weeklyDays = [day];
      } else {
        _weeklyDays.add(day);
        _weeklyDays.sort();
      }
    });
  }

  Future<void> _save() async {
    try {
      await widget.backupRef.set({
        'enabled': _enabled,
        'frequency': _frequency,
        'dailyHour': _dailyHour,
        'weeklyDays': _weeklyDays,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        UserSettingsDocsCache.put(widget.uid, 'backup', {
          'enabled': _enabled,
          'frequency': _frequency,
          'dailyHour': _dailyHour,
          'weeklyDays': _weeklyDays,
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Configuração salva.')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Erro ao salvar: ${e.toString().split('\n').first}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Backup automático',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                'O backup é salvo no seu aparelho. Envie o arquivo para o seu Google Drive ou outra nuvem para não ocupar espaço e ter cópia segura. Não usamos nosso banco para guardar seu backup.',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
                title: const Text('Ativar backup automático'),
              ),
              const SizedBox(height: 8),
              const Text('Frequência',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              RadioListTile<String>(
                value: 'daily',
                groupValue: _frequency,
                onChanged: (v) => setState(() => _frequency = v ?? 'daily'),
                title: const Text('Diário'),
              ),
              if (_frequency == 'daily') ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: Row(
                    children: [
                      Text('Horário:',
                          style: TextStyle(
                              fontSize: 14, color: AppColors.textSecondary)),
                      const SizedBox(width: 12),
                      DropdownButton<int>(
                        value: _dailyHour.clamp(0, 23),
                        items: List.generate(
                            24,
                            (i) => DropdownMenuItem(
                                value: i,
                                child: Text(
                                    '${i.toString().padLeft(2, '0')}:00'))),
                        onChanged: (v) => setState(() => _dailyHour = v ?? 0),
                      ),
                    ],
                  ),
                ),
              ],
              RadioListTile<String>(
                value: 'weekly',
                groupValue: _frequency,
                onChanged: (v) => setState(() => _frequency = v ?? 'weekly'),
                title: const Text('Semanal'),
              ),
              if (_frequency == 'weekly') ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text('Dias da semana',
                      style:
                          TextStyle(fontSize: 13, color: AppColors.textMuted)),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _backupWeekdayLabels.entries.map((e) {
                    final selected = _weeklyDays.contains(e.key);
                    return FilterChip(
                      label: Text(e.value),
                      selected: selected,
                      onSelected: (_) => _toggleWeekDay(e.key),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Salvar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Monta seções abaixo da dobra no frame seguinte — 1º paint mais leve.
class _DeferredSettingsSection extends StatefulWidget {
  const _DeferredSettingsSection({required this.child});

  final Widget child;

  @override
  State<_DeferredSettingsSection> createState() => _DeferredSettingsSectionState();
}

class _DeferredSettingsSectionState extends State<_DeferredSettingsSection> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const SizedBox(height: 8);
    }
    return widget.child;
  }
}

class _PlanningSettingsSection extends StatefulWidget {
  const _PlanningSettingsSection({
    required this.uid,
    required this.blocked,
    required this.planningRef,
  });

  final String uid;
  final bool blocked;
  final DocumentReference<Map<String, dynamic>> planningRef;

  @override
  State<_PlanningSettingsSection> createState() => _PlanningSettingsSectionState();
}

class _PlanningSettingsSectionState extends State<_PlanningSettingsSection> {
  Map<String, dynamic> _data = const {};

  @override
  void initState() {
    super.initState();
    final cached = UserSettingsDocsCache.peek(widget.uid, 'planning');
    if (cached != null) {
      _data = Map<String, dynamic>.from(cached);
    }
    UserSettingsDocsCache.ensure(widget.uid, 'planning').then((d) {
      if (!mounted || d == null) return;
      setState(() => _data = Map<String, dynamic>.from(d));
    });
  }

  @override
  Widget build(BuildContext context) {
    final raw = _data[kHomeDefaultStartModuleField];
    final selected = normalizeHomeStartModuleIndex(
      raw is num ? raw.toInt() : 1,
    );
    final label = kHomeDefaultStartModuleLabels[selected] ??
        kHomeDefaultStartModuleLabels[1]!;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: const Icon(Icons.home_max_rounded,
            color: AppColors.primary, size: 26),
        title: const Text('Tela inicial padrão',
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          'Ao abrir o app: $label',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: AppColors.textMuted),
        onTap: () => showHomeStartModulePickerSheet(
          context,
          uid: widget.uid,
          initialSelected: selected,
        ),
      ),
    );
  }
}

class _PlanningFinanceTipsTile extends StatefulWidget {
  const _PlanningFinanceTipsTile({
    required this.uid,
    required this.blocked,
    required this.planningRef,
  });

  final String uid;
  final bool blocked;
  final DocumentReference<Map<String, dynamic>> planningRef;

  @override
  State<_PlanningFinanceTipsTile> createState() => _PlanningFinanceTipsTileState();
}

class _PlanningFinanceTipsTileState extends State<_PlanningFinanceTipsTile> {
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    final cached = UserSettingsDocsCache.peek(widget.uid, 'planning');
    if (cached != null) {
      _enabled = cached['dailyTipsEnabled'] == true;
    }
    UserSettingsDocsCache.ensure(widget.uid, 'planning').then((d) {
      if (!mounted || d == null) return;
      setState(() => _enabled = d['dailyTipsEnabled'] == true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SwitchListTile(
        secondary: Icon(Icons.lightbulb_outline_rounded,
            color: AppColors.amber, size: 26),
        title: const Text('Dicas financeiras diárias',
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text(
          'Dicas bíblicas sobre economia e planejamento no Início. Opcional.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        value: _enabled,
        onChanged: widget.blocked
            ? null
            : (v) async {
                setState(() => _enabled = v);
                try {
                  await widget.planningRef.set({
                    'dailyTipsEnabled': v,
                    'updatedAt': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));
                  final prev =
                      UserSettingsDocsCache.peek(widget.uid, 'planning') ?? {};
                  UserSettingsDocsCache.put(widget.uid, 'planning', {
                    ...prev,
                    'dailyTipsEnabled': v,
                  });
                } catch (_) {
                  if (mounted) setState(() => _enabled = !v);
                }
              },
      ),
    );
  }
}

typedef _BackupAutoSheetOpener = void Function(
  BuildContext context,
  bool enabled,
  String frequency,
  int dailyHour,
  List<int> weeklyDays,
);

class _BackupAutoSettingsTile extends StatefulWidget {
  const _BackupAutoSettingsTile({
    required this.uid,
    required this.blocked,
    required this.backupRef,
    required this.onOpenSheet,
  });

  final String uid;
  final bool blocked;
  final DocumentReference<Map<String, dynamic>> backupRef;
  final _BackupAutoSheetOpener onOpenSheet;

  @override
  State<_BackupAutoSettingsTile> createState() => _BackupAutoSettingsTileState();
}

class _BackupAutoSettingsTileState extends State<_BackupAutoSettingsTile> {
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _data = UserSettingsDocsCache.peek(widget.uid, 'backup');
    UserSettingsDocsCache.ensure(widget.uid, 'backup').then((d) {
      if (!mounted) return;
      setState(() => _data = d);
    });
  }

  List<int> _weeklyDays(Map<String, dynamic>? data) {
    final weeklyDaysRaw = data?['weeklyDays'];
    List<int> weeklyDays = [1];
    if (weeklyDaysRaw is List && weeklyDaysRaw.isNotEmpty) {
      weeklyDays = weeklyDaysRaw
          .map((e) => e is int ? e : (e is num ? e.toInt() : 1))
          .where((d) => d >= 1 && d <= 7)
          .toSet()
          .toList()
        ..sort();
      if (weeklyDays.isEmpty) weeklyDays = [1];
    }
    return weeklyDays;
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final enabled = (data?['enabled'] ?? false) as bool;
    final frequency = (data?['frequency'] ?? 'daily') as String;
    final dailyHour = (data?['dailyHour'] is int) ? data!['dailyHour'] as int : 0;
    final weeklyDays = _weeklyDays(data);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Icon(Icons.backup_rounded, color: Colors.teal, size: 26),
        title: const Text('Backup automático',
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text(
          'Backup periódico no seu aparelho; salve no seu Google Drive ou nuvem.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: AppColors.textMuted),
        onTap: widget.blocked
            ? null
            : () => widget.onOpenSheet(
                  context,
                  enabled,
                  frequency,
                  dailyHour.clamp(0, 23),
                  weeklyDays,
                ),
      ),
    );
  }
}