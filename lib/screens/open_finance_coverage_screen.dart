import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Grupo informativo (Open Finance / agregadores — cobertura típica no Brasil).
class OpenFinanceCoverageGroup {
  final String title;
  final String hint;
  final IconData icon;
  final Color accent;
  final List<String> institutions;

  const OpenFinanceCoverageGroup({
    required this.title,
    required this.hint,
    required this.icon,
    required this.accent,
    required this.institutions,
  });
}

/// Referência para UX e educação do usuário; conectores efetivos dependem do agregador contratado.
const List<String> kOpenFinancePopularHighlightNames = [
  'Nubank',
  'Itaú Unibanco',
  'Bradesco',
  'Banco do Brasil',
  'Caixa (incl. Caixa Tem)',
  'Santander',
  'Inter',
  'C6 Bank',
];

const List<OpenFinanceCoverageGroup> kOpenFinanceCoverageGroups = [
  OpenFinanceCoverageGroup(
    title: 'Grandes bancos',
    hint: 'Integrações mais maduras: saldo, extrato e cartões (PF/PJ conforme banco).',
    icon: Icons.account_balance_rounded,
    accent: Color(0xFF1E3A5F),
    institutions: [
      'Itaú / Itaú Unibanco (PF e PJ)',
      'Bradesco (PF e PJ)',
      'Banco do Brasil (PF e PJ)',
      'Santander (PF e PJ)',
      'Caixa Econômica Federal (incluindo Caixa Tem)',
    ],
  ),
  OpenFinanceCoverageGroup(
    title: 'Bancos digitais e fintechs',
    hint: 'Favoritos de quem busca automação no dia a dia.',
    icon: Icons.smartphone_rounded,
    accent: Color(0xFF0D9488),
    institutions: [
      'Nubank (PF e expansão PJ)',
      'Banco Inter',
      'C6 Bank',
      'BTG Pactual (banking e investimentos)',
      'Neon',
      'Next',
      'Digio',
    ],
  ),
  OpenFinanceCoverageGroup(
    title: 'Carteiras e pagamentos',
    hint: 'Pix, saldo e movimentação quando o conector estiver disponível.',
    icon: Icons.wallet_rounded,
    accent: Color(0xFF7C3AED),
    institutions: [
      'Mercado Pago',
      'PicPay',
      'PagBank (PagSeguro)',
      'Stone',
      'RecargaPay',
    ],
  ),
  OpenFinanceCoverageGroup(
    title: 'Cooperativas e outros',
    hint: 'Cobertura ampla em agregadores como Pluggy ou Belvo.',
    icon: Icons.groups_rounded,
    accent: Color(0xFFB45309),
    institutions: [
      'Sicredi',
      'Sicoob',
      'Banrisul',
      'XP Investimentos / Rico (conta e cartões, conforme conector)',
    ],
  ),
];

/// Tela informativa: instituições típicas no Brasil (referência de mercado).
class OpenFinanceCoverageScreen extends StatelessWidget {
  const OpenFinanceCoverageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 168,
            pinned: true,
            stretch: true,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                'Open Finance no Brasil',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, shadows: [
                  Shadow(color: Colors.black26, blurRadius: 8),
                ]),
              ),
              background: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E3A5F), Color(0xFF0D9488)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 52, 20, 24),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Text(
                        'Mais de 90% das contas ativas costumam ter opção de conexão via agregadores certificados — a lista efetiva depende do provedor (Pluggy, Belvo, etc.).',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 13,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            sliver: SliverToBoxAdapter(
              child: _PopularStrip(),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            sliver: SliverToBoxAdapter(
              child: _InfoProCard(),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final g = kOpenFinanceCoverageGroups[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _GroupCard(group: g),
                  );
                },
                childCount: kOpenFinanceCoverageGroups.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PopularStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_fire_department_rounded, color: Colors.orange.shade700, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Mais populares',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Aparecem primeiro também na busca de conexão do app.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.3),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kOpenFinancePopularHighlightNames
                  .map(
                    (n) => Chip(
                      label: Text(n, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      side: BorderSide(color: AppColors.primary.withValues(alpha: 0.25)),
                      backgroundColor: AppColors.primary.withValues(alpha: 0.06),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoProCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: const Color(0xFFECFDF5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppColors.success.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_outlined, color: AppColors.success, size: 24),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'O que o app pode mostrar (referência)',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF065F46)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _InfoProCardBullet('Saldo em tempo real — conciliação imediata (quando o banco expõe na API).'),
            _InfoProCardBullet('Extrato e Pix/cartão — captura automática de compras para lançamentos.'),
            _InfoProCardBullet('Cartão de crédito — fatura, limite e parcelas (conforme instituição e agregador).'),
            const SizedBox(height: 8),
            Text(
              'Você autoriza só o necessário no ambiente seguro do banco; o app não armazena senha de acesso.',
              style: TextStyle(fontSize: 12, color: Colors.green.shade900, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoProCardBullet extends StatelessWidget {
  final String text;

  const _InfoProCardBullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded, size: 18, color: Colors.green.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, height: 1.35, color: Colors.green.shade900)),
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final OpenFinanceCoverageGroup group;

  const _GroupCard({required this.group});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: CircleAvatar(
            backgroundColor: group.accent.withValues(alpha: 0.12),
            child: Icon(group.icon, color: group.accent, size: 22),
          ),
          title: Text(group.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(group.hint, style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35)),
          ),
          children: [
            ...group.institutions.map(
              (name) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.circle, size: 6, color: group.accent.withValues(alpha: 0.8)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(name, style: const TextStyle(fontSize: 14, height: 1.35)),
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
