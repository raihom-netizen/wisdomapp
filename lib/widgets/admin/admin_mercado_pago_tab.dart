import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/app_brand.dart';
import '../../constants/currency_formats.dart';
import '../../services/functions_service.dart';
import '../../services/mp_admin_config_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/fast_text_field.dart';

/// Painel Mercado Pago dual (Raihom + Johnathan), split interno e preços.
class AdminMercadoPagoTab extends StatefulWidget {
  const AdminMercadoPagoTab({
    super.key,
    required this.brandBlue,
    required this.brandTeal,
  });

  final Color brandBlue;
  final Color brandTeal;

  @override
  AdminMercadoPagoTabState createState() => AdminMercadoPagoTabState();
}

class AdminMercadoPagoTabState extends State<AdminMercadoPagoTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _loading = true;
  bool _saving = false;
  bool _syncingAll = false;
  bool _splitEnabled = true;
  bool _splitModeFixed = true;
  bool _syncLanding = true;
  bool _syncingSplitFields = false;
  bool _ownerConfigured = false;
  bool _partnerConfigured = false;
  String? _loadError;

  final _ownerPublicKey = TextEditingController();
  final _ownerAccessToken = TextEditingController();
  final _ownerClientId = TextEditingController();
  final _ownerClientSecret = TextEditingController();
  final _ownerWebhookUrl = TextEditingController();
  final _ownerWebhookSecret = TextEditingController();
  final _ownerCollectorId = TextEditingController();

  final _partnerPublicKey = TextEditingController();
  final _partnerAccessToken = TextEditingController();
  final _partnerClientId = TextEditingController();
  final _partnerCollectorId = TextEditingController();

  final _licenseGross = TextEditingController();
  final _ownerFixed = TextEditingController();
  final _partnerFixed = TextEditingController();
  final _ownerPercent = TextEditingController();
  final _partnerPercent = TextEditingController();
  final _premiumAnnual = TextEditingController();

  static const _ownerAccent = Color(0xFF0D9488);
  static const _partnerAccent = Color(0xFF7C3AED);

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    reload();
  }

  Future<void> reload() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final c = await MpAdminConfigService.instance.load();
      if (!mounted) return;
      _applySnapshot(c);
    } catch (e) {
      if (mounted) {
        _loadError = e.toString().split('\n').first;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _applySnapshot(MpAdminConfigSnapshot c) {
    _ownerConfigured = c.ownerConfigured;
    _partnerConfigured = c.partnerConfigured;
    _ownerPublicKey.text = c.ownerPublicKey;
    _ownerAccessToken.text = c.ownerAccessToken;
    _ownerClientId.text = c.ownerClientId;
    _ownerClientSecret.text = c.ownerClientSecret;
    _ownerWebhookUrl.text = c.ownerWebhookUrl.isNotEmpty
        ? c.ownerWebhookUrl
        : c.webhookDefaultUrl;
    _ownerWebhookSecret.text = c.ownerWebhookSecret;
    _ownerCollectorId.text = c.ownerCollectorId;
    _partnerPublicKey.text = c.partnerPublicKey;
    _partnerAccessToken.text = c.partnerAccessToken;
    _partnerClientId.text = c.partnerClientId;
    _partnerCollectorId.text = c.partnerCollectorId;
    _splitEnabled = c.splitEnabled;
    _splitModeFixed = c.splitModeFixed;
    _setMoney(_licenseGross, c.premiumMonthly);
    _setMoney(_premiumAnnual, c.premiumAnnual);
    _setMoney(_ownerFixed, c.ownerShareFixed);
    _setMoney(_partnerFixed, c.partnerShareFixed);
    _ownerPercent.text = c.ownerSharePercent.toStringAsFixed(2);
    _partnerPercent.text = c.partnerSharePercent.toStringAsFixed(2);
    if (!_partnerConfigured && _tabCtrl.index == 1) {
      // ok
    } else if (!_partnerConfigured) {
      // destaca aba do parceiro após carregar se Raihom já ok
      if (_ownerConfigured) {
        Future.microtask(() {
          if (mounted) _tabCtrl.animateTo(1);
        });
      }
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _ownerPublicKey.dispose();
    _ownerAccessToken.dispose();
    _ownerClientId.dispose();
    _ownerClientSecret.dispose();
    _ownerWebhookUrl.dispose();
    _ownerWebhookSecret.dispose();
    _ownerCollectorId.dispose();
    _partnerPublicKey.dispose();
    _partnerAccessToken.dispose();
    _partnerClientId.dispose();
    _partnerCollectorId.dispose();
    _licenseGross.dispose();
    _ownerFixed.dispose();
    _partnerFixed.dispose();
    _ownerPercent.dispose();
    _partnerPercent.dispose();
    _premiumAnnual.dispose();
    super.dispose();
  }

  double _parseMoney(TextEditingController c) {
    final digits = c.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return 0;
    return int.parse(digits) / 100;
  }

  void _setMoney(TextEditingController c, double v) {
    c.text = CurrencyFormats.formatBRL(v);
  }

  double _parsePercent(TextEditingController c) {
    return double.tryParse(c.text.replaceAll(',', '.')) ?? 0;
  }

  void _onLicenseGrossChanged() {
    if (_syncingSplitFields) return;
    _syncingSplitFields = true;
    final gross = _parseMoney(_licenseGross);
    if (gross > 0) {
      final owner = _parseMoney(_ownerFixed);
      final partner = (gross - owner).clamp(0, gross);
      _setMoney(_partnerFixed, partner.toDouble());
      _ownerPercent.text = ((owner / gross) * 100).toStringAsFixed(2);
      _partnerPercent.text = ((partner / gross) * 100).toStringAsFixed(2);
    }
    _syncingSplitFields = false;
  }

  void _onOwnerFixedChanged() {
    if (_syncingSplitFields) return;
    _syncingSplitFields = true;
    final gross = _parseMoney(_licenseGross);
    final owner = _parseMoney(_ownerFixed);
    if (gross > 0) {
      final partner = (gross - owner).clamp(0, gross);
      _setMoney(_partnerFixed, partner.toDouble());
      _ownerPercent.text = ((owner / gross) * 100).toStringAsFixed(2);
      _partnerPercent.text = ((partner / gross) * 100).toStringAsFixed(2);
    }
    _syncingSplitFields = false;
  }

  void _onOwnerPercentChanged() {
    if (_syncingSplitFields) return;
    _syncingSplitFields = true;
    final gross = _parseMoney(_licenseGross);
    final pct = _parsePercent(_ownerPercent).clamp(0, 100);
    if (gross > 0) {
      final owner = gross * pct / 100;
      final partner = gross - owner;
      _setMoney(_ownerFixed, owner);
      _setMoney(_partnerFixed, partner.toDouble());
      _partnerPercent.text = (100 - pct).toStringAsFixed(2);
    }
    _syncingSplitFields = false;
  }

  MpAdminConfigSnapshot _buildSnapshot() {
    final gross = _parseMoney(_licenseGross);
    return MpAdminConfigSnapshot(
      ownerPublicKey: _ownerPublicKey.text.trim(),
      ownerAccessToken: _ownerAccessToken.text.trim(),
      ownerClientId: _ownerClientId.text.trim(),
      ownerClientSecret: _ownerClientSecret.text.trim(),
      ownerWebhookUrl: _ownerWebhookUrl.text.trim(),
      ownerWebhookSecret: _ownerWebhookSecret.text.trim(),
      ownerCollectorId: _ownerCollectorId.text.trim(),
      ownerConfigured: _ownerConfigured,
      partnerPublicKey: _partnerPublicKey.text.trim(),
      partnerAccessToken: _partnerAccessToken.text.trim(),
      partnerClientId: _partnerClientId.text.trim(),
      partnerCollectorId: _partnerCollectorId.text.trim(),
      partnerConfigured: _partnerConfigured,
      splitEnabled: _splitEnabled,
      splitModeFixed: _splitModeFixed,
      ownerSharePercent: _parsePercent(_ownerPercent),
      partnerSharePercent: _parsePercent(_partnerPercent),
      ownerShareFixed: _parseMoney(_ownerFixed),
      partnerShareFixed: _parseMoney(_partnerFixed),
      referenceGross: gross,
      premiumMonthly: gross,
      premiumAnnual: _parseMoney(_premiumAnnual),
      webhookDefaultUrl: MpAdminConfigService.defaultWebhookUrl,
    );
  }

  Future<void> _save() async {
    if (_ownerAccessToken.text.trim().isEmpty && !_ownerConfigured) {
      _snack('Access Token de ${AppBrand.developerName} é obrigatório.');
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await MpAdminConfigService.instance.save(
        config: _buildSnapshot(),
        syncLandingTexts: _syncLanding,
      );
      if (mounted) {
        _snack(res['message']?.toString() ?? 'Configuração salva.');
        await reload();
      }
    } catch (e) {
      if (mounted) _snack('Erro: ${e.toString().split('\n').first}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _syncAll() async {
    setState(() => _syncingAll = true);
    try {
      final res = await FunctionsService().syncAllMpPayments();
      if (mounted) _snack(res['message']?.toString() ?? 'Sincronização concluída.');
    } catch (e) {
      if (mounted) _snack('Erro: ${e.toString().split('\n').first}');
    } finally {
      if (mounted) setState(() => _syncingAll = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heroHeader(),
        if (_loadError != null) ...[
          const SizedBox(height: 10),
          _errorBanner(_loadError!),
        ],
        const SizedBox(height: 14),
        _statusRow(),
        const SizedBox(height: 14),
        _gradientTabBar(),
        const SizedBox(height: 12),
        AnimatedBuilder(
          animation: _tabCtrl,
          builder: (context, _) {
            return _tabCtrl.index == 0
                ? _credentialsForm(
                    title: AppBrand.developerName,
                    subtitle: 'Conta principal — checkout e webhook',
                    accent: _ownerAccent,
                    configured: _ownerConfigured,
                    publicKey: _ownerPublicKey,
                    accessToken: _ownerAccessToken,
                    clientId: _ownerClientId,
                    clientSecret: _ownerClientSecret,
                    webhookUrl: _ownerWebhookUrl,
                    webhookSecret: _ownerWebhookSecret,
                    collectorId: _ownerCollectorId,
                    showWebhook: true,
                    tokenStored: _ownerConfigured,
                  )
                : _credentialsForm(
                    title: AppBrand.idealizerName,
                    subtitle: 'Recebedor interno — split automático',
                    accent: _partnerAccent,
                    configured: _partnerConfigured,
                    publicKey: _partnerPublicKey,
                    accessToken: _partnerAccessToken,
                    clientId: _partnerClientId,
                    clientSecret: null,
                    webhookUrl: null,
                    webhookSecret: null,
                    collectorId: _partnerCollectorId,
                    showWebhook: false,
                    tokenStored: _partnerConfigured,
                    pendingHint: true,
                  );
          },
        ),
        const SizedBox(height: 16),
        _splitCard(),
        const SizedBox(height: 16),
        _actionsRow(),
      ],
    );
  }

  Widget _heroHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [widget.brandBlue, widget.brandTeal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: widget.brandBlue.withValues(alpha: 0.28),
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
            child: const Icon(Icons.payments_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mercado Pago',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Checkout único para o usuário · split interno '
                  '${AppBrand.developerName} + ${AppBrand.idealizerName}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Recarregar do banco',
            onPressed: reload,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(String msg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg, style: TextStyle(color: Colors.red.shade900, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _statusRow() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _statusChip(
          label: AppBrand.developerName,
          ok: _ownerConfigured,
          color: _ownerAccent,
        ),
        _statusChip(
          label: AppBrand.idealizerName,
          ok: _partnerConfigured,
          color: _partnerAccent,
        ),
        if (_splitEnabled)
          Chip(
            avatar: Icon(Icons.call_split_rounded, size: 16, color: widget.brandTeal),
            label: const Text('Split ativo', style: TextStyle(fontSize: 12)),
            backgroundColor: widget.brandTeal.withValues(alpha: 0.12),
          ),
      ],
    );
  }

  Widget _statusChip({
    required String label,
    required bool ok,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ok ? color.withValues(alpha: 0.12) : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ok ? color.withValues(alpha: 0.45) : Colors.orange.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.pending_rounded,
            size: 16,
            color: ok ? color : Colors.orange.shade800,
          ),
          const SizedBox(width: 6),
          Text(
            ok ? '$label · OK' : '$label · pendente',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: ok ? color : Colors.orange.shade900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradientTabBar() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.grey.shade100,
      ),
      child: TabBar(
        controller: _tabCtrl,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(colors: [widget.brandBlue, widget.brandTeal]),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey.shade700,
        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        onTap: (_) => setState(() {}),
        tabs: [
          Tab(text: AppBrand.developerName),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(AppBrand.idealizerName),
                if (!_partnerConfigured) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.circle, size: 8, color: Colors.orange.shade700),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _credentialsForm({
    required String title,
    required String subtitle,
    required Color accent,
    required bool configured,
    required TextEditingController publicKey,
    required TextEditingController accessToken,
    required TextEditingController clientId,
    required TextEditingController? clientSecret,
    required TextEditingController? webhookUrl,
    required TextEditingController? webhookSecret,
    required TextEditingController collectorId,
    required bool showWebhook,
    required bool tokenStored,
    bool pendingHint = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white,
        border: Border.all(color: accent.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.account_balance_wallet_rounded, color: accent, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(fontWeight: FontWeight.w900, color: accent, fontSize: 16),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                if (configured)
                  Icon(Icons.verified_rounded, color: accent, size: 22),
              ],
            ),
            if (pendingHint && !configured) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Text(
                  'Preencha Public Key, Access Token e Collector ID de '
                  '${AppBrand.idealizerName}. Suas credenciais (${AppBrand.developerName}) '
                  'já estão gravadas no banco.',
                  style: TextStyle(fontSize: 11.5, color: Colors.orange.shade900, height: 1.35),
                ),
              ),
            ],
            const SizedBox(height: 14),
            _field('Public Key', publicKey, icon: Icons.vpn_key_rounded),
            _field(
              'Access Token',
              accessToken,
              obscure: true,
              icon: Icons.lock_rounded,
              helper: tokenStored && accessToken.text.isNotEmpty
                  ? 'Gravado no banco — deixe como está ou cole um novo para trocar'
                  : null,
            ),
            _field('Client ID', clientId, icon: Icons.tag_rounded),
            if (clientSecret != null)
              _field(
                'Client Secret',
                clientSecret,
                obscure: true,
                icon: Icons.key_rounded,
                helper: tokenStored && clientSecret.text.isNotEmpty
                    ? 'Gravado — deixe vazio no save para manter o atual'
                    : null,
              ),
            _field('Collector ID (conta MP)', collectorId, icon: Icons.badge_rounded),
            if (showWebhook && webhookUrl != null) ...[
              _field(
                'Webhook URL',
                webhookUrl,
                icon: Icons.link_rounded,
                readOnly: false,
              ),
              if (webhookSecret != null)
                _field(
                  'Webhook Secret',
                  webhookSecret,
                  obscure: true,
                  icon: Icons.shield_rounded,
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    bool obscure = false,
    IconData? icon,
    String? helper,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FastTextField(
        controller: ctrl,
        obscureText: obscure,
        readOnly: readOnly,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 2,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.grey.shade50,
          prefixIcon: icon != null ? Icon(icon, size: 20) : null,
        ),
      ),
    );
  }

  Widget _splitCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0EA5E9).withValues(alpha: 0.10),
            const Color(0xFFF97316).withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Divisão interna (invisível ao usuário)',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'Ex.: licença ${CurrencyFormats.formatBRL(49.90)} → '
            '${AppBrand.developerName} ${CurrencyFormats.formatBRL(14.90)} + '
            '${AppBrand.idealizerName} ${CurrencyFormats.formatBRL(35.00)}. '
            'Taxas MP são descontadas depois.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade800, height: 1.35),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Split automático ativo'),
            value: _splitEnabled,
            onChanged: (v) => setState(() => _splitEnabled = v),
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Valor fixo (R\$)')),
              ButtonSegment(value: false, label: Text('Percentual (%)')),
            ],
            selected: {_splitModeFixed},
            onSelectionChanged: (s) => setState(() => _splitModeFixed = s.first),
          ),
          const SizedBox(height: 12),
          _moneyField('Valor bruto da licença (mensal)', _licenseGross, onChanged: _onLicenseGrossChanged),
          _moneyField('Plano anual (checkout)', _premiumAnnual),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 420;
              if (narrow) {
                return Column(
                  children: [
                    _splitModeFixed
                        ? _moneyField('Parte ${AppBrand.developerName}', _ownerFixed, onChanged: _onOwnerFixedChanged)
                        : _percentField('% ${AppBrand.developerName}', _ownerPercent, onChanged: _onOwnerPercentChanged),
                    _splitModeFixed
                        ? _moneyField('Parte ${AppBrand.idealizerName}', _partnerFixed, readOnly: true)
                        : _percentField('% ${AppBrand.idealizerName}', _partnerPercent, readOnly: true),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _splitModeFixed
                        ? _moneyField('Parte ${AppBrand.developerName}', _ownerFixed, onChanged: _onOwnerFixedChanged)
                        : _percentField('% ${AppBrand.developerName}', _ownerPercent, onChanged: _onOwnerPercentChanged),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _splitModeFixed
                        ? _moneyField('Parte ${AppBrand.idealizerName}', _partnerFixed, readOnly: true)
                        : _percentField('% ${AppBrand.idealizerName}', _partnerPercent, readOnly: true),
                  ),
                ],
              );
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sincronizar preços no site e apps ao salvar'),
            value: _syncLanding,
            onChanged: (v) => setState(() => _syncLanding = v),
          ),
        ],
      ),
    );
  }

  Widget _moneyField(
    String label,
    TextEditingController ctrl, {
    VoidCallback? onChanged,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FastTextField(
        controller: ctrl,
        readOnly: readOnly,
        inputFormatters: CurrencyFormats.brlInputFormatters,
        keyboardType: TextInputType.number,
        onChanged: onChanged == null ? null : (_) => onChanged(),
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: readOnly ? Colors.grey.shade100 : Colors.white,
        ),
      ),
    );
  }

  Widget _percentField(
    String label,
    TextEditingController ctrl, {
    VoidCallback? onChanged,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FastTextField(
        controller: ctrl,
        readOnly: readOnly,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d,\.]'))],
        onChanged: onChanged == null ? null : (_) => onChanged(),
        decoration: InputDecoration(
          labelText: label,
          suffixText: '%',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: readOnly ? Colors.grey.shade100 : Colors.white,
        ),
      ),
    );
  }

  Widget _actionsRow() {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save_rounded),
          label: Text(_saving ? 'Salvando…' : 'Salvar configuração'),
          style: FilledButton.styleFrom(
            backgroundColor: widget.brandTeal,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
        ),
        FilledButton.icon(
          onPressed: (_saving || _syncingAll) ? null : _syncAll,
          icon: _syncingAll
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.sync_rounded),
          label: Text(_syncingAll ? 'Sincronizando…' : 'Sync pagamentos (24h)'),
          style: FilledButton.styleFrom(
            backgroundColor: widget.brandBlue,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
        ),
      ],
    );
  }
}
