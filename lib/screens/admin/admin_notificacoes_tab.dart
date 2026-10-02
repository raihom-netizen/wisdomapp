import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../utils/admin_load_guard.dart';
import '../../widgets/admin/admin_notificacoes_diag_sheet.dart';
import '../../widgets/admin/admin_notificacoes_teste_lote.dart';
import '../../widgets/admin/admin_page_shell.dart';
import '../../widgets/admin/admin_ui_kit.dart';

/// Admin — **Notificações** (porte do Controle Total, 02/10/2026): busca um
/// usuário → abre o diagnóstico de push dele (aparelhos, preferências, fila,
/// veredito). Com [podeTestar] (master) aparece também o teste de push em lote
/// e o botão «Testar push» dentro do diagnóstico — o servidor confere de novo
/// (`ctAdminNotificacoesTeste` exige master).
///
/// Lista de usuários: `ctAdminNotificacoesUsuarios` (uma leitura, guardada no
/// State; a busca filtra local).
class AdminNotificacoesTab extends StatefulWidget {
  const AdminNotificacoesTab({super.key, required this.podeTestar});

  final bool podeTestar;

  @override
  State<AdminNotificacoesTab> createState() => _AdminNotificacoesTabState();
}

class _AdminNotificacoesTabState extends State<AdminNotificacoesTab> {
  static final _df = DateFormat('dd/MM/yy');
  final _busca = TextEditingController();
  late Future<List<Map<String, dynamic>>> _usuarios = _carregar();
  String _filtro = 'todos';

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _carregar() async {
    final r = await AdminLoadGuard.comPrazo(
      FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('ctAdminNotificacoesUsuarios', options: HttpsCallableOptions(timeout: AdminLoadGuard.callable))
          .call<dynamic>({}),
      prazo: AdminLoadGuard.callable + const Duration(seconds: 5),
      oQue: 'a lista de usuários',
    );
    final d = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : <String, dynamic>{};
    return ((d['usuarios'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  void _recarregar() => setState(() => _usuarios = _carregar());

  static int _aparelhos(Map<String, dynamic> u) => (u['aparelhos'] as num?)?.toInt() ?? 0;

  bool _passa(Map<String, dynamic> u) {
    final p = ((u['plataformas'] as List?) ?? const []).map((e) => '$e');
    final ok = switch (_filtro) {
      'com' => _aparelhos(u) > 0,
      'sem' => _aparelhos(u) == 0,
      'off' => u['pushEnabled'] == false,
      'ios' => p.contains('ios'),
      'android' => p.contains('android'),
      'web' => p.contains('web'),
      _ => true,
    };
    if (!ok) return false;
    final q = _busca.text.trim().toLowerCase();
    return q.isEmpty || '${u['nome'] ?? ''} ${u['email'] ?? ''} ${u['uid'] ?? ''}'.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final pad = AdminPageShell.listPadding(context, top: 4);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _usuarios,
      builder: (context, snap) {
        final carregando = snap.connectionState != ConnectionState.done;
        final todos = snap.data ?? const <Map<String, dynamic>>[];
        final visiveis = todos.where(_passa).toList();
        int conta(bool Function(Map<String, dynamic>) f) => todos.where(f).length;
        return RefreshIndicator(
          onRefresh: () async => _recarregar(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: pad.copyWith(bottom: pad.bottom + 32),
            children: [
              AdminHero(
                titulo: 'Notificações',
                subtitulo: 'Diagnóstico de push por usuário'
                    '${widget.podeTestar ? ' e teste de envio (master)' : ''}',
                icone: Icons.notifications_active_rounded,
                cores: const [Color(0xFF1E3A8A), AdminUi.roxo, AdminUi.teal],
                carregando: carregando,
                onAtualizar: _recarregar,
              ),
              if (widget.podeTestar) ...[
                const SizedBox(height: 12),
                Material(
                  color: AdminUi.roxo.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: AdminUi.roxo.withValues(alpha: 0.3)),
                    ),
                    leading: const CircleAvatar(
                      backgroundColor: AdminUi.roxo,
                      child: Icon(Icons.groups_rounded, color: Colors.white),
                    ),
                    title: Text('Teste de push em lote',
                        style: TextStyle(fontWeight: FontWeight.w900, color: AdminUi.tintaOf(context))),
                    subtitle: Text('Escolha alguns usuários (máx. 20) e envie um push de verdade',
                        style: TextStyle(color: AdminUi.apoioOf(context), fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AdminUi.roxo),
                    onTap: () => abrirTesteNotificacaoEmLote(context),
                  ),
                ),
              ],
              if (snap.hasError)
                AdminErroCard(
                  erro: mensagemErroNotificacoes(snap.error, 'ctAdminNotificacoesUsuarios'),
                  onTentar: _recarregar,
                  titulo: 'Não foi possível carregar os usuários',
                )
              else if (carregando)
                const AdminCarregando(texto: 'Lendo usuários e aparelhos…')
              else ...[
                AdminSecao(titulo: 'Aparelhos registrados', cor: AdminUi.azul, icone: Icons.devices_rounded),
                AdminKpiGrid(children: [
                  for (final f in <(String, String, IconData, Color, int)>[
                    ('todos', 'Usuários', Icons.people_alt_rounded, AdminUi.azul, todos.length),
                    ('com', 'Com aparelho', Icons.phonelink_ring_rounded, AdminUi.verde,
                        conta((u) => _aparelhos(u) > 0)),
                    ('sem', 'Sem aparelho', Icons.phonelink_erase_rounded, AdminUi.vermelho,
                        conta((u) => _aparelhos(u) == 0)),
                    ('off', 'Push desligado', Icons.notifications_off_rounded, AdminUi.ambar,
                        conta((u) => u['pushEnabled'] == false)),
                    ('ios', 'iPhone', Icons.phone_iphone_rounded, AdminUi.azul,
                        conta((u) => ((u['plataformas'] as List?) ?? const []).contains('ios'))),
                    ('android', 'Android', Icons.phone_android_rounded, AdminUi.verde,
                        conta((u) => ((u['plataformas'] as List?) ?? const []).contains('android'))),
                    ('web', 'Web', Icons.language_rounded, AdminUi.teal,
                        conta((u) => ((u['plataformas'] as List?) ?? const []).contains('web'))),
                  ])
                    AdminKpi(
                      rotulo: f.$2,
                      valor: '${f.$5}',
                      icone: f.$3,
                      cor: f.$4,
                      selecionado: _filtro == f.$1,
                      onTap: () => setState(() => _filtro = f.$1),
                    ),
                ]),
                AdminSecao(
                  titulo: 'Buscar usuário (${visiveis.length})',
                  cor: AdminUi.roxo,
                  icone: Icons.person_search_rounded,
                ),
                AdminBusca(
                  controller: _busca,
                  onChanged: (_) => setState(() {}),
                  hint: 'Nome, e-mail ou UID — toque para diagnosticar',
                ),
                const SizedBox(height: 10),
                if (visiveis.isEmpty)
                  const AdminVazio(texto: 'Nenhum usuário encontrado.', icone: Icons.person_off_rounded)
                else ...[
                  for (final u in visiveis.take(60)) _linha(u),
                  if (visiveis.length > 60)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Mostrando 60 de ${visiveis.length}. Refine a busca.',
                          style: TextStyle(fontSize: 12, color: AdminUi.apoioOf(context))),
                    ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _linha(Map<String, dynamic> u) {
    final nome = '${u['nome'] ?? ''}';
    final email = '${u['email'] ?? ''}';
    final uid = '${u['uid'] ?? ''}';
    final plataformas = ((u['plataformas'] as List?) ?? const []).map((e) => '$e').toList();
    final n = _aparelhos(u);
    final visto = DateTime.tryParse('${u['ultimoRegistro'] ?? ''}')?.toLocal();
    final cor = n == 0 ? AdminUi.vermelho : (u['pushEnabled'] == false ? AdminUi.ambar : AdminUi.verde);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AdminUi.cardOf(context),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => abrirDiagnosticoNotificacoes(
            context,
            uid: uid,
            nome: nome.isNotEmpty ? nome : email,
            podeTestar: widget.podeTestar,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AdminUi.bordaOf(context)),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: cor.withValues(alpha: 0.14),
                child: Icon(n == 0 ? Icons.phonelink_erase_rounded : Icons.notifications_rounded, color: cor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(nome.isNotEmpty ? nome : (email.isNotEmpty ? email : uid),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, color: AdminUi.tintaOf(context))),
                  Text(
                    [
                      if (nome.isNotEmpty && email.isNotEmpty) email,
                      n == 0 ? 'sem aparelho' : '$n aparelho(s) · ${plataformas.join(', ')}',
                      if (visto != null) 'visto ${_df.format(visto)}',
                      if (u['pushEnabled'] == false) 'push desligado',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: AdminUi.apoioOf(context)),
                  ),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: AdminUi.roxo),
            ]),
          ),
        ),
      ),
    );
  }
}
