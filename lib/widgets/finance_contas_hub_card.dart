import 'package:flutter/material.dart';

/// Atalhos do «Saldos por conta» num card moderno e colorido — port do
/// Controle Total: **Cadastrar bancos**, **Cadastrar categorias** e
/// **Migrar lançamentos** (atribuir em massa).
///
/// No CT o destaque do card é a conexão com o banco real (Open Finance/Finance
/// Pro), que o WISDOMAPP não tem; aqui o destaque é o **Pix** do Financeiro:
/// «Gerar Pix» (QR Code + copia e cola com a sua chave) e «Meu Pix» (chaves
/// de cada banco e o Pix padrão).
class FinanceContasHubCard extends StatelessWidget {
  const FinanceContasHubCard({
    super.key,
    required this.onBancos,
    required this.onCategorias,
    required this.onAtribuir,
    required this.onGerarPix,
    required this.onMeuPix,
  });

  final VoidCallback onBancos;
  final VoidCallback onCategorias;
  final VoidCallback onAtribuir;
  final VoidCallback onGerarPix;
  final VoidCallback onMeuPix;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E3A8A), Color(0xFF0D9488)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A8A).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Destaque: Pix (cobrar e receber).
          Material(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onGerarPix,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF14B8A6), Color(0xFF0D9488)]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.qr_code_2_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Gerar Pix',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                        SizedBox(height: 2),
                        Text('QR Code e copia e cola com a sua chave · WhatsApp e Telegram',
                            style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            _atalho(Icons.add_card_rounded, 'Cadastrar\nbancos', const Color(0xFF3B82F6), onBancos),
            const SizedBox(width: 8),
            _atalho(Icons.category_rounded, 'Cadastrar\ncategorias', const Color(0xFFA855F7), onCategorias),
            const SizedBox(width: 8),
            _atalho(Icons.swap_horiz_rounded, 'Migrar\nlançamentos', const Color(0xFFF59E0B), onAtribuir),
            const SizedBox(width: 8),
            _atalho(Icons.key_rounded, 'Meu\nPix', const Color(0xFF14B8A6), onMeuPix),
          ]),
        ],
      ),
    );
  }

  Widget _atalho(IconData icone, String rotulo, Color cor, VoidCallback onTap) {
    return Expanded(
      child: Material(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Column(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(11)),
                child: Icon(icone, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 6),
              Text(rotulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11, height: 1.15)),
            ]),
          ),
        ),
      ),
    );
  }
}
