import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import '../constants/bank_brand_assets.dart';
import '../constants/spotlight_banks.dart';
import '../models/user_profile.dart';
import '../services/mp_checkout_pricing_service.dart';
import '../theme/app_colors.dart';
import '../utils/debounced_text_controller.dart';
import 'escolha_plano_page.dart';

/// Lista de bancos de referência (mercado). A ligação automática a contas **não** está à venda.
class SupportedBanksPage extends StatefulWidget {
  const SupportedBanksPage({super.key});

  @override
  State<SupportedBanksPage> createState() => _SupportedBanksPageState();
}

class _SupportedBanksPageState extends State<SupportedBanksPage> {
  final _searchCtrl = TextEditingController();
  VoidCallback? _detachSearchListener;

  @override
  void initState() {
    super.initState();
    // Debounce: a lista de bancos é grande — sem isso o teclado trava.
    _detachSearchListener = attachDebouncedRebuild(_searchCtrl, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _detachSearchListener?.call();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<SpotlightBank> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return kSpotlightBanks;
    return kSpotlightBanks.where((b) {
      if (b.name.toLowerCase().contains(q) || b.shortLabel.toLowerCase().contains(q)) return true;
      final tokens = BankBrandAssets.tokensFor(b.id);
      return tokens.any((t) => t.contains(q) || q.contains(t));
    }).toList();
  }

  Future<void> _onConnectNow(BuildContext context) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entre na sua conta para ver os planos.')),
      );
      return;
    }
    final snap = await FirebaseFirestore.instance.collection('users').doc(u.uid).get();
    if (!context.mounted) return;
    final profile = UserProfile.fromFirestoreMap(u.uid, snap.data() ?? {});

    if (!profile.hasActiveLicense) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Renove ou ative a licença Premium para continuar.'),
        ),
      );
    }
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const EscolhaPlanoPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FA),
      appBar: AppBar(
        title: const Text('Bancos suportados'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<MpCheckoutPricingSnapshot>(
        stream: MpCheckoutPricingService.watch(),
        builder: (context, snap) {
          final p = snap.data ?? MpCheckoutPricingSnapshot.defaults();
          final banks = _filtered;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Material(
                  elevation: 0,
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Plano Premium',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.blueGrey.shade800,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          p.premiumMonthlyLine,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Ou ${p.premiumAnnualLine} (${p.premiumAnnualEquivPerMonthLine} em média)',
                          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'A lista abaixo é só de referência. O app não abre novas ligações automáticas a bancos; use lançamentos manuais no Premium.',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Material(
                  elevation: 0,
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: FastTextField(
                      controller: _searchCtrl,
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
                      decoration: InputDecoration(
                        hintText: 'Busca offline: nome, código ou apelido (ex.: nu, 237, c6…)',
                        prefixIcon: Icon(Icons.search_rounded, color: AppColors.primary.withValues(alpha: 0.85)),
                        border: InputBorder.none,
                        suffixIcon: _searchCtrl.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Limpar',
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() {});
                                  FocusScope.of(context).unfocus();
                                },
                                icon: const Icon(Icons.clear_rounded),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: banks.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Nenhum banco encontrado para "${_searchCtrl.text}".',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.98,
                        ),
                        cacheExtent: 280,
                        itemCount: banks.length,
                        itemBuilder: (context, i) => _BankBrandTile(bank: banks[i]),
                      ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: Material(
        color: Colors.white,
        elevation: 8,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: FilledButton(
              onPressed: () => _onConnectNow(context),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Ver plano Premium'),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cartão com SVG em bundle (rápido, offline). Se o ficheiro falhar, usa ícone Material.
class _BankBrandTile extends StatelessWidget {
  const _BankBrandTile({required this.bank});

  final SpotlightBank bank;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      shadowColor: Colors.black12,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  RepaintBoundary(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 54,
                        height: 54,
                        color: bank.placeholderColor.withValues(alpha: 0.06),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(4),
                        child: Image.asset(
                          bank.localLogoPngPath,
                          width: 46,
                          height: 46,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => Icon(bank.icon, color: bank.placeholderColor, size: 30),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    bank.shortLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                bank.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, height: 1.2),
              ),
              const SizedBox(height: 4),
              Text(
                'Logo offline · sem rede',
                style: TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
