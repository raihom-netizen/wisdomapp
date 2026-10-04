// Card «Investimentos» do Financeiro: patrimônio investido + quanto rendeu no
// mês; toque abre a carteira. Uma leitura por aplicação (stream) + os índices
// do BCB (cache da sessão).

import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_context.dart';
import '../../utils/firestore_user_doc_id.dart';
import 'investimentos_calculo.dart';
import 'investimentos_page.dart';
import 'investimentos_repo.dart';
import 'investimentos_ui_comum.dart';

class InvestimentosAtalhoCard extends StatefulWidget {
  const InvestimentosAtalhoCard({super.key, required this.uid, required this.profile});
  final String uid;
  final UserProfile profile;

  @override
  State<InvestimentosAtalhoCard> createState() => _InvestimentosAtalhoCardState();
}

class _InvestimentosAtalhoCardState extends State<InvestimentosAtalhoCard> {
  final _repo = InvestimentosRepo.instance;
  late final String _uidDoc = firestoreUserDocIdForAppShell(widget.uid);
  late final Stream<List<Investimento>>? _stream = _uidDoc.isEmpty ? null : _repo.stream(_uidDoc);
  IndicesBcb? _idx;

  @override
  void initState() {
    super.initState();
    _repo.indices().then((i) {
      if (mounted) setState(() => _idx = i);
    }).catchError((_) {});
  }

  void _abrir() {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => InvestimentosPage(uid: widget.uid, profile: widget.profile)));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _abrir,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: context.appPanelDecoration(radius: 16, borderAccent: AppColors.accent),
            child: StreamBuilder<List<Investimento>>(
              stream: _stream,
              builder: (context, snap) {
                final lista = (snap.data ?? const <Investimento>[]).where((i) => i.ativo).toList();
                final idx = _idx;
                String sub = 'CDB, Tesouro, caixinhas, poupança… com as taxas do Banco Central';
                String? valor;
                if (lista.isNotEmpty && idx != null) {
                  final t = TotaisCarteira.de(lista, idx, hojeBrasilia());
                  valor = brl(t.bruto);
                  sub = 'Rendeu no mês ${brl(t.mes)} · líquido ${brl(t.liquido)}';
                }
                return Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.trending_up_rounded, color: AppColors.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Investimentos', style: TextStyle(fontWeight: FontWeight.w800, color: context.appDeepTitle)),
                      Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: context.appTextSecondary)),
                    ]),
                  ),
                  if (valor != null)
                    Text(valor, style: TextStyle(fontWeight: FontWeight.w900, color: context.appTextPrimary)),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, color: context.appTextMuted),
                ]);
              },
            ),
          ),
        ),
      ),
    );
  }
}
